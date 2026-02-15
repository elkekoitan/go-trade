package engine

import (
	"math"

	"go-trade/internal/model"
)

// Scoring implements the composite multi-indicator scoring system.
// It uses simplified indicator calculations from tick data to produce
// a direction score from -100 to +100.
type Scoring struct {
	rsiPeriod  int
	maFast     int
	maSlow     int
	bbPeriod   int
	bbDeviation float64
	stochPeriod int
	stochSmooth int
}

// NewScoring creates a scoring engine with standard parameters.
func NewScoring() *Scoring {
	return &Scoring{
		rsiPeriod:   14,
		maFast:      10,
		maSlow:      50,
		bbPeriod:    20,
		bbDeviation: 2.0,
		stochPeriod: 14,
		stochSmooth: 3,
	}
}

// weights for each indicator
const (
	wRSI   = 0.20
	wMACD  = 0.25
	wBB    = 0.15
	wMA    = 0.20
	wStoch = 0.10
	wADX   = 0.10
)

// Score computes a composite score for a symbol from its tick history.
func (s *Scoring) Score(symbol string, ticks []model.Tick) model.ScoringResult {
	result := model.ScoringResult{Symbol: symbol}

	mids := tickMids(ticks)
	if len(mids) < s.maSlow+1 {
		return result
	}

	// RSI
	result.RSIScore = s.computeRSI(mids)

	// MACD
	result.MACDScore = s.computeMACD(mids)

	// Bollinger Bands
	result.BBScore = s.computeBB(mids)

	// Moving Average crossover
	result.MAScore = s.computeMA(mids)

	// Stochastic
	result.StochScore = s.computeStoch(mids)

	// ADX (trend strength)
	result.ADXScore = s.computeADX(mids)

	// Composite weighted score
	result.CompositeScore = clamp(
		result.RSIScore*wRSI+
			result.MACDScore*wMACD+
			result.BBScore*wBB+
			result.MAScore*wMA+
			result.StochScore*wStoch+
			result.ADXScore*wADX,
		-100, 100,
	)

	result.TrendStrength = math.Abs(result.CompositeScore)

	if result.CompositeScore > 30 {
		result.Direction = model.SideBuy
	} else if result.CompositeScore < -30 {
		result.Direction = model.SideSell
	} else {
		result.Direction = "" // neutral
	}

	return result
}

// computeRSI calculates RSI score: <30 → +80 (buy), >70 → -80 (sell)
func (s *Scoring) computeRSI(mids []float64) float64 {
	n := len(mids)
	period := s.rsiPeriod
	if n < period+1 {
		return 0
	}

	gains := 0.0
	losses := 0.0
	for i := n - period; i < n; i++ {
		diff := mids[i] - mids[i-1]
		if diff > 0 {
			gains += diff
		} else {
			losses += math.Abs(diff)
		}
	}

	if losses == 0 {
		return -80 // overbought
	}
	rs := (gains / float64(period)) / (losses / float64(period))
	rsi := 100 - 100/(1+rs)

	if rsi < 30 {
		return 80 // oversold → buy
	} else if rsi > 70 {
		return -80 // overbought → sell
	}
	return (50 - rsi) * 2 // linear interpolation
}

// computeMACD calculates MACD signal score
func (s *Scoring) computeMACD(mids []float64) float64 {
	n := len(mids)
	if n < 26 {
		return 0
	}

	ema12 := ema(mids, 12)
	ema26 := ema(mids, 26)
	macdLine := ema12 - ema26
	signal := emaFromSlice(macdHistory(mids), 9)

	score := 0.0

	// Crossover
	if macdLine > signal {
		score += 50
	} else {
		score -= 50
	}

	// Histogram direction
	hist := macdLine - signal
	if hist > 0 {
		score += 20
	} else {
		score -= 20
	}

	// Zero line
	if macdLine > 0 {
		score += 10
	} else {
		score -= 10
	}

	return clamp(score, -100, 100)
}

