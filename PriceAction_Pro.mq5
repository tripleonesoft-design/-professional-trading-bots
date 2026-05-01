//+------------------------------------------------------------------+
//|                                     PriceAction_Pro.mq5         |
//|                         Professional Price Action Trading         |
//|                              Version 10.0 Build 2025.01           |
//+------------------------------------------------------------------+
#property copyright "Professional Trading Systems"
#property version   "10.00"
#property description "Professional Price Action - S/R + PA Patterns"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#define PRODUCTION_READY

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES Inp_HTF = PERIOD_H4;      // Higher TF for trend
input ENUM_TIMEFRAMES Inp_LTF = PERIOD_M30;     // Lower TF for entries

input group "=== Order Types ==="
input bool Inp_UseMarket    = true;
input bool Inp_UseLimit    = true;
input bool Inp_UseStop     = true;
input bool Inp_UseStopLimit = false;    // Stop-limit orders

input group "=== Risk Management ==="
input double   Inp_RiskPercent = 1.0;
input double   Inp_RewardRisk  = 2.0;
input int     Inp_MaxSpread  = 3000;
input int     Inp_Slippage  = 100;
input double  Inp_MaxLot    = 100.0;
input int     Inp_Cooldown = 30;
input bool    Inp_MaxSpreadCheck = true;

input group "=== Price Action Settings ==="
input int     Inp_SwingDepth = 3;
input int     Inp_SR_Period  = 20;
input double Inp_SR_ZonePct  = 0.002;
input double Inp_PinBarRatio = 2.0;
input double Inp_ConfZone   = 0.3;    // Zone confirmation %

input group "=== Consensus Scoring ==="
input bool    Inp_UseConsensus = true;
input int     Inp_MinScore = 3;
input bool    Inp_ScoreRSI = true;
input bool    Inp_ScoreMA  = true;
input bool    Inp_ScorePA  = true;
input bool    Inp_ScoreSR  = true;
input bool    Inp_ScoreTrend = true;

input group "=== Indicators ==="
input int     Inp_RSI_Period = 14;
input int     Inp_RSI_OB = 65;
input int     Inp_RSI_OS = 35;
input int     Inp_MA_Fast = 50;
input int     Inp_MA_Slow = 200;

input group "=== Trailing ==="
input bool   Inp_UseTrail = true;
input double Inp_TrailStart = 2.0;
input double Inp_TrailStep  = 1.0;
input int     Inp_TrailMode  = 0;    // 0=ATR, 1=Breakeven

input group "=== Protection ==="
input bool    Inp_MaxTrades = true;
input int     Inp_MaxPositions = 3;
input bool    Inp_CloseOnSaturday = false;

double   g_pt, g_dig;
int      g_atrHTF, g_atrLTF, g_rsiH;
int      g_maHTF1, g_maHTF2, g_maLTF1, g_maLTF2;
datetime g_lastBar = 0, g_lastTrade = 0;
datetime g_lastSaturdayCheck = 0;
const int g_magic = 20251001;
bool     g_canTrade = true;
bool     g_initialized = false;
string   g_lastError = "";
long     g_buyTickets[];
long     g_sellTickets[];
ENUM_INIT_RETCODE g_initCode = INIT_RETCODE_UNKNOWN;

struct SSignal {
   int dir;
   double entry;
   double sl;
   double tp;
   double atr;
   string reason;
   int score;
   bool hasRSI;
   bool hasMA;
   bool hasPA;
   bool hasSR;
   bool hasTrend;
};

