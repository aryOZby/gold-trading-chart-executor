#property copyright "Gold Trading"
#property version   "3.20"
#property description "Chart Executor: reads listener signals, strategies 1-5, breakeven, 50-pip guard, Friday close"

#include <Trade/Trade.mqh>

input bool   InpTrade1 = false; // Trade VIP SIGNALS ROOM
input double InpLot1   = 0.01;  // Lot VIP SIGNALS ROOM
input int    InpStrat1 = 1;     // Strategy VIP SIGNALS ROOM (1-5)
input long   InpChat1  = -1002001216034; // Chat id VIP SIGNALS ROOM
input int    InpMax1   = 0;     // Max open trades VIP SIGNALS ROOM (0 = unlimited)

input bool   InpTrade2 = false; // Trade Technical Pips
input double InpLot2   = 0.01;  // Lot Technical Pips
input int    InpStrat2 = 1;     // Strategy Technical Pips (1-5)
input long   InpChat2  = -1001569906975; // Chat id Technical Pips
input int    InpMax2   = 0;     // Max open trades Technical Pips (0 = unlimited)

input bool   InpTrade3 = false; // Trade profit__kings
input double InpLot3   = 0.01;  // Lot profit__kings
input int    InpStrat3 = 2;     // Strategy profit__kings (1-5)
input long   InpChat3  = -1002984909577; // Chat id profit__kings
input int    InpMax3   = 0;     // Max open trades profit__kings (0 = unlimited)

input bool   InpTrade4 = false; // Trade GOLD SNIPER
input double InpLot4   = 0.01;  // Lot GOLD SNIPER
input int    InpStrat4 = 3;     // Strategy GOLD SNIPER (1-5)
input long   InpChat4  = -1001754381715; // Chat id GOLD SNIPER
input int    InpMax4   = 0;     // Max open trades GOLD SNIPER (0 = unlimited)

input bool   InpTrade5 = false; // Trade Trade With Samder
input double InpLot5   = 0.01;  // Lot Trade With Samder
input int    InpStrat5 = 1;     // Strategy Trade With Samder (1-5)
input long   InpChat5  = -1002366136201; // Chat id Trade With Samder
input int    InpMax5   = 0;     // Max open trades Trade With Samder (0 = unlimited)

input bool   InpTrade6 = false; // Trade GOLD BULLET SIGNALS
input double InpLot6   = 0.01;  // Lot GOLD BULLET SIGNALS
input int    InpStrat6 = 1;     // Strategy GOLD BULLET SIGNALS (1-5)
input long   InpChat6  = -1003186082440; // Chat id GOLD BULLET SIGNALS
input int    InpMax6   = 0;     // Max open trades GOLD BULLET SIGNALS (0 = unlimited)

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
#define SIG_DIR    "gt_signals\\"
#define DONE_DIR   "gt_signals\\done\\"
#define SKIP_DIR   "gt_signals\\skipped\\"
#define STATE_DIR  "gt_state\\"
#define COUNT_DIR  "gt_count\\"
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

int SlotStrategy(const int slot)
{
   switch(slot)
   {
      case 1: return InpStrat1;
      case 2: return InpStrat2;
      case 3: return InpStrat3;
      case 4: return InpStrat4;
      case 5: return InpStrat5;
      case 6: return InpStrat6;
   }
   return 0;
}

long SlotChat(const int slot)
{
   switch(slot)
   {
      case 1: return InpChat1;
      case 2: return InpChat2;
      case 3: return InpChat3;
      case 4: return InpChat4;
      case 5: return InpChat5;
      case 6: return InpChat6;
   }
   return 0;
}

int SlotMax(const int slot)
{
   switch(slot)
   {
      case 1: return InpMax1;
      case 2: return InpMax2;
      case 3: return InpMax3;
      case 4: return InpMax4;
      case 5: return InpMax5;
      case 6: return InpMax6;
   }
   return 0;
}

