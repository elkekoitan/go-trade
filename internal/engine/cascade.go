package engine

import (
	"fmt"
	"math"
	"time"

	"go-trade/internal/model"

	"go.uber.org/zap"
)

// CascadeEngine manages progressive take-profit levels (R1-R6)
// for grid positions on a single symbol+account.
type CascadeEngine struct {
	symbol    string
	accountID string
	levels    []model.CascadeLevel
	maxDepth  int
	logger    *zap.Logger
}

// NewCascadeEngine creates a cascade engine with the given depth.
func NewCascadeEngine(symbol, accountID string, maxDepth int, logger *zap.Logger) *CascadeEngine {
	if maxDepth > 6 {
		maxDepth = 6
	}
	if maxDepth < 1 {
		maxDepth = 1
	}
	levels := make([]model.CascadeLevel, maxDepth)
	for i := range levels {
		levels[i].Level = i + 1
	}
	return &CascadeEngine{
		symbol:    symbol,
		accountID: accountID,
		levels:    levels,
		maxDepth:  maxDepth,
		logger:    logger,
	}
}

// Levels returns the current cascade levels.
func (c *CascadeEngine) Levels() []model.CascadeLevel {
	out := make([]model.CascadeLevel, len(c.levels))
	copy(out, c.levels)
	return out
}

// Initialize sets cascade level prices based on the anchor price and spacing.
func (c *CascadeEngine) Initialize(anchorPrice, spacing float64, side model.Side) {
	pip := pipSize(c.symbol)
	for i := range c.levels {
		depth := float64(i+1) * spacing * pip
		if side == model.SideBuy {
			c.levels[i].Price = anchorPrice - depth
		} else {
			c.levels[i].Price = anchorPrice + depth
		}
		// K-level take profits: each deeper level has a wider TP
		tpMultiplier := 1.0 + float64(i)*0.5
		c.levels[i].TPPrice = c.calculateTP(c.levels[i].Price, side, spacing*tpMultiplier, pip)
		c.levels[i].Triggered = false
		c.levels[i].TPHit = false
	}
}

// calculateTP computes the take-profit price for a cascade level.
func (c *CascadeEngine) calculateTP(price float64, side model.Side, pips, pip float64) float64 {
	offset := pips * pip
	if side == model.SideBuy {
		return price + offset
	}
	return price - offset
}

// Evaluate checks cascade trigger conditions against current price
// and positions. Returns commands for any new cascade entries.
func (c *CascadeEngine) Evaluate(
	bid, ask float64,
	positions []model.Position,
	guard GuardResult,
	gridPreset GridCascadeParams,
) []model.Command {
	if !guard.AllowCascade {
		return nil
	}

	mid := (bid + ask) / 2
	var cmds []model.Command

	for i := range c.levels {
		if c.levels[i].Triggered {
			// Check if TP hit for this cascade level
			if !c.levels[i].TPHit && c.isTPHit(c.levels[i], mid, positions) {
				c.levels[i].TPHit = true
				// Close positions at this cascade level
				closeCmds := c.buildCascadeClose(c.levels[i], positions)
				cmds = append(cmds, closeCmds...)
				c.logger.Info("cascade_tp_hit",
					zap.String("symbol", c.symbol),
					zap.Int("level", c.levels[i].Level),
					zap.Float64("tp_price", c.levels[i].TPPrice),
				)
			}
			continue
		}

		// Check trigger condition
		if c.isTriggered(c.levels[i], mid) {
			c.levels[i].Triggered = true
			c.logger.Info("cascade_triggered",
				zap.String("symbol", c.symbol),
				zap.Int("level", c.levels[i].Level),
				zap.Float64("price", c.levels[i].Price),
			)

			// Generate cascade order
			cmd := c.buildCascadeOrder(c.levels[i], gridPreset, guard, bid, ask)
			if cmd != nil {
				cmds = append(cmds, *cmd)
			}
		}
	}

	return cmds
}

