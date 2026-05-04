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

## Market-Optimized Bots (New!)

Specialized versions of SmartConsensus Pro optimized for specific markets with calibrated settings:

### 1. SmartConsensus_Forex.mq5 (Liquid Forex)
**Optimized for EURUSD, GBPUSD, and other major pairs.**

| Setting | Value | Purpose |
|---------|-------|---------|
| Max Spread | 35 pts (3.5 pips) | Blocks high-cost sessions |
| ATR Filter | 50 pts | Filters dead Asian sessions |
| SL Multiplier | 1.2× ATR | Tight stop for majors |
| Max Lot | **1.0** | Conservative for pairs |
| Trailing | Start 1.0×, Step 0.5× | Secures gains incrementally |
| Risk | 2% | Standard risk |

### 2. SmartConsensus_Gold.mq5 (XAUUSD)
**Optimized for Gold trading on M15 timeframe.**

| Setting | Value | Purpose |
|---------|-------|---------|
| Max Spread | 85 pts ($0.85) | Ceiling for day trading |
| ATR Filter | 180 pts ($1.80) | Ensures healthy momentum |
| SL Multiplier | 1.0× ATR | Tighter than default |
| Max Lot | **0.1** | Low due to high nominal value |
| Trailing | Start 1.2×, Step 0.6× | Locks profit at 20% of move |
| Risk | 2% | Standard risk |

### 3. SmartConsensus_BTC.mq5 (Bitcoin)
**Optimized for BTCUSD with crypto-specific settings.**

| Setting | Value | Purpose |
|---------|-------|---------|
| Max Spread | 3000 pts ($30) | Covers normal volatility |
| ATR Filter | 1000 pts ($10) | Avoids flat ranges |
| SL Multiplier | **0.5× ATR** | Safer for crypto (reduced from 1.5×) |
| Max Lot | **0.1** | Very conservative (high value) |
| Trailing | Start 1.5×, Step 0.75× | Waits for $15 profit before trail |
| Risk | 2% | Standard risk |

### 4. SmartConsensus_ETH.mq5 (Ethereum)
**Optimized for ETHUSD with altcoin considerations.**

| Setting | Value | Purpose |
|---------|-------|---------|
| Max Spread | 500 pts ($5) | Covers liquidity drops |
| ATR Filter | 250 pts ($2.50) | Filters minor spikes |
| SL Multiplier | 0.8× ATR | Balanced for alts |
| Max Lot | **1.0** | Higher than BTC (lower value) |
| Trailing | Start 1.2×, Step 0.6× | Locks at $3.00 profit |
| Risk | 2% | Standard risk |

### 5. SmartConsensus_Oil.mq5 (Crude Oil)
**Optimized for Crude Oil (WTI/Brent) trading.**

| Setting | Value | Purpose |
|---------|-------|---------|
| Max Spread | 12 pts ($0.12) | Highly liquid market |
| ATR Filter | 45 pts ($0.45) | Ensures $0.45+ movement |
| SL Multiplier | 1.2× ATR | Standard for oil |
| Max Lot | **0.1** | Conservative |
| Trailing | Start 1.0×, Step 0.5× | Quick profit lock |
| Risk | 2% | Standard risk |

> **Note:** The original `SmartConsensus_Pro.mq5` is preserved unchanged. Use the specialized versions for better performance per market.

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