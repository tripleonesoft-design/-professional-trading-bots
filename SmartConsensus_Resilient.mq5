//+------------------------------------------------------------------+
//|                                     SmartConsensus_Resilient.mq5 |
//|                                   Production Ready | v8.02        |
//+------------------------------------------------------------------+
#property copyright "Advanced Strategy Bot"
#property version   "8.02"
#property description "Production-ready with adaptive retries"

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES Inp_TrendTF   = PERIOD_M15;
input ENUM_TIMEFRAMES Inp_EntryTF   = PERIOD_M5;

input group "=== Order Execution ==="
input bool Inp_UseMarketOrders  = true;
input bool Inp_UseLimitOrders   = true;
input bool Inp_UseStopOrders    = true;

input group "=== Risk & Money ==="
input double   Inp_RiskPercent      = 1.0;
input double   Inp_MinRR            = 1.5;
input int      Inp_MaxSpread        = 3000;
input int      Inp_Slippage         = 100;
input bool     Inp_UseTrailing      = true;
input double   Inp_TrailingStart    = 1.2;
input double   Inp_TrailingStep     = 0.5;
input int      Inp_CooldownMinutes  = 30;

input group "=== Confirmation ==="
input int      Inp_MinConfirmations = 1;

input group "=== Pending Orders ==="
input int      Inp_PendingExpiryBars= 6;
input double   Inp_LimitOrderOffset = 0.3;

input group "=== Indicators ==="
input int      Inp_RSI_Period       = 14;
input double   Inp_RSI_OB           = 70;
input double   Inp_RSI_OS           = 30;
input int      Inp_MACD_Fast        = 12;
input int      Inp_MACD_Slow        = 26;
input int      Inp_MACD_Signal      = 9;
input double   Inp_VolumeRatio      = 1.3;
input int      Inp_ATR_Period       = 14;

input group "=== Zones ==="
input int      Inp_ZoneStrength     = 2;
input double  Inp_LiquiditySweepPct= 0.05;
input int      Inp_SwingDepth       = 3;
input int      Inp_RangeBars        = 12;

double   g_point, g_digits;
int      g_atrHTF, g_atrETF, g_rsiH, g_macdH;
int      g_maFastHTF, g_maSlowHTF, g_maFastETF, g_maSlowETF;
datetime g_lastBar = 0, g_lastTrade = 0;
const int g_magic = 20250602;
bool     g_active = true;

struct STrend {
   int dir;
   double demandL, demandH, supplyL, supplyH;
   double supp, resi;
   bool range, wyckoffSpring, wyckoffUpthrust;
   double limitPrice, stopPrice, stopLoss, takeProfit1, takeProfit2;
};