int SlotForChat(const long chatId)
{
   for(int slot = 1; slot <= SLOTS; slot++)
      if(SlotChat(slot) == chatId)
         return slot;
   return 0;
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
   FolderCreate("gt_signals", FILE_COMMON);
   FolderCreate("gt_signals\\done", FILE_COMMON);
   FolderCreate("gt_signals\\skipped", FILE_COMMON);
   FolderCreate("gt_state", FILE_COMMON);
   FolderCreate("gt_count", FILE_COMMON);
   LoadStates();
   if(!EventSetMillisecondTimer(InpTimerMs))
      EventSetTimer(1);
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
   WeekendClose();
   ProcessSignals();
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

bool StateAlive(const int i)
{
   for(int k = 0; k < sCount[i]; k++)
   {
      ulong id = sTickets[i][k];
      if(OrderSelect(id) || SelectPositionById(id))
         return true;
   }
   return false;
}

void CleanupStates()
{
   for(int i = ArraySize(sKey) - 1; i >= 0; i--)
   {
      if(TimeCurrent() - sCreated[i] < STATE_GRACE_SEC)
         continue;
      if(StateAlive(i))
         continue;
      FileDelete(STATE_DIR + sKey[i] + ".txt", FILE_COMMON);
      RemoveState(i);
   }
}

// A trade is one signal: it counts while any of its positions or pending orders is open.
int OpenTrades(const int slot)
{
   string prefix = IntegerToString(slot) + "-";
   int n = 0;
   for(int i = 0; i < ArraySize(sKey); i++)
      if(StringFind(sKey[i], prefix) == 0 && StateAlive(i))
         n++;
   return n;
}

// ---------------------------------------------------------------- Monthly trade number

// Per group, per Israel calendar month: the first trade of the month is N1.
string CounterFile(const int slot)
{
   MqlDateTime t;
   TimeToStruct(IsraelNow(), t);
   return COUNT_DIR + StringFormat("G%d_%04d%02d.txt", slot, t.year, t.mon);
}

int LastTradeNumber(const int slot)
{
   string lines[];
   if(!ReadLines(CounterFile(slot), lines) || ArraySize(lines) == 0)
      return 0;
   return (int)StringToInteger(lines[0]);
}

void SaveTradeNumber(const int slot, const int number)
{
   WriteTextFile(CounterFile(slot), IntegerToString(number) + "\n", true);
}

// ---------------------------------------------------------------- Strategies 1-5

// entry: 0 market, 1 limit at the first header price (market when price is already past it),
//        2 always a pending order at the first header price.
// take: 0 every TP row, 1 last <count> rows, 2 <count> rows farthest from the zone middle.
// be: 0 first TP row, 1 the <beIdx>-th TP row from the end. All legs share the signal SL.
bool GetStrategy(const int id, int &entry, int &take, int &count, int &be, int &beIdx)
{
   switch(id)
   {
      case 1: entry = 0; take = 1; count = 3; be = 1; beIdx = 3; return true; // #XAUUSD SELL 4315-4318
      case 2: entry = 1; take = 0; count = 0; be = 0; beIdx = 1; return true; // XAUUSD SELL PLAN @4365_4368
      case 3: entry = 2; take = 2; count = 2; be = 1; beIdx = 2; return true; // XAUUSD SELL 4083 / MORE SELL
      case 4: entry = 0; take = 1; count = 3; be = 1; beIdx = 3; return true; // GOLD SELL 4146/4150
      case 5: entry = 0; take = 1; count = 3; be = 1; beIdx = 3; return true; // double #XAUUSD header
   }
   return false;
}

double TpDistance(const double &tps[], const int row, const bool isBuy, const double mid)
{
   return isBuy ? tps[row - 1] - mid : mid - tps[row - 1];
}

// Fills chosen[] with 1-based TP rows and returns the breakeven TP row.
int PlanLegs(const double &tps[], const bool isBuy, const double mid, const int take,
             const int count, const int be, const int beIdx, int &chosen[])
{
   int n = ArraySize(tps);
   ArrayResize(chosen, 0);
   if(n == 0)
      return 0;
   int k = (count > 0 && count < n) ? count : n;
   if(take == 0)
   {
      ArrayResize(chosen, n);
      for(int i = 0; i < n; i++)
         chosen[i] = i + 1;
   }
   else if(take == 1)
   {
      ArrayResize(chosen, k);
      for(int i = 0; i < k; i++)
         chosen[i] = n - k + 1 + i;
   }
   else
   {
      int order[];
      ArrayResize(order, n);
      for(int i = 0; i < n; i++)
         order[i] = i + 1;
      // Farthest first; on equal distance the later row wins.
      for(int i = 0; i < n - 1; i++)
         for(int j = i + 1; j < n; j++)
         {
            double dj = TpDistance(tps, order[j], isBuy, mid);
            double di = TpDistance(tps, order[i], isBuy, mid);
            if(dj > di || (dj == di && order[j] > order[i]))
            {
               int tmp = order[i];
               order[i] = order[j];
               order[j] = tmp;
            }
         }
      ArrayResize(chosen, k);
      for(int i = 0; i < k; i++)
         chosen[i] = order[i];
      ArraySort(chosen);
   }
   if(be == 0 || beIdx <= 0 || beIdx > n)
      return 1;
   return n - beIdx + 1;
}

// ---------------------------------------------------------------- Signals from the listener

string ReadAll(const string path)
{
   int h = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ, 0, CP_UTF8);
   if(h == INVALID_HANDLE)
      return "";
   string text = "";
   while(!FileIsEnding(h))
      text += FileReadString(h) + "\n";
   FileClose(h);
   return text;
}

