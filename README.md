# Professional Trading Bots for MT5

![Version](https://img.shields.io/badge/Version-12.00-blue)
![MQ5](https://img.shields.io/badge/Language-MQL5-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

> **Professional Trading Bots for Wise and Smart Traders**
> 
> Using large institution concepts and trading techniques

---

## Our Mission

We build **institutional-grade trading bots** that combine:
- **Large institution concepts** - Professional trading desk techniques
- **Market structure analysis** - Support/resistance, liquidity, order flow
- **Multi-confirmation signals** - Minimum 3 confirmations required
- **Proper risk management** - 1:2 Risk:Reward, proper SL/TP on ALL orders

> "We don't just trade - we execute with the precision of institutional traders."

---

## Trading Bots Available

### 1. SmartConsensus Pro v12.0 (Main Production Bot)

**Our flagshtip production-ready trading bot.**

```
Features:
├── All Order Types: Market, Limit, Stop, Stop-Limit
├── Timeframes: H1 (Trend) + M15 (Entry)
├── Daily Target: 6 trades per day
├── Confirmations: 3 required for execution
├── Risk:Reward: 1:2 (configurable)
├── Pending Orders: 12-hour expiry
├── No Auto-Close: Let orders fill or expire naturally
└── Fill Policy: IOC (Immediate or Cancel)
```

**Ideal For:** Continuous daily trading with multiple order types

---

### 2. PriceAction Pro (Pure Price Action)

**Stripped-down price action only version.**

```
Features:
├── Pure Price Action: No indicators needed
├── Candlestick Patterns: Pin bars, engulfing
├── Support/Resistance: Automatic detection
├── Trend: EMA 50/200 alignment
├── Conservative: Higher confirmation threshold
└── Best For: Price action traders
```

**Ideal For:** Traders who prefer pure price action over indicators

---

### 3. SmartConsensus Resilient (with Retries)

**Legacy version with progressive retries.**

```
Features:
├── Market Order Retries: Up to 3 attempts
├── Adaptive SL/TP: Dynamic distance adjustment
├── Spread Protection: Max spread filter
└── Best For: High-spread symbols
```

**Ideal For:** High-spread instruments (crypto, commodities)

---

## Order Types Explained

We teach you how institutions trade:

| Order Type | When to Use | Institutional Concept |
|-----------|------------|------------------|
| **Market** | Immediate entry when signal fires | "Get filled now" |
| **Buy Limit** | Buy below market (dip buying) | "Buy the dip" - Institutional buyers |
| **Sell Limit** | Sell above market (sell rips) | "Sell the rip" - Institutional sellers |
| **Buy Stop** | Breakout above resistance | "Momentum breakout" |
| **Sell Stop** | Breakdown below support | "momentum breakdown" |
| **Buy Stop Limit** | Breakout + retest confirmation | "Advanced confirmation" |

### Critical: Fill Policies

```mql5
// Always specify fill policy!
ORDER_FILLING_IOC   // Immediate or Cancel - Accept partial fill
ORDER_FILLING_FOK  // Fill or Kill - Full volume only
ORDER_FILLING_RETURN // Return - Keep remaining as pending
```

---

## Technical Specifications

### Confirmation Score (Minimum 3 Required)

Each trade requires **3+ confirmations** from these 8 checks:

1. **Candle Pattern** - Bullish/Bearish candle formation
2. **Volume Spike** - Above 1.3x average
3. **Momentum** - RSI + MACD aligned
4. **Liquidity Sweep** - Recent high/low sweep
5. **Consolidation Break** - Tight range breakout
6. **Range Expansion** - ATR expansion > 1.15x
7. **Fair Value Gap** - Price gap filled
8. **Multi-Timeframe** - HTF + LTF aligned

### Risk Management

```mql5
// Always include SL/TP on EVERY order
input double Risk_Percent = 1.0;     // 1% max risk per trade
input double Reward_Risk_Ratio = 2.0;   // 1:2 RR minimum
input int Maximum_Spread = 3000;         // Max spread filter
input int Slippage = 100;            // Slippage tolerance
```

---

## Installation

1. **Download** the `.mq5` file
2. **Open** MetaTrader 5
3. **Press** `Ctrl+O` to open Files
4. **Navigate** to `Experts` folder
5. **Copy** the `.mq5` file
6. **Restart** MT5 or refresh Expert Advisors
7. **Drag** EA onto chart

---

## Upcoming Bots

We are developing more professional bots:

- [ ] **Scalping Pro** - Ultra-low latency scalper
- [ ] **Swing Trader** - Multi-day swing system
- [ ] **News Trader** - News event specialist
- [ ] **Grid Trader** - Market maker grid system
- [ ] **AI Enhanced** - Machine learning filters

---

## Why Professional Traders Choose Us

✅ **No emotional trading** - Rules-based execution  
✅ **Proper SL/TP** - Never trade without protection  
✅ **Multiple confirmations** - Filter out noise  
✅ **Institutional concepts** - How big banks trade  
✅ **Production ready** - Tested code, no debugging  
✅ **Multi-symbol** - Single EA on multiple charts  
✅ **12 trades/day** - Continuous opportunity  

---

## Disclaimer

**Trading involves risk.** Past performance does not guarantee future results. Always:
- Test on demo account first
- Use proper position sizing
- Never risk more than 1-2% per trade
- Understand the strategy before trading live

---

## License

MIT License - Free to use, modify, and distribute.

---

**For questions, support, or custom development:**
- Open an issue on GitHub
- Star the repository ⭐

**Build with precision. Trade with confidence.**

*SmartConsensus - Professional Trading Bots*