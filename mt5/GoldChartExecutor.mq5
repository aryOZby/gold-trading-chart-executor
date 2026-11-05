#property copyright "Gold Trading"
#property version   "2.00"
#property description "Chart Executor: per-group Inputs, orders, breakeven, 50-pip guard, Friday close"

#include <Trade/Trade.mqh>

input bool   InpTrade1 = false; // Trade VIP SIGNALS ROOM
input double InpLot1   = 0.01;  // Lot VIP SIGNALS ROOM
input int    InpStrat1 = 1;     // Strategy VIP SIGNALS ROOM (1-5)

input bool   InpTrade2 = false; // Trade Technical Pips
input double InpLot2   = 0.01;  // Lot Technical Pips
input int    InpStrat2 = 1;     // Strategy Technical Pips (1-5)

input bool   InpTrade3 = false; // Trade profit__kings
input double InpLot3   = 0.01;  // Lot profit__kings
input int    InpStrat3 = 2;     // Strategy profit__kings (1-5)

input bool   InpTrade4 = false; // Trade GOLD SNIPER
input double InpLot4   = 0.01;  // Lot GOLD SNIPER
input int    InpStrat4 = 3;     // Strategy GOLD SNIPER (1-5)

input bool   InpTrade5 = false; // Trade Trade With Samder
input double InpLot5   = 0.01;  // Lot Trade With Samder
input int    InpStrat5 = 1;     // Strategy Trade With Samder (1-5)

input bool   InpTrade6 = false; // Trade GOLD BULLET SIGNALS
input double InpLot6   = 0.01;  // Lot GOLD BULLET SIGNALS
input int    InpStrat6 = 1;     // Strategy GOLD BULLET SIGNALS (1-5)

input bool   InpDryRun            = true; // Dry run (log only, no orders)
input double InpPipSize           = 0.1;  // Pip size (XAUUSD = 0.1)
input int    InpSafetyPips        = 50;   // Emergency SL/TP distance (pips)
input int    InpSafetyDelaySec    = 5;    // Seconds before emergency SL/TP
input int    InpFridayCloseHour   = 23;   // Friday close hour (Israel time)
input int    InpFridayCloseMinute = 30;   // Friday close minute (Israel time)
input int    InpMaxSignalAgeSec   = 300;  // Ignore signals older than (seconds)
input int    InpDeviation         = 30;   // Deviation (points)
input int    InpTimerMs           = 200;  // Timer ms

#define MAGIC_BASE 270100
#define SLOTS      6
#define MAX_LEGS   12
#define CMD_DIR    "gt_cmd\\"
#define STATE_DIR  "gt_state\\"
#define STATE_GRACE_SEC 60

CTrade trade;

// One entry per signal that opened orders: needed to move SL to entry later.
string   sKey[];
int      sSide[];
double   sTrigger[];
bool     sBe[];
int      sCount[];
datetime sCreated[];
ulong    sTickets[][MAX_LEGS];

datetime lastGuardLog = 0;
datetime lastWeekendLog = 0;

// ---------------------------------------------------------------- Inputs

bool SlotTrade(const int slot)
{
   switch(slot)
   {
      case 1: return InpTrade1;
      case 2: return InpTrade2;
      case 3: return InpTrade3;
      case 4: return InpTrade4;
      case 5: return InpTrade5;
      case 6: return InpTrade6;
   }
   return false;
}

double SlotLot(const int slot)
{
   switch(slot)
   {
      case 1: return InpLot1;
      case 2: return InpLot2;
      case 3: return InpLot3;
      case 4: return InpLot4;
      case 5: return InpLot5;
      case 6: return InpLot6;
   }
   return 0.0;
}

int ClampStrategy(const int value)
{
   if(value < 1)
      return 1;
   if(value > 5)
      return 5;
   return value;
}

bool IsOurMagic(const long magic)
{
   return magic > MAGIC_BASE && magic <= MAGIC_BASE + SLOTS;
}

// ---------------------------------------------------------------- Israel time

datetime MakeDate(const int y, const int m, const int d)
{
   MqlDateTime t;
   ZeroMemory(t);
   t.year = y;
   t.mon  = m;
   t.day  = d;
   return StructToTime(t);
}