bool IsBlank(const ushort c)
{
   return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

// Minimal reader for the listener's flat JSON: first occurrence of "key", as raw text.
// Strings come back without quotes, arrays without brackets.
string JsonValue(const string &js, const string key)
{
   int pos = StringFind(js, "\"" + key + "\"");
   if(pos < 0)
      return "";
   pos = StringFind(js, ":", pos);
   if(pos < 0)
      return "";
   int len = StringLen(js);
   pos++;
   while(pos < len && IsBlank(StringGetCharacter(js, pos)))
      pos++;
   if(pos >= len)
      return "";
   ushort c = StringGetCharacter(js, pos);
   int end;
   if(c == '"')
   {
      end = StringFind(js, "\"", pos + 1);
      return end < 0 ? "" : StringSubstr(js, pos + 1, end - pos - 1);
   }
   if(c == '[')
   {
      end = StringFind(js, "]", pos);
      return end < 0 ? "" : StringSubstr(js, pos + 1, end - pos - 1);
   }
   end = pos;
   while(end < len)
   {
      ushort d = StringGetCharacter(js, end);
      if(d == ',' || d == '}' || d == '\n' || d == '\r')
         break;
      end++;
   }
   string v = StringSubstr(js, pos, end - pos);
   StringTrimLeft(v);
   StringTrimRight(v);
   return v;
}

// "2026-11-05T13:16:19.699123+00:00" -> GMT seconds.
long ParseIsoUtc(const string iso)
{
   if(StringLen(iso) < 19)
      return 0;
   string s = StringSubstr(iso, 0, 19);
   StringReplace(s, "T", " ");
   StringReplace(s, "-", ".");
   long t = (long)StringToTime(s);
   int len = StringLen(iso);
   for(int i = 19; i < len; i++)
   {
      ushort c = StringGetCharacter(iso, i);
      if(c != '+' && c != '-')
         continue;
      if(len >= i + 6)
      {
         int sign = (c == '-') ? -1 : 1;
         int hh = (int)StringToInteger(StringSubstr(iso, i + 1, 2));
         int mm = (int)StringToInteger(StringSubstr(iso, i + 4, 2));
         t -= sign * (hh * 3600 + mm * 60);
      }
      break;
   }
   return t;
}

void Archive(const string name, const string dir)
{
   if(!FileMove(SIG_DIR + name, FILE_COMMON, dir + name, FILE_COMMON|FILE_REWRITE))
      FileDelete(SIG_DIR + name, FILE_COMMON);
}

void ProcessSignals()
{
   string names[];
   string name;
   long h = FileFindFirst(SIG_DIR + "*.json", name, FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   do
   {
      if(StringFind(name, ".tmp") >= 0)
         continue;
      int n = ArraySize(names);
      ArrayResize(names, n + 1);
      names[n] = name;
   }
   while(FileFindNext(h, name));
   FileFindClose(h);
   for(int i = 0; i < ArraySize(names); i++)
      HandleSignal(names[i]);
}

void Skip(const string name, const string why)
{
   PrintFormat("Skip %s: %s", name, why);
   Archive(name, SKIP_DIR);
}

void HandleSignal(const string name)
{
   string path = SIG_DIR + name;
   if(FileIsExist(DONE_DIR + name, FILE_COMMON) || FileIsExist(SKIP_DIR + name, FILE_COMMON))
   {
      PrintFormat("Duplicate %s already handled — discarded", name);
      FileDelete(path, FILE_COMMON);
      return;
   }
   string js = ReadAll(path);
   if(StringLen(js) == 0)
      return;

   // File name is <chat_id>_<message_id>.json
   string base = StringSubstr(name, 0, StringLen(name) - 5);
   int us = -1;
   for(int i = StringLen(base) - 1; i >= 0; i--)
      if(StringGetCharacter(base, i) == '_')
      {
         us = i;
         break;
      }
   if(us <= 0)
   {
      Skip(name, "file name is not <chat_id>_<message_id>.json");
      return;
   }
   long chatId = StringToInteger(StringSubstr(base, 0, us));
   string msgId = StringSubstr(base, us + 1);
   string title = JsonValue(js, "title");
   string side = JsonValue(js, "side");
   double entry = StringToDouble(JsonValue(js, "entry"));
   double zoneLow = StringToDouble(JsonValue(js, "zone_low"));
   double zoneHigh = StringToDouble(JsonValue(js, "zone_high"));
   double sl = StringToDouble(JsonValue(js, "sl"));
   long receivedAt = ParseIsoUtc(JsonValue(js, "received_at"));
   double tps[];
   string parts[];
   int np = StringSplit(JsonValue(js, "tps"), ',', parts);
   for(int i = 0; i < np; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0)
         continue;
      int n = ArraySize(tps);
      ArrayResize(tps, n + 1);
      tps[n] = StringToDouble(p);
   }
   if(entry <= 0.0)
      entry = zoneLow;
   if(zoneHigh <= 0.0)
      zoneHigh = zoneLow;

   int slot = SlotForChat(chatId);
   if(slot == 0)
   {
      Skip(name, "chat " + IntegerToString(chatId) + " is not in any slot");
      return;
   }
   string key = IntegerToString(slot) + "-" + msgId;
   string who = title + " | slot " + IntegerToString(slot);
   bool isBuy = (side == "BUY");
   if((side != "BUY" && side != "SELL") || sl <= 0.0 || entry <= 0.0 || ArraySize(tps) == 0)
   {
      Skip(name, "incomplete signal from " + who);
      return;
   }
   if(InWeekendBlock())
   {
      Skip(name, "weekend block (Friday close until Monday 00:00 Israel)");
      return;
   }
   if(!SlotTrade(slot))
   {
      Skip(name, "Trade is off for " + who);
      return;
   }
   if(receivedAt > 0 && (long)TimeGMT() - receivedAt > InpMaxSignalAgeSec)
   {
      Skip(name, "signal from " + who + " is " +
           IntegerToString((long)TimeGMT() - receivedAt) + " seconds old");
      return;
   }
   if(StateIndex(key) >= 0)
   {
      Skip(name, "already opened");
      return;
   }
   int maxOpen = SlotMax(slot);
   if(maxOpen > 0)
   {
      int running = OpenTrades(slot);
      if(running >= maxOpen)
      {
         Skip(name, StringFormat("%s already has %d open trades (max %d)", who, running, maxOpen));
         return;
      }
   }
   if((isBuy && sl >= entry) || (!isBuy && sl <= entry))
   {
      Skip(name, StringFormat("SL %.2f is on the wrong side of entry %.2f", sl, entry));
      return;
   }
   int strategy = SlotStrategy(slot);
   int sEntry, sTake, sCountN, sBeMode, sBeIdx;
   if(!GetStrategy(strategy, sEntry, sTake, sCountN, sBeMode, sBeIdx))
   {
      Skip(name, "unknown strategy " + IntegerToString(strategy) + " for " + who);
      return;
   }
   int rows[];
   int beRow = PlanLegs(tps, isBuy, (zoneLow + zoneHigh) / 2.0, sTake, sCountN, sBeMode, sBeIdx, rows);
   double trigger = tps[beRow - 1];
   string entryType = (sEntry == 2) ? "pending" : (sEntry == 1) ? "limit" : "market";
   double volume = NormalizeVolume(_Symbol, SlotLot(slot));

   int number = LastTradeNumber(slot) + 1;
   // Reads left to right as strategy, group, monthly trade number; each leg adds its TP row.
   string comment = StringFormat("S%d|G%d|N%d", strategy, slot, number);
   string plan = "";
   for(int l = 0; l < ArraySize(rows); l++)
      plan += StringFormat(" TP%d=%.2f", rows[l], tps[rows[l] - 1]);
   PrintFormat("%s [%s] %s from %s: %s %s lot=%.2f entry=%.2f sl=%.2f breakeven-at=%.2f |%s",
               (InpDryRun ? "DRY RUN" : "Signal"), comment, key, who, side, entryType,
               volume, entry, sl, trigger, plan);
   if(InpDryRun)
   {
      Archive(name, DONE_DIR);
      return;
   }

   trade.SetExpertMagicNumber(MAGIC_BASE + slot);
   int st = AddState(key, isBuy ? 1 : -1, trigger, false);
   for(int l = 0; l < ArraySize(rows); l++)
   {
      string legComment = comment + "|tp" + IntegerToString(rows[l]);
      ulong ticket = OpenLeg(isBuy, entryType, volume, entry, sl, tps[rows[l] - 1], legComment);
      if(ticket > 0)
         AddTicket(st, ticket);
   }
   // Acted on once, even when the broker refused: a retry would open late.
   Archive(name, DONE_DIR);
   if(sCount[st] == 0)
   {
      PrintFormat("Open FAILED for every leg of %s [%s]", key, comment);
      RemoveState(st);
      return;
   }
   SaveTradeNumber(slot, number);
   SaveState(st);
   PrintFormat("Opened [%s] %s: %d/%d legs, lot=%.2f, breakeven-at=%.2f",
               comment, key, sCount[st], ArraySize(rows), volume, trigger);
}

// "limit": a limit when price has not reached entry yet, otherwise market, since the market is
// already at or better than entry.
ulong OpenLeg(const bool isBuy, const string entryType, const double volume,
              const double entry, const double sl, const double tp, const string comment)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slN = NormalizeDouble(sl, _Digits);
   double tpN = NormalizeDouble(tp, _Digits);
   double entryN = NormalizeDouble(entry, _Digits);
   bool ok;
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double now = isBuy ? ask : bid;
   // "pending" always waits at the signal price: limit from the losing side, stop from the
   // better side. Only a price already within the broker's minimum distance fills at market.
   bool pending = (entryType == "pending" && MathAbs(now - entryN) > MathMax(minDist, _Point / 2));
   if(entryType == "limit" && isBuy && ask > entryN)
      ok = trade.BuyLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(entryType == "limit" && !isBuy && bid < entryN)
      ok = trade.SellLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(pending && isBuy && ask > entryN)
      ok = trade.BuyLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(pending && isBuy)
      ok = trade.BuyStop(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(pending && bid < entryN)
      ok = trade.SellLimit(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
   else if(pending)
      ok = trade.SellStop(volume, entryN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, comment);
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
   int maxOpen = SlotMax(slot);
   return "G" + IntegerToString(slot) + " " + label + "  " + OnOff(on) +
          "  lot " + DoubleToString(lot, 2) +
          "  S" + IntegerToString(ClampStrategy(strategy)) +
          "  open " + IntegerToString(OpenTrades(slot)) + "/" +
          (maxOpen > 0 ? IntegerToString(maxOpen) : "unlimited") +
          "  next N" + IntegerToString(LastTradeNumber(slot) + 1) + "\n";
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