//+------------------------------------------------------------------+
int OnInit() {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (double)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_point == 0) g_point = 0.00001;
   
   g_atrHTF   = iATR(_Symbol, Inp_TrendTF, Inp_ATR_Period);
   g_atrETF   = iATR(_Symbol, Inp_EntryTF, Inp_ATR_Period);
   g_rsiH    = iRSI(_Symbol, Inp_EntryTF, Inp_RSI_Period, PRICE_CLOSE);
   g_macdH   = iMACD(_Symbol, Inp_EntryTF, Inp_MACD_Fast, Inp_MACD_Slow, Inp_MACD_Signal, PRICE_CLOSE);
   g_maFastHTF = iMA(_Symbol, Inp_TrendTF, 10, 0, MODE_SMA, PRICE_CLOSE);
   g_maSlowHTF = iMA(_Symbol, Inp_TrendTF, 20, 0, MODE_SMA, PRICE_CLOSE);
   g_maFastETF = iMA(_Symbol, Inp_EntryTF, 10, 0, MODE_SMA, PRICE_CLOSE);
   g_maSlowETF = iMA(_Symbol, Inp_EntryTF, 20, 0, MODE_SMA, PRICE_CLOSE);
   
   if(g_atrHTF==INVALID_HANDLE || g_atrETF==INVALID_HANDLE || g_rsiH==INVALID_HANDLE ||
      g_macdH==INVALID_HANDLE || g_maFastHTF==INVALID_HANDLE || g_maSlowHTF==INVALID_HANDLE ||
      g_maFastETF==INVALID_HANDLE || g_maSlowETF==INVALID_HANDLE) {
      Print("Indicator init failed");
      return INIT_FAILED;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   Print("EA Ready | ", _Symbol, " | Lots: ", minLot, "-", maxLot);
   
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(g_atrHTF); IndicatorRelease(g_atrETF);
   IndicatorRelease(g_rsiH); IndicatorRelease(g_macdH);
   IndicatorRelease(g_maFastHTF); IndicatorRelease(g_maSlowHTF);
   IndicatorRelease(g_maFastETF); IndicatorRelease(g_maSlowETF);
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer() {
   if(!g_active) return;
   
   if(Inp_UseLimitOrders || Inp_UseStopOrders) RemoveExpired();
   if(Inp_UseTrailing) TrailStops();
   
   if(TimeCurrent() - g_lastTrade < Inp_CooldownMinutes * 60) return;
   
   datetime curBar = iTime(_Symbol, Inp_EntryTF, 0);
   if(curBar == g_lastBar) return;
   g_lastBar = curBar;
   
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   if(spread > Inp_MaxSpread) {
      Print("Spread high: ", spread, " > ", Inp_MaxSpread);
      g_active = false;
      EventSetTimer(300);
      return;
   }
   g_active = true;
   
   STrend t = Analyze();
   if(t.dir == 0) return;
   
   int score = Confirm(t.dir);
   if(score < Inp_MinConfirmations) {
      Print("Score ", score, " < ", Inp_MinConfirmations);
      return;
   }
   Print("Score ", score, " | Dir ", t.dir);
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * Inp_RiskPercent / 100.0;
   double atr = GetATR(Inp_EntryTF, 0);
   double slDist = MathAbs(t.limitPrice - t.stopLoss);
   if(slDist < g_point * 10) slDist = atr * 0.4;
   
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot = riskAmt / (slDist * tickVal / g_point);
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = NormalizeDouble(MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)), 2);
   lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   
   if(Inp_UseMarketOrders) {
      if(ExecMarket(t.dir, t.stopLoss, t.takeProfit1, lot)) g_lastTrade = TimeCurrent();
   }
   if(Inp_UseLimitOrders) {
      ENUM_ORDER_TYPE ot = (t.dir == 1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      if(ExecPending(ot, t.limitPrice, lot, t.dir, t.stopLoss, t.takeProfit1)) g_lastTrade = TimeCurrent();
   }
   if(Inp_UseStopOrders) {
      ENUM_ORDER_TYPE ot = (t.dir == 1) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      if(ExecPending(ot, t.stopPrice, lot, t.dir, t.stopLoss, t.takeProfit1)) g_lastTrade = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
STrend Analyze() {
   STrend r; ZeroMemory(r);
   
   double maF[], maS[];
   if(CopyBuffer(g_maFastHTF, 0, 0, 1, maF) <= 0) return r;
   if(CopyBuffer(g_maSlowHTF, 0, 0, 1, maS) <= 0) return r;
   
   bool up = maF[0] > maS[0], down = maF[0] < maS[0];
   
   r.supp = iLow(_Symbol, Inp_TrendTF, iLowest(_Symbol, Inp_TrendTF, MODE_LOW, 10, 1));
   r.resi = iHigh(_Symbol, Inp_TrendTF, iHighest(_Symbol, Inp_TrendTF, MODE_HIGH, 10, 1));
   
   double price = iClose(_Symbol, Inp_TrendTF, 0);
   double atr = GetATR(Inp_TrendTF, 0);
   double minDist = MinStopDist();
   double zone = atr * Inp_LimitOrderOffset;
   
   if(up && !down) {
      if(MathAbs(price - r.supp) <= zone) {
         r.dir = 1;
         r.limitPrice = r.supp;
         r.stopPrice = r.supp + zone;
         r.stopLoss = r.supp - MathMax(atr * 0.4, minDist);
      }
      else if(r.wyckoffSpring) {
         r.dir = 1;
         r.limitPrice = iClose(_Symbol, Inp_TrendTF, 1);
         r.stopLoss = r.limitPrice - MathMax(atr * 0.6, minDist * 1.5);
      }
   }
   else if(down && !up) {
      if(MathAbs(price - r.resi) <= zone) {
         r.dir = -1;
         r.limitPrice = r.resi;
         r.stopPrice = r.resi - zone;
         r.stopLoss = r.resi + MathMax(atr * 0.4, minDist);
      }
      else if(r.wyckoffUpthrust) {
         r.dir = -1;
         r.limitPrice = iClose(_Symbol, Inp_TrendTF, 1);
         r.stopLoss = r.limitPrice + MathMax(atr * 0.6, minDist * 1.5);
      }
   }
   
   if(r.dir != 0) {
      r.takeProfit1 = (r.dir == 1) ? r.limitPrice + MathMax(atr * 1.5, minDist * 3) : r.limitPrice - MathMax(atr * 1.5, minDist * 3);
      double sl = MathAbs(r.limitPrice - r.stopLoss);
      double tp = MathAbs(r.takeProfit1 - r.limitPrice);
      if(sl > 0 && tp / sl < Inp_MinRR) r.dir = 0;
   }
   return r;
}

//+------------------------------------------------------------------+
int Confirm(int dir) {
   int s = 0;
   if((dir == 1 && Bullish()) || (dir == -1 && Bearish())) s++;
   if(VolSpike()) s++;
   if(Momentum(dir)) s++;
   if(LiqSwept(dir)) s++;
   if(PatternBreakout(dir)) s++;
   if(RangeExpand()) s++;
   if(OrderBlock(dir)) s++;
   if(FVG(dir)) s++;
   if(MTMF(dir)) s++;
   if(SRFlip(dir)) s++;
   if(MTFAlign(dir)) s++;
   return s;
}

//+------------------------------------------------------------------+
double MinStopDist() {
   long stopL = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeL = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double d = MathMax((double)stopL, (double)freezeL) * g_point;
   return MathMax(d, g_point * 10);
}

double GetATR(ENUM_TIMEFRAMES tf, int sh) {
   int h = (tf == Inp_TrendTF) ? g_atrHTF : g_atrETF;
   double a[];
   if(CopyBuffer(h, 0, sh, 1, a) > 0) return a[0];
   return g_point * 10;
}

//+------------------------------------------------------------------+
bool Bullish() {
   double o0 = iOpen(_Symbol, Inp_EntryTF, 0), c0 = iClose(_Symbol, Inp_EntryTF, 0);
   double o1 = iOpen(_Symbol, Inp_EntryTF, 1), c1 = iClose(_Symbol, Inp_EntryTF, 1);
   if(c0 > o0 && c1 < o1 && c0 > o1 && o0 < c1) return true;
   double h = iHigh(_Symbol, Inp_EntryTF, 0), l = iLow(_Symbol, Inp_EntryTF, 0);
   double body = MathAbs(c0 - o0), lw = MathMin(o0, c0) - l;
   return (body < (h - l) * 0.3 && lw > body * 2 && c0 > o0);
}

bool Bearish() {
   double o0 = iOpen(_Symbol, Inp_EntryTF, 0), c0 = iClose(_Symbol, Inp_EntryTF, 0);
   double o1 = iOpen(_Symbol, Inp_EntryTF, 1), c1 = iClose(_Symbol, Inp_EntryTF, 1);
   if(c0 < o0 && c1 > o1 && c0 < o1 && o0 > c1) return true;
   double h = iHigh(_Symbol, Inp_EntryTF, 0), l = iLow(_Symbol, Inp_EntryTF, 0);
   double body = MathAbs(c0 - o0), uw = h - MathMax(o0, c0);
   return (body < (h - l) * 0.3 && uw > body * 2 && c0 < o0);
}

bool VolSpike() {
   double v0 = (double)iVolume(_Symbol, Inp_EntryTF, 0);
   double sum = 0;
   for(int i = 1; i <= 10; i++) sum += (double)iVolume(_Symbol, Inp_EntryTF, i);
   return (v0 > (sum / 10.0) * Inp_VolumeRatio);
}

bool Momentum(int dir) {
   double rsi[], mMain[], mSig[];
   if(CopyBuffer(g_rsiH, 0, 0, 1, rsi) <= 0) return false;
   if(CopyBuffer(g_macdH, 0, 0, 1, mMain) <= 0) return false;
   if(CopyBuffer(g_macdH, 1, 0, 1, mSig) <= 0) return false;
   if(dir == 1) return (rsi[0] < Inp_RSI_OS && mMain[0] > mSig[0] && mMain[0] < 0);
   if(dir == -1) return (rsi[0] > Inp_RSI_OB && mMain[0] < mSig[0] && mMain[0] > 0);
   return false;
}

bool LiqSwept(int dir) {
   double rh = iHigh(_Symbol, Inp_EntryTF, iHighest(_Symbol, Inp_EntryTF, MODE_HIGH, 10, 1));
   double rl = iLow(_Symbol, Inp_EntryTF, iLowest(_Symbol, Inp_EntryTF, MODE_LOW, 10, 1));
   double sweep = (rh - rl) * Inp_LiquiditySweepPct;
   double h0 = iHigh(_Symbol, Inp_EntryTF, 0);
   double l0 = iLow(_Symbol, Inp_EntryTF, 0);
   double c0 = iClose(_Symbol, Inp_EntryTF, 0);
   if(dir == 1) return (l0 < rl - sweep && c0 > rl);
   if(dir == -1) return (h0 > rh + sweep && c0 < rh);
   return false;
}

bool PatternBreakout(int dir) {
   double h20 = iHigh(_Symbol, Inp_EntryTF, iHighest(_Symbol, Inp_EntryTF, MODE_HIGH, 20, 0));
   double l20 = iLow(_Symbol, Inp_EntryTF, iLowest(_Symbol, Inp_EntryTF, MODE_LOW, 20, 0));
   double h5 = iHigh(_Symbol, Inp_EntryTF, iHighest(_Symbol, Inp_EntryTF, MODE_HIGH, 5, 0));
   double l5 = iLow(_Symbol, Inp_EntryTF, iLowest(_Symbol, Inp_EntryTF, MODE_LOW, 5, 0));
   if(h20 - l20 == 0) return false;
   if((h5 - l5) / (h20 - l20) >= 0.3) return false;
   double c0 = iClose(_Symbol, Inp_EntryTF, 0);
   if(dir == 1 && c0 > h5) return true;
   if(dir == -1 && c0 < l5) return true;
   return false;
}

bool RangeExpand() {
   double a0 = GetATR(Inp_EntryTF, 0), a1 = GetATR(Inp_EntryTF, 1);
   return (a1 > 0 && a0 / a1 > 1.2);
}

bool OrderBlock(int dir) {
   for(int i = 1; i < 10; i++) {
      double o = iOpen(_Symbol, Inp_EntryTF, i);
      double c = iClose(_Symbol, Inp_EntryTF, i);
      double body = MathAbs(c - o);
      double range = iHigh(_Symbol, Inp_EntryTF, i) - iLow(_Symbol, Inp_EntryTF, i);
      if(dir == 1 && c > o && body > range * 0.6) {
         double h = iHigh(_Symbol, Inp_EntryTF, i);
         if(iClose(_Symbol, Inp_EntryTF, 0) >= h * 0.99) return true;
      }
      if(dir == -1 && c < o && body > range * 0.6) {
         double l = iLow(_Symbol, Inp_EntryTF, i);
         if(iClose(_Symbol, Inp_EntryTF, 0) <= l * 1.01) return true;
      }
   }
   return false;
}

bool FVG(int dir) {
   double h0 = iHigh(_Symbol, Inp_EntryTF, 0), l0 = iLow(_Symbol, Inp_EntryTF, 0);
   double h2 = iHigh(_Symbol, Inp_EntryTF, 2), l2 = iLow(_Symbol, Inp_EntryTF, 2);
   if(dir == 1 && l0 > h2 && iClose(_Symbol, Inp_EntryTF, 1) < l0) return true;
   if(dir == -1 && h0 < l2 && iClose(_Symbol, Inp_EntryTF, 1) > h0) return true;
   return false;
}

bool MTMF(int dir) {
   double rsi[];
   if(CopyBuffer(g_rsiH, 0, 0, 2, rsi) < 2) return false;
   double p0 = iClose(_Symbol, Inp_EntryTF, 0);
   double p1 = iClose(_Symbol, Inp_EntryTF, 1);
   if(dir == 1 && p0 < p1 && rsi[0] > rsi[1]) return true;
   if(dir == -1 && p0 > p1 && rsi[0] < rsi[1]) return true;
   return false;
}

bool SRFlip(int dir) {
   double sup = iLow(_Symbol, Inp_EntryTF, iLowest(_Symbol, Inp_EntryTF, MODE_LOW, 10, 1));
   double res = iHigh(_Symbol, Inp_EntryTF, iHighest(_Symbol, Inp_EntryTF, MODE_HIGH, 10, 1));
   double price = iClose(_Symbol, Inp_EntryTF, 0);
   if(dir == 1 && price > sup && price < sup + 10 * g_point) return true;
   if(dir == -1 && price < res && price > res - 10 * g_point) return true;
   return false;
}

bool MTFAlign(int dir) {
   double maFHTF[], maSHTF[], maFETF[], maSETF[];
   if(CopyBuffer(g_maFastHTF, 0, 0, 1, maFHTF) <= 0) return false;
   if(CopyBuffer(g_maSlowHTF, 0, 0, 1, maSHTF) <= 0) return false;
   if(CopyBuffer(g_maFastETF, 0, 0, 1, maFETF) <= 0) return false;
   if(CopyBuffer(g_maSlowETF, 0, 0, 1, maSETF) <= 0) return false;
   bool htfUp = maFHTF[0] > maSHTF[0];
   bool etfUp = maFETF[0] > maSETF[0];
   if(dir == 1 && htfUp && etfUp) return true;
   if(dir == -1 && !htfUp && !etfUp) return true;
   return false;
}

//+------------------------------------------------------------------+
bool ExecMarket(int dir, double sl, double tp, double lot) {
   for(int i = 0; i < 3; i++) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double price = (dir == 1) ? ask : bid;
      
      sl = NormalizeDouble(sl, (int)g_digits);
      tp = NormalizeDouble(tp, (int)g_digits);
      
      if(!ValidateStops(dir, price, sl, tp)) {
         double d = MinStopDist();
         sl = (dir == 1) ? price - d : price + d;
         sl = NormalizeDouble(sl, (int)g_digits);
         tp = (dir == 1) ? price + d * 2 : price - d * 2;
         tp = NormalizeDouble(tp, (int)g_digits);
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
            Print("Market ", dir == 1 ? "BUY" : "SELL", " | ", price);
            return true;
         }
      }
      if(res.retcode == 10019) Sleep(100 + i * 100);
   }
   return false;
}

