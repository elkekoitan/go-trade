package engine

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"go-trade/internal/bridge"
	"go-trade/internal/config"
	"go-trade/internal/model"

	"go.uber.org/zap"
)

// Engine is the main trading engine orchestrator.
// It reads ticks/positions/accounts from the bridge, updates the store,
// runs grid/cascade/guard/smartclose logic, and dispatches commands.
type Engine struct {
	store    *Store
	bridge   *bridge.Bridge
	signals  chan model.Signal
	commands chan model.Command
	mu       sync.Mutex
	lastSig  map[string]model.Signal
	started  time.Time
	metrics  Metrics
	recentCmds []model.Command
	paused   bool
	frozen   bool
	cfg      ConfigSnapshot
	fullCfg  *config.Config
	logger   *zap.Logger

	// Phase 2 modules
	guard        *Guard
	gridMgr      *GridManager
	cascadeMgr   *CascadeManager
	smartClose   *SmartClose
	detector     *MarketDetector
	consolFilter *ConsolidationFilter
	scoring      *Scoring
}

// Status represents the current engine state for API consumers.
type Status struct {
	Time          time.Time         `json:"time"`
	StartedAt     time.Time         `json:"startedAt"`
	BridgeMode    string            `json:"bridgeMode"`
	Mode          string            `json:"mode"`
	Snapshot      StoreSnapshot     `json:"snapshot"`
	SymbolCount   int               `json:"symbolCount"`
	AccountCount  int               `json:"accountCount"`
	PositionCount int               `json:"positionCount"`
	LastSignals   []model.Signal    `json:"lastSignals"`
	LastCommands  []model.Command   `json:"lastCommands"`
	Metrics       Metrics           `json:"metrics"`
	Config        ConfigSnapshot    `json:"config"`
	LatestTickAt  time.Time         `json:"latestTickAt"`
	LatestSymbol  string            `json:"latestSymbol"`
	GridStates    []model.GridState `json:"gridStates"`
	GuardLevel    model.GuardLevel  `json:"guardLevel"`
}

// Metrics tracks engine processing counters.
type Metrics struct {
	TickCount     int64     `json:"tickCount"`
	PositionCount int64     `json:"positionCount"`
	CommandCount  int64     `json:"commandCount"`
	SignalCount   int64     `json:"signalCount"`
	LastTickAt    time.Time `json:"lastTickAt"`
	LastCommandAt time.Time `json:"lastCommandAt"`
	LastSignalAt  time.Time `json:"lastSignalAt"`
}

// ConfigSnapshot is a serializable view of the active configuration.
type ConfigSnapshot struct {
	BridgeName       string `json:"bridgeName"`
	TickCapacity     int    `json:"tickCapacity"`
	PositionCapacity int    `json:"positionCapacity"`
	CommandCapacity  int    `json:"commandCapacity"`
	AccountCapacity  int    `json:"accountCapacity"`
	DefaultPreset    string `json:"defaultPreset"`
}

// New creates a new Engine from configuration and bridge.
func New(cfg *config.Config, br *bridge.Bridge) *Engine {
	logger := zap.NewNop()

	e := &Engine{
		store:    NewStore(),
		bridge:   br,
		signals:  make(chan model.Signal, 1024),
		commands: make(chan model.Command, 1024),
		lastSig:  make(map[string]model.Signal),
		started:  time.Now(),
		logger:   logger,
		fullCfg:  cfg,
		cfg: ConfigSnapshot{
			BridgeName:       cfg.Bridge.SharedMemoryName,
			TickCapacity:     cfg.Bridge.TickCapacity,
			PositionCapacity: cfg.Bridge.PositionCapacity,
			CommandCapacity:  cfg.Bridge.CommandCapacity,
			AccountCapacity:  cfg.Bridge.AccountCapacity,
			DefaultPreset:    cfg.Engine.DefaultPreset,
		},
	}

	// Initialize Phase 2 modules
	e.guard = NewGuard(cfg.Risk.DrawdownLevels, logger)
	e.gridMgr = NewGridManager(logger)
	e.cascadeMgr = NewCascadeManager(logger)
	e.smartClose = NewSmartClose(
		cfg.Hedge.SmartClosePnl,
		10.0, // min drawdown % to activate smart close
		50.0, // max loss $ emergency close
		logger,
	)
	e.detector = NewMarketDetector(
		cfg.Engine.MarketDetector.ATRPeriod,
		cfg.Engine.MarketDetector.ADXPeriod,
		cfg.Engine.MarketDetector.RangeADX,
		cfg.Engine.MarketDetector.TrendADX,
	)
	e.consolFilter = NewConsolidationFilter(e.detector)
	e.scoring = NewScoring()

	return e
}

