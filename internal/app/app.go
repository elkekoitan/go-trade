package app

import (
	"context"
	"errors"
	"math"
	"math/rand"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go-trade/internal/bridge"
	"go-trade/internal/config"
	"go-trade/internal/engine"
	"go-trade/internal/logging"
	"go-trade/internal/model"

	"go.uber.org/zap"
)

// App is the application lifecycle manager.
type App struct {
	cfg *config.Config
}

// New creates a new App instance.
func New(cfg *config.Config) *App {
	return &App{cfg: cfg}
}

// Run starts the full application: bridge, engine, API, and signal handling.
func (a *App) Run() error {
	log, err := logging.Build(a.cfg.App.LogLevel)
	if err != nil {
		return err
	}
	defer log.Sync()

	log.Info("starting hayalet",
		zap.String("version", "0.1.0"),
		zap.String("log_level", a.cfg.App.LogLevel),
	)

	// Open bridge (SHM with pipe fallback)
	br, bridgeErr := bridge.Open(
		a.cfg.Bridge.SharedMemoryName,
		uint32(a.cfg.Bridge.TickCapacity),
		uint32(a.cfg.Bridge.PositionCapacity),
		uint32(a.cfg.Bridge.CommandCapacity),
		uint32(a.cfg.Bridge.AccountCapacity),
	)
	if bridgeErr != nil {
		log.Warn("bridge_fallback", zap.Error(bridgeErr))
	}
	defer br.Close()

	log.Info("bridge_opened", zap.String("mode", string(br.Mode())))

	// Create engine
	eng := engine.New(a.cfg, br)
	eng.SetLogger(log)

	// Seed demo data if SHM is not available (pipe fallback)
	if br.Mode() == bridge.ModePipe {
		log.Info("seeding demo data for pipe mode")
		seedDemoData(eng, log)
	}

	// TODO Phase 4: Start API server
	// TODO Phase 4: Start gRPC server

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error, 2)
	go func() {
		errCh <- eng.Run(ctx)
	}()

	// If demo mode, start live tick simulator
	if br.Mode() == bridge.ModePipe {
		go demoTickLoop(ctx, eng, log)
	}

	// Wait for shutdown signal or fatal error
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Info("shutdown_signal", zap.String("signal", sig.String()))
	case err := <-errCh:
		if err != nil && !errors.Is(err, context.Canceled) {
			log.Error("fatal_error", zap.Error(err))
		}
	}

	cancel()
	log.Info("hayalet stopped")
	return nil
}

// seedDemoData populates the engine store with TickMill demo account data.
func seedDemoData(eng *engine.Engine, log *zap.Logger) {
	store := eng.Store()
	now := time.Now()

	store.SetAccount(model.AccountState{
		AccountID: "25289974",
		Balance:   10000.00,
		Equity:    9847.35,
		Margin:    312.50,
		Time:      now,
	})

	ticks := []model.Tick{
		{Symbol: "EURUSD", Bid: 1.08342, Ask: 1.08354, Time: now},
		{Symbol: "GBPUSD", Bid: 1.26185, Ask: 1.26201, Time: now},
		{Symbol: "USDJPY", Bid: 151.823, Ask: 151.841, Time: now},
		{Symbol: "XAUUSD", Bid: 2024.50, Ask: 2025.10, Time: now},
		{Symbol: "USDCHF", Bid: 0.87645, Ask: 0.87663, Time: now},
	}
	store.AddTicks(ticks)

	positions := []model.Position{
		{ID: 100001, Symbol: "EURUSD", Side: model.SideBuy, Volume: 0.01, Price: 1.08250, OpenTime: now.Add(-2 * time.Hour), Magic: 1001, AccountID: "25289974"},
		{ID: 100002, Symbol: "EURUSD", Side: model.SideBuy, Volume: 0.02, Price: 1.08150, OpenTime: now.Add(-90 * time.Minute), Magic: 1002, AccountID: "25289974"},
		{ID: 100003, Symbol: "EURUSD", Side: model.SideBuy, Volume: 0.04, Price: 1.08050, OpenTime: now.Add(-60 * time.Minute), Magic: 1003, AccountID: "25289974"},
		{ID: 100004, Symbol: "GBPUSD", Side: model.SideBuy, Volume: 0.01, Price: 1.26100, OpenTime: now.Add(-45 * time.Minute), Magic: 1001, AccountID: "25289974"},
		{ID: 100005, Symbol: "GBPUSD", Side: model.SideBuy, Volume: 0.02, Price: 1.26000, OpenTime: now.Add(-30 * time.Minute), Magic: 1002, AccountID: "25289974"},
		{ID: 100006, Symbol: "EURUSD", Side: model.SideSell, Volume: 0.03, Price: 1.08400, OpenTime: now.Add(-15 * time.Minute), Magic: 2001, AccountID: "25289974"},
		{ID: 100007, Symbol: "USDJPY", Side: model.SideSell, Volume: 0.01, Price: 151.900, OpenTime: now.Add(-5 * time.Minute), Magic: 5001, AccountID: "25289974"},
	}
	store.UpdatePositions(positions)

	log.Info("demo_seed_complete",
		zap.String("account_id", "25289974"),
		zap.Float64("balance", 10000.00),
		zap.Int("positions", len(positions)),
		zap.Int("symbols", len(ticks)),
	)
}

// demoTickLoop continuously updates tick prices to simulate live market movement.
func demoTickLoop(ctx context.Context, eng *engine.Engine, log *zap.Logger) {
	log.Info("starting demo tick simulator")

	type symbolState struct {
		symbol  string
		baseBid float64
		spread  float64
		digits  int
	}
	symbols := []symbolState{
		{"EURUSD", 1.08342, 0.00012, 5},
		{"GBPUSD", 1.26185, 0.00016, 5},
		{"USDJPY", 151.823, 0.018, 3},
		{"XAUUSD", 2024.50, 0.60, 2},
		{"USDCHF", 0.87645, 0.00018, 5},
	}

	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	step := 0

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			step++
			store := eng.Store()
			now := time.Now()
			ticks := make([]model.Tick, 0, len(symbols))

			for i := range symbols {
				s := &symbols[i]
				delta := (rng.Float64() - 0.5) * s.spread * 3
				wave := math.Sin(float64(step)/20.0+float64(i)*1.5) * s.spread * 0.5
				s.baseBid += delta + wave
				pow := math.Pow(10, float64(s.digits))
				ticks = append(ticks, model.Tick{
					Symbol: s.symbol,
					Bid:    math.Round(s.baseBid*pow) / pow,
					Ask:    math.Round((s.baseBid+s.spread)*pow) / pow,
					Time:   now,
				})
			}
			store.AddTicks(ticks)

			if step%10 == 0 {
				equity := 10000.0 + (rng.Float64()-0.48)*50 - float64(step%100)*0.1
				store.SetAccount(model.AccountState{
					AccountID: "25289974",
					Balance:   10000.00,
					Equity:    math.Round(equity*100) / 100,
					Margin:    312.50 + rng.Float64()*10,
					Time:      now,
				})
			}
		}
	}
}
