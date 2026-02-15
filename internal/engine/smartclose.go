package engine

import (
	"math"
	"sort"
	"time"

	"go-trade/internal/model"

	"go.uber.org/zap"
)

// SmartClose implements the intelligent position closing algorithm.
// It finds the worst losing position and a group of profitable positions
// that together yield a net positive P&L, then closes them all.
type SmartClose struct {
	enabled    bool
	minPnL     float64 // minimum net P&L threshold for smart close ($)
	minDD      float64 // minimum drawdown % to activate
	maxSL      float64 // maximum loss per account before emergency close ($)
	singleTP   float64 // single position TP ($)
	groupTP    float64 // group TP ($)
	portfolioTP float64 // portfolio TP ($)
	logger     *zap.Logger
}

// NewSmartClose creates a new smart close engine.
func NewSmartClose(minPnL, minDD, maxSL float64, logger *zap.Logger) *SmartClose {
	return &SmartClose{
		enabled:     true,
		minPnL:      minPnL,
		minDD:       minDD,
		maxSL:       maxSL,
		singleTP:    0.50,
		groupTP:     3.00,
		portfolioTP: 5.00,
		logger:      logger,
	}
}

// SmartCloseResult holds the evaluation output.
type SmartCloseResult struct {
	ShouldClose bool
	Commands    []model.Command
	Groups      []model.SmartCloseGroup
	Reason      string
}

// Evaluate checks if a smart close should be executed.
func (sc *SmartClose) Evaluate(
	positions []model.Position,
	acct model.AccountState,
) SmartCloseResult {
	if !sc.enabled || len(positions) == 0 {
		return SmartCloseResult{}
	}

	// Emergency check: maximum loss SL
	totalPL := totalProfitLoss(positions)
	if sc.maxSL > 0 && totalPL <= -sc.maxSL {
		return sc.buildEmergencyClose(positions, acct.AccountID, totalPL)
	}

	// Portfolio TP check
	if sc.portfolioTP > 0 && totalPL >= sc.portfolioTP {
		return sc.buildPortfolioClose(positions, acct.AccountID, totalPL)
	}

	// Smart close only activates above minimum drawdown
	if acct.DrawdownPct < sc.minDD {
		return SmartCloseResult{}
	}

	// Find worst position (most negative P&L)
	worst := findWorstPosition(positions)
	if worst == nil || worst.ProfitLoss >= 0 {
		return SmartCloseResult{}
	}

	// Find best group of profitable positions that can offset the worst
	group := findBestGroup(positions, *worst, sc.minPnL)
	if group == nil {
		return SmartCloseResult{}
	}

	// Build close commands
	var cmds []model.Command
	// Close the worst position
	cmds = append(cmds, model.Command{
		Type:      model.CommandClose,
		Symbol:    worst.Symbol,
		Side:      worst.Side,
		Ticket:    worst.ID,
		Volume:    worst.Volume,
		AccountID: acct.AccountID,
		Reason:    "SMART_CLOSE_WORST",
		Time:      time.Now(),
	})

	// Close the profitable group
	for _, posID := range group.Positions {
		pos := findPositionByID(positions, posID)
		if pos != nil {
			cmds = append(cmds, model.Command{
				Type:      model.CommandClose,
				Symbol:    pos.Symbol,
				Side:      pos.Side,
				Ticket:    pos.ID,
				Volume:    pos.Volume,
				AccountID: acct.AccountID,
				Reason:    "SMART_CLOSE_GROUP",
				Time:      time.Now(),
			})
		}
	}

	sc.logger.Info("smart_close_triggered",
		zap.Float64("worst_pl", worst.ProfitLoss),
		zap.Float64("group_pl", group.NetPL),
		zap.Int("group_size", group.GroupSize),
		zap.Float64("net_pl", group.NetPL+worst.ProfitLoss),
	)

	return SmartCloseResult{
		ShouldClose: true,
		Commands:    cmds,
		Groups:      []model.SmartCloseGroup{*group},
		Reason:      "SMART_CLOSE",
	}
}

// buildEmergencyClose creates close-all commands when max loss is hit.
func (sc *SmartClose) buildEmergencyClose(
	positions []model.Position, accountID string, totalPL float64,
) SmartCloseResult {
	var cmds []model.Command
	for _, pos := range positions {
		if pos.Pending {
			continue
		}
		cmds = append(cmds, model.Command{
			Type:      model.CommandClose,
			Symbol:    pos.Symbol,
			Side:      pos.Side,
			Ticket:    pos.ID,
			Volume:    pos.Volume,
			AccountID: accountID,
			Reason:    "EMERGENCY_MAX_LOSS",
			Time:      time.Now(),
		})
	}

	sc.logger.Warn("emergency_close",
		zap.Float64("total_pl", totalPL),
		zap.Float64("max_sl", sc.maxSL),
		zap.Int("positions", len(cmds)),
	)

	return SmartCloseResult{
		ShouldClose: true,
		Commands:    cmds,
		Reason:      "EMERGENCY_MAX_LOSS",
	}
}