// SetLogger sets the structured logger for the engine and all sub-modules.
func (e *Engine) SetLogger(logger *zap.Logger) {
	if logger != nil {
		e.logger = logger
		e.guard.logger = logger
		e.gridMgr.logger = logger
		e.cascadeMgr.logger = logger
		e.smartClose.logger = logger
	}
}

// Store returns the underlying state store (for seeding demo data).
func (e *Engine) Store() *Store {
	return e.store
}

// PushSignal queues a trading signal for processing.
func (e *Engine) PushSignal(sig model.Signal) {
	select {
	case e.signals <- sig:
	default:
	}
	e.mu.Lock()
	e.metrics.SignalCount++
	e.metrics.LastSignalAt = time.Now()
	e.mu.Unlock()
}

// PushCommand queues a command for execution.
func (e *Engine) PushCommand(cmd model.Command) {
	select {
	case e.commands <- cmd:
	default:
	}
}

// StatusJSON returns the engine status as JSON bytes (for API).
func (e *Engine) StatusJSON() ([]byte, error) {
	return json.Marshal(e.Status())
}

// GridStatesJSON returns grid states as JSON bytes.
func (e *Engine) GridStatesJSON() ([]byte, error) {
	return json.Marshal(e.gridMgr.AllStates())
}

// Status returns the current engine status.
func (e *Engine) Status() Status {
	snapshot := e.store.Snapshot()

	latestTickAt := time.Time{}
	latestSymbol := ""
	for _, s := range snapshot.Symbols {
		if s.HasTick && s.Time.After(latestTickAt) {
			latestTickAt = s.Time
			latestSymbol = s.Symbol
		}
	}

	e.mu.Lock()
	mode := "RUNNING"
	if e.frozen {
		mode = "FROZEN"
	} else if e.paused {
		mode = "PAUSED"
	}
	metrics := e.metrics
	signals := make([]model.Signal, 0, len(e.lastSig))
	for _, sig := range e.lastSig {
		signals = append(signals, sig)
	}
	cmds := make([]model.Command, len(e.recentCmds))
	copy(cmds, e.recentCmds)
	guardLevel := e.guard.prev
	e.mu.Unlock()

	positionCount := 0
	for _, pos := range snapshot.Positions {
		if !pos.Pending {
			positionCount++
		}
	}

	return Status{
		Time:          time.Now(),
		StartedAt:     e.started,
		BridgeMode:    string(e.bridge.Mode()),
		Mode:          mode,
		Snapshot:      snapshot,
		SymbolCount:   len(snapshot.Symbols),
		AccountCount:  len(snapshot.Accounts),
		PositionCount: positionCount,
		LastSignals:   signals,
		LastCommands:  cmds,
		Metrics:       metrics,
		Config:        e.cfg,
		LatestTickAt:  latestTickAt,
		LatestSymbol:  latestSymbol,
		GridStates:    e.gridMgr.AllStates(),
		GuardLevel:    guardLevel,
	}
}

// Run starts the engine processing loop. It blocks until ctx is cancelled.
func (e *Engine) Run(ctx context.Context) error {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()

	e.logger.Info("engine_started",
		zap.String("bridge_mode", string(e.bridge.Mode())),
		zap.String("bridge_name", e.cfg.BridgeName),
	)

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case sig := <-e.signals:
			e.mu.Lock()
			e.lastSig[sig.AccountID+"|"+sig.Symbol] = sig
			e.mu.Unlock()
		case cmd := <-e.commands:
			e.handleCommand(cmd)
		case <-ticker.C:
			e.step()
		}
	}
}

