// Package model defines shared data types used across all HAYALET modules.
package model

import "time"

// Side represents a trading direction.
type Side string

const (
	SideBuy  Side = "BUY"
	SideSell Side = "SELL"
)

// CommandType represents a trading command type.
type CommandType string

const (
	CommandOpen     CommandType = "OPEN"
	CommandClose    CommandType = "CLOSE"
	CommandModify   CommandType = "MODIFY"
	CommandPause    CommandType = "PAUSE"
	CommandResume   CommandType = "RESUME"
	CommandHedgeAll CommandType = "HEDGE_ALL"
	CommandCloseAll CommandType = "CLOSE_ALL"
	CommandFreeze   CommandType = "FREEZE"
)

// GuardLevel represents a Balance Guard protection level.
type GuardLevel string

const (
	GuardGreen  GuardLevel = "GREEN"  // Normal operation
	GuardYellow GuardLevel = "YELLOW" // 10% DD - reduce lots
	GuardOrange GuardLevel = "ORANGE" // 20% DD - freeze cascade
	GuardRed    GuardLevel = "RED"    // 30% DD - hedge all
	GuardBlack  GuardLevel = "BLACK"  // 40% DD - close all
)

// MarketState represents detected market condition.
type MarketState string

const (
	MarketRange    MarketState = "RANGE"
	MarketTrend    MarketState = "TREND"
	MarketVolatile MarketState = "VOLATILE"
)

// UserRole represents a dashboard user's authorization level.
type UserRole string

const (
	RoleAdmin    UserRole = "ADMIN"    // Full control
	RoleOperator UserRole = "OPERATOR" // Trade + monitor
	RoleViewer   UserRole = "VIEWER"   // Read-only
)

// Tick represents a price tick from MT4/MT5.
type Tick struct {
	Symbol string    `json:"symbol"`
	Bid    float64   `json:"bid"`
	Ask    float64   `json:"ask"`
	Time   time.Time `json:"time"`
}

// Position represents an open position or pending order.
type Position struct {
	ID        int64     `json:"id"`
	Symbol    string    `json:"symbol"`
	Side      Side      `json:"side"`
	Volume    float64   `json:"volume"`
	Price     float64   `json:"price"`
	OpenTime  time.Time `json:"openTime"`
	Magic     int       `json:"magic"`
	AccountID string    `json:"accountId"`
	Pending   bool      `json:"pending"`
	ProfitLoss float64  `json:"profitLoss"`
	Swap      float64   `json:"swap"`
	Comment   string    `json:"comment"`
}

// AccountState represents the current state of a trading account.
type AccountState struct {
	AccountID    string    `json:"accountId"`
	Balance      float64   `json:"balance"`
	Equity       float64   `json:"equity"`
	Margin       float64   `json:"margin"`
	FreeMargin   float64   `json:"freeMargin"`
	MarginLevel  float64   `json:"marginLevel"`
	PeakEquity   float64   `json:"peakEquity"`
	DrawdownPct  float64   `json:"drawdownPct"`
	GuardLevel   GuardLevel `json:"guardLevel"`
	Time         time.Time `json:"time"`
}

// Command represents a trading command sent to the EA.
type Command struct {
	Type      CommandType `json:"type"`
	Symbol    string      `json:"symbol"`
	Side      Side        `json:"side"`
	Volume    float64     `json:"volume"`
	Price     float64     `json:"price"`
	TP        float64     `json:"tp"`
	SL        float64     `json:"sl"`
	Ticket    int64       `json:"ticket"`
	Magic     int         `json:"magic"`
	AccountID string      `json:"accountId"`
	Reason    string      `json:"reason"`
	Time      time.Time   `json:"time"`
}

// Signal represents an external trading signal.
type Signal struct {
	Source    string         `json:"source"`
	Symbol   string         `json:"symbol"`
	Score    float64        `json:"score"`
	Action   CommandType    `json:"action"`
	Side     Side           `json:"side"`
	Time     time.Time      `json:"time"`
	Raw      map[string]any `json:"raw,omitempty"`
	AccountID string        `json:"accountId"`
}