datetime LastSunday(const int y, const int m)
{
   int ny = (m == 12) ? y + 1 : y;
   int nm = (m == 12) ? 1 : m + 1;
   datetime last = MakeDate(ny, nm, 1) - 86400;
   MqlDateTime t;
   TimeToStruct(last, t);
   return last - t.day_of_week * 86400;
}

// Israel: UTC+3 from the Friday before the last Sunday of March 02:00
// until the last Sunday of October 02:00, otherwise UTC+2.
int IsraelOffsetHours(const datetime gmt)
{
   MqlDateTime t;
   TimeToStruct(gmt, t);
   datetime start = LastSunday(t.year, 3) - 2 * 86400;
   datetime end   = LastSunday(t.year, 10) - 3600;
   if(gmt >= start && gmt < end)
      return 3;
   return 2;
}

datetime IsraelNow()
{
   datetime gmt = TimeGMT();
   return gmt + IsraelOffsetHours(gmt) * 3600;
}

// From Friday close until Monday 00:00 Israel: no new trades, everything closed.
bool InWeekendBlock()
{
   MqlDateTime t;
   TimeToStruct(IsraelNow(), t);
   int minutes = t.hour * 60 + t.min;
   if(t.day_of_week == 5 && minutes >= InpFridayCloseHour * 60 + InpFridayCloseMinute)
      return true;
   return t.day_of_week == 6 || t.day_of_week == 0;
}

// ---------------------------------------------------------------- Lifecycle

int OnInit()
{
   trade.SetDeviationInPoints(InpDeviation);
   FolderCreate("gt_cmd", FILE_COMMON);
   FolderCreate("gt_state", FILE_COMMON);
   LoadStates();
   if(!EventSetMillisecondTimer(InpTimerMs))
      EventSetTimer(1);
   WriteChart();
   PrintFormat("GoldChartExecutor started: symbol=%s mode=%s tracked=%d",
               _Symbol, (InpDryRun ? "DRY RUN" : "LIVE"), ArraySize(sKey));
   ShowStatus();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
}

void OnTick()
{
   ManageBreakeven();
}

void OnTimer()
{
   WriteChart();
   WeekendClose();
   ProcessCommands();
   ManageBreakeven();
   SafetyGuard();
   CleanupStates();
   ShowStatus();
}

// ---------------------------------------------------------------- Helpers

double NormalizeVolume(const string symbol, double volume)
{
   double vmin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(vstep > 0.0)
      volume = MathFloor(volume / vstep + 0.0000001) * vstep;
   if(vmin > 0.0 && volume < vmin)
      volume = vmin;
   if(vmax > 0.0 && volume > vmax)
      volume = vmax;
   return NormalizeDouble(volume, 2);
}

// A stop can only sit on the losing side of the current price, beyond the broker minimum.
bool CanPlaceStop(const bool isBuy, const double stop)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(isBuy)
      return bid - stop > minDist;
   return stop - ask > minDist;
}

bool SelectPositionById(const ulong id)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == id)
         return true;
   }
   return false;
}

void ClosePosition(const ulong ticket, const string reason)
{
   if(trade.PositionClose(ticket, InpDeviation))
      PrintFormat("Closed ticket=%I64u (%s)", ticket, reason);
   else
      PrintFormat("Close FAILED ticket=%I64u (%s): %u %s", ticket, reason,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

bool ReadLines(const string path, string &lines[])
{
   int h = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   ArrayResize(lines, 0);
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0)
         continue;
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = line;
   }
   FileClose(h);
   return true;
}

bool SplitKV(const string line, string &key, string &value)
{
   int pos = StringFind(line, "=");
   if(pos <= 0)
      return false;
   key = StringSubstr(line, 0, pos);
   value = StringSubstr(line, pos + 1);
   return true;
}

void WriteTextFile(const string name, const string body, const bool common)
{
   int flags = FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common)
      flags |= FILE_COMMON;
   int h = FileOpen(name, flags);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, body);
   FileClose(h);
}

// ---------------------------------------------------------------- Chart Inputs → Python