// isTriggered checks if price has reached the cascade level.
func (c *CascadeEngine) isTriggered(level model.CascadeLevel, mid float64) bool {
	pip := pipSize(c.symbol)
	tolerance := pip * 2 // 2 pip tolerance
	return math.Abs(mid-level.Price) <= tolerance
}

// isTPHit checks if the take-profit for a cascade level has been reached.
func (c *CascadeEngine) isTPHit(level model.CascadeLevel, mid float64, positions []model.Position) bool {
	// Determine the effective side of the cascade
	hasBuy := false
	hasSell := false
	for _, pos := range positions {
		if pos.Side == model.SideBuy {
			hasBuy = true
		} else {
			hasSell = true
		}
	}

	if hasBuy && mid >= level.TPPrice {
		return true
	}
	if hasSell && mid <= level.TPPrice {
		return true
	}
	return false
}

// buildCascadeOrder creates a command for a new cascade entry.
func (c *CascadeEngine) buildCascadeOrder(
	level model.CascadeLevel,
	params GridCascadeParams,
	guard GuardResult,
	bid, ask float64,
) *model.Command {
	lot := params.BaseLot * math.Pow(params.LotMultiplier, float64(level.Level-1))
	lot *= guard.LotScale
	lot = math.Round(lot*100) / 100
	if lot < 0.01 {
		return nil
	}

	// Cascade opens in the dominant direction
	side := params.Direction
	price := ask
	if side == model.SideSell {
		price = bid
	}

	magic := 1000 + level.Level*100

	return &model.Command{
		Type:      model.CommandOpen,
		Symbol:    c.symbol,
		Side:      side,
		Volume:    lot,
		Price:     price,
		TP:        level.TPPrice,
		Magic:     magic,
		AccountID: c.accountID,
		Reason:    fmt.Sprintf("CASCADE_R%d", level.Level),
		Time:      time.Now(),
	}
}

// buildCascadeClose creates close commands for positions associated with a cascade level.
func (c *CascadeEngine) buildCascadeClose(level model.CascadeLevel, positions []model.Position) []model.Command {
	var cmds []model.Command
	for _, pos := range positions {
		// Match positions by magic number pattern
		expectedMagic := 1000 + level.Level*100
		if pos.Magic >= expectedMagic && pos.Magic < expectedMagic+100 {
			cmds = append(cmds, model.Command{
				Type:      model.CommandClose,
				Symbol:    c.symbol,
				Side:      pos.Side,
				Ticket:    pos.ID,
				Volume:    pos.Volume,
				AccountID: c.accountID,
				Reason:    fmt.Sprintf("CASCADE_R%d_TP", level.Level),
				Time:      time.Now(),
			})
		}
	}
	return cmds
}

// Reset resets all cascade levels to untriggered state.
func (c *CascadeEngine) Reset() {
	for i := range c.levels {
		c.levels[i].Triggered = false
		c.levels[i].TPHit = false
	}
}

// GridCascadeParams holds parameters shared between grid and cascade.
type GridCascadeParams struct {
	BaseLot       float64
	LotMultiplier float64
	Direction     model.Side
}

// CascadeManager manages cascade engines across symbols.
type CascadeManager struct {
	cascades map[string]*CascadeEngine // key: accountID|symbol
	logger   *zap.Logger
}

// NewCascadeManager creates a cascade manager.
func NewCascadeManager(logger *zap.Logger) *CascadeManager {
	return &CascadeManager{
		cascades: make(map[string]*CascadeEngine),
		logger:   logger,
	}
}

// GetOrCreate returns existing cascade or creates a new one.
func (m *CascadeManager) GetOrCreate(symbol, accountID string, maxDepth int) *CascadeEngine {
	key := accountID + "|" + symbol
	if c, ok := m.cascades[key]; ok {
		return c
	}
	c := NewCascadeEngine(symbol, accountID, maxDepth, m.logger)
	m.cascades[key] = c
	return c
}

// Get returns a cascade engine if it exists.
func (m *CascadeManager) Get(symbol, accountID string) (*CascadeEngine, bool) {
	key := accountID + "|" + symbol
	c, ok := m.cascades[key]
	return c, ok
}
