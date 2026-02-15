// hayalet_shm.h — HAYALET Trading System DLL interface
// Shared memory IPC layer for MT4/MT5 ↔ Go communication
#pragma once

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize shared memory region with given ring buffer capacities.
// Returns 1 on success, 0 on failure.
__declspec(dllexport) int HB_Init(const wchar_t* name,
                                   uint32_t tickCap,
                                   uint32_t posCap,
                                   uint32_t cmdCap,
                                   uint32_t accountCap);

// Write a tick entry to the tick ring buffer. Returns 1 on success, 0 if full.
__declspec(dllexport) int HB_SendTick(const void* tick);

// Write a position entry to the position ring buffer. Returns 1 on success, 0 if full.
__declspec(dllexport) int HB_SendPosition(const void* pos);

// Read the next command from the command ring buffer. Returns 1 if a command was read, 0 if empty.
__declspec(dllexport) int HB_GetCommand(void* cmd);

// Write an account state entry to the account ring buffer. Returns 1 on success, 0 if full.
__declspec(dllexport) int HB_SendAccount(const void* acc);

// Write a heartbeat timestamp (nanoseconds since epoch).
__declspec(dllexport) void HB_Heartbeat(long long ts);

// Close and release the shared memory mapping. Returns 1 on success.
__declspec(dllexport) int HB_Close(void);

#ifdef __cplusplus
}
#endif