string SlotLine(const int slot, const bool on, const double lot, const int strategy)
{
   return IntegerToString(slot) + "=" +
          IntegerToString(on ? 1 : 0) + "," +
          DoubleToString(lot, 4) + "," +
          IntegerToString(ClampStrategy(strategy));
}

void WriteChart()
{
   string body =
      SlotLine(1, InpTrade1, InpLot1, InpStrat1) + "\n" +
      SlotLine(2, InpTrade2, InpLot2, InpStrat2) + "\n" +
      SlotLine(3, InpTrade3, InpLot3, InpStrat3) + "\n" +
      SlotLine(4, InpTrade4, InpLot4, InpStrat4) + "\n" +
      SlotLine(5, InpTrade5, InpLot5, InpStrat5) + "\n" +
      SlotLine(6, InpTrade6, InpLot6, InpStrat6) + "\n";
   WriteTextFile("gs_chart.txt", body, true);
}

// ---------------------------------------------------------------- Signal state

int StateIndex(const string key)
{
   for(int i = 0; i < ArraySize(sKey); i++)
      if(sKey[i] == key)
         return i;
   return -1;
}

int AddState(const string key, const int side, const double trigger, const bool be)
{
   int n = ArraySize(sKey);
   ArrayResize(sKey, n + 1);
   ArrayResize(sSide, n + 1);
   ArrayResize(sTrigger, n + 1);
   ArrayResize(sBe, n + 1);
   ArrayResize(sCount, n + 1);
   ArrayResize(sCreated, n + 1);
   ArrayResize(sTickets, n + 1);
   sKey[n] = key;
   sSide[n] = side;
   sTrigger[n] = trigger;
   sBe[n] = be;
   sCount[n] = 0;
   sCreated[n] = TimeCurrent();
   for(int k = 0; k < MAX_LEGS; k++)
      sTickets[n][k] = 0;
   return n;
}

void AddTicket(const int i, const ulong ticket)
{
   if(sCount[i] >= MAX_LEGS)
      return;
   sTickets[i][sCount[i]] = ticket;
   sCount[i]++;
}

void RemoveState(const int i)
{
   int n = ArraySize(sKey);
   for(int j = i; j < n - 1; j++)
   {
      sKey[j] = sKey[j + 1];
      sSide[j] = sSide[j + 1];
      sTrigger[j] = sTrigger[j + 1];
      sBe[j] = sBe[j + 1];
      sCount[j] = sCount[j + 1];
      sCreated[j] = sCreated[j + 1];
      for(int k = 0; k < MAX_LEGS; k++)
         sTickets[j][k] = sTickets[j + 1][k];
   }
   ArrayResize(sKey, n - 1);
   ArrayResize(sSide, n - 1);
   ArrayResize(sTrigger, n - 1);
   ArrayResize(sBe, n - 1);
   ArrayResize(sCount, n - 1);
   ArrayResize(sCreated, n - 1);
   ArrayResize(sTickets, n - 1);
}

// Saved to disk so changing Inputs (which restarts the EA) keeps breakeven tracking.
void SaveState(const int i)
{
   string body = "side=" + IntegerToString(sSide[i]) + "\n" +
                 "trigger=" + DoubleToString(sTrigger[i], _Digits) + "\n" +
                 "be=" + (sBe[i] ? "1" : "0") + "\n";
   for(int k = 0; k < sCount[i]; k++)
      body += "ticket=" + IntegerToString((long)sTickets[i][k]) + "\n";
   WriteTextFile(STATE_DIR + sKey[i] + ".txt", body, true);
}

