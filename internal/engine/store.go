package engine

import (
	"sync"
	"time"

	"go-trade/internal/model"
)

// Store is a thread-safe in-memory state store for ticks, positions, and accounts.
type Store struct {
	mu        sync.RWMutex
	positions map[string]map[int64]model.Position // key: accountID|symbol -> posID -> Position
	accounts  map[string]model.AccountState       // accountID -> AccountState
	ticks     map[string][]model.Tick             // symbol -> recent ticks (capped)
}

// SymbolSnapshot holds the latest state for a single symbol.
type SymbolSnapshot struct {
	Symbol        string    `json:"symbol"`
	Bid           float64   `json:"bid"`
	Ask           float64   `json:"ask"`
	Time          time.Time `json:"time"`
	PositionCount int       `json:"positionCount"`
	HasTick       bool      `json:"hasTick"`
}

// StoreSnapshot is a point-in-time snapshot of all store data.
type StoreSnapshot struct {
	Symbols   []SymbolSnapshot     `json:"symbols"`
	Accounts  []model.AccountState `json:"accounts"`
	Positions []model.Position     `json:"positions"`
}

// NewStore creates an empty state store.
func NewStore() *Store {
	return &Store{
		positions: make(map[string]map[int64]model.Position),
		accounts:  make(map[string]model.AccountState),
		ticks:     make(map[string][]model.Tick),
	}
}

// UpdatePositions upserts position entries grouped by accountID|symbol.
func (s *Store) UpdatePositions(list []model.Position) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, pos := range list {
		key := pos.AccountID + "|" + pos.Symbol
		if _, ok := s.positions[key]; !ok {
			s.positions[key] = make(map[int64]model.Position)
		}
		s.positions[key][pos.ID] = pos
	}
}

// SetAccount sets the account state for a single account.
func (s *Store) SetAccount(state model.AccountState) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.accounts[state.AccountID] = state
}

// UpdateAccounts upserts multiple account states.
func (s *Store) UpdateAccounts(list []model.AccountState) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, acc := range list {
		s.accounts[acc.AccountID] = acc
	}
}

// AddTicks appends ticks per symbol, capping at 2048 entries.
func (s *Store) AddTicks(list []model.Tick) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, tick := range list {
		buf := s.ticks[tick.Symbol]
		buf = append(buf, tick)
		if len(buf) > 2048 {
			buf = buf[len(buf)-2048:]
		}
		s.ticks[tick.Symbol] = buf
	}
}

// GetPositions returns non-pending positions for a given account and symbol.
func (s *Store) GetPositions(accountID, symbol string) []model.Position {
	s.mu.RLock()
	defer s.mu.RUnlock()
	key := accountID + "|" + symbol
	m := s.positions[key]
	out := make([]model.Position, 0, len(m))
	for _, pos := range m {
		if pos.Pending {
			continue
		}
		out = append(out, pos)
	}
	return out
}

// GetPendingPositions returns pending-only positions for a given account and symbol.
func (s *Store) GetPendingPositions(accountID, symbol string) []model.Position {
	s.mu.RLock()
	defer s.mu.RUnlock()
	key := accountID + "|" + symbol
	m := s.positions[key]
	out := make([]model.Position, 0, len(m))
	for _, pos := range m {
		if !pos.Pending {
			continue
		}
		out = append(out, pos)
	}
	return out
}

// GetAllPositions returns all positions across all accounts and symbols.
func (s *Store) GetAllPositions() []model.Position {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]model.Position, 0)
	for _, m := range s.positions {
		for _, pos := range m {
			out = append(out, pos)
		}
	}
	return out
}

// GetTicks returns a copy of all recent ticks for a symbol.
func (s *Store) GetTicks(symbol string) []model.Tick {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.ticks[symbol]
	out := make([]model.Tick, len(list))
	copy(out, list)
	return out
}

// LastTick returns the most recent tick for a symbol, if any.
func (s *Store) LastTick(symbol string) (model.Tick, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.ticks[symbol]
	if len(list) == 0 {
		return model.Tick{}, false
	}
	return list[len(list)-1], true
}

// Equity returns balance and equity for an account.
func (s *Store) Equity(accountID string) (float64, float64, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	state, ok := s.accounts[accountID]
	if !ok {
		return 0, 0, false
	}
	return state.Balance, state.Equity, true
}

// GetAccounts returns all account states.
func (s *Store) GetAccounts() []model.AccountState {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]model.AccountState, 0, len(s.accounts))
	for _, acc := range s.accounts {
		out = append(out, acc)
	}
	return out
}

// PurgePositions removes positions older than the given time.
func (s *Store) PurgePositions(olderThan time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for key, items := range s.positions {
		for id, pos := range items {
			if pos.OpenTime.Before(olderThan) {
				delete(items, id)
			}
		}
		if len(items) == 0 {
			delete(s.positions, key)
		}
	}
}

// Snapshot returns a point-in-time copy of all state data.
func (s *Store) Snapshot() StoreSnapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()

	positions := make([]model.Position, 0)
	positionCounts := make(map[string]int)
	for key, items := range s.positions {
		for _, pos := range items {
			positions = append(positions, pos)
			if !pos.Pending {
				positionCounts[key]++
				positionCounts[pos.Symbol]++
			}
		}
	}

	symbols := make([]SymbolSnapshot, 0, len(s.ticks))
	for symbol, list := range s.ticks {
		snap := SymbolSnapshot{
			Symbol:        symbol,
			PositionCount: positionCounts[symbol],
		}
		if len(list) > 0 {
			last := list[len(list)-1]
			snap.Bid = last.Bid
			snap.Ask = last.Ask
			snap.Time = last.Time
			snap.HasTick = true
		}
		symbols = append(symbols, snap)
	}

	accounts := make([]model.AccountState, 0, len(s.accounts))
	for _, acc := range s.accounts {
		accounts = append(accounts, acc)
	}

	return StoreSnapshot{
		Symbols:   symbols,
		Accounts:  accounts,
		Positions: positions,
	}
}