// computeBB calculates Bollinger Band position score
func (s *Scoring) computeBB(mids []float64) float64 {
	n := len(mids)
	if n < s.bbPeriod {
		return 0
	}

	recent := mids[n-s.bbPeriod:]
	mean := sma(recent)
	stddev := stdDev(recent, mean)

	upper := mean + s.bbDeviation*stddev
	lower := mean - s.bbDeviation*stddev
	current := mids[n-1]

	if upper == lower {
		return 0
	}

	// Percent B: 0% = at lower band, 100% = at upper band
	pctB := (current - lower) / (upper - lower) * 100

	if pctB < 10 {
		return 80 // near lower band → buy
	} else if pctB > 90 {
		return -80 // near upper band → sell
	}
	return (50 - pctB) * 1.6
}

// computeMA calculates moving average crossover score
func (s *Scoring) computeMA(mids []float64) float64 {
	n := len(mids)
	if n < s.maSlow+1 {
		return 0
	}

	fast := sma(mids[n-s.maFast:])
	slow := sma(mids[n-s.maSlow:])

	prevFast := sma(mids[n-s.maFast-1 : n-1])
	prevSlow := sma(mids[n-s.maSlow-1 : n-1])

	score := 0.0

	// Crossover detection
	if prevFast <= prevSlow && fast > slow {
		score += 60 // bullish cross
	} else if prevFast >= prevSlow && fast < slow {
		score -= 60 // bearish cross
	}

	// Distance from slow MA
	if slow > 0 {
		dist := (fast - slow) / slow * 1000
		score += clamp(dist*40, -40, 40)
	}

	return clamp(score, -100, 100)
}

// computeStoch calculates stochastic oscillator score
func (s *Scoring) computeStoch(mids []float64) float64 {
	n := len(mids)
	if n < s.stochPeriod {
		return 0
	}

	recent := mids[n-s.stochPeriod:]
	high := maxVal(recent)
	low := minVal(recent)

	if high == low {
		return 0
	}

	k := (mids[n-1] - low) / (high - low) * 100

	if k < 20 {
		return 80 // oversold → buy
	} else if k > 80 {
		return -80 // overbought → sell
	}
	return (50 - k) * 1.6
}

// computeADX calculates a simplified ADX directional score
func (s *Scoring) computeADX(mids []float64) float64 {
	n := len(mids)
	period := 14
	if n < period+1 {
		return 0
	}

	plusDM := 0.0
	minusDM := 0.0
	for i := n - period; i < n; i++ {
		diff := mids[i] - mids[i-1]
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

	// DI+ vs DI-
	diPlus := plusDM / total * 100
	diMinus := minusDM / total * 100
	dx := math.Abs(diPlus-diMinus) / (diPlus + diMinus) * 100

	score := (diPlus - diMinus) * dx / 25
	return clamp(score, -100, 100)
}

// Helper functions

func tickMids(ticks []model.Tick) []float64 {
	mids := make([]float64, len(ticks))
	for i, t := range ticks {
		mids[i] = (t.Bid + t.Ask) / 2
	}
	return mids
}

func ema(data []float64, period int) float64 {
	if len(data) < period {
		return 0
	}
	k := 2.0 / float64(period+1)
	e := sma(data[:period])
	for i := period; i < len(data); i++ {
		e = data[i]*k + e*(1-k)
	}
	return e
}

func emaFromSlice(data []float64, period int) float64 {
	return ema(data, period)
}

func macdHistory(mids []float64) []float64 {
	if len(mids) < 26 {
		return nil
	}
	history := make([]float64, 0)
	for i := 26; i <= len(mids); i++ {
		e12 := ema(mids[:i], 12)
		e26 := ema(mids[:i], 26)
		history = append(history, e12-e26)
	}
	return history
}

func stdDev(values []float64, mean float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range values {
		diff := v - mean
		sum += diff * diff
	}
	return math.Sqrt(sum / float64(len(values)))
}

func maxVal(values []float64) float64 {
	m := values[0]
	for _, v := range values[1:] {
		if v > m {
			m = v
		}
	}
	return m
}

func minVal(values []float64) float64 {
	m := values[0]
	for _, v := range values[1:] {
		if v < m {
			m = v
		}
	}
	return m
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