void LoadStates()
{
   string names[];
   string name;
   long h = FileFindFirst(STATE_DIR + "*.txt", name, FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   do
   {
      int n = ArraySize(names);
      ArrayResize(names, n + 1);
      names[n] = name;
   }
   while(FileFindNext(h, name));
   FileFindClose(h);

   for(int f = 0; f < ArraySize(names); f++)
   {
      string lines[];
      if(!ReadLines(STATE_DIR + names[f], lines))
         continue;
      string key = StringSubstr(names[f], 0, StringLen(names[f]) - 4);
      int side = 0;
      double trigger = 0.0;
      bool be = false;
      int i = AddState(key, 0, 0.0, false);
      for(int l = 0; l < ArraySize(lines); l++)
      {
         string k, v;
         if(!SplitKV(lines[l], k, v))
            continue;
         if(k == "side")
            side = (int)StringToInteger(v);
         else if(k == "trigger")
            trigger = StringToDouble(v);
         else if(k == "be")
            be = (v == "1");
         else if(k == "ticket")
            AddTicket(i, (ulong)StringToInteger(v));
      }
      sSide[i] = side;
      sTrigger[i] = trigger;
      sBe[i] = be;
   }
}

void CleanupStates()
{
   for(int i = ArraySize(sKey) - 1; i >= 0; i--)
   {
      if(TimeCurrent() - sCreated[i] < STATE_GRACE_SEC)
         continue;
      bool alive = false;
      for(int k = 0; k < sCount[i] && !alive; k++)
      {
         ulong id = sTickets[i][k];
         if(OrderSelect(id) || SelectPositionById(id))
            alive = true;
      }
      if(alive)
         continue;
      FileDelete(STATE_DIR + sKey[i] + ".txt", FILE_COMMON);
      RemoveState(i);
   }
}

// ---------------------------------------------------------------- Orders from Python

void ProcessCommands()
{
   string names[];
   string name;
   long h = FileFindFirst(CMD_DIR + "*.txt", name, FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   do
   {
      int n = ArraySize(names);
      ArrayResize(names, n + 1);
      names[n] = name;
   }
   while(FileFindNext(h, name));
   FileFindClose(h);
   for(int i = 0; i < ArraySize(names); i++)
      HandleCommand(names[i]);
}

void HandleCommand(const string name)
{
   string path = CMD_DIR + name;
   string lines[];
   if(!ReadLines(path, lines))
      return;
   // Delete first: a command is acted on at most once, even if opening fails.
   FileDelete(path, FILE_COMMON);

   string key = "", side = "", entryType = "market";
   int slot = 0;
   double entry = 0.0, sl = 0.0, trigger = 0.0;
   long receivedAt = 0;
   int legIdx[];
   double legTp[];
   for(int i = 0; i < ArraySize(lines); i++)
   {
      string k, v;
      if(!SplitKV(lines[i], k, v))
         continue;
      if(k == "key")
         key = v;
      else if(k == "slot")
         slot = (int)StringToInteger(v);
      else if(k == "side")
         side = v;
      else if(k == "entry_type")
         entryType = v;
      else if(k == "entry")
         entry = StringToDouble(v);
      else if(k == "sl")
         sl = StringToDouble(v);
      else if(k == "trigger")
         trigger = StringToDouble(v);
      else if(k == "received_at")
         receivedAt = StringToInteger(v);
      else if(k == "leg")
      {
         string parts[];
         if(StringSplit(v, '|', parts) == 2)
         {
            int n = ArraySize(legTp);
            ArrayResize(legIdx, n + 1);
            ArrayResize(legTp, n + 1);
            legIdx[n] = (int)StringToInteger(parts[0]);
            legTp[n] = StringToDouble(parts[1]);
         }
      }
   }

   bool isBuy = (side == "BUY");
   if(key == "" || slot < 1 || slot > SLOTS || (side != "BUY" && side != "SELL") ||
      sl <= 0.0 || ArraySize(legTp) == 0)
   {
      PrintFormat("Rejected %s: incomplete order file", name);
      return;
   }
   if(InWeekendBlock())
   {
      PrintFormat("Skip %s: weekend block (Friday close until Monday 00:00 Israel)", key);
      return;
   }
   if(!SlotTrade(slot))
   {
      PrintFormat("Skip %s: Trade is off for slot %d", key, slot);
      return;
   }
   if(receivedAt > 0 && (long)TimeGMT() - receivedAt > InpMaxSignalAgeSec)
   {
      PrintFormat("Skip %s: signal is %d seconds old", key, (int)((long)TimeGMT() - receivedAt));
      return;
   }
   if(StateIndex(key) >= 0)
   {
      PrintFormat("Skip %s: already opened", key);
      return;
   }
   if((isBuy && sl >= entry) || (!isBuy && sl <= entry))
   {
      PrintFormat("Rejected %s: SL %.2f is on the wrong side of entry %.2f", key, sl, entry);
      return;
   }

   double volume = NormalizeVolume(_Symbol, SlotLot(slot));
   if(InpDryRun)
   {
      PrintFormat("DRY RUN %s slot=%d %s %s legs=%d lot=%.2f entry=%.2f sl=%.2f breakeven-at=%.2f",
                  key, slot, side, entryType, ArraySize(legTp), volume, entry, sl, trigger);
      return;
   }

   trade.SetExpertMagicNumber(MAGIC_BASE + slot);
   int i = AddState(key, isBuy ? 1 : -1, trigger, false);
   for(int l = 0; l < ArraySize(legTp); l++)
   {
      string comment = "GT" + key + "-TP" + IntegerToString(legIdx[l]);
      ulong ticket = OpenLeg(isBuy, entryType, volume, entry, sl, legTp[l], comment);
      if(ticket > 0)
         AddTicket(i, ticket);
   }
   if(sCount[i] == 0)
   {
      PrintFormat("Open FAILED for every leg of %s", key);
      RemoveState(i);
      return;
   }
   SaveState(i);
   PrintFormat("Opened %s: %d/%d legs, lot=%.2f, breakeven-at=%.2f",
               key, sCount[i], ArraySize(legTp), volume, trigger);
}

// Limit when the price has not reached entry yet; otherwise the market is already at or
// better than entry, so a market order fills where the limit would.
ulong OpenLeg(const bool isBuy, const string entryType, const double volume,
              const double entry, const double sl, const double tp, const string comment)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slN = NormalizeDouble(sl, _Digits);
   double tpN = NormalizeDouble(tp, _Digits);
   double entryN = NormalizeDouble(entry, _Digits);
   bool ok;
   if(entryType == "limit" && isBuy && ask > entryN)
      ok = trade.BuyLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(entryType == "limit" && !isBuy && bid < entryN)
      ok = trade.SellLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(isBuy)
      ok = trade.Buy(volume, _Symbol, 0.0, slN, tpN, comment);
   else
      ok = trade.Sell(volume, _Symbol, 0.0, slN, tpN, comment);
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("Open FAILED %s: %u %s", comment, rc, trade.ResultRetcodeDescription());
      return 0;
   }
   return trade.ResultOrder();
}

