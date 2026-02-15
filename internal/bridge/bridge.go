package bridge

import (
	"fmt"
	"time"

	"go-trade/internal/model"
)

// Mode represents the IPC communication mode.
type Mode string

const (
	ModeSharedMemory Mode = "shm"
	ModePipe         Mode = "pipe"
	ModeTCP          Mode = "tcp"
)

// Bridge abstracts the IPC layer between Go and MT4/MT5 terminals.
// It attempts SHM first, then falls back to pipe mode.
type Bridge struct {
	mode Mode
	shm  *SharedMemory
	cmdQ chan model.Command
}

// Open attempts to open a shared memory bridge. If SHM fails, it falls back to pipe mode.
func Open(name string, tickCap, posCap, cmdCap, acctCap uint32) (*Bridge, error) {
	shm, err := OpenSharedMemory(name, tickCap, posCap, cmdCap, acctCap)
	if err == nil {
		return &Bridge{
			mode: ModeSharedMemory,
			shm:  shm,
			cmdQ: make(chan model.Command, 1024),
		}, nil
	}

	// Fallback to pipe mode (demo/testing)
	return &Bridge{
		mode: ModePipe,
		cmdQ: make(chan model.Command, 1024),
	}, fmt.Errorf("SHM unavailable, using pipe mode: %w", err)
}

// Mode returns the current IPC mode.
func (b *Bridge) Mode() Mode {
	return b.mode
}

// Close releases all bridge resources.
func (b *Bridge) Close() error {
	if b.shm != nil {
		return b.shm.Close()
	}
	return nil
}

// ReadTicks reads up to max tick entries from the bridge.
func (b *Bridge) ReadTicks(max int) []model.Tick {
	if b.shm != nil {
		return b.shm.ReadTicks(max)
	}
	return nil
}

// ReadPositions reads up to max position entries from the bridge.
func (b *Bridge) ReadPositions(max int) []model.Position {
	if b.shm != nil {
		return b.shm.ReadPositions(max)
	}
	return nil
}

// ReadAccounts reads up to max account state entries from the bridge.
func (b *Bridge) ReadAccounts(max int) []model.AccountState {
	if b.shm != nil {
		return b.shm.ReadAccounts(max)
	}
	return nil
}

// SendCommand sends a trading command through the bridge.
func (b *Bridge) SendCommand(cmd model.Command) bool {
	if b.shm != nil {
		return b.shm.WriteCommand(cmd)
	}
	select {
	case b.cmdQ <- cmd:
		return true
	default:
		return false
	}
}

// Heartbeat sends a heartbeat timestamp through the bridge.
func (b *Bridge) Heartbeat(ts time.Time) {
	if b.shm != nil {
		b.shm.Heartbeat(ts)
	}
}
