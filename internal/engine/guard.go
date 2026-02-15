package engine

import (
	"go-trade/internal/config"
	"go-trade/internal/model"

	"go.uber.org/zap"
)

// Guard implements the 5-level Balance Guard risk protection system.
// It monitors drawdown and returns the appropriate guard level plus
// any forced actions (hedge, close).
type Guard struct {
	levels []config.DrawdownLevel
	logger *zap.Logger
	prev   model.GuardLevel
}

// NewGuard creates a Balance Guard from configured drawdown levels.
func NewGuard(levels []config.DrawdownLevel, logger *zap.Logger) *Guard {
	return &Guard{
		levels: levels,
		logger: logger,
		prev:   model.GuardGreen,
	}
}

// GuardResult holds the output of a guard evaluation.
type GuardResult struct {
	Level        model.GuardLevel
	MaxGridLevel int
	LotScale     float64
	AllowCascade bool
	AllowStealth bool
	ForceHedge   bool
	ForceClose   bool
}

// Evaluate computes the guard level for the given account state.
// It walks the configured levels from highest threshold to lowest,
// returning the first match.
func (g *Guard) Evaluate(acct model.AccountState) GuardResult {
	dd := acct.DrawdownPct
	result := GuardResult{
		Level:        model.GuardGreen,
		MaxGridLevel: 100,
		LotScale:     1.0,
		AllowCascade: true,
		AllowStealth: true,
	}

	// Walk levels in reverse (highest threshold first)
	for i := len(g.levels) - 1; i >= 0; i-- {
		lvl := g.levels[i]
		if dd >= lvl.ThresholdPercent {
			result.Level = model.GuardLevel(lvl.Name)
			result.MaxGridLevel = lvl.MaxGridLevel
			result.LotScale = lvl.LotScale
			result.AllowCascade = lvl.AllowCascade
			result.AllowStealth = lvl.AllowStealth
			result.ForceHedge = lvl.ForceHedge
			result.ForceClose = lvl.ForceClose
			break
		}
	}

	if result.Level != g.prev {
		g.logger.Warn("guard_level_changed",
			zap.String("account", acct.AccountID),
			zap.String("from", string(g.prev)),
			zap.String("to", string(result.Level)),
			zap.Float64("drawdown_pct", dd),
		)
		g.prev = result.Level
	}

	return result
}

// UpdateDrawdown recalculates drawdown fields on an AccountState
// based on peak equity tracking. Returns the updated state.
func UpdateDrawdown(acct model.AccountState) model.AccountState {
	if acct.Equity > acct.PeakEquity || acct.PeakEquity == 0 {
		acct.PeakEquity = acct.Equity
	}
	if acct.PeakEquity > 0 {
		acct.DrawdownPct = (acct.PeakEquity - acct.Equity) / acct.PeakEquity * 100
	}
	return acct
}