bool ExecPending(ENUM_ORDER_TYPE ot, double price, double lot, int dir, double sl, double tp) {
   price = NormalizeDouble(price, (int)g_digits);
   double d = MinStopDist();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double cur = (dir == 1) ? ask : bid;
   
   bool isBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
   double vsl = sl, vtp = tp;
   
   if(isBuy) {
      if(sl >= price || sl >= cur) vsl = MathMin(price, cur) - MathMax(d, g_point * 10);
      if(tp <= price || tp <= cur) vtp = MathMax(price, cur) + d * 2;
   } else {
      if(sl <= price || sl <= cur) vsl = MathMax(price, cur) + MathMax(d, g_point * 10);
      if(tp >= price || tp >= cur) vtp = MathMin(price, cur) - d * 2;
   }
   
   vsl = NormalizeDouble(MathMax(vsl, g_point), (int)g_digits);
   vtp = NormalizeDouble(MathMax(vtp, g_point), (int)g_digits);
   
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
   req.expiration = TimeCurrent() + Inp_PendingExpiryBars * (int)PeriodSeconds(Inp_EntryTF);
   
   if(OrderSend(req, res)) {
      if(res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE) {
         Print("Pending ", EnumToString(ot), " | ", price);
         return true;
      }
      Print("Pending err ", res.retcode);
   }
   return false;
}

