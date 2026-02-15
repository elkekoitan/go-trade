package engine

import (
	"fmt"
	"math"
	"sort"
	"time"

	"go-trade/internal/config"
	"go-trade/internal/model"

	"go.uber.org/zap"
)

// GridDirection controls what side(s) the grid opens.
type GridDirection int

const (
	GridBothDir GridDirection = iota
	GridBuyOnly
	GridSellOnly
)

// GridEngine manages grid position placement for a single symbol+account.
type GridEngine struct {
	symbol    string
	accountID string
	preset    config.PresetConfig
	state     model.GridState
	logger    *zap.Logger
}

// NewGridEngine creates a grid engine for a symbol.
func NewGridEngine(symbol, accountID string, preset config.PresetConfig, logger *zap.Logger) *GridEngine {
	return &GridEngine{
		symbol:    symbol,
		accountID: accountID,
		preset:    preset,
		logger:    logger,
		state: model.GridState{
			Symbol:    symbol,
			AccountID: accountID,
			Active:    true,
			MaxLevel:  preset.MaxLevels,
			CreatedAt: time.Now(),
		},
	}
}

// State returns the current grid state.
func (g *GridEngine) State() model.GridState {
	return g.state
}

// SetActive enables or disables the grid.
func (g *GridEngine) SetActive(active bool) {
	g.state.Active = active
}

// Evaluate checks if new grid orders should be placed based on current
// price and existing positions. Returns commands to open new grid levels.
func (g *GridEngine) Evaluate(
	bid, ask float64,
	positions []model.Position,
	guard GuardResult,
	direction GridDirection,
	magicBase int,
) []model.Command {
	if !g.state.Active {
		return nil
	}

	// Respect guard max grid level
	maxLevel := g.state.MaxLevel
	if guard.MaxGridLevel < maxLevel {
		maxLevel = guard.MaxGridLevel
	}
	if maxLevel <= 0 {
		return nil
	}

	// Filter positions to only grid magic range (1000-4999)
	gridPositions := filterGridPositions(positions, magicBase, magicBase+3999)

	// Update floating PL and total lots
	g.updateMetrics(gridPositions)

	// If no positions exist, set anchor price to current mid
	if len(gridPositions) == 0 && g.state.AnchorPrice == 0 {
		g.state.AnchorPrice = (bid + ask) / 2
		g.state.CurrentLevel = 0
	}

	if g.state.AnchorPrice == 0 {
		return nil
	}

	mid := (bid + ask) / 2
	spacing := g.preset.GridSpacing // in pips (points for 5-digit)

	var cmds []model.Command

	// Check buy levels (below anchor)
	if direction == GridBothDir || direction == GridBuyOnly {
		cmds = append(cmds, g.checkLevels(
			mid, spacing, model.SideBuy, gridPositions, maxLevel, guard.LotScale, magicBase, ask,
		)...)
	}

	// Check sell levels (above anchor)
	if direction == GridBothDir || direction == GridSellOnly {
		cmds = append(cmds, g.checkLevels(
			mid, spacing, model.SideSell, gridPositions, maxLevel, guard.LotScale, magicBase, bid,
		)...)
	}

	return cmds
}

// checkLevels determines if new grid orders are needed for a given side.
func (g *GridEngine) checkLevels(
	mid, spacing float64,
	side model.Side,
	existing []model.Position,
	maxLevel int,
	lotScale float64,
	magicBase int,
	entryPrice float64,
) []model.Command {
	var cmds []model.Command

	// Count existing positions on this side
	sideCount := 0
	occupiedLevels := make(map[int]bool)
	for _, pos := range existing {
		if pos.Side == side {
			sideCount++
			level := g.priceToLevel(pos.Price, spacing, side)
			occupiedLevels[level] = true
		}
	}

	if sideCount >= maxLevel {
		return nil
	}

	// Check each level
	for level := 1; level <= maxLevel; level++ {
		if occupiedLevels[level] {
			continue
		}

		levelPrice := g.levelToPrice(level, spacing, side)
		distance := math.Abs(mid - levelPrice)

		// Only open if price has reached the level (within half a spacing)
		if distance > spacing*0.6 {
			continue
		}

		// Calculate lot size with multiplier and guard scale
		lot := g.calculateLot(level, lotScale)
		if lot <= 0 {
			continue
		}

		magic := magicBase + level
		if side == model.SideSell {
			magic += 500
		}

		tp := g.calculateTP(entryPrice, side)

		cmd := model.Command{
			Type:      model.CommandOpen,
			Symbol:    g.symbol,
			Side:      side,
			Volume:    lot,
			Price:     entryPrice,
			TP:        tp,
			Magic:     magic,
			AccountID: g.accountID,
			Reason:    fmt.Sprintf("GRID_L%d", level),
			Time:      time.Now(),
		}
		cmds = append(cmds, cmd)

		g.logger.Info("grid_order",
			zap.String("symbol", g.symbol),
			zap.String("side", string(side)),
			zap.Int("level", level),
			zap.Float64("lot", lot),
			zap.Float64("price", entryPrice),
			zap.Float64("tp", tp),
		)
	}

	return cmds
}

