package bridge

import (
	"errors"
	"fmt"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"

	"go-trade/internal/model"
)

// SharedMemory provides direct access to the Windows shared memory region
// created by the C++ DLL or the Go process itself.
type SharedMemory struct {
	handle windows.Handle
	view   uintptr
	size   uintptr
	header uintptr
	ticks  uintptr
	poses  uintptr
	cmds   uintptr
	accts  uintptr
}

// OpenSharedMemory opens or creates a Windows shared memory region with the given ring buffer capacities.
func OpenSharedMemory(name string, tickCap, posCap, cmdCap, acctCap uint32) (*SharedMemory, error) {
	namePtr, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, fmt.Errorf("converting SHM name to UTF-16: %w", err)
	}

	totalSize := headerSize() +
		uintptr(tickCap)*tickSize() +
		uintptr(posCap)*posSize() +
		uintptr(cmdCap)*cmdSize() +
		uintptr(acctCap)*accountSize_()

	handle, err := windows.CreateFileMapping(
		windows.InvalidHandle, nil,
		windows.PAGE_READWRITE,
		0, uint32(totalSize),
		namePtr,
	)
	if err != nil {
		return nil, fmt.Errorf("creating file mapping %q: %w", name, err)
	}

	view, err := windows.MapViewOfFile(
		handle,
		windows.FILE_MAP_READ|windows.FILE_MAP_WRITE,
		0, 0, totalSize,
	)
	if err != nil {
		_ = windows.CloseHandle(handle)
		return nil, fmt.Errorf("mapping view of file: %w", err)
	}

	// Read and validate header
	headerAddr := view
	var hdr shmHeader
	if err := memRead(headerAddr, unsafe.Pointer(&hdr), headerSize()); err != nil {
		_ = windows.UnmapViewOfFile(view)
		_ = windows.CloseHandle(handle)
		return nil, fmt.Errorf("reading SHM header: %w", err)
	}

	if hdr.Version != 0 && hdr.Version != shmVersion {
		_ = windows.UnmapViewOfFile(view)
		_ = windows.CloseHandle(handle)
		return nil, errors.New("incompatible SHM version")
	}

	// Calculate ring buffer base addresses
	base := view + headerSize()
	ticksAddr := base
	posesAddr := ticksAddr + uintptr(hdr.TickCapacity)*tickSize()
	cmdsAddr := posesAddr + uintptr(hdr.PositionCapacity)*posSize()
	acctsAddr := cmdsAddr + uintptr(hdr.CommandCapacity)*cmdSize()

	return &SharedMemory{
		handle: handle,
		view:   view,
		size:   totalSize,
		header: headerAddr,
		ticks:  ticksAddr,
		poses:  posesAddr,
		cmds:   cmdsAddr,
		accts:  acctsAddr,
	}, nil
}

// Close releases the shared memory mapping and handle.
func (s *SharedMemory) Close() error {
	if s.view != 0 {
		_ = windows.UnmapViewOfFile(s.view)
		s.view = 0
	}
	if s.handle != 0 {
		_ = windows.CloseHandle(s.handle)
		s.handle = 0
	}
	return nil
}

// ReadTicks reads up to max tick entries from the tick ring buffer.
func (s *SharedMemory) ReadTicks(max int) []model.Tick {
	hdr, err := s.readHeader()
	if err != nil {
		return nil
	}

	out := make([]model.Tick, 0, max)
	for range max {
		if hdr.TickRead == hdr.TickWrite {
			break
		}
		idx := hdr.TickRead % hdr.TickCapacity
		var entry shmTick
		if err := memRead(s.ticks+uintptr(idx)*tickSize(), unsafe.Pointer(&entry), tickSize()); err != nil {
			break
		}
		out = append(out, model.Tick{
			Symbol: trimNull(entry.Symbol[:]),
			Bid:    entry.Bid,
			Ask:    entry.Ask,
			Time:   time.Unix(0, entry.TimeNs),
		})
		hdr.TickRead++
	}
	_ = s.writeField(unsafe.Offsetof(shmHeader{}.TickRead), hdr.TickRead)
	return out
}

// ReadPositions reads up to max position entries from the position ring buffer.
func (s *SharedMemory) ReadPositions(max int) []model.Position {
	hdr, err := s.readHeader()
	if err != nil {
		return nil
	}

	out := make([]model.Position, 0, max)
	for range max {
		if hdr.PositionRead == hdr.PositionWrite {
			break
		}
		idx := hdr.PositionRead % hdr.PositionCapacity
		var entry shmPosition
		if err := memRead(s.poses+uintptr(idx)*posSize(), unsafe.Pointer(&entry), posSize()); err != nil {
			break
		}

		side := model.SideBuy
		if entry.Side < 0 {
			side = model.SideSell
		}
		pending := entry.Type == 1

		out = append(out, model.Position{
			ID:        entry.ID,
			Symbol:    trimNull(entry.Symbol[:]),
			Side:      side,
			Volume:    entry.Volume,
			Price:     entry.Price,
			OpenTime:  time.Unix(0, entry.TimeNs),
			Magic:     int(entry.Magic),
			AccountID: trimNull(entry.Account[:]),
			Pending:   pending,
		})
		hdr.PositionRead++
	}
	_ = s.writeField(unsafe.Offsetof(shmHeader{}.PositionRead), hdr.PositionRead)
	return out
}

