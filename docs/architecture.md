# HAYALET System Architecture

## System Overview

HAYALET is an algorithmic trading system that connects to MT4/MT5 terminals via shared memory, runs trading strategies in a Go engine, and provides monitoring/control through a web dashboard.

```
┌─────────────────────────────────────────────────────────────────┐
│                      WEB DASHBOARD (Next.js)                     │
│  Multi-user, Multi-account, i18n (TR/EN)                        │
│  Real-time via WebSocket, Control via REST API                   │
└─────────────────────┬───────────────────────────────────────────┘
                      │ HTTP :3000 → API :8090
┌─────────────────────▼───────────────────────────────────────────┐
│                       GO ENGINE LAYER                            │
│                                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │   Grid   │ │ Cascade  │ │  Hedge   │ │  Balance Guard   │   │
│  │  Engine  │ │  Engine  │ │  Engine  │ │  (5 levels)      │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │ Stealth  │ │  Market  │ │ Circuit  │ │    Scoring       │   │
│  │   HFT    │ │ Detector │ │ Breaker  │ │   (Composite)    │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │  Order   │ │ Account  │ │  Smart   │ │     Preset       │   │
│  │  System  │ │ Manager  │ │  Close   │ │   Management     │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘   │
│                                                                  │
│  REST API (:8090) + WebSocket (/ws) + gRPC (:8091)              │
└─────────────────────┬───────────────────────────────────────────┘
                      │ Shared Memory (Ring Buffers)
┌─────────────────────▼───────────────────────────────────────────┐
│                    C++ DLL BRIDGE LAYER                          │
│  CreateFileMapping → Ring Buffers (Tick/Position/Command/Acct)  │
│  Lock-free SPSC (Single Producer Single Consumer)                │
└─────────────────────┬───────────────────────────────────────────┘
                      │ DLL Import
┌─────────────────────▼───────────────────────────────────────────┐
│                  MT4/MT5 TERMINAL(S)                             │
│  Expert Advisor (MQL5)                                           │
│  - OnTick → HB_SendTick()                                       │
│  - OnTimer → HB_GetCommand() → OrderSend/Close/Modify          │
│  - AccountState → HB_SendAccount()                               │
│  - Positions → HB_SendPosition()                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Tick Data (EA → Go)
```
MT5 OnTick → DLL HB_SendTick → SHM Tick Ring → Go Bridge Reader → Engine Store
```

### Commands (Go → EA)
```
Engine Decision → Command Ring → DLL HB_GetCommand → EA OnTimer → OrderSend
```

### Dashboard (Go → Browser)
```
Engine Store → WebSocket Hub → Browser → Zustand Store → React Components
```

## Shared Memory Layout

```
Offset 0:     SHM Header (version, capacities, read/write cursors, heartbeat)
Offset H:     Tick Ring Buffer    [capacity × 40 bytes]
Offset T:     Position Ring Buffer [capacity × 96 bytes]
Offset P:     Command Ring Buffer  [capacity × 104 bytes]
Offset C:     Account Ring Buffer  [capacity × 64 bytes]
```

## Module Dependencies

```
cmd/hayaletd → internal/app → internal/engine
                             → internal/bridge
                             → internal/api
                             → internal/config
                             → internal/logging

internal/engine → internal/model (types only)
internal/bridge → internal/model
internal/api    → internal/engine (read-only access)
                → internal/model

web/ → REST API (:8090) + WebSocket (/ws)
```

**Rule**: No circular imports. Engine never imports api. Api accesses engine via interface.

## Authentication & Authorization

| Role | REST Read | REST Write | Override | User Mgmt | Config |
|------|-----------|------------|----------|-----------|--------|
| ADMIN | Yes | Yes | Yes | Yes | Yes |
| OPERATOR | Yes | Yes | Yes | No | No |
| VIEWER | Yes | No | No | No | No |

## Trading Strategy Architecture

### Grid Trading
- 3 spacing modes: Arithmetic, Geometric, ATR-adaptive
- 4 lot models: Fixed, Martingale, Anti-Martingale, Balance-proportional
- 4 directional modes: Same-direction fixed/multiplying, Opposite-direction fixed/multiplying

### Cascade System
- R1-R6: 6 cascade depth levels
- K2-K6: Individual take-profit per level
- Re-trigger: After partial close, recalculate remaining grid

### Balance Guard Levels
| Level | Drawdown | Action |
|-------|----------|--------|
| GREEN | 0% | Normal operation |
| YELLOW | 10% | Reduce lots, max 4 grid levels |
| ORANGE | 20% | Freeze cascade, suspend stealth |
| RED | 30% | Hedge all positions |
| BLACK | 40% | Close all, system freeze |

### Magic Number Allocation
| Range | Usage |
|-------|-------|
| 1000-4999 | Grid trading |
| 5000-5999 | Stealth HFT |
| 6000-6999 | Signal-based |

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Engine & API | Go 1.24 |
| DLL Bridge | C++20 (Windows API) |
| Expert Advisors | MQL4/MQL5 |
| Web Dashboard | Next.js 14+, TypeScript, Tailwind, shadcn/ui |
| State Management | Zustand |
| i18n | next-intl (TR + EN) |
| Charts | Lightweight-charts, Recharts |
| Configuration | YAML |
| Logging | Zap (JSON) + Lumberjack (rotation) |
| Metrics | Prometheus |
| Auth | JWT (access + refresh tokens) |
