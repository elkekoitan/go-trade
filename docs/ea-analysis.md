# MQL5 Expert Advisor Analysis

Analysis of reference EAs in `ea/reference/` for porting trading logic to Go engine.

## Source Files
- `ticktrade.mq5` (TickDecisionEA v3.00) - Tick-based smart decision with multi-indicator scoring
- `ticktradev8.mq5` (TickTrader Pro v8.0) - Multi-instrument with SmartClose and consolidation filter
- `ticktrav8.1.mq5` (v8.1) - Updated version
- `ticktradev7sc-hs%$-islem30+-.mq5` (v7.0) - Earlier variant

## 1. Composite Scoring System

### Indicator Weights (ticktrade.mq5)

| Indicator | Weight | Signal Range |
|-----------|--------|-------------|
| RSI (14) | 20 | Oversold <30: BUY, Overbought >70: SELL |
| MACD (12/26/9) | 25 | Crossover: +/-50, Histogram momentum: +/-20, Zero line: +/-10 |
| Bollinger Bands (20, 2.0) | 15 | Below 10%: +80, Above 90%: -80 |
| Moving Average (EMA 10/50) | 20 | Cross: +/-60, Distance-based: +/-40 |
| Stochastic (14/3/3) | 10 | K<20 + K>D: +80, K>80 + K<D: -80 |
| ADX (14) | 10 | DI+ > DI-: BUY, scaled by ADX/25 trend strength |

### Scoring Algorithm
```
For each indicator:
  1. Calculate raw signal (-100 to +100)
  2. Multiply by weight
  3. Sum weighted scores
  4. Divide by total weight
  5. Clamp to [-100, +100]

Direction decision:
  Score > +30  → BUY only
  Score < -30  → SELL only
  -30 to +30   → Both directions (or force by strategy)
```

### Port Target: `internal/engine/scoring.go`

## 2. SmartClose Algorithm (ticktradev8.mq5)

### Trigger Conditions
- Drawdown reaches configured threshold (default 10%)
- Dollar loss reaches threshold (default $20)

### Closing Logic
1. Find the single worst-performing position
2. Find the best group of positions (by combined P&L)
3. Close worst position + best group if net P&L is positive
4. Groups: 3-6 profitable position groupings tested

### Aggressive Mode
Scales thresholds based on drawdown severity:
- DD >= 20%: min loss threshold = 25% of normal
- DD >= 15%: min loss threshold = 50% of normal
- DD >= 10%: min loss threshold = 75% of normal

### Port Target: `internal/engine/smartclose.go`

## 3. Grid Management (ticktradev8.mq5)

### Order Configuration
- Buy Limit levels: 3 (below market, default 100pt spacing)
- Buy Stop levels: 2 (above market)
- Sell Limit levels: 3 (above market)
- Sell Stop levels: 2 (below market)
- Maximum distance: 400 points from current price

### Position Limits
- Max open positions: 30
- Max total lots: 0.30
- Fixed lot: 0.01
- Min free margin: $50
- Min margin level: 30%
- Max drawdown: 40% (auto-liquidation)
- Max position range: 500 points

### Recovery Grid
- Activated when loss > $1.00
- Grid shift: 20 points from main grid
- Creates rescue orders to catch reversals

### Port Target: `internal/engine/grid.go`

## 4. Consolidation Filter (ticktradev8.mq5)

### Detection Method
- ATR period: 14 bars
- Calculate current ATR / average ATR ratio
- Min ATR ratio: 0.5 (below = consolidation/horizontal)
- Max ATR ratio: 2.5 (above = strong trend)
- Lookback: 50 bars for average

### Behavior
- When consolidation detected: pause new grid orders
- Auto-restart when ATR ratio returns to normal range
- Can be used to switch between range/trend presets

### Port Target: `internal/engine/market.go` (as part of MarketDetector)

## 5. Profit Hierarchy (ticktradev8.mq5)

### 3-Tier Take Profit
| Level | Target | Action |
|-------|--------|--------|
| Single Position TP | $0.50 | Close individual position |
| Group TP (buy or sell) | $3.00 | Close all positions of one side |
| Total Portfolio TP | $5.00 | Close everything |
| Maximum Loss SL | -$50.00 | Emergency close all |

### Port Target: `internal/engine/engine.go` (profit monitoring in main loop)

## 6. Explorer Mode (ticktrade.mq5)

### Multi-Symbol Scanning
- Scans up to 10 symbols every 30 seconds
- For each symbol: calculate composite score using temp indicator handles
- Select symbol with highest absolute score (if > MinScore threshold)
- Auto-switch indicators when symbol changes

### Scoring Per Symbol
Same algorithm as composite scoring but:
- Creates temporary indicator handles
- Releases handles after scoring
- Normalized to [-100, +100] per symbol

### Port Target: This is EA-side logic. In Go architecture, each account runs on a specific symbol. Multi-symbol scanning can be implemented as a Go-side market scanner that recommends symbol switches via dashboard.

## 7. Position Partitioning (ticktradev8.mq5)

### 3-Partition System
- **Robot positions**: Magic number matches EA (tracked for grid/close logic)
- **Other EA positions**: Different magic numbers (monitored but not managed)
- **Manual positions**: Magic = 0 (monitored but not managed)

### Port Target: `internal/engine/store.go` (position filtering by magic range)

## 8. Key Parameters to Expose in Config

From EA analysis, these parameters should be configurable in `config/config.yaml`:

```yaml
scoring:
  rsiPeriod: 14
  rsiWeight: 20
  macdFast: 12
  macdSlow: 26
  macdSignal: 9
  macdWeight: 25
  bbPeriod: 20
  bbDeviation: 2.0
  bbWeight: 15
  maFast: 10
  maSlow: 50
  maWeight: 20
  stochK: 14
  stochD: 3
  stochSlow: 3
  stochWeight: 10
  adxPeriod: 14
  adxWeight: 10
  minScore: 30

smartclose:
  drawdownTrigger: 10.0    # percent
  dollarLossTrigger: 20.0
  minGroupSize: 3
  maxGroupSize: 6
  aggressiveMode: true

grid:
  buyLimitLevels: 3
  buyStopLevels: 2
  sellLimitLevels: 3
  sellStopLevels: 2
  gridStep: 100            # points
  maxDistance: 400          # points
  maxPositions: 30
  maxTotalLots: 0.30
  recoveryEnabled: true
  recoveryShift: 20        # points
  recoveryMinLoss: 1.0     # dollars

consolidation:
  atrPeriod: 14
  minAtrRatio: 0.5
  maxAtrRatio: 2.5
  lookbackPeriod: 50

profit:
  singleTP: 0.50
  groupTP: 3.00
  totalTP: 5.00
  maxLoss: -50.00
```