//+------------------------------------------------------------------+
int OnInit() {
   g_initCode = ValidateParameters();
   if(g_initCode != INIT_RETCODE_OK) {
      Print("=== PARAMETER VALIDATION FAILED ===");
      Print(g_lastError);
      return INIT_FAILED;
   }
   
   g_pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_dig = (double)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_pt == 0) g_pt = 0.00001;
   
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_ALLOWED)) {
      Print("Symbol trading not allowed: ", _Symbol);
      return INIT_FAILED;
   }
   
   g_atrHTF = iATR(_Symbol, Inp_HTF, 14);
   g_atrLTF = iATR(_Symbol, Inp_LTF, 14);
   g_rsiH   = iRSI(_Symbol, Inp_LTF, Inp_RSI_Period, PRICE_CLOSE);
   g_maHTF1 = iMA(_Symbol, Inp_HTF, Inp_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   g_maHTF2 = iMA(_Symbol, Inp_HTF, Inp_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
   g_maLTF1 = iMA(_Symbol, Inp_LTF, Inp_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   g_maLTF2 = iMA(_Symbol, Inp_LTF, Inp_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
   
   if(g_atrHTF==INVALID_HANDLE || g_atrLTF==INVALID_HANDLE || g_rsiH==INVALID_HANDLE ||
      g_maHTF1==INVALID_HANDLE || g_maHTF2==INVALID_HANDLE || g_maLTF1==INVALID_HANDLE || g_maLTF2==INVALID_HANDLE) {
      Print("Init failed - indicator handles");
      return INIT_FAILED;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   long stopLev = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   Print("=== PriceAction Pro v10 Ready ===");
   Print("Symbol: ", _Symbol, " | Lots: ", minLot, "-", maxLot);
   Print("TF: ", EnumToString(Inp_HTF), "/", EnumToString(Inp_LTF));
   Print("RR 1:", Inp_RewardRisk, " | Swing: ", Inp_SwingDepth);
   Print("Min Score: ", Inp_MinScore, " | Consensus: ", Inp_UseConsensus);
   
   g_initialized = true;
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
ENUM_INIT_RETCODE ValidateParameters() {
   if(Inp_RiskPercent <= 0 || Inp_RiskPercent > 10) {
      g_lastError = "RiskPercent must be 0.1-10";
      return INIT_RETCODE_PARAM;
   }
   if(Inp_RewardRisk < 1.0 || Inp_RewardRisk > 10) {
      g_lastError = "RewardRisk must be 1-10";
      return INIT_RETCODE_PARAM;
   }
   if(Inp_MaxSpread < 0 || Inp_MaxSpread > 10000) {
      g_lastError = "MaxSpread out of range";
      return INIT_RETCODE_PARAM;
   }
   if(Inp_MA_Fast >= Inp_MA_Slow) {
      g_lastError = "MA_Fast must be < MA_Slow";
      return INIT_RETCODE_PARAM;
   }
   if(Inp_SR_Period < 5 || Inp_SR_Period > 100) {
      g_lastError = "SR_Period must be 5-100";
      return INIT_RETCODE_PARAM;
   }
   if(Inp_SwingDepth < 1 || Inp_SwingDepth > 10) {
      g_lastError = "SwingDepth must be 1-10";
      return INIT_RETCODE_PARAM;
   }
   return INIT_RETCODE_OK;
}

int CountOpenTrades() {
   int cnt = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionGetTicket(i) > 0) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            if(PositionGetInteger(POSITION_MAGIC) == g_magic) {
               cnt++;
            }
         }
      }
   }
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderGetTicket(i) > 0) {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol) {
            if(OrderGetInteger(ORDER_MAGIC) == g_magic) {
               cnt++;
            }
         }
      }
   }
   return cnt;
}

