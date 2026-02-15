// Package bridge provides the shared memory IPC layer between Go and MT4/MT5 via C++ DLL.
package bridge

import "unsafe"

// SHM protocol constants matching C++ DLL definitions.
const (
	shmVersion  = 3
	symbolSize  = 16
	accountSize = 16
	reasonSize  = 32
)

// shmHeader is the shared memory header at offset 0.
// It stores ring buffer capacities and read/write cursors.
type shmHeader struct {
	Version          uint32
	TickCapacity     uint32
	PositionCapacity uint32
	CommandCapacity  uint32
	AccountCapacity  uint32
	TickWrite        uint32
	TickRead         uint32
	PositionWrite    uint32
	PositionRead     uint32
	CommandWrite     uint32
	CommandRead      uint32
	AccountWrite     uint32
	AccountRead      uint32
	Heartbeat        uint64
}

// shmTick represents a single tick entry in the tick ring buffer (40 bytes).
type shmTick struct {
	Symbol [symbolSize]byte
	Bid    float64
	Ask    float64
	TimeNs int64
}

// shmPosition represents a single position entry in the position ring buffer (96 bytes).
type shmPosition struct {
	ID      int64
	Symbol  [symbolSize]byte
	Side    int32
	Type    int32
	Volume  float64
	Price   float64
	TimeNs  int64
	Magic   int32
	Account [accountSize]byte
}

// shmCommand represents a single command entry in the command ring buffer (104 bytes).
type shmCommand struct {
	Type    int32
	Symbol  [symbolSize]byte
	Side    int32
	Volume  float64
	Price   float64
	TP      float64
	SL      float64
	Ticket  int64
	Magic   int32
	Account [accountSize]byte
	Reason  [reasonSize]byte
	TimeNs  int64
}

// shmAccount represents a single account state entry in the account ring buffer (64 bytes).
type shmAccount struct {
	Account [accountSize]byte
	Balance float64
	Equity  float64
	Margin  float64
	TimeNs  int64
}

// Size helper functions for memory layout calculations.

func headerSize() uintptr  { return unsafe.Sizeof(shmHeader{}) }
func tickSize() uintptr    { return unsafe.Sizeof(shmTick{}) }
func posSize() uintptr     { return unsafe.Sizeof(shmPosition{}) }
func cmdSize() uintptr     { return unsafe.Sizeof(shmCommand{}) }
func accountSize_() uintptr { return unsafe.Sizeof(shmAccount{}) }