// handleCommand processes override commands (pause, resume, etc.)
func (e *Engine) handleCommand(cmd model.Command) {
	switch cmd.Type {
	case model.CommandPause:
		e.mu.Lock()
		e.paused = true
		e.mu.Unlock()
		e.logger.Info("engine_paused")
	case model.CommandResume:
		e.mu.Lock()
		e.paused = false
		e.frozen = false
		e.mu.Unlock()
		e.logger.Info("engine_resumed")
	case model.CommandHedgeAll:
		cmds := e.buildHedgeAllCommands(cmd.AccountID)
		e.sendAll(cmds)
	case model.CommandCloseAll:
		cmds := e.buildCloseAllCommands(cmd.AccountID, "CLOSE_ALL", time.Now())
		e.sendAll(cmds)
	case model.CommandFreeze:
		e.mu.Lock()
		e.frozen = true
		e.mu.Unlock()
		e.logger.Warn("engine_frozen")
	default:
		e.bridge.SendCommand(cmd)
	}

	e.mu.Lock()
	e.metrics.CommandCount++
	e.metrics.LastCommandAt = time.Now()
	e.recentCmds = append(e.recentCmds, cmd)
	if len(e.recentCmds) > 50 {
		e.recentCmds = e.recentCmds[len(e.recentCmds)-50:]
	}
	e.mu.Unlock()
}

// step is the main 50ms processing tick.
func (e *Engine) step() {
	now := time.Now()

	// ── Read data from bridge ──
	ticks := e.bridge.ReadTicks(1024)
	if len(ticks) > 0 {
		e.store.AddTicks(ticks)
		e.mu.Lock()
		e.metrics.TickCount += int64(len(ticks))
		e.metrics.LastTickAt = ticks[len(ticks)-1].Time
		e.mu.Unlock()
	}

	positions := e.bridge.ReadPositions(1024)
	if len(positions) > 0 {
		e.store.UpdatePositions(positions)
		e.mu.Lock()
		e.metrics.PositionCount += int64(len(positions))
		e.mu.Unlock()
	}

	accounts := e.bridge.ReadAccounts(1024)
	if len(accounts) > 0 {
		e.store.UpdateAccounts(accounts)
	}

	e.bridge.Heartbeat(now)

	// ── Skip trading logic if paused or frozen ──
	e.mu.Lock()
	paused := e.paused
	frozen := e.frozen
	e.mu.Unlock()
	if paused || frozen {
		return
	}

	// ── Phase 2: Trading logic ──
	e.processTradingLogic()
}

// processTradingLogic runs grid, cascade, guard, and smart close.
func (e *Engine) processTradingLogic() {
	snapshot := e.store.Snapshot()
	if len(snapshot.Accounts) == 0 {
		return
	}

	preset := e.findPreset(e.cfg.DefaultPreset)
	if preset == nil {
		return
	}

	for _, acct := range snapshot.Accounts {
		// Update drawdown
		acct = UpdateDrawdown(acct)
		e.store.SetAccount(acct)

		// Evaluate guard level
		guard := e.guard.Evaluate(acct)

		// Handle forced actions
		if guard.ForceClose {
			cmds := e.buildCloseAllCommands(acct.AccountID, "GUARD_BLACK", time.Now())
			e.sendAll(cmds)
			e.mu.Lock()
			e.frozen = true
			e.mu.Unlock()
			e.logger.Error("guard_black_close_all",
				zap.String("account", acct.AccountID),
				zap.Float64("drawdown", acct.DrawdownPct),
			)
			continue
		}
		if guard.ForceHedge {
			cmds := e.buildHedgeAllCommands(acct.AccountID)
			e.sendAll(cmds)
			continue
		}

		acctPositions := filterAccountPositions(snapshot.Positions, acct.AccountID)

		// Smart close evaluation
		scResult := e.smartClose.Evaluate(acctPositions, acct)
		if scResult.ShouldClose {
			e.sendAll(scResult.Commands)
			continue
		}

		// Process each symbol
		for _, sym := range snapshot.Symbols {
			if !sym.HasTick || sym.Bid <= 0 || sym.Ask <= 0 || len(sym.Symbol) < 3 {
				continue
			}

			symbolPositions := filterSymbolPositions(acctPositions, sym.Symbol)

			// Consolidation filter
			ticks := e.store.GetTicks(sym.Symbol)
			consol := e.consolFilter.Check(sym.Symbol, ticks)
			if consol.IsConsolidating {
				continue
			}

			// Determine grid direction from scoring
			direction := GridBothDir
			if len(ticks) > 50 {
				score := e.scoring.Score(sym.Symbol, ticks)
				if score.Direction == model.SideBuy {
					direction = GridBuyOnly
				} else if score.Direction == model.SideSell {
					direction = GridSellOnly
				}
			}

			// Grid evaluation
			grid := e.gridMgr.GetOrCreate(sym.Symbol, acct.AccountID, *preset)
			gridCmds := grid.Evaluate(sym.Bid, sym.Ask, symbolPositions, guard, direction, 1000)
			e.sendAll(gridCmds)

			// Cascade evaluation
			if guard.AllowCascade && preset.CascadeLevels > 0 {
				cascade := e.cascadeMgr.GetOrCreate(sym.Symbol, acct.AccountID, preset.CascadeLevels)
				if grid.State().AnchorPrice > 0 {
					if len(cascade.Levels()) > 0 && cascade.Levels()[0].Price == 0 {
						side := model.SideBuy
						if direction == GridSellOnly {
							side = model.SideSell
						}
						cascade.Initialize(grid.State().AnchorPrice, preset.GridSpacing, side)
					}

					cascadeParams := GridCascadeParams{
						BaseLot:       preset.BaseLot,
						LotMultiplier: preset.LotMultiplier,
						Direction:     model.SideBuy,
					}
					if direction == GridSellOnly {
						cascadeParams.Direction = model.SideSell
					}
					cascadeCmds := cascade.Evaluate(sym.Bid, sym.Ask, symbolPositions, guard, cascadeParams)
					e.sendAll(cascadeCmds)
				}
			}
		}
	}
}