// buildPortfolioClose creates close-all commands when portfolio TP is hit.
func (sc *SmartClose) buildPortfolioClose(
	positions []model.Position, accountID string, totalPL float64,
) SmartCloseResult {
	var cmds []model.Command
	for _, pos := range positions {
		if pos.Pending {
			continue
		}
		cmds = append(cmds, model.Command{
			Type:      model.CommandClose,
			Symbol:    pos.Symbol,
			Side:      pos.Side,
			Ticket:    pos.ID,
			Volume:    pos.Volume,
			AccountID: accountID,
			Reason:    "PORTFOLIO_TP",
			Time:      time.Now(),
		})
	}

	sc.logger.Info("portfolio_tp_hit",
		zap.Float64("total_pl", totalPL),
		zap.Float64("portfolio_tp", sc.portfolioTP),
	)

	return SmartCloseResult{
		ShouldClose: true,
		Commands:    cmds,
		Reason:      "PORTFOLIO_TP",
	}
}

// CheckSingleTP checks individual position take-profits.
func (sc *SmartClose) CheckSingleTP(positions []model.Position, accountID string) []model.Command {
	var cmds []model.Command
	for _, pos := range positions {
		if pos.Pending || pos.ProfitLoss < sc.singleTP {
			continue
		}
		cmds = append(cmds, model.Command{
			Type:      model.CommandClose,
			Symbol:    pos.Symbol,
			Side:      pos.Side,
			Ticket:    pos.ID,
			Volume:    pos.Volume,
			AccountID: accountID,
			Reason:    "SINGLE_TP",
			Time:      time.Now(),
		})
	}
	return cmds
}

// CheckGroupTP checks group take-profits (all buy or all sell for a symbol).
func (sc *SmartClose) CheckGroupTP(positions []model.Position, accountID string) []model.Command {
	// Group by symbol + side
	groups := make(map[string][]model.Position)
	for _, pos := range positions {
		if pos.Pending {
			continue
		}
		key := pos.Symbol + "|" + string(pos.Side)
		groups[key] = append(groups[key], pos)
	}

	var cmds []model.Command
	for _, group := range groups {
		groupPL := 0.0
		for _, pos := range group {
			groupPL += pos.ProfitLoss
		}
		if groupPL >= sc.groupTP {
			for _, pos := range group {
				cmds = append(cmds, model.Command{
					Type:      model.CommandClose,
					Symbol:    pos.Symbol,
					Side:      pos.Side,
					Ticket:    pos.ID,
					Volume:    pos.Volume,
					AccountID: accountID,
					Reason:    "GROUP_TP",
					Time:      time.Now(),
				})
			}
		}
	}
	return cmds
}

// findWorstPosition returns the position with the most negative P&L.
func findWorstPosition(positions []model.Position) *model.Position {
	var worst *model.Position
	for i, pos := range positions {
		if pos.Pending {
			continue
		}
		if worst == nil || pos.ProfitLoss < worst.ProfitLoss {
			worst = &positions[i]
		}
	}
	return worst
}

// findBestGroup finds a group of profitable positions whose combined
// P&L plus the worst position's P&L exceeds the minimum threshold.
func findBestGroup(positions []model.Position, worst model.Position, minNetPL float64) *model.SmartCloseGroup {
	// Collect profitable positions sorted by P&L descending
	var profitable []model.Position
	for _, pos := range positions {
		if pos.ID != worst.ID && !pos.Pending && pos.ProfitLoss > 0 {
			profitable = append(profitable, pos)
		}
	}

	if len(profitable) == 0 {
		return nil
	}

	sort.Slice(profitable, func(i, j int) bool {
		return profitable[i].ProfitLoss > profitable[j].ProfitLoss
	})

	// Greedy: add profitable positions until net P&L is positive enough
	groupPL := 0.0
	var groupIDs []int64
	for _, pos := range profitable {
		groupPL += pos.ProfitLoss
		groupIDs = append(groupIDs, pos.ID)
		netPL := groupPL + worst.ProfitLoss
		if netPL >= minNetPL {
			return &model.SmartCloseGroup{
				Positions: groupIDs,
				NetPL:     netPL,
				GroupSize: len(groupIDs) + 1, // +1 for worst
			}
		}
	}

	return nil
}

// totalProfitLoss sums up P&L across all non-pending positions.
func totalProfitLoss(positions []model.Position) float64 {
	total := 0.0
	for _, pos := range positions {
		if !pos.Pending {
			total += pos.ProfitLoss
		}
	}
	return math.Round(total*100) / 100
}

// findPositionByID finds a position by ticket ID.
func findPositionByID(positions []model.Position, id int64) *model.Position {
	for i, pos := range positions {
		if pos.ID == id {
			return &positions[i]
		}
	}
	return nil
}