// levelToPrice calculates the price for a given grid level.
func (g *GridEngine) levelToPrice(level int, spacing float64, side model.Side) float64 {
	offset := float64(level) * spacing * pipSize(g.symbol)
	if side == model.SideBuy {
		return g.state.AnchorPrice - offset
	}
	return g.state.AnchorPrice + offset
}

// priceToLevel maps a position price back to its approximate grid level.
func (g *GridEngine) priceToLevel(price, spacing float64, side model.Side) int {
	pip := pipSize(g.symbol)
	if pip == 0 {
		return 0
	}
	var distance float64
	if side == model.SideBuy {
		distance = g.state.AnchorPrice - price
	} else {
		distance = price - g.state.AnchorPrice
	}
	level := int(math.Round(distance / (spacing * pip)))
	if level < 1 {
		return 0
	}
	return level
}

// calculateLot computes the lot size for a grid level, applying the
// configured multiplier and guard scale.
func (g *GridEngine) calculateLot(level int, guardScale float64) float64 {
	lot := g.preset.BaseLot
	for i := 1; i < level; i++ {
		lot *= g.preset.LotMultiplier
	}
	lot *= guardScale
	// Round to 2 decimal places
	lot = math.Round(lot*100) / 100
	if lot < 0.01 {
		return 0
	}
	return lot
}

// calculateTP calculates the take-profit price.
func (g *GridEngine) calculateTP(price float64, side model.Side) float64 {
	if g.preset.TPPips <= 0 {
		return 0
	}
	pip := pipSize(g.symbol)
	offset := g.preset.TPPips * pip
	if side == model.SideBuy {
		return price + offset
	}
	return price - offset
}

// updateMetrics recalculates grid state from current positions.
func (g *GridEngine) updateMetrics(positions []model.Position) {
	totalLots := 0.0
	floatingPL := 0.0
	maxLevel := 0
	for _, pos := range positions {
		totalLots += pos.Volume
		floatingPL += pos.ProfitLoss
		level := g.priceToLevel(pos.Price, g.preset.GridSpacing, pos.Side)
		if level > maxLevel {
			maxLevel = level
		}
	}
	g.state.TotalLots = totalLots
	g.state.FloatingPL = floatingPL
	g.state.CurrentLevel = maxLevel
}

// ResetAnchor resets the grid anchor to a new price.
func (g *GridEngine) ResetAnchor(price float64) {
	g.state.AnchorPrice = price
	g.state.CurrentLevel = 0
	g.state.CreatedAt = time.Now()
}

// filterGridPositions returns only positions within the magic number range.
func filterGridPositions(positions []model.Position, magicStart, magicEnd int) []model.Position {
	var out []model.Position
	for _, pos := range positions {
		if pos.Magic >= magicStart && pos.Magic <= magicEnd && !pos.Pending {
			out = append(out, pos)
		}
	}
	return out
}

// pipSize returns the pip multiplier for a symbol.
// For 5-digit forex pairs this is 0.00001, for JPY pairs 0.001, etc.
func pipSize(symbol string) float64 {
	// JPY pairs
	if len(symbol) >= 6 {
		suffix := symbol[3:6]
		if suffix == "JPY" {
			return 0.01
		}
	}
	// Crypto and indices
	switch {
	case len(symbol) >= 3 && (symbol[:3] == "BTC" || symbol[:3] == "ETH" || symbol[:3] == "XAU"):
		return 0.01
	case len(symbol) >= 3 && (symbol[:3] == "US3" || symbol[:3] == "US5" || symbol[:2] == "SP" || symbol[:3] == "NAS"):
		return 0.01
	default:
		return 0.0001 // Standard forex
	}
}

// GridManager manages grid engines across multiple symbols.
type GridManager struct {
	grids  map[string]*GridEngine // key: accountID|symbol
	logger *zap.Logger
}

// NewGridManager creates a grid manager.
func NewGridManager(logger *zap.Logger) *GridManager {
	return &GridManager{
		grids:  make(map[string]*GridEngine),
		logger: logger,
	}
}

// GetOrCreate returns existing grid or creates a new one.
func (m *GridManager) GetOrCreate(symbol, accountID string, preset config.PresetConfig) *GridEngine {
	key := accountID + "|" + symbol
	if g, ok := m.grids[key]; ok {
		return g
	}
	g := NewGridEngine(symbol, accountID, preset, m.logger)
	m.grids[key] = g
	return g
}

// Get returns a grid if it exists.
func (m *GridManager) Get(symbol, accountID string) (*GridEngine, bool) {
	key := accountID + "|" + symbol
	g, ok := m.grids[key]
	return g, ok
}

// AllStates returns the current state of all grids.
func (m *GridManager) AllStates() []model.GridState {
	states := make([]model.GridState, 0, len(m.grids))
	for _, g := range m.grids {
		states = append(states, g.State())
	}
	sort.Slice(states, func(i, j int) bool {
		return states[i].Symbol < states[j].Symbol
	})
	return states
}