// findPreset returns the preset config by name.
func (e *Engine) findPreset(name string) *config.PresetConfig {
	for i := range e.fullCfg.Engine.Presets {
		if e.fullCfg.Engine.Presets[i].Name == name {
			return &e.fullCfg.Engine.Presets[i]
		}
	}
	if len(e.fullCfg.Engine.Presets) > 0 {
		return &e.fullCfg.Engine.Presets[0]
	}
	return nil
}

// buildHedgeAllCommands creates hedge commands for all open positions.
func (e *Engine) buildHedgeAllCommands(accountID string) []model.Command {
	snapshot := e.store.Snapshot()
	cmds := make([]model.Command, 0)
	for _, pos := range snapshot.Positions {
		if pos.Pending {
			continue
		}
		if accountID != "" && pos.AccountID != accountID {
			continue
		}
		side := model.SideBuy
		if pos.Side == model.SideBuy {
			side = model.SideSell
		}
		cmds = append(cmds, model.Command{
			Type:      model.CommandOpen,
			Symbol:    pos.Symbol,
			Side:      side,
			Volume:    pos.Volume,
			Magic:     pos.Magic,
			AccountID: pos.AccountID,
			Reason:    "HEDGE_ALL",
			Time:      time.Now(),
		})
	}
	return cmds
}

// buildCloseAllCommands creates close commands for all open positions.
func (e *Engine) buildCloseAllCommands(accountID, reason string, at time.Time) []model.Command {
	snapshot := e.store.Snapshot()
	cmds := make([]model.Command, 0, len(snapshot.Positions))
	for _, pos := range snapshot.Positions {
		if pos.Pending {
			continue
		}
		if accountID != "" && pos.AccountID != accountID {
			continue
		}
		cmds = append(cmds, model.Command{
			Type:      model.CommandClose,
			Symbol:    pos.Symbol,
			Side:      pos.Side,
			Ticket:    pos.ID,
			Volume:    pos.Volume,
			AccountID: pos.AccountID,
			Reason:    reason,
			Time:      at,
		})
	}
	return cmds
}

// sendAll sends multiple commands through the bridge.
func (e *Engine) sendAll(cmds []model.Command) {
	for _, cmd := range cmds {
		e.bridge.SendCommand(cmd)
		e.mu.Lock()
		e.metrics.CommandCount++
		e.metrics.LastCommandAt = time.Now()
		e.recentCmds = append(e.recentCmds, cmd)
		if len(e.recentCmds) > 50 {
			e.recentCmds = e.recentCmds[len(e.recentCmds)-50:]
		}
		e.mu.Unlock()
	}
}

// filterAccountPositions returns positions for a specific account.
func filterAccountPositions(positions []model.Position, accountID string) []model.Position {
	var out []model.Position
	for _, pos := range positions {
		if pos.AccountID == accountID && !pos.Pending {
			out = append(out, pos)
		}
	}
	return out
}

// filterSymbolPositions returns positions for a specific symbol.
func filterSymbolPositions(positions []model.Position, symbol string) []model.Position {
	var out []model.Position
	for _, pos := range positions {
		if pos.Symbol == symbol {
			out = append(out, pos)
		}
	}
	return out
}