// ReadAccounts reads up to max account state entries from the account ring buffer.
func (s *SharedMemory) ReadAccounts(max int) []model.AccountState {
	hdr, err := s.readHeader()
	if err != nil {
		return nil
	}

	out := make([]model.AccountState, 0, max)
	for range max {
		if hdr.AccountRead == hdr.AccountWrite {
			break
		}
		idx := hdr.AccountRead % hdr.AccountCapacity
		var entry shmAccount
		if err := memRead(s.accts+uintptr(idx)*accountSize_(), unsafe.Pointer(&entry), accountSize_()); err != nil {
			break
		}
		out = append(out, model.AccountState{
			AccountID: trimNull(entry.Account[:]),
			Balance:   entry.Balance,
			Equity:    entry.Equity,
			Margin:    entry.Margin,
			Time:      time.Unix(0, entry.TimeNs),
		})
		hdr.AccountRead++
	}
	_ = s.writeField(unsafe.Offsetof(shmHeader{}.AccountRead), hdr.AccountRead)
	return out
}

// WriteCommand writes a trading command to the command ring buffer.
func (s *SharedMemory) WriteCommand(cmd model.Command) bool {
	hdr, err := s.readHeader()
	if err != nil {
		return false
	}
	if hdr.CommandWrite-hdr.CommandRead >= hdr.CommandCapacity {
		return false // ring buffer full
	}

	idx := hdr.CommandWrite % hdr.CommandCapacity
	entry := shmCommand{
		Type:   commandTypeToInt(cmd.Type),
		Side:   sideToInt(cmd.Side),
		Volume: cmd.Volume,
		Price:  cmd.Price,
		TP:     cmd.TP,
		SL:     cmd.SL,
		Ticket: cmd.Ticket,
		Magic:  int32(cmd.Magic),
		TimeNs: cmd.Time.UnixNano(),
	}
	copy(entry.Symbol[:], cmd.Symbol)
	copy(entry.Account[:], cmd.AccountID)
	copy(entry.Reason[:], cmd.Reason)

	if err := memWrite(s.cmds+uintptr(idx)*cmdSize(), unsafe.Pointer(&entry), cmdSize()); err != nil {
		return false
	}
	_ = s.writeField(unsafe.Offsetof(shmHeader{}.CommandWrite), hdr.CommandWrite+1)
	return true
}

// Heartbeat writes the current timestamp to the SHM heartbeat field.
func (s *SharedMemory) Heartbeat(ts time.Time) {
	val := uint64(ts.UnixNano())
	_ = memWrite(
		s.header+unsafe.Offsetof(shmHeader{}.Heartbeat),
		unsafe.Pointer(&val),
		unsafe.Sizeof(val),
	)
}

// --- Internal helpers ---

func (s *SharedMemory) readHeader() (shmHeader, error) {
	var hdr shmHeader
	err := memRead(s.header, unsafe.Pointer(&hdr), headerSize())
	return hdr, err
}

func (s *SharedMemory) writeField(offset uintptr, value uint32) error {
	return memWrite(s.header+offset, unsafe.Pointer(&value), unsafe.Sizeof(value))
}

func memRead(addr uintptr, dst unsafe.Pointer, size uintptr) error {
	proc, err := windows.GetCurrentProcess()
	if err != nil {
		return err
	}
	var read uintptr
	return windows.ReadProcessMemory(proc, addr, (*byte)(dst), size, &read)
}

func memWrite(addr uintptr, src unsafe.Pointer, size uintptr) error {
	proc, err := windows.GetCurrentProcess()
	if err != nil {
		return err
	}
	var written uintptr
	return windows.WriteProcessMemory(proc, addr, (*byte)(src), size, &written)
}

func trimNull(b []byte) string {
	for i, c := range b {
		if c == 0 {
			return string(b[:i])
		}
	}
	return string(b)
}

func sideToInt(s model.Side) int32 {
	if s == model.SideSell {
		return -1
	}
	return 1
}

func commandTypeToInt(t model.CommandType) int32 {
	switch t {
	case model.CommandOpen:
		return 1
	case model.CommandClose:
		return 2
	case model.CommandModify:
		return 3
	case model.CommandPause:
		return 4
	case model.CommandResume:
		return 5
	case model.CommandHedgeAll:
		return 6
	case model.CommandCloseAll:
		return 7
	case model.CommandFreeze:
		return 8
	default:
		return 0
	}
}