void CloseAllPositions(string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            if(PositionGetInteger(POSITION_MAGIC) == g_magic) {
               ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               double vol = PositionGetDouble(POSITION_VOLUME);
               MqlTradeRequest req = {};
               MqlTradeResult res = {};
               req.action = TRADE_ACTION_DEAL;
               req.symbol = _Symbol;
               req.volume = vol;
               req.price = (t == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               req.deviation = Inp_Slippage;
               req.type_filling = ORDER_FILLING_IOC;
               req.magic = g_magic;
               req.position = tk;
               req.type = (t == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               if(OrderSend(req, res)) {
                  Print("Closed ", reason, " #", tk);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnTimer() {
   if(!g_canTrade) return;
   
   if(Inp_CloseOnSaturday) {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.day_of_week == 6 && g_lastSaturdayCheck != iTime(_Symbol, PERIOD_D1, 0)) {
         g_lastSaturdayCheck = iTime(_Symbol, PERIOD_D1, 0);
         CloseAllPositions("Saturday close");
         return;
      }
   }
   
   CleanupOrders();
   if(Inp_UseTrail) TrailPositions();
   
   if(TimeCurrent() - g_lastTrade < Inp_Cooldown * 60) return;
   
   datetime cb = iTime(_Symbol, Inp_LTF, 0);
   if(cb == g_lastBar) return;
   g_lastBar = cb;
   
   if(Inp_MaxSpreadCheck) {
      double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_pt;
      if(spr > Inp_MaxSpread) {
         g_canTrade = false;
         EventSetTimer(300);
         Print("Spread too high: ", spr);
         return;
      }
   }
   g_canTrade = true;
   
   if(Inp_MaxTrades) {
      if(CountOpenTrades() >= Inp_MaxPositions) {
         Print("Max positions reached: ", Inp_MaxPositions);
         return;
      }
   }
   
   SSignal sig = FindSignal();
   if(sig.dir == 0) return;
   
   Print("=== SIGNAL: ", sig.dir==1?"BUY":"SELL", " | ", sig.reason);
   Print("    Entry: ", sig.entry, " | SL: ", sig.sl, " | TP: ", sig.tp);
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * Inp_RiskPercent / 100.0;
   double slDist = MathAbs(sig.entry - sig.sl);
   if(slDist < g_pt * 10) slDist = sig.atr * 0.5;
   
   double lot = risk / (slDist * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / g_pt);
   lot = MathFloor(lot / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = NormalizeDouble(MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)), 2);
   lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   lot = MathMin(lot, Inp_MaxLot);
   
   bool done = false;
   if(Inp_UseMarket) {
      if(ExecMarket(sig.dir, sig.sl, sig.tp, lot)) {
         done = true;
         g_lastTrade = TimeCurrent();
      }
   }
   if(!done && Inp_UseLimit) {
      ENUM_ORDER_TYPE ot = (sig.dir == 1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      if(ExecPending(ot, sig.entry, lot, sig.dir, sig.sl, sig.tp)) {
         done = true;
         g_lastTrade = TimeCurrent();
      }
   }
   if(!done && Inp_UseStop) {
      ENUM_ORDER_TYPE ot = (sig.dir == 1) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      double stopPx = (sig.dir == 1) ? sig.entry + sig.atr * 0.2 : sig.entry - sig.atr * 0.2;
      if(ExecPending(ot, stopPx, lot, sig.dir, sig.sl, sig.tp)) {
         g_lastTrade = TimeCurrent();
      }
   }
   if(!done && Inp_UseStopLimit) {
      ENUM_ORDER_TYPE ot = (sig.dir == 1) ? ORDER_TYPE_BUY_STOP_LIMIT : ORDER_TYPE_SELL_STOP_LIMIT;
      double stopPx = (sig.dir == 1) ? sig.entry + sig.atr * 0.3 : sig.entry - sig.atr * 0.3;
      double limitPx = sig.entry;
      if(ExecStopLimit(ot, stopPx, limitPx, lot, sig.dir, sig.sl, sig.tp)) {
         g_lastTrade = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
SSignal FindSignal() {
   SSignal s; ZeroMemory(s);
   
   double maHTF1[], maHTF2[];
   if(CopyBuffer(g_maHTF1, 0, 0, 1, maHTF1) <= 0) return s;
   if(CopyBuffer(g_maHTF2, 0, 0, 1, maHTF2) <= 0) return s;
   
   bool htfUp = maHTF1[0] > maHTF2[0];
   bool htfDn = maHTF1[0] < maHTF2[0];
   
   double maLTF1[], maLTF2[];
   if(CopyBuffer(g_maLTF1, 0, 0, 1, maLTF1) <= 0) return s;
   if(CopyBuffer(g_maLTF2, 0, 0, 1, maLTF2) <= 0) return s;
   
   bool ltfUp = maLTF1[0] > maLTF2[0];
   bool ltfDn = maLTF1[0] < maLTF2[0];
   
   if(htfUp != ltfUp && Inp_ScoreTrend) return s;
   
   s.atr = GetATR(Inp_LTF, 0);
   double minD = MinStop();
   
   double sup, res;
   FindSRZones(sup, res);
   
   double price = iClose(_Symbol, Inp_LTF, 0);
   
   if(htfUp && ltfUp) {
      bool nearSup = MathAbs(price - sup) <= (res - sup) * Inp_ConfZone;
      bool pinBar = IsPinBar(1);
      bool engul = IsEngulfing(1);
      
      if(nearSup || pinBar || engul) {
         s.dir = 1;
         s.entry = sup;
         s.sl = sup - MathMax(s.atr * 0.6, minD);
         s.tp = s.entry + MathMax(s.atr * Inp_RewardRisk * 1.2, minD * Inp_RewardRisk);
         
         if(nearSup && Inp_ScoreSR) { s.hasSR = true; s.score++; }
         if(pinBar && Inp_ScorePA) { s.hasPA = true; s.score++; }
         if(engul && Inp_ScorePA) { s.hasPA = true; s.score++; }
         if(Inp_ScoreTrend) { s.hasTrend = true; s.score++; }
         if(htfUp) s.reason = "Buy at Support";
      }
   }
   else if(htfDn && ltfDn) {
      bool nearRes = MathAbs(price - res) <= (res - sup) * Inp_ConfZone;
      bool pinBar = IsPinBar(-1);
      bool engul = IsEngulfing(-1);
      
      if(nearRes || pinBar || engul) {
         s.dir = -1;
         s.entry = res;
         s.sl = res + MathMax(s.atr * 0.6, minD);
         s.tp = s.entry - MathMax(s.atr * Inp_RewardRisk * 1.2, minD * Inp_RewardRisk);
         
         if(nearRes && Inp_ScoreSR) { s.hasSR = true; s.score++; }
         if(pinBar && Inp_ScorePA) { s.hasPA = true; s.score++; }
         if(engul && Inp_ScorePA) { s.hasPA = true; s.score++; }
         if(Inp_ScoreTrend) { s.hasTrend = true; s.score++; }
         if(htfDn) s.reason = "Sell at Resistance";
      }
   }
   
   double rsi[];
   if(CopyBuffer(g_rsiH, 0, 0, 1, rsi) > 0) {
      if(Inp_ScoreRSI) {
         if(s.dir == 1 && rsi[0] > Inp_RSI_OS) { s.hasRS = true; s.score++; }
         if(s.dir == -1 && rsi[0] < Inp_RSI_OB) { s.hasRS = true; s.score++; }
      }
      if(s.dir == 1 && rsi[0] <= Inp_RSI_OS * 0.5) s.dir = 0;
      if(s.dir == -1 && rsi[0] >= Inp_RSI_OB * 1.5) s.dir = 0;
   }
   
   if(Inp_ScoreMA) {
      if(s.dir == 1 && ltfUp) { s.hasMA = true; s.score++; }
      if(s.dir == -1 && ltfDn) { s.hasMA = true; s.score++; }
   }
   
   if(Inp_UseConsensus && s.score < Inp_MinScore) {
      s.dir = 0;
      return s;
   }
   
   double risk = MathAbs(s.entry - s.sl);
   double reward = MathAbs(s.tp - s.entry);
   if(risk <= 0 || reward / risk < 1.5) s.dir = 0;
   
   return s;
}

//+------------------------------------------------------------------+
void FindSRZones(double &sup, double &res) {
   sup = 0; res = 0;
   
   double prices[];
   for(int i = 2; i < Inp_SR_Period + 5; i++) {
      int sz = ArraySize(prices);
      ArrayResize(prices, sz + 1);
      prices[sz] = iClose(_Symbol, Inp_LTF, i);
   }
   
   if(ArraySize(prices) < 5) return;
   
   sup = prices[0];
   res = prices[0];
   for(int i = 1; i < ArraySize(prices); i++) {
      if(prices[i] < sup) sup = prices[i];
      if(prices[i] > res) res = prices[i];
   }
   
   double zone = (res - sup) * Inp_SR_ZonePct;
   for(int i = 1; i < ArraySize(prices) - 1; i++) {
      for(int j = i + 1; j < ArraySize(prices); j++) {
         if(MathAbs(prices[i] - prices[j]) < zone) {
            double avg = (prices[i] + prices[j]) / 2;
            if(avg < sup + zone * 2) sup = avg;
            if(avg > res - zone * 2) res = avg;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsPinBar(int dir) {
   double o = iOpen(_Symbol, Inp_LTF, 0);
   double c = iClose(_Symbol, Inp_LTF, 0);
   double h = iHigh(_Symbol, Inp_LTF, 0);
   double l = iLow(_Symbol, Inp_LTF, 0);
   
   double body = MathAbs(c - o);
   double range = h - l;
   if(range == 0) return false;
   
   double upperWick = h - MathMax(o, c);
   double lowerWick = MathMin(o, c) - l;
   
   if(dir == 1) {
      return (lowerWick > body * Inp_PinBarRatio && upperWick < body * 0.5 && c > o);
   }
   if(dir == -1) {
      return (upperWick > body * Inp_PinBarRatio && lowerWick < body * 0.5 && c < o);
   }
   return false;
}

bool IsEngulfing(int dir) {
   double o0 = iOpen(_Symbol, Inp_LTF, 0), c0 = iClose(_Symbol, Inp_LTF, 0);
   double o1 = iOpen(_Symbol, Inp_LTF, 1), c1 = iClose(_Symbol, Inp_LTF, 1);
   
   if(dir == 1) {
      return (c0 > o0 && c1 < o1 && c0 > o1 && o0 < c1);
   }
   if(dir == -1) {
      return (c0 < o0 && c1 > o1 && c0 < o1 && o0 > c1);
   }
   return false;
}

bool IsSwingHigh(int idx) {
   double h = iHigh(_Symbol, Inp_LTF, idx);
   for(int i = 1; i <= Inp_SwingDepth; i++) {
      if(iHigh(_Symbol, Inp_LTF, idx - i) >= h) return false;
      if(iHigh(_Symbol, Inp_LTF, idx + i) >= h) return false;
   }
   return true;
}

bool IsSwingLow(int idx) {
   double l = iLow(_Symbol, Inp_LTF, idx);
   for(int i = 1; i <= Inp_SwingDepth; i++) {
      if(iLow(_Symbol, Inp_LTF, idx - i) <= l) return false;
      if(iLow(_Symbol, Inp_LTF, idx + i) <= l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
double MinStop() {
   long sl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long fr = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double d = MathMax((double)sl, (double)fr) * g_pt;
   return MathMax(d, g_pt * 10);
}

double GetATR(ENUM_TIMEFRAMES tf, int sh) {
   int h = (tf == Inp_HTF) ? g_atrHTF : g_atrLTF;
   double a[];
   if(CopyBuffer(h, 0, sh, 1, a) > 0) return a[0];
   return g_pt * 10;
}

//+------------------------------------------------------------------+
bool ExecMarket(int dir, double sl, double tp, double lot) {
   for(int i = 0; i < 3; i++) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double price = (dir == 1) ? ask : bid;
      
      sl = NormalizeDouble(sl, (int)g_dig);
      tp = NormalizeDouble(tp, (int)g_dig);
      
      if(!ValidStops(dir, price, sl, tp)) {
         double d = MinStop();
         sl = (dir == 1) ? price - d : price + d;
         sl = NormalizeDouble(sl, (int)g_dig);
         tp = (dir == 1) ? price + d * Inp_RewardRisk : price - d * Inp_RewardRisk;
         tp = NormalizeDouble(tp, (int)g_dig);
      }
      
      MqlTradeRequest req = {};
      MqlTradeResult res = {};
      req.action = TRADE_ACTION_DEAL;
      req.symbol = _Symbol;
      req.volume = lot;
      req.price = price;
      req.sl = sl;
      req.tp = tp;
      req.deviation = Inp_Slippage;
      req.type_filling = ORDER_FILLING_IOC;
      req.magic = g_magic;
      req.type = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      if(OrderSend(req, res)) {
         if(res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE) {
            Print("MARKET ", dir==1?"BUY":"SELL", " | E:", price, " SL:", sl, " TP:", tp);
            return true;
         }
      }
      if(res.retcode == 10019) Sleep(100 + i * 100);
   }
   return false;
}

bool ExecPending(ENUM_ORDER_TYPE ot, double price, double lot, int dir, double sl, double tp) {
   price = NormalizeDouble(price, (int)g_dig);
   double d = MinStop();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double cur = (dir == 1) ? ask : bid;
   
   bool isBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
   double vsl = sl, vtp = tp;
   
   if(isBuy) {
      if(sl >= price || sl >= cur) vsl = MathMin(price, cur) - MathMax(d, g_pt * 10);
      if(tp <= price || tp <= cur) vtp = MathMax(price, cur) + d * Inp_RewardRisk;
   } else {
      if(sl <= price || sl <= cur) vsl = MathMax(price, cur) + MathMax(d, g_pt * 10);
      if(tp >= price || tp >= cur) vtp = MathMin(price, cur) - d * Inp_RewardRisk;
   }
   
   vsl = NormalizeDouble(MathMax(vsl, g_pt), (int)g_dig);
   vtp = NormalizeDouble(MathMax(vtp, g_pt), (int)g_dig);
   
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = lot;
   req.price = price;
   req.sl = vsl;
   req.tp = vtp;
   req.deviation = Inp_Slippage;
   req.type_filling = ORDER_FILLING_IOC;
   req.magic = g_magic;
   req.type = ot;
   req.expiration = TimeCurrent() + 6 * (int)PeriodSeconds(Inp_LTF);
   
   if(OrderSend(req, res)) {
      if(res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE) {
         Print("PENDING ", EnumToString(ot), " | E:", price);
         return true;
      }
      Print("Err ", res.retcode);
   }
   return false;
}

bool ValidStops(int dir, double ent, double sl, double tp) {
   double d = MinStop();
   if(dir == 1) {
      if(sl >= ent - d * 0.5) return false;
      if(tp <= ent + d) return false;
   } else {
      if(sl <= ent + d * 0.5) return false;
      if(tp >= ent - d) return false;
   }
   return true;
}

bool ExecStopLimit(ENUM_ORDER_TYPE ot, double stopPrice, double limitPrice, double lot, int dir, double sl, double tp) {
   stopPrice = NormalizeDouble(stopPrice, (int)g_dig);
   limitPrice = NormalizeDouble(limitPrice, (int)g_dig);
   double d = MinStop();
   
   bool isBuy = (ot == ORDER_TYPE_BUY_STOP_LIMIT);
   double vsl = sl, vtp = tp;
   
   if(isBuy) {
      if(sl >= stopPrice) vsl = stopPrice - d;
      if(tp <= stopPrice) vtp = stopPrice + d * Inp_RewardRisk;
   } else {
      if(sl <= stopPrice) vsl = stopPrice + d;
      if(tp >= stopPrice) vtp = stopPrice - d * Inp_RewardRisk;
   }
   
   vsl = NormalizeDouble(MathMax(vsl, g_pt), (int)g_dig);
   vtp = NormalizeDouble(MathMax(vtp, g_pt), (int)g_dig);
   
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = lot;
   req.price = limitPrice;
   req.stopprice = stopPrice;
   req.sl = vsl;
   req.tp = vtp;
   req.deviation = Inp_Slippage;
   req.type_filling = ORDER_FILLING_IOC;
   req.magic = g_magic;
   req.type = ot;
   req.expiration = TimeCurrent() + 6 * (int)PeriodSeconds(Inp_LTF);
   
   if(OrderSend(req, res)) {
      if(res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE) {
         Print("STOP_LIMIT ", EnumToString(ot), " | Stop:", stopPrice, " Limit:", limitPrice);
         return true;
      }
      Print("StopLimit Err ", res.retcode);
   }
   return false;
}

//+------------------------------------------------------------------+
void CleanupOrders() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong tk = OrderGetTicket(i);
      if(tk > 0 && OrderSelect(tk)) {
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) == g_magic) {
            ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_SELL_LIMIT ||
               t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP) {
               datetime exp = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
               if(TimeCurrent() >= exp) {
                  MqlTradeRequest req = {}; MqlTradeResult res = {};
                  req.action = TRADE_ACTION_REMOVE;
                  req.order = tk;
                  if(OrderSend(req, res)) Print("Cleaned #", tk);
               }
            }
         }
      }
   }
}

void TrailPositions() {
   double atr = GetATR(Inp_LTF, 0);
   double start = Inp_TrailStart * atr;
   double step = Inp_TrailStep * atr;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
      
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         double prof = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - open) / g_pt;
         double newSL = 0;
         
         if(Inp_TrailMode == 0) {
            if(prof >= start / g_pt) {
               newSL = SymbolInfoDouble(_Symbol, SYMBOL_BID) - atr * 0.5;
            }
         } else {
            double breakeven = open + MinStop();
            if(prof >= (breakeven - open) * 2 / g_pt && (sl < breakeven || sl == 0)) {
               newSL = open + MinStop();
            }
         }
         newSL = NormalizeDouble(newSL, (int)g_dig);
         if(newSL > sl + step / g_pt) {
            if(Mod_SL_TP(tk, newSL, tp)) {
               Print("Trail BUY #", tk, " SL:", newSL);
            }
         }
      } else {
         double prof = (open - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / g_pt;
         double newSL = 0;
         
         if(Inp_TrailMode == 0) {
            if(prof >= start / g_pt) {
               newSL = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + atr * 0.5;
            }
         } else {
            double breakeven = open - MinStop();
            if(prof >= (open - breakeven) * 2 / g_pt && (sl > breakeven || sl == 0)) {
               newSL = open - MinStop();
            }
         }
         newSL = NormalizeDouble(newSL, (int)g_dig);
         if(newSL < sl - step / g_pt || (sl == 0 && newSL > 0)) {
            if(Mod_SL_TP(tk, newSL, tp)) {
               Print("Trail SELL #", tk, " SL:", newSL);
            }
         }
      }
   }
}

bool Mod_SL_TP(ulong tk, double sl, double tp) {
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_SLTP;
   req.position = tk;
   req.sl = sl;
   req.tp = tp;
   if(OrderSend(req, res)) {
      return (res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE);
   }
   return false;
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result) {
   if(trans.symbol != _Symbol) return;
   
   ENUM_TRADE_TRANSACTION_TYPE type = trans.type;
   
   if(type == TRADE_TRANSACTION_ORDER_ADD) {
      if(request.magic == g_magic) {
         Print("Order Added: ", EnumToString(request.type), " ", request.volume);
      }
   }
   else if(type == TRADE_TRANSACTION_ORDER_FILL) {
      if(request.magic == g_magic) {
         g_lastTrade = TimeCurrent();
         if(request.type == ORDER_TYPE_BUY || request.type == ORDER_TYPE_BUY_LIMIT || request.type == ORDER_TYPE_BUY_STOP || request.type == ORDER_TYPE_BUY_STOP_LIMIT) {
            ArrayResize(g_buyTickets, ArraySize(g_buyTickets) + 1);
            g_buyTickets[ArraySize(g_buyTickets) - 1] = trans.order;
         } else {
            ArrayResize(g_sellTickets, ArraySize(g_sellTickets) + 1);
            g_sellTickets[ArraySize(g_sellTickets) - 1] = trans.order;
         }
         Print("Order Filled: ", request.type, " Price: ", trans.price);
      }
   }
   else if(type == TRADE_TRANSACTION_POSITION) {
      if(trans.magic == g_magic) {
         Print("Position Modified #", trans.position);
      }
   }
}