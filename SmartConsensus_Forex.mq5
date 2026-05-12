//+------------------------------------------------------------------+
//|                                 SmartConsensus_Forex.mq5        |
//|                    Liquid Forex Optimized v1.0                   |
//+------------------------------------------------------------------+
#property copyright "Professional Trading System"
#property version   "1.14"
#property description "Liquid Forex Optimized - Signal Memory / Lookback Windows - Max Spread 60, ATR 100, SL 1.5x"

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES Timeframe_Trend  = PERIOD_H1;
input ENUM_TIMEFRAMES Timeframe_Entry = PERIOD_M15;

input group "=== Order Types ==="
input bool    Enable_Market_Orders     = true;
input bool    Enable_Limit_Orders      = true;
input bool    Enable_Stop_Orders       = true;
input bool    Enable_StopLimit_Orders = true;
input bool    Allow_Multiple_Entries_Per_Signal = false; // If false, only one order executes per signal
input int     Pending_Order_Expiry_Seconds = 43200;

input group "=== Risk Management (Exness Optimized - Research Based) ==="
input double  Risk_Percent         = 2.0;
input double  Reward_Risk_Ratio    = 3.0;
input int     Maximum_Spread_Points = 60;
input int     Slippage_Points      = 50;
input double  Maximum_Lot_Size     = 0.5;
input double  Min_Lot_Size         = 0.01;

input group "=== Trading Settings ==="
input int     Daily_Trade_Target    = 6;
input int     Minimum_Confirmations = 3;
input double  ATR_Filter_Min       = 100.0;
input int     Cooldown_Seconds       = 0;

input group "=== Fill Policy ==="
input ENUM_ORDER_TYPE_FILLING Fill_Policy = ORDER_FILLING_IOC;

input group "=== Trailing Stop (Forex Optimized) ==="
input bool    Enable_Trailing_Stop  = true;
input double  Trailing_Start_ATR    = 1.0;
input double  Trailing_Step_ATR      = 0.5;

input group "=== Indicators ==="
input int RSI_Period        = 14;
input int RSI_Overbought    = 65;
input int RSI_Oversold      = 35;
input int MACD_Fast_Period  = 12;
input int MACD_Slow_Period  = 26;
input int MACD_Signal_Period = 9;
input int ATR_Period        = 14;

input group "=== Debug Settings ==="
input bool Enable_Debug_Prints = false;

input group "=== Trading Control ==="
input bool Enable_Trading_Enabled = true;

input group "=== Named Constants ==="

const double SL_MULTIPLIER = 1.5;

const int LIQUIDITY_SWEEP_LOOKBACK     = 3;
const int FVG_VALID_BARS               = 4;
const int VOLUME_SPIKE_LOOKBACK        = 2;
const int RANGE_EXPANSION_LOOKBACK     = 2;
const int CONSOLIDATION_BREAK_LOOKBACK = 3;
const int MTF_ALIGNMENT_SCORE         = 1;
const int RSI_ZONE_OVERSOLD            = 35;
const int RSI_ZONE_OVERBOUGHT         = 65;
const bool ENABLE_DEBUG_PRINTS        = true;

double   Point_Value, Digits_Value;
int      Indicator_Handle_ATR_High, Indicator_Handle_ATR_Low;
int      Indicator_Handle_RSI, Indicator_Handle_MACD;
int      Indicator_Handle_MA_High_Fast, Indicator_Handle_MA_High_Slow;
int      Indicator_Handle_MA_Low_Fast, Indicator_Handle_MA_Low_Slow;
datetime Last_Analyzed_Bar = 0;
datetime Last_Trade_Time = 0;
datetime Day_Start_Time = 0;
int      Today_Trade_Count = 0;
string   GlobalPrefix = "SmartForex_";
const int Magic_Number = 20251202;
bool     Trading_Enabled = Enable_Trading_Enabled;

int    Last_Liquidity_Sweep_Bar = -1;
int    Last_FVG_Bar = -1;
int    Last_Consolidation_Break_Bar = -1;
bool   Multitimeframe_Aligned_Bull = false;
bool   Multitimeframe_Aligned_Bear = false;

struct Trade_Signal {
   int    Direction;
   double Entry_Price;
   double Stop_Loss;
   double Take_Profit;
   double ATR_Value;
};

void Initialize_Daily_Trades() {
   string GV_Day = GlobalPrefix + _Symbol + "_Day";
   string GV_Count = GlobalPrefix + _Symbol + "_TradeCount";
   
   MqlDateTime ct;
   TimeToStruct(TimeCurrent(), ct);
   int Current_Day = ct.day;
   
   int Saved_Day = (int)GlobalVariableGet(GV_Day);
   int Saved_Count = (int)GlobalVariableGet(GV_Count);
   
   if(Saved_Day == Current_Day) {
      Today_Trade_Count = Saved_Count;
      Day_Start_Time = TimeCurrent();
   } else {
      Today_Trade_Count = 0;
      Day_Start_Time = TimeCurrent();
      GlobalVariableSet(GV_Day, Current_Day);
      GlobalVariableSet(GV_Count, 0);
   }
}

