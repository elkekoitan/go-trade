package engine

import (
	"math"

	"go-trade/internal/model"
)

// MarketDetector analyzes recent tick data to detect market conditions
// (range, trend, volatile) using simplified ATR and ADX approximations.
type MarketDetector struct {
	atrPeriod int
	adxPeriod int
	rangeADX  float64 // Below this = range
	trendADX  float64 // Above this = trend
}

// NewMarketDetector creates a market condition detector.
func NewMarketDetector(atrPeriod, adxPeriod int, rangeADX, trendADX float64) *MarketDetector {
	return &MarketDetector{
		atrPeriod: atrPeriod,
		adxPeriod: adxPeriod,
		rangeADX:  rangeADX,
		trendADX:  trendADX,
	}
}

// MarketAnalysis holds the result of market detection.
type MarketAnalysis struct {
	State     model.MarketState
	ATR       float64
	AvgATR    float64
	ATRRatio  float64
	Spread    float64
	IsConsolidating bool
}

// Analyze evaluates tick data to determine market condition.
// Requires at least atrPeriod+1 ticks to compute ATR.
func (d *MarketDetector) Analyze(ticks []model.Tick) MarketAnalysis {
	result := MarketAnalysis{State: model.MarketRange}

	if len(ticks) < d.atrPeriod+1 {
		return result
	}

	// Compute True Range series
	n := len(ticks)
	trSeries := make([]float64, 0, n-1)
	for i := 1; i < n; i++ {
		prevMid := (ticks[i-1].Bid + ticks[i-1].Ask) / 2
		curHigh := ticks[i].Ask
		curLow := ticks[i].Bid
		tr := math.Max(curHigh-curLow, math.Max(
			math.Abs(curHigh-prevMid),
			math.Abs(curLow-prevMid),
		))
		trSeries = append(trSeries, tr)
	}

	if len(trSeries) < d.atrPeriod {
		return result
	}

	// Current ATR = average of last atrPeriod true ranges
	atr := sma(trSeries[len(trSeries)-d.atrPeriod:])
	result.ATR = atr

	// Average ATR over longer lookback (50 periods or available)
	lookback := 50
	if len(trSeries) < lookback {
		lookback = len(trSeries)
	}
	avgATR := sma(trSeries[len(trSeries)-lookback:])
	result.AvgATR = avgATR

	// ATR ratio for consolidation detection
	if avgATR > 0 {
		result.ATRRatio = atr / avgATR
	}
	result.IsConsolidating = result.ATRRatio < 0.5

	// Spread
	last := ticks[len(ticks)-1]
	result.Spread = last.Ask - last.Bid

	// Simplified directional movement approximation
	// Use tick mid-price momentum as a proxy for ADX
	adxApprox := d.approximateADX(ticks)

	if adxApprox < d.rangeADX {
		result.State = model.MarketRange
	} else if adxApprox >= d.trendADX {
		result.State = model.MarketTrend
	} else {
		// Between rangeADX and trendADX, check volatility
		if result.ATRRatio > 2.0 {
			result.State = model.MarketVolatile
		} else {
			result.State = model.MarketRange
		}
	}

	return result
}

// approximateADX computes a simplified ADX-like trend strength from tick data.
// This uses rolling directional movement on mid prices.
func (d *MarketDetector) approximateADX(ticks []model.Tick) float64 {
	n := len(ticks)
	period := d.adxPeriod
	if n < period+1 {
		return 0
	}

	// Calculate +DM and -DM series from mid prices
	var plusDM, minusDM float64
	for i := n - period; i < n; i++ {
		curMid := (ticks[i].Bid + ticks[i].Ask) / 2
		prevMid := (ticks[i-1].Bid + ticks[i-1].Ask) / 2
		diff := curMid - prevMid
		if diff > 0 {
			plusDM += diff
		} else {
			minusDM += math.Abs(diff)
		}
	}

	total := plusDM + minusDM
	if total == 0 {
		return 0
	}

	// DX = |plusDM - minusDM| / total * 100
	dx := math.Abs(plusDM-minusDM) / total * 100

	return dx
}

// ConsolidationFilter wraps MarketDetector to provide per-symbol
// consolidation detection state.
type ConsolidationFilter struct {
	detector *MarketDetector
	states   map[string]model.ConsolidationState
}

// NewConsolidationFilter creates a consolidation filter.
func NewConsolidationFilter(detector *MarketDetector) *ConsolidationFilter {
	return &ConsolidationFilter{
		detector: detector,
		states:   make(map[string]model.ConsolidationState),
	}
}

// Check evaluates if a symbol is consolidating.
func (f *ConsolidationFilter) Check(symbol string, ticks []model.Tick) model.ConsolidationState {
	analysis := f.detector.Analyze(ticks)
	state := model.ConsolidationState{
		Symbol:          symbol,
		CurrentATR:      analysis.ATR,
		AverageATR:      analysis.AvgATR,
		ATRRatio:        analysis.ATRRatio,
		IsConsolidating: analysis.IsConsolidating,
	}
	f.states[symbol] = state
	return state
}

// IsConsolidating returns whether a symbol is currently in consolidation.
func (f *ConsolidationFilter) IsConsolidating(symbol string) bool {
	state, ok := f.states[symbol]
	if !ok {
		return false
	}
	return state.IsConsolidating
}

// sma calculates the simple moving average of a float64 slice.
func sma(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}
