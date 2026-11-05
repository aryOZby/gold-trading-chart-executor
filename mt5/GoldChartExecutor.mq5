#property copyright "Gold Trading"
#property version   "1.00"
#property description "Chart Inputs: Trade / Lot / Strategy 1-5 per Telegram group"

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

input int    InpTimerMs = 200;  // Timer ms

int OnInit()
{
   if(!EventSetMillisecondTimer(InpTimerMs))
      EventSetTimer(1);
   WriteChart();
   ShowStatus();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
}

void OnTimer()
{
   WriteChart();
   ShowStatus();
}

int ClampStrategy(const int value)
{
   if(value < 1)
      return 1;
   if(value > 5)
      return 5;
   return value;
}

string SlotLine(const int slot, const bool trade, const double lot, const int strategy)
{
   return IntegerToString(slot) + "=" +
          IntegerToString(trade ? 1 : 0) + "," +
          DoubleToString(lot, 4) + "," +
          IntegerToString(ClampStrategy(strategy));
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
   WriteTextFile("gs_chart.txt", body, false);
}

string OnOff(const bool value)
{
   return value ? "ON" : "off";
}

void ShowStatus()
{
   Comment(
      "Gold Trading — Chart Executor\n",
      "1 VIP        ", OnOff(InpTrade1), " lot ", DoubleToString(InpLot1, 2), " S", IntegerToString(ClampStrategy(InpStrat1)), "\n",
      "2 Pips       ", OnOff(InpTrade2), " lot ", DoubleToString(InpLot2, 2), " S", IntegerToString(ClampStrategy(InpStrat2)), "\n",
      "3 Kings      ", OnOff(InpTrade3), " lot ", DoubleToString(InpLot3, 2), " S", IntegerToString(ClampStrategy(InpStrat3)), "\n",
      "4 Sniper     ", OnOff(InpTrade4), " lot ", DoubleToString(InpLot4, 2), " S", IntegerToString(ClampStrategy(InpStrat4)), "\n",
      "5 Samder     ", OnOff(InpTrade5), " lot ", DoubleToString(InpLot5, 2), " S", IntegerToString(ClampStrategy(InpStrat5)), "\n",
      "6 Bullet     ", OnOff(InpTrade6), " lot ", DoubleToString(InpLot6, 2), " S", IntegerToString(ClampStrategy(InpStrat6))
   );
}