// GridState represents the current state of a grid for a symbol.
type GridState struct {
	Symbol       string    `json:"symbol"`
	AccountID    string    `json:"accountId"`
	Active       bool      `json:"active"`
	Direction    Side      `json:"direction"`
	AnchorPrice  float64   `json:"anchorPrice"`
	CurrentLevel int       `json:"currentLevel"`
	MaxLevel     int       `json:"maxLevel"`
	TotalLots    float64   `json:"totalLots"`
	FloatingPL   float64   `json:"floatingPl"`
	CreatedAt    time.Time `json:"createdAt"`
}

// CascadeLevel represents a single cascade level (R1-R6).
type CascadeLevel struct {
	Level     int     `json:"level"`     // 1-6
	Price     float64 `json:"price"`
	Triggered bool    `json:"triggered"`
	TPPrice   float64 `json:"tpPrice"`   // K2-K6 take profit
	TPHit     bool    `json:"tpHit"`
}

// ScoringResult holds composite indicator scoring output.
type ScoringResult struct {
	Symbol         string  `json:"symbol"`
	CompositeScore float64 `json:"compositeScore"` // -100 to +100
	RSIScore       float64 `json:"rsiScore"`
	MACDScore      float64 `json:"macdScore"`
	BBScore        float64 `json:"bbScore"`
	MAScore        float64 `json:"maScore"`
	StochScore     float64 `json:"stochScore"`
	ADXScore       float64 `json:"adxScore"`
	TrendStrength  float64 `json:"trendStrength"`
	Direction      Side    `json:"direction"`
}

// SmartCloseGroup represents a group of positions selected for smart close.
type SmartCloseGroup struct {
	Positions []int64 `json:"positions"` // ticket IDs
	NetPL     float64 `json:"netPl"`
	GroupSize int     `json:"groupSize"`
}

// ConsolidationState holds ATR-based consolidation filter state.
type ConsolidationState struct {
	Symbol        string  `json:"symbol"`
	CurrentATR    float64 `json:"currentAtr"`
	AverageATR    float64 `json:"averageAtr"`
	ATRRatio      float64 `json:"atrRatio"`
	IsConsolidating bool  `json:"isConsolidating"`
}

// Preset represents a trading strategy preset configuration.
type Preset struct {
	Name          string  `json:"name" yaml:"name"`
	GridSpacing   float64 `json:"gridSpacing" yaml:"gridSpacing"`
	MaxLevels     int     `json:"maxLevels" yaml:"maxLevels"`
	BaseLot       float64 `json:"baseLot" yaml:"baseLot"`
	LotMultiplier float64 `json:"lotMultiplier" yaml:"lotMultiplier"`
	TPPips        float64 `json:"tpPips" yaml:"tpPips"`
	CascadeLevels int     `json:"cascadeLevels" yaml:"cascadeLevels"`
}

// DashboardUser represents a web dashboard user.
type DashboardUser struct {
	ID       string   `json:"id"`
	Username string   `json:"username"`
	Role     UserRole `json:"role"`
	Locale   string   `json:"locale"` // "tr" or "en"
}

// Metrics holds runtime performance metrics.
type Metrics struct {
	TickCount      int64         `json:"tickCount"`
	PositionCount  int           `json:"positionCount"`
	CommandCount   int64         `json:"commandCount"`
	SignalCount    int64         `json:"signalCount"`
	LastTickAge    time.Duration `json:"lastTickAge"`
	Uptime         time.Duration `json:"uptime"`
	BridgeLatency  time.Duration `json:"bridgeLatency"`
	BridgeMode     string        `json:"bridgeMode"`
	ActiveAccounts int           `json:"activeAccounts"`
}

// WSMessage represents a WebSocket message sent to dashboard clients.
type WSMessage struct {
	Type      string    `json:"type"` // tick, position, account, risk, alert, grid, signal, heartbeat
	Data      any       `json:"data"`
	Timestamp time.Time `json:"timestamp"`
}

// APIResponse is the standard REST API response envelope.
type APIResponse struct {
	Data      any       `json:"data,omitempty"`
	Error     string    `json:"error,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}
