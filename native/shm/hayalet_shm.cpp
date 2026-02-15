// hayalet_shm.cpp — HAYALET Trading System shared memory DLL
// SPSC lock-free ring buffers for MT4/MT5 ↔ Go IPC via Windows shared memory.

#include <windows.h>
#include <cstdint>
#include <cstring>

static const uint32_t kVersion = 3;
static const int kSymbolSize = 16;
static const int kAccountSize = 16;
static const int kReasonSize = 32;

#pragma pack(push, 1)
struct ShmHeader {
    uint32_t Version;
    uint32_t TickCapacity;
    uint32_t PositionCapacity;
    uint32_t CommandCapacity;
    uint32_t AccountCapacity;
    volatile LONG TickWrite;
    volatile LONG TickRead;
    volatile LONG PositionWrite;
    volatile LONG PositionRead;
    volatile LONG CommandWrite;
    volatile LONG CommandRead;
    volatile LONG AccountWrite;
    volatile LONG AccountRead;
    volatile LONG64 Heartbeat;
};

struct ShmTick {
    char Symbol[kSymbolSize];
    double Bid;
    double Ask;
    int64_t TimeNs;
};

struct ShmPosition {
    int64_t ID;
    char Symbol[kSymbolSize];
    int32_t Side;
    int32_t Type;
    double Volume;
    double Price;
    int64_t TimeNs;
    int32_t Magic;
    char Account[kAccountSize];
};

struct ShmCommand {
    int32_t Type;
    char Symbol[kSymbolSize];
    int32_t Side;
    double Volume;
    double Price;
    double TP;
    double SL;
    int64_t Ticket;
    int32_t Magic;
    char Account[kAccountSize];
    char Reason[kReasonSize];
    int64_t TimeNs;
};

struct ShmAccount {
    char Account[kAccountSize];
    double Balance;
    double Equity;
    double Margin;
    int64_t TimeNs;
};
#pragma pack(pop)

struct ShmState {
    HANDLE Map;
    void* View;
    ShmHeader* Header;
    ShmTick* Ticks;
    ShmPosition* Positions;
    ShmCommand* Commands;
    ShmAccount* Accounts;
    size_t Size;
};

static ShmState g_state{};

static size_t CalcSize(uint32_t tickCap, uint32_t posCap, uint32_t cmdCap, uint32_t accountCap) {
    return sizeof(ShmHeader)
        + sizeof(ShmTick) * tickCap
        + sizeof(ShmPosition) * posCap
        + sizeof(ShmCommand) * cmdCap
        + sizeof(ShmAccount) * accountCap;
}

static void InitLayout(ShmState& state) {
    uint8_t* base = reinterpret_cast<uint8_t*>(state.View);
    state.Header = reinterpret_cast<ShmHeader*>(base);
    base += sizeof(ShmHeader);
    state.Ticks = reinterpret_cast<ShmTick*>(base);
    base += sizeof(ShmTick) * state.Header->TickCapacity;
    state.Positions = reinterpret_cast<ShmPosition*>(base);
    base += sizeof(ShmPosition) * state.Header->PositionCapacity;
    state.Commands = reinterpret_cast<ShmCommand*>(base);
    base += sizeof(ShmCommand) * state.Header->CommandCapacity;
    state.Accounts = reinterpret_cast<ShmAccount*>(base);
}

extern "C" __declspec(dllexport) int HB_Init(const wchar_t* name, uint32_t tickCap, uint32_t posCap, uint32_t cmdCap, uint32_t accountCap) {
    if (g_state.View) {
        return 1; // already initialized
    }
    size_t size = CalcSize(tickCap, posCap, cmdCap, accountCap);
    HANDLE map = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, static_cast<DWORD>(size), name);
    if (!map) {
        return 0;
    }
    void* view = MapViewOfFile(map, FILE_MAP_ALL_ACCESS, 0, 0, size);
    if (!view) {
        CloseHandle(map);
        return 0;
    }
    g_state.Map = map;
    g_state.View = view;
    g_state.Size = size;

    // If header version doesn't match, initialize fresh
    ShmHeader* hdr = reinterpret_cast<ShmHeader*>(view);
    if (hdr->Version != kVersion) {
        std::memset(view, 0, size);
        hdr->Version = kVersion;
        hdr->TickCapacity = tickCap;
        hdr->PositionCapacity = posCap;
        hdr->CommandCapacity = cmdCap;
        hdr->AccountCapacity = accountCap;
    }

    InitLayout(g_state);
    return 1;
}

extern "C" __declspec(dllexport) int HB_SendTick(const void* tick) {
    if (!g_state.Header) {
        return 0;
    }
    LONG read = g_state.Header->TickRead;
    LONG write = g_state.Header->TickWrite;
    if (static_cast<uint32_t>(write - read) >= g_state.Header->TickCapacity) {
        return 0; // ring buffer full
    }
    uint32_t idx = static_cast<uint32_t>(write) % g_state.Header->TickCapacity;
    g_state.Ticks[idx] = *reinterpret_cast<const ShmTick*>(tick);
    InterlockedExchange(&g_state.Header->TickWrite, write + 1);
    return 1;
}

extern "C" __declspec(dllexport) int HB_SendPosition(const void* pos) {
    if (!g_state.Header) {
        return 0;
    }
    LONG read = g_state.Header->PositionRead;
    LONG write = g_state.Header->PositionWrite;
    if (static_cast<uint32_t>(write - read) >= g_state.Header->PositionCapacity) {
        return 0;
    }
    uint32_t idx = static_cast<uint32_t>(write) % g_state.Header->PositionCapacity;
    g_state.Positions[idx] = *reinterpret_cast<const ShmPosition*>(pos);
    InterlockedExchange(&g_state.Header->PositionWrite, write + 1);
    return 1;
}

extern "C" __declspec(dllexport) int HB_GetCommand(void* cmd) {
    if (!g_state.Header) {
        return 0;
    }
    LONG read = g_state.Header->CommandRead;
    LONG write = g_state.Header->CommandWrite;
    if (read == write) {
        return 0; // no commands
    }
    uint32_t idx = static_cast<uint32_t>(read) % g_state.Header->CommandCapacity;
    *reinterpret_cast<ShmCommand*>(cmd) = g_state.Commands[idx];
    InterlockedExchange(&g_state.Header->CommandRead, read + 1);
    return 1;
}

extern "C" __declspec(dllexport) int HB_SendAccount(const void* acc) {
    if (!g_state.Header) {
        return 0;
    }
    LONG read = g_state.Header->AccountRead;
    LONG write = g_state.Header->AccountWrite;
    if (static_cast<uint32_t>(write - read) >= g_state.Header->AccountCapacity) {
        return 0;
    }
    uint32_t idx = static_cast<uint32_t>(write) % g_state.Header->AccountCapacity;
    g_state.Accounts[idx] = *reinterpret_cast<const ShmAccount*>(acc);
    InterlockedExchange(&g_state.Header->AccountWrite, write + 1);
    return 1;
}

extern "C" __declspec(dllexport) void HB_Heartbeat(long long ts) {
    if (!g_state.Header) {
        return;
    }
    InterlockedExchange64(&g_state.Header->Heartbeat, ts);
}

extern "C" __declspec(dllexport) int HB_Close(void) {
    if (g_state.View) {
        UnmapViewOfFile(g_state.View);
    }
    if (g_state.Map) {
        CloseHandle(g_state.Map);
    }
    std::memset(&g_state, 0, sizeof(g_state));
    return 1;
}
