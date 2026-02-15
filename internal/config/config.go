// Package config handles loading and validating HAYALET configuration from YAML files.
package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config is the root configuration structure for the HAYALET system.
type Config struct {
	App       AppConfig       `yaml:"app" validate:"required"`
	Bridge    BridgeConfig    `yaml:"bridge" validate:"required"`
	Engine    EngineConfig    `yaml:"engine" validate:"required"`
	Risk      RiskConfig      `yaml:"risk" validate:"required"`
	Hedge     HedgeConfig     `yaml:"hedge" validate:"required"`
	Stealth   StealthConfig   `yaml:"stealth"`
	Signal    SignalConfig    `yaml:"signal"`
	API       APIConfig       `yaml:"api" validate:"required"`
	GRPC      GRPCConfig      `yaml:"grpc"`
	Dashboard DashboardConfig `yaml:"dashboard"`
}

// AppConfig holds general application settings.
type AppConfig struct {
	Env      string `yaml:"env" validate:"required,oneof=dev staging prod"`
	LogLevel string `yaml:"logLevel" validate:"required,oneof=debug info warn error"`
}

// BridgeConfig configures the shared memory bridge.
type BridgeConfig struct {
	SharedMemoryName string `yaml:"sharedMemoryName" validate:"required"`
	TickCapacity     int    `yaml:"tickCapacity" validate:"required,gt=0"`
	PositionCapacity int    `yaml:"positionCapacity" validate:"required,gt=0"`
	CommandCapacity  int    `yaml:"commandCapacity" validate:"required,gt=0"`
	AccountCapacity  int    `yaml:"accountCapacity" validate:"required,gt=0"`
}

// EngineConfig holds trading engine settings.
type EngineConfig struct {
	DefaultPreset  string          `yaml:"defaultPreset" validate:"required"`
	TickIntervalMs int             `yaml:"tickIntervalMs"`
	MarketDetector MarketDetConfig `yaml:"marketDetector"`
	Presets        []PresetConfig  `yaml:"presets" validate:"required,min=1,dive"`
}

// MarketDetConfig holds market condition detector parameters.
type MarketDetConfig struct {
	ATRPeriod int     `yaml:"atrPeriod" validate:"gt=0"`
	ADXPeriod int     `yaml:"adxPeriod" validate:"gt=0"`
	RangeADX  float64 `yaml:"rangeAdx"`
	TrendADX  float64 `yaml:"trendAdx"`
}

// PresetConfig defines a trading strategy preset.
type PresetConfig struct {
	Name          string  `yaml:"name" validate:"required"`
	GridSpacing   float64 `yaml:"gridSpacing" validate:"gt=0"`
	MaxLevels     int     `yaml:"maxLevels" validate:"gt=0"`
	BaseLot       float64 `yaml:"baseLot" validate:"gt=0"`
	LotMultiplier float64 `yaml:"lotMultiplier" validate:"gt=0"`
	TPPips        float64 `yaml:"tpPips" validate:"gte=0"`
	CascadeLevels int     `yaml:"cascadeLevels" validate:"gte=0"`
}

// RiskConfig holds risk management settings.
type RiskConfig struct {
	DrawdownLevels []DrawdownLevel `yaml:"drawdownLevels" validate:"required,min=1,dive"`
}

// DrawdownLevel defines a single Balance Guard level.
type DrawdownLevel struct {
	Name             string  `yaml:"name" validate:"required"`
	ThresholdPercent float64 `yaml:"thresholdPercent" validate:"gte=0"`
	MaxGridLevel     int     `yaml:"maxGridLevel" validate:"gte=0"`
	LotScale         float64 `yaml:"lotScale" validate:"gt=0"`
	AllowCascade     bool    `yaml:"allowCascade"`
	AllowStealth     bool    `yaml:"allowStealth"`
	ForceHedge       bool    `yaml:"forceHedge"`
	ForceClose       bool    `yaml:"forceClose"`
}

// HedgeConfig holds hedging parameters.
type HedgeConfig struct {
	Enable          bool    `yaml:"enable"`
	LockThresholdPip float64 `yaml:"lockThresholdPip"`
	PartialClosePip float64 `yaml:"partialClosePip"`
	SmartClosePnl   float64 `yaml:"smartClosePnl"`
}

// StealthConfig holds stealth HFT engine parameters.
type StealthConfig struct {
	Enable           bool    `yaml:"enable"`
	MaxPositions     int     `yaml:"maxPositions"`
	MaxHoldMinutes   int     `yaml:"maxHoldMinutes"`
	MaxLossPerTrade  float64 `yaml:"maxLossPerTrade"`
	MaxLossPerDay    float64 `yaml:"maxLossPerDay"`
	PauseAfterLosses int     `yaml:"pauseAfterLosses"`
	PauseMinutes     int     `yaml:"pauseMinutes"`
	MagicRangeStart  int     `yaml:"magicRangeStart"`
	MagicRangeEnd    int     `yaml:"magicRangeEnd"`
	PopulationSize   int     `yaml:"populationSize"`
	MutationRateBase float64 `yaml:"mutationRateBase"`
	MutationRateBoost float64 `yaml:"mutationRateBoost"`
}

// SignalConfig holds webhook/signal settings.
type SignalConfig struct {
	Secret string `yaml:"secret"`
}

// APIConfig holds REST API server settings.
type APIConfig struct {
	ListenAddress     string `yaml:"listenAddress" validate:"required"`
	JwtSecret         string `yaml:"jwtSecret" validate:"required"`
	RateLimitPerMinute int   `yaml:"rateLimitPerMinute"`
	RateLimitBurst    int    `yaml:"rateLimitBurst"`
}

// GRPCConfig holds gRPC server settings.
type GRPCConfig struct {
	ListenAddress string `yaml:"listenAddress"`
}

// DashboardConfig holds web dashboard settings.
type DashboardConfig struct {
	Enabled       bool   `yaml:"enabled"`
	StaticPath    string `yaml:"staticPath"`
	DefaultLocale string `yaml:"defaultLocale"`
}

// Load reads and parses a YAML configuration file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config file %s: %w", path, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config YAML: %w", err)
	}

	if err := cfg.setDefaults(); err != nil {
		return nil, fmt.Errorf("setting config defaults: %w", err)
	}

	return &cfg, nil
}

// setDefaults applies sensible defaults for optional fields.
func (c *Config) setDefaults() error {
	if c.Engine.TickIntervalMs == 0 {
		c.Engine.TickIntervalMs = 50
	}
	if c.Engine.MarketDetector.ATRPeriod == 0 {
		c.Engine.MarketDetector.ATRPeriod = 14
	}
	if c.Engine.MarketDetector.ADXPeriod == 0 {
		c.Engine.MarketDetector.ADXPeriod = 14
	}
	if c.Dashboard.DefaultLocale == "" {
		c.Dashboard.DefaultLocale = "tr"
	}
	if c.Stealth.MagicRangeStart == 0 {
		c.Stealth.MagicRangeStart = 5000
	}
	if c.Stealth.MagicRangeEnd == 0 {
		c.Stealth.MagicRangeEnd = 5999
	}
	return nil
}