// ---------------------------------------------------------------- Breakeven

bool ClosedAtTpBeyond(const ulong id, const int side, const double trigger)
{
   if(OrderSelect(id) || SelectPositionById(id))
      return false;
   if(!HistorySelectByPosition(id))
      return false;
   double eps = _Point * 2;
   for(int d = HistoryDealsTotal() - 1; d >= 0; d--)
   {
      ulong deal = HistoryDealGetTicket(d);
      if(deal == 0)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_REASON) != DEAL_REASON_TP)
         continue;
      double price = HistoryDealGetDouble(deal, DEAL_PRICE);
      if(side > 0 && price >= trigger - eps)
         return true;
      if(side < 0 && price <= trigger + eps)
         return true;
   }
   return false;
}

bool TriggerTouched(const int i)
{
   if(sTrigger[i] <= 0.0 || sSide[i] == 0)
      return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(sSide[i] > 0 && bid > 0.0 && bid >= sTrigger[i])
      return true;
   if(sSide[i] < 0 && ask > 0.0 && ask <= sTrigger[i])
      return true;
   for(int k = 0; k < sCount[i]; k++)
      if(ClosedAtTpBeyond(sTickets[i][k], sSide[i], sTrigger[i]))
         return true;
   return false;
}

void ApplyBreakeven(const int i)
{
   for(int k = 0; k < sCount[i]; k++)
   {
      ulong id = sTickets[i][k];
      if(OrderSelect(id))
      {
         // Target already reached before this limit filled: drop it.
         if(trade.OrderDelete(id))
            PrintFormat("Breakeven %s: deleted unfilled order %I64u", sKey[i], id);
         continue;
      }
      if(!SelectPositionById(id))
         continue;
      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double open = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(sl > 0.0 && ((isBuy && sl >= open) || (!isBuy && sl <= open)))
         continue;
      if(!CanPlaceStop(isBuy, open))
      {
         ClosePosition(ticket, "breakeven: price is back at entry");
         continue;
      }
      if(trade.PositionModify(ticket, open, tp))
         PrintFormat("Breakeven %s: ticket=%I64u SL moved to entry %.2f", sKey[i], ticket, open);
      else
         ClosePosition(ticket, "breakeven: SL modify failed");
   }
}