void Save_Daily_Trades() {
   string GV_Count = GlobalPrefix + _Symbol + "_TradeCount";
   GlobalVariableSet(GV_Count, Today_Trade_Count);
}

int OnInit() {
   Point_Value  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Digits_Value = (double)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(Point_Value == 0) Point_Value = 0.00001;
   
   Indicator_Handle_ATR_High  = iATR(_Symbol, Timeframe_Trend, ATR_Period);
   Indicator_Handle_ATR_Low   = iATR(_Symbol, Timeframe_Entry, ATR_Period);
   Indicator_Handle_RSI       = iRSI(_Symbol, Timeframe_Entry, RSI_Period, PRICE_CLOSE);
   Indicator_Handle_MACD     = iMACD(_Symbol, Timeframe_Entry, MACD_Fast_Period, MACD_Slow_Period, MACD_Signal_Period, PRICE_CLOSE);
   Indicator_Handle_MA_High_Fast = iMA(_Symbol, Timeframe_Trend, 10, 0, MODE_SMA, PRICE_CLOSE);
   Indicator_Handle_MA_High_Slow = iMA(_Symbol, Timeframe_Trend, 20, 0, MODE_SMA, PRICE_CLOSE);
   Indicator_Handle_MA_Low_Fast = iMA(_Symbol, Timeframe_Entry, 10, 0, MODE_SMA, PRICE_CLOSE);
   Indicator_Handle_MA_Low_Slow = iMA(_Symbol, Timeframe_Entry, 20, 0, MODE_SMA, PRICE_CLOSE);
   
   if(Any_Handle_Invalid()) {
      Print("Initialization Failed - Invalid Indicator Handle");
      return INIT_FAILED;
   }
   
   Initialize_Daily_Trades();
   
   Print("=======================================================");
   Print("   SmartConsensus Forex v1.0 - Liquid Forex Optimized");
   Print("=======================================================");
   Print("Symbol: ", _Symbol);
   Print("Max Spread: ", Maximum_Spread_Points, " pts");
   Print("ATR Filter: ", ATR_Filter_Min, " pts");
   Print("SL Multiplier: ", SL_MULTIPLIER, "x ATR");
   Print("Max Lot Size: ", Maximum_Lot_Size);
   Print("Risk: ", Risk_Percent, "%");
   Print("Trailing: Start ", Trailing_Start_ATR, "x ATR, Step ", Trailing_Step_ATR, "x ATR");
   Print("=======================================================");
   
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

bool Any_Handle_Invalid() {
   return (Indicator_Handle_ATR_High == INVALID_HANDLE || Indicator_Handle_ATR_Low == INVALID_HANDLE ||
           Indicator_Handle_RSI == INVALID_HANDLE || Indicator_Handle_MACD == INVALID_HANDLE ||
           Indicator_Handle_MA_High_Fast == INVALID_HANDLE || Indicator_Handle_MA_High_Slow == INVALID_HANDLE ||
           Indicator_Handle_MA_Low_Fast == INVALID_HANDLE || Indicator_Handle_MA_Low_Slow == INVALID_HANDLE);
}

void OnDeinit(const int reason) {
   IndicatorRelease(Indicator_Handle_ATR_High); IndicatorRelease(Indicator_Handle_ATR_Low);
   IndicatorRelease(Indicator_Handle_RSI); IndicatorRelease(Indicator_Handle_MACD);
   IndicatorRelease(Indicator_Handle_MA_High_Fast); IndicatorRelease(Indicator_Handle_MA_High_Slow);
   IndicatorRelease(Indicator_Handle_MA_Low_Fast); IndicatorRelease(Indicator_Handle_MA_Low_Slow);
   EventKillTimer();
}

void OnTick() {
    static datetime Last_Settings_Check = 0;
    datetime Current_Time = TimeCurrent();
    
    if(Current_Time - Last_Settings_Check >= 1) {
       Last_Settings_Check = Current_Time;
       
       MqlDateTime ct, ds;
       TimeToStruct(Current_Time, ct);
       TimeToStruct(Day_Start_Time, ds);
       
       if(ct.day != ds.day) {
          Today_Trade_Count = 0;
          Day_Start_Time = Current_Time;
          GlobalVariableSet(GlobalPrefix + _Symbol + "_Day", ct.day);
          GlobalVariableSet(GlobalPrefix + _Symbol + "_TradeCount", 0);
       }
    }
    
    if(Enable_Trailing_Stop) Manage_Trailing_Stops();
    
    if(!Trading_Enabled) return;
    if(Today_Trade_Count >= Daily_Trade_Target) return;
    if(Cooldown_Seconds > 0 && Current_Time - Last_Trade_Time < Cooldown_Seconds) return;
    
    datetime Current_Bar = iTime(_Symbol, Timeframe_Entry, 0);
    if(Current_Bar == Last_Analyzed_Bar) return;
    Last_Analyzed_Bar = Current_Bar;
    Update_Multitimeframe_Alignment();
    
    double Current_Spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Point_Value;
    bool Spread_Too_High = (Current_Spread > Maximum_Spread_Points);
    if(Spread_Too_High) {
       Print("Spread Too High - Skipping order execution");
       return;
    }
    
    Trade_Signal Signal = Analyze_Market();
    if(Signal.Direction == 0) return;
    
    int Confirmation_Score = Calculate_Confirmation(Signal.Direction);
    if(Confirmation_Score < Minimum_Confirmations) return;
    
    if(Signal.ATR_Value < ATR_Filter_Min * Point_Value) return;
    
    Print("=== Signal Detected: ", Signal.Direction==1?"BUY":"SELL");
    Print("    Confirmation Score: ", Confirmation_Score, "/", Minimum_Confirmations);
    Print("    Entry: ", DoubleToString(Signal.Entry_Price, (int)Digits_Value));
    Print("    Stop Loss: ", DoubleToString(Signal.Stop_Loss, (int)Digits_Value));
    Print("    Take Profit: ", DoubleToString(Signal.Take_Profit, (int)Digits_Value));
    double Risk_Distance = MathAbs(Signal.Entry_Price - Signal.Stop_Loss);
    double Reward_Distance = MathAbs(Signal.Take_Profit - Signal.Entry_Price);
    double Actual_Ratio = Reward_Distance / Risk_Distance;
    Print("    Risk/Reward: 1:", DoubleToString(Actual_Ratio, 2), " (Target: 1:", Reward_Risk_Ratio, ")");
    Print("    ATR: ", DoubleToString(Signal.ATR_Value/Point_Value, 1), " points");
    Print("    Spread: ", DoubleToString(Current_Spread, 1), " pts");
    
    double Lot_Size = Calculate_Lot_Size(Signal.Entry_Price, Signal.Stop_Loss, Signal.ATR_Value);
    if(Lot_Size < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
    
    bool Order_Executed = false;
    string Execution_Type = "";
    
    if(Enable_Market_Orders && !Spread_Too_High) {
       if(Execute_Market_Order(Signal.Direction, Signal.Stop_Loss, Signal.Take_Profit, Lot_Size)) {
          Order_Executed = true;
          Execution_Type = "MARKET";
          Today_Trade_Count++;
          Save_Daily_Trades();
          Last_Trade_Time = Current_Time;
       }
    }
    
    if(!Order_Executed && Enable_Limit_Orders && !Spread_Too_High) {
       ENUM_ORDER_TYPE Order_Type = (Signal.Direction == 1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
       if(Execute_Pending_Order(Order_Type, Signal.Entry_Price, Signal.Entry_Price, Lot_Size, Signal.Direction, Signal.Stop_Loss, Signal.Take_Profit)) {
          Order_Executed = true;
          Execution_Type = "LIMIT";
          Today_Trade_Count++;
          Save_Daily_Trades();
          Last_Trade_Time = Current_Time;
       }
    }
    
    if(!Order_Executed && Enable_Stop_Orders && !Spread_Too_High) {
       ENUM_ORDER_TYPE Order_Type = (Signal.Direction == 1) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
       double Stop_Price = (Signal.Direction == 1) ? Signal.Entry_Price + Signal.ATR_Value * 0.2 : Signal.Entry_Price - Signal.ATR_Value * 0.2;
       if(Execute_Pending_Order(Order_Type, Stop_Price, Signal.Entry_Price, Lot_Size, Signal.Direction, Signal.Stop_Loss, Signal.Take_Profit)) {
          Order_Executed = true;
          Execution_Type = "STOP";
          Today_Trade_Count++;
          Save_Daily_Trades();
          Last_Trade_Time = Current_Time;
       }
    }
    
    if(!Order_Executed && Enable_StopLimit_Orders && !Spread_Too_High) {
       ENUM_ORDER_TYPE Order_Type = (Signal.Direction == 1) ? ORDER_TYPE_BUY_STOP_LIMIT : ORDER_TYPE_SELL_STOP_LIMIT;
       double Stop_Price = (Signal.Direction == 1) ? Signal.Entry_Price + Signal.ATR_Value * 0.3 : Signal.Entry_Price - Signal.ATR_Value * 0.3;
       double Limit_Price = (Signal.Direction == 1) ? Signal.Entry_Price + Signal.ATR_Value * 0.10 : Signal.Entry_Price - Signal.ATR_Value * 0.10;
       if(Execute_Pending_Order(Order_Type, Stop_Price, Limit_Price, Lot_Size, Signal.Direction, Signal.Stop_Loss, Signal.Take_Profit)) {
          Order_Executed = true;
          Execution_Type = "STOP_LIMIT";
          Today_Trade_Count++;
          Save_Daily_Trades();
          Last_Trade_Time = Current_Time;
       }
    }
    
    if(Order_Executed) {
       Print("=== Order Executed: ", Execution_Type);
       Print("    Today's Trades: ", Today_Trade_Count, "/", Daily_Trade_Target);
    }
}


void OnTimer() {
    MqlDateTime Current_Time_Struct, Day_Start_Time_Struct;
    datetime Current_Time = TimeCurrent();
    TimeToStruct(Current_Time, Current_Time_Struct);
    TimeToStruct(Day_Start_Time, Day_Start_Time_Struct);
    
    if(Current_Time_Struct.day != Day_Start_Time_Struct.day) {
       Today_Trade_Count = 0;
       Day_Start_Time = Current_Time;
       GlobalVariableSet(GlobalPrefix + _Symbol + "_Day", Current_Time_Struct.day);
       GlobalVariableSet(GlobalPrefix + _Symbol + "_TradeCount", 0);
    }
}


Trade_Signal Analyze_Market() {
   Trade_Signal Result;
   ZeroMemory(Result);
   
   double MA_Fast_Trend[], MA_Slow_Trend[];
   if(CopyBuffer(Indicator_Handle_MA_High_Fast, 0, 0, 1, MA_Fast_Trend) <= 0) return Result;
   if(CopyBuffer(Indicator_Handle_MA_High_Slow, 0, 0, 1, MA_Slow_Trend) <= 0) return Result;
   
    bool Uptrend = MA_Fast_Trend[0] > MA_Slow_Trend[0];
    bool Downtrend = MA_Fast_Trend[0] < MA_Slow_Trend[0];

    Result.ATR_Value = Get_ATR_Value(Timeframe_Entry, 0);
   double Minimum_Stop = Get_Minimum_Stop_Distance();
   
   double Swing_Low_M15 = iLow(_Symbol, Timeframe_Entry, iLowest(_Symbol, Timeframe_Entry, MODE_LOW, 20, 1));
   double Swing_High_M15 = iHigh(_Symbol, Timeframe_Entry, iHighest(_Symbol, Timeframe_Entry, MODE_HIGH, 20, 1));
   
   double ATR_Based_SL = Result.ATR_Value * SL_MULTIPLIER;
   double Minimum_SL_Distance = Result.ATR_Value * 0.8;
   
    if(Uptrend) {
       Result.Direction = 1;
       double Entry_Price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
       Result.Entry_Price = Entry_Price;
      
      double Structural_SL = Swing_Low_M15 - Minimum_Stop;
      double Volatility_SL = Entry_Price - ATR_Based_SL;
      
      if(Structural_SL > Volatility_SL) {
         Result.Stop_Loss = Structural_SL;
      } else {
         Result.Stop_Loss = Volatility_SL;
      }
      double Minimum_Acceptable_SL = Entry_Price - Minimum_SL_Distance;
      Result.Stop_Loss = MathMax(Result.Stop_Loss, Minimum_Acceptable_SL);
   }
    else if(Downtrend) {
       Result.Direction = -1;
       double Entry_Price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
       Result.Entry_Price = Entry_Price;
      
      double Structural_SL = Swing_High_M15 + Minimum_Stop;
      double Volatility_SL = Entry_Price + ATR_Based_SL;
      
      if(Structural_SL < Volatility_SL) {
         Result.Stop_Loss = Structural_SL;
      } else {
         Result.Stop_Loss = Volatility_SL;
      }
      double Minimum_Acceptable_SL = Entry_Price + Minimum_SL_Distance;
      Result.Stop_Loss = MathMin(Result.Stop_Loss, Minimum_Acceptable_SL);
   }
   
   double Actual_Risk = MathAbs(Result.Entry_Price - Result.Stop_Loss);
   Result.Take_Profit = Result.Entry_Price + (Actual_Risk * Reward_Risk_Ratio);
   if(Result.Direction == -1) {
      Result.Take_Profit = Result.Entry_Price - (Actual_Risk * Reward_Risk_Ratio);
   }
   double Actual_Reward = MathAbs(Result.Take_Profit - Result.Entry_Price);
   
   if(Actual_Reward < Actual_Risk * Reward_Risk_Ratio * 0.8) {
      Result.Direction = 0;
   }
   
   return Result;
}

int Calculate_Confirmation(int Direction) {
    int Score = 0;

    if(Is_Liquidity_Swept(Direction, LIQUIDITY_SWEEP_LOOKBACK)) Score++;
    if(Is_Fair_Value_Gap(Direction, FVG_VALID_BARS)) Score++;
    if(Is_Consolidation_Breakout(Direction, CONSOLIDATION_BREAK_LOOKBACK)) Score++;
    if(Is_Multitimeframe_Aligned(Direction)) Score += MTF_ALIGNMENT_SCORE;

    if((Direction == 1 && Is_Bullish_Candle()) || (Direction == -1 && Is_Bearish_Candle())) Score++;
    if(Is_Volume_Spike_Recent(VOLUME_SPIKE_LOOKBACK)) Score++;
    if(Is_Momentum_Confirmed_Loose(Direction)) Score++;
    if(Is_Range_Expansion_Recent(RANGE_EXPANSION_LOOKBACK)) Score++;

    if(ENABLE_DEBUG_PRINTS) {
        Print("=== Signal Memory Debug ===");
        Print("Liq Sweep (", LIQUIDITY_SWEEP_LOOKBACK, " bars): ", Is_Liquidity_Swept(Direction, LIQUIDITY_SWEEP_LOOKBACK),
              " | FVG (", FVG_VALID_BARS, " bars): ", Is_Fair_Value_Gap(Direction, FVG_VALID_BARS),
              " | Consolidation (", CONSOLIDATION_BREAK_LOOKBACK, " bars): ", Is_Consolidation_Breakout(Direction, CONSOLIDATION_BREAK_LOOKBACK),
              " | MTF: ", Is_Multitimeframe_Aligned(Direction));
        Print("Bullish Candle: ", (Direction==1?Is_Bullish_Candle():Is_Bearish_Candle()),
              " | Volume (", VOLUME_SPIKE_LOOKBACK, " bars): ", Is_Volume_Spike_Recent(VOLUME_SPIKE_LOOKBACK),
              " | Momentum: ", Is_Momentum_Confirmed_Loose(Direction),
              " | Range Exp (", RANGE_EXPANSION_LOOKBACK, " bars): ", Is_Range_Expansion_Recent(RANGE_EXPANSION_LOOKBACK));
        Print("Total Score: ", Score, " / ", Minimum_Confirmations, " required");
    }

    return Score;
}

double Calculate_Lot_Size(double Entry_Price, double Stop_Loss, double ATR) {
   double Account_Balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double Risk_Amount = Account_Balance * Risk_Percent / 100.0;
   double Stop_Distance = MathAbs(Entry_Price - Stop_Loss);
   
   double Min_Stop_Distance = ATR * 0.8;
   if(Stop_Distance < Min_Stop_Distance) Stop_Distance = Min_Stop_Distance;
   
   double Tick_Value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double Lot_Step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double Min_Lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(Min_Lot_Size > Min_Lot) Min_Lot = Min_Lot_Size;
   
   double Lot = Risk_Amount / (Stop_Distance * Tick_Value / Point_Value);
   if(Lot_Step > 0) Lot = MathFloor(Lot / Lot_Step) * Lot_Step;
   Lot = NormalizeDouble(MathMax(Lot, Min_Lot), 2);
   Lot = MathMin(Lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   Lot = MathMin(Lot, Maximum_Lot_Size);
   
   if(Lot < Min_Lot) return 0;
   return Lot;
}

double Get_Minimum_Stop_Distance() {
   long Stop_Level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long Freeze_Level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double Distance = MathMax((double)Stop_Level, (double)Freeze_Level) * Point_Value;
   return MathMax(Distance, Point_Value * 10);
}

double Get_ATR_Value(ENUM_TIMEFRAMES Timeframe, int Shift) {
   int Handle = (Timeframe == Timeframe_Trend) ? Indicator_Handle_ATR_High : Indicator_Handle_ATR_Low;
   double ATR_Value[];
   if(CopyBuffer(Handle, 0, Shift, 1, ATR_Value) > 0) return ATR_Value[0];
   return Point_Value * 10;
}

bool Is_Bullish_Candle() {
   double Open = iOpen(_Symbol, Timeframe_Entry, 0), Close = iClose(_Symbol, Timeframe_Entry, 0);
   double Open_Prev = iOpen(_Symbol, Timeframe_Entry, 1), Close_Prev = iClose(_Symbol, Timeframe_Entry, 1);
   if(Close > Open && Close_Prev < Open_Prev) return true;
   double High = iHigh(_Symbol, Timeframe_Entry, 0), Low = iLow(_Symbol, Timeframe_Entry, 0);
   double Body = MathAbs(Close - Open), Lower_Wick = MathMin(Open, Close) - Low;
   return (Body < (High - Low) * 0.35 && Lower_Wick > Body * 1.5 && Close > Open);
}

bool Is_Bearish_Candle() {
   double Open = iOpen(_Symbol, Timeframe_Entry, 0), Close = iClose(_Symbol, Timeframe_Entry, 0);
   double Open_Prev = iOpen(_Symbol, Timeframe_Entry, 1), Close_Prev = iClose(_Symbol, Timeframe_Entry, 1);
   if(Close < Open && Close_Prev > Open_Prev) return true;
   double High = iHigh(_Symbol, Timeframe_Entry, 0), Low = iLow(_Symbol, Timeframe_Entry, 0);
   double Body = MathAbs(Close - Open), Upper_Wick = High - MathMax(Open, Close);
   return (Body < (High - Low) * 0.35 && Upper_Wick > Body * 1.5 && Close < Open);
}

bool Is_Volume_Spike() {
   double Volume_Current = (double)iVolume(_Symbol, Timeframe_Entry, 0);
   double Volume_Sum = 0;
   for(int i = 1; i <= 10; i++) Volume_Sum += (double)iVolume(_Symbol, Timeframe_Entry, i);
   return Volume_Current > (Volume_Sum / 10.0) * 1.3;
}

bool Is_Volume_Spike_Recent(int lookback = 2) {
    for(int bar = 0; bar <= lookback; bar++) {
        double Volume_Current = (double)iVolume(_Symbol, Timeframe_Entry, bar);
        double Volume_Sum = 0;
        for(int i = bar+1; i <= bar+10; i++) Volume_Sum += (double)iVolume(_Symbol, Timeframe_Entry, i);
        double Average = Volume_Sum / 10.0;
        if(Volume_Current > Average * 1.3)
            return true;
    }
    return false;
}

bool Is_Momentum_Confirmed_Loose(int Direction) {
    double RSI[], MACD_Main[], MACD_Signal[];
    if(CopyBuffer(Indicator_Handle_RSI, 0, 0, 1, RSI) <= 0) return false;
    if(CopyBuffer(Indicator_Handle_MACD, 0, 0, 1, MACD_Main) <= 0) return false;
    if(CopyBuffer(Indicator_Handle_MACD, 1, 0, 1, MACD_Signal) <= 0) return false;
    if(Direction == 1) return (RSI[0] < RSI_ZONE_OVERSOLD) && (MACD_Main[0] > MACD_Signal[0]);
    if(Direction == -1) return (RSI[0] > RSI_ZONE_OVERBOUGHT) && (MACD_Main[0] < MACD_Signal[0]);
    return false;
}

bool Is_Range_Expansion_Recent(int lookback = 2) {
    for(int bar = 0; bar <= lookback; bar++) {
        double ATR_Current = Get_ATR_Value(Timeframe_Entry, bar);
        double ATR_Previous = Get_ATR_Value(Timeframe_Entry, bar+1);
        if(ATR_Previous > 0 && ATR_Current / ATR_Previous > 1.15)
            return true;
    }
    return false;
}

bool Is_Liquidity_Swept(int Direction, int lookback = 3) {
    for(int bar = 0; bar <= lookback; bar++) {
        double Recent_High = iHigh(_Symbol, Timeframe_Entry, iHighest(_Symbol, Timeframe_Entry, MODE_HIGH, 10, bar+1));
        double Recent_Low = iLow(_Symbol, Timeframe_Entry, iLowest(_Symbol, Timeframe_Entry, MODE_LOW, 10, bar+1));
        double Sweep_Amount = (Recent_High - Recent_Low) * 0.05;
        double High = iHigh(_Symbol, Timeframe_Entry, bar);
        double Low = iLow(_Symbol, Timeframe_Entry, bar);
        double Close = iClose(_Symbol, Timeframe_Entry, bar);
        if(Direction == 1 && Low < Recent_Low - Sweep_Amount && Close > Recent_Low) {
            Last_Liquidity_Sweep_Bar = bar;
            return true;
        }
        if(Direction == -1 && High > Recent_High + Sweep_Amount && Close < Recent_High) {
            Last_Liquidity_Sweep_Bar = bar;
            return true;
        }
    }
    return false;
}

bool Is_Consolidation_Breakout(int Direction, int lookback = 3) {
    for(int bar = 0; bar <= lookback; bar++) {
        double High_20 = iHigh(_Symbol, Timeframe_Entry, iHighest(_Symbol, Timeframe_Entry, MODE_HIGH, 20, bar));
        double Low_20 = iLow(_Symbol, Timeframe_Entry, iLowest(_Symbol, Timeframe_Entry, MODE_LOW, 20, bar));
        double High_5 = iHigh(_Symbol, Timeframe_Entry, iHighest(_Symbol, Timeframe_Entry, MODE_HIGH, 5, bar));
        double Low_5 = iLow(_Symbol, Timeframe_Entry, iLowest(_Symbol, Timeframe_Entry, MODE_LOW, 5, bar));
        if(High_20 - Low_20 == 0) continue;
        if((High_5 - Low_5) / (High_20 - Low_20) >= 0.25) continue;
        double Close = iClose(_Symbol, Timeframe_Entry, bar);
        if(Direction == 1 && Close > High_5) {
            Last_Consolidation_Break_Bar = bar;
            return true;
        }
        if(Direction == -1 && Close < Low_5) {
            Last_Consolidation_Break_Bar = bar;
            return true;
        }
    }
    return false;
}

bool Is_Fair_Value_Gap(int Direction, int lookback = 4) {
    for(int bar = 0; bar <= lookback; bar++) {
        double High_0 = iHigh(_Symbol, Timeframe_Entry, bar);
        double Low_0  = iLow(_Symbol, Timeframe_Entry, bar);
        double High_2 = iHigh(_Symbol, Timeframe_Entry, bar+2);
        double Low_2  = iLow(_Symbol, Timeframe_Entry, bar+2);
        double Close_1 = iClose(_Symbol, Timeframe_Entry, bar+1);
        if(Direction == 1 && Low_0 > High_2 && Close_1 < Low_0) {
            Last_FVG_Bar = bar;
            return true;
        }
        if(Direction == -1 && High_0 < Low_2 && Close_1 > High_0) {
            Last_FVG_Bar = bar;
            return true;
        }
    }
    return false;
}

void Update_Multitimeframe_Alignment() {
    double MA_Trend_Fast[], MA_Trend_Slow[], MA_Entry_Fast[], MA_Entry_Slow[];
    if(CopyBuffer(Indicator_Handle_MA_High_Fast, 0, 0, 1, MA_Trend_Fast) <= 0) return;
    if(CopyBuffer(Indicator_Handle_MA_High_Slow, 0, 0, 1, MA_Trend_Slow) <= 0) return;
    if(CopyBuffer(Indicator_Handle_MA_Low_Fast, 0, 0, 1, MA_Entry_Fast) <= 0) return;
    if(CopyBuffer(Indicator_Handle_MA_Low_Slow, 0, 0, 1, MA_Entry_Slow) <= 0) return;
    bool Trend_Uptrend = MA_Trend_Fast[0] > MA_Trend_Slow[0];
    bool Entry_Uptrend = MA_Entry_Fast[0] > MA_Entry_Slow[0];
    if(Trend_Uptrend && Entry_Uptrend) {
        Multitimeframe_Aligned_Bull = true;
        Multitimeframe_Aligned_Bear = false;
    } else if(!Trend_Uptrend && !Entry_Uptrend) {
        Multitimeframe_Aligned_Bull = false;
        Multitimeframe_Aligned_Bear = true;
    } else {
        Multitimeframe_Aligned_Bull = false;
        Multitimeframe_Aligned_Bear = false;
    }
}

bool Is_Multitimeframe_Aligned(int Direction) {
    if(Direction == 1) return Multitimeframe_Aligned_Bull;
    if(Direction == -1) return Multitimeframe_Aligned_Bear;
    return false;
}

bool Execute_Market_Order(int Direction, double Stop_Loss, double Take_Profit, double Lot_Size) {
   double Ask_Price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid_Price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double Entry_Price = (Direction == 1) ? Ask_Price : Bid_Price;
   
    Stop_Loss = Validate_Stop_Loss(Direction, Entry_Price, Stop_Loss, Get_ATR_Value(Timeframe_Entry, 0));
   
   double Risk_Distance = MathAbs(Entry_Price - Stop_Loss);
   double Target_Reward = Risk_Distance * Reward_Risk_Ratio;
   
   if(Direction == 1) {
      Take_Profit = Entry_Price + Target_Reward;
   } else {
      Take_Profit = Entry_Price - Target_Reward;
   }
   Take_Profit = NormalizeDouble(Take_Profit, (int)Digits_Value);
   
   MqlTradeRequest Request = {};
   MqlTradeResult Result = {};
   Request.action = TRADE_ACTION_DEAL;
   Request.symbol = _Symbol;
   Request.volume = Lot_Size;
   Request.price = Entry_Price;
   Request.sl = Stop_Loss;
   Request.tp = Take_Profit;
   Request.deviation = Slippage_Points;
   Request.type_filling = Fill_Policy;
   Request.magic = Magic_Number;
   Request.type = (Direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   for(int Retry = 0; Retry < 3; Retry++) {
      if(OrderSend(Request, Result)) {
         if(Result.retcode == TRADE_RETCODE_PLACED || Result.retcode == TRADE_RETCODE_DONE) {
            Print("MARKET ORDER ", Direction==1?"BUY":"SELL", " EXECUTED AT ", DoubleToString(Entry_Price, (int)Digits_Value));
            return true;
         }
         if(Result.retcode == 10019) {
            Sleep(100 * (Retry + 1));
            Request.price = (Direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            continue;
         }
         Print("Market Order Error: ", Result.retcode);
         return false;
      }
   }
   return false;
}

bool Execute_Pending_Order(ENUM_ORDER_TYPE Order_Type, double Price, double LimitPrice, double Lot_Size, int Direction, double Stop_Loss, double Take_Profit) {
   Price = NormalizeDouble(Price, (int)Digits_Value);
   double Minimum_Stop = Get_Minimum_Stop_Distance();
   double Ask_Price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid_Price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double Current_Price = (Direction == 1) ? Ask_Price : Bid_Price;
   
   Stop_Loss = Adjust_Stop_Loss_For_Pending(Order_Type, Price, Current_Price, Stop_Loss, Direction);
   
   double Actual_Risk = MathAbs(Price - Stop_Loss);
   double New_Take_Profit = (Direction == 1) ? Price + (Actual_Risk * Reward_Risk_Ratio) : Price - (Actual_Risk * Reward_Risk_Ratio);
   Take_Profit = NormalizeDouble(New_Take_Profit, (int)Digits_Value);
   
   MqlTradeRequest Request = {};
   MqlTradeResult Result = {};
   Request.action = TRADE_ACTION_PENDING;
   Request.symbol = _Symbol;
   Request.volume = Lot_Size;
   Request.price = Price;
   if(Order_Type == ORDER_TYPE_BUY_STOP_LIMIT || Order_Type == ORDER_TYPE_SELL_STOP_LIMIT) {
       Request.stoplimit = Price;
       Request.price = LimitPrice;
   }
   Request.sl = Stop_Loss;
   Request.tp = Take_Profit;
   Request.deviation = Slippage_Points;
   Request.type_filling = Fill_Policy;
   Request.magic = Magic_Number;
   Request.type = Order_Type;
   Request.expiration = TimeCurrent() + Pending_Order_Expiry_Seconds;
   
   if(OrderSend(Request, Result)) {
      if(Result.retcode == TRADE_RETCODE_PLACED || Result.retcode == TRADE_RETCODE_DONE) {
         Print("PENDING ORDER ", Get_Order_Type_Name(Order_Type), " PLACED AT ", DoubleToString(Price, (int)Digits_Value));
         return true;
      }
      Print("Pending Order Error: ", Result.retcode);
      return false;
   }
   return false;
}

double Validate_Stop_Loss(int Direction, double Entry, double Stop_Loss, double ATR) {
   double Broker_Min_Stop = Get_Minimum_Stop_Distance();
   double ATR_Min_Stop = ATR * 0.8;
   double Min_Acceptable = MathMax(Broker_Min_Stop, ATR_Min_Stop);
   
   if(Direction == 1) {
      if(Stop_Loss >= Entry - Min_Acceptable * 0.8) Stop_Loss = Entry - Min_Acceptable;
   } else {
      if(Stop_Loss <= Entry + Min_Acceptable * 0.8) Stop_Loss = Entry + Min_Acceptable;
   }
   return NormalizeDouble(Stop_Loss, (int)Digits_Value);
}

double Adjust_Stop_Loss_For_Pending(ENUM_ORDER_TYPE Order_Type, double Price, double Current_Price, double Stop_Loss, int Direction) {
   double Minimum_Stop = Get_Minimum_Stop_Distance();
   bool Is_Buy_Order = (Order_Type == ORDER_TYPE_BUY_LIMIT || Order_Type == ORDER_TYPE_BUY_STOP || Order_Type == ORDER_TYPE_BUY_STOP_LIMIT);
   double Adjusted_SL = Stop_Loss;
   
   if(Is_Buy_Order) {
      if(Stop_Loss >= Price || Stop_Loss >= Current_Price) Adjusted_SL = MathMin(Price, Current_Price) - Minimum_Stop;
   } else {
      if(Stop_Loss <= Price || Stop_Loss <= Current_Price) Adjusted_SL = MathMax(Price, Current_Price) + Minimum_Stop;
   }
   return NormalizeDouble(MathMax(Adjusted_SL, Point_Value), (int)Digits_Value);
}

string Get_Order_Type_Name(ENUM_ORDER_TYPE Order_Type) {
   switch(Order_Type) {
      case ORDER_TYPE_BUY: return "BUY";
      case ORDER_TYPE_SELL: return "SELL";
      case ORDER_TYPE_BUY_LIMIT: return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT: return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP: return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP: return "SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT: return "BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT: return "SELL_STOP_LIMIT";
      default: return "UNKNOWN";
   }
}

void Manage_Trailing_Stops() {
   double ATR = Get_ATR_Value(Timeframe_Entry, 0);
   double Trailing_Start_Price = Trailing_Start_ATR * ATR;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong Ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(Ticket)) {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number) {
            double Entry_Price = PositionGetDouble(POSITION_PRICE_OPEN);
            double Stop_Loss = PositionGetDouble(POSITION_SL);
            double Take_Profit = PositionGetDouble(POSITION_TP);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               double Profit_In_Points = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - Entry_Price) / Point_Value;
               if(Profit_In_Points >= Trailing_Start_Price / Point_Value) {
                  double New_Stop_Loss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - Trailing_Step_ATR * ATR;
                  New_Stop_Loss = NormalizeDouble(New_Stop_Loss, (int)Digits_Value);
                  if(New_Stop_Loss > Stop_Loss) Modify_Position(Ticket, New_Stop_Loss, Take_Profit);
               }
            } else {
               double Profit_In_Points = (Entry_Price - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / Point_Value;
               if(Profit_In_Points >= Trailing_Start_Price / Point_Value) {
                  double New_Stop_Loss = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + Trailing_Step_ATR * ATR;
                  New_Stop_Loss = NormalizeDouble(New_Stop_Loss, (int)Digits_Value);
                  if(New_Stop_Loss < Stop_Loss || Stop_Loss == 0) Modify_Position(Ticket, New_Stop_Loss, Take_Profit);
               }
            }
         }
      }
   }
}

void Modify_Position(ulong Ticket, double New_Stop_Loss, double New_Take_Profit) {
   MqlTradeRequest Request = {};
   MqlTradeResult Result = {};
   Request.action = TRADE_ACTION_SLTP;
   Request.position = Ticket;
   Request.sl = New_Stop_Loss;
   Request.tp = New_Take_Profit;
   if(OrderSend(Request, Result)) {
      if(Result.retcode == TRADE_RETCODE_PLACED || Result.retcode == TRADE_RETCODE_DONE) {
         Print("Position Modified - Ticket #", Ticket);
      }
   }
}