bool ValidateStops(int dir, double ent, double sl, double tp) {
   double d = MinStopDist();
   if(dir == 1) {
      if(sl >= ent - d * 0.5) return false;
      if(tp <= ent + d) return false;
   } else {
      if(sl <= ent + d * 0.5) return false;
      if(tp >= ent - d) return false;
   }
   return true;
}

void RemoveExpired() {
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
                  if(OrderSend(req, res)) Print("Removed #", tk);
               }
            }
         }
      }
   }
}

void TrailStops() {
   double atr = GetATR(Inp_EntryTF, 0);
   double tStart = Inp_TrailingStart * atr;
   double tStep = Inp_TrailingStep * atr;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk)) {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) == g_magic) {
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               double prof = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - open) / g_point;
               if(prof >= tStart / g_point) {
                  double nsl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - tStep;
                  nsl = NormalizeDouble(nsl, (int)g_digits);
                  if(nsl > sl) {
                     MqlTradeRequest req = {}; MqlTradeResult res = {};
                     req.action = TRADE_ACTION_SLTP;
                     req.position = tk;
                     req.sl = nsl;
                     req.tp = tp;
                     if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE))
                        Print("Trail BUY #", tk, " SL ", nsl);
                  }
               }
            } else {
               double prof = (open - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / g_point;
               if(prof >= tStart / g_point) {
                  double nsl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + tStep;
                  nsl = NormalizeDouble(nsl, (int)g_digits);
                  if(nsl < sl || sl == 0) {
                     MqlTradeRequest req = {}; MqlTradeResult res = {};
                     req.action = TRADE_ACTION_SLTP;
                     req.position = tk;
                     req.sl = nsl;
                     req.tp = tp;
                     if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE))
                        Print("Trail SELL #", tk, " SL ", nsl);
                  }
               }
            }
         }
      }
   }
}

string ErrDesc(int c) {
   switch(c) {
      case 10006: return "REJECT"; case 10015: return "BAD_STOPS";
      case 10019: return "PRICE_CHANGED"; case 10016: return "DISABLED";
      default: return "Err" + IntegerToString(c);
   }
}