void ManageBreakeven()
{
   for(int i = 0; i < ArraySize(sKey); i++)
   {
      if(sBe[i])
      {
         // Retry deleting any limit that could not be removed on the first pass.
         for(int k = 0; k < sCount[i]; k++)
            if(OrderSelect(sTickets[i][k]))
               trade.OrderDelete(sTickets[i][k]);
         continue;
      }
      if(!TriggerTouched(i))
         continue;
      PrintFormat("Breakeven trigger %.2f touched for %s", sTrigger[i], sKey[i]);
      ApplyBreakeven(i);
      sBe[i] = true;
      SaveState(i);
   }
}

// ---------------------------------------------------------------- 50-pip guard

// Runs on every position of this EA, whatever opened it, even in dry run.
void SafetyGuard()
{
   double dist = InpSafetyPips * InpPipSize;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl > 0.0 && tp > 0.0)
         continue;
      if(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME) < InpSafetyDelaySec)
         continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double newSl = sl > 0.0 ? sl : NormalizeDouble(isBuy ? open - dist : open + dist, _Digits);
      double newTp = tp > 0.0 ? tp : NormalizeDouble(isBuy ? open + dist : open - dist, _Digits);
      if(sl <= 0.0 && !CanPlaceStop(isBuy, newSl))
      {
         ClosePosition(ticket, "safety: price already past the 50-pip stop");
         continue;
      }
      if(trade.PositionModify(ticket, newSl, newTp))
         PrintFormat("Safety: ticket=%I64u had no SL/TP, set SL=%.2f TP=%.2f", ticket, newSl, newTp);
      else if(TimeCurrent() - lastGuardLog >= 10)
      {
         lastGuardLog = TimeCurrent();
         PrintFormat("Safety modify FAILED ticket=%I64u: %u %s — retrying", ticket,
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

// ---------------------------------------------------------------- Friday close

void WeekendClose()
{
   if(!InWeekendBlock())
      return;
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(trade.PositionClose(ticket, InpDeviation))
         closed++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         continue;
      if(trade.OrderDelete(ticket))
         closed++;
   }
   if(closed > 0 || TimeCurrent() - lastWeekendLog >= 600)
   {
      lastWeekendLog = TimeCurrent();
      PrintFormat("Weekend block: closed/deleted %d, no new trades until Monday 00:00 Israel", closed);
   }
}

// ---------------------------------------------------------------- Display

int OurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         n++;
   }
   return n;
}

string OnOff(const bool value)
{
   return value ? "ON" : "off";
}

string SlotStatus(const int slot, const string label, const bool on, const double lot, const int strategy)
{
   return IntegerToString(slot) + " " + label + "  " + OnOff(on) +
          "  lot " + DoubleToString(lot, 2) +
          "  S" + IntegerToString(ClampStrategy(strategy)) + "\n";
}

void ShowStatus()
{
   Comment(
      "Gold Trading — Chart Executor  [", (InpDryRun ? "DRY RUN" : "LIVE"), "]\n",
      "Israel ", TimeToString(IsraelNow(), TIME_DATE|TIME_MINUTES),
      (InWeekendBlock() ? "  WEEKEND BLOCK" : ""), "\n",
      SlotStatus(1, "VIP   ", InpTrade1, InpLot1, InpStrat1),
      SlotStatus(2, "Pips  ", InpTrade2, InpLot2, InpStrat2),
      SlotStatus(3, "Kings ", InpTrade3, InpLot3, InpStrat3),
      SlotStatus(4, "Sniper", InpTrade4, InpLot4, InpStrat4),
      SlotStatus(5, "Samder", InpTrade5, InpLot5, InpStrat5),
      SlotStatus(6, "Bullet", InpTrade6, InpLot6, InpStrat6),
      "open ", IntegerToString(OurPositions()), "  tracked ", IntegerToString(ArraySize(sKey)),
      "  guard ", IntegerToString(InpSafetyPips), " pips"
   );
}
