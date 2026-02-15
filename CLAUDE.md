# HAYALET PROJECT - Claude Code Rules

## Project Identity
- **Project**: HAYALET (Ghost) Algorithmic Trading System
- **Module**: go-trade
- **Languages**: Go 1.24 (engine/API), C++20 (DLL bridge), MQL5 (EA), TypeScript (dashboard)
- **Reference Project**: `C:\Users\qw\Desktop\expert-trade` (read-only reference, do not copy)

## Architecture Overview
```
MT5 Terminal → EA (MQL5) → DLL (C++20) → Shared Memory → Go Engine → REST/WS API → Web Dashboard
```

## Code Conventions

### Go
- Standard layout: `cmd/`, `internal/`, `config/`
- All exports must have godoc comments
- Error handling: `fmt.Errorf("doing X: %w", err)` - always wrap with context
- Context: all long-running functions accept `context.Context` as first parameter
- Logging: `zap.Logger` (structured JSON), never `fmt.Print` in production code
- Testing: table-driven tests, target >80% coverage for engine package
- Naming: use domain terms (Grid, Cascade, Hedge, Guard - not generic names)
- Float comparison: never `==` for float64, use `math.Abs(a-b) < epsilon`
- Concurrency: prefer channels over mutexes, document lock ordering when mutex needed
- Imports: group as stdlib, external, internal (separated by blank lines)

### TypeScript (Web Dashboard)
- Strict mode enabled in tsconfig.json
- Components: functional components with hooks only
- State: Zustand for global state, React state for local UI
- API calls: centralized in `lib/api.ts`, never direct fetch in components
- WebSocket: single connection via `useWebSocket` hook
- Styling: Tailwind utility classes, shadcn/ui components, no inline styles
- i18n: all UI strings via next-intl, never hardcoded text

### MQL5 (Expert Advisors)
- All trades through DLL bridge commands only (no direct EA trading logic in bridge mode)
- EA must survive bridge disconnection (survival mode)
- Comments in Turkish are acceptable for EA files

## Architecture Rules
- All inter-module types defined in `internal/model/`
- Bridge layer is the ONLY code that touches Windows SHM APIs
- Engine NEVER imports api or dashboard packages
- API layer accesses engine only through Engine struct methods
- Dashboard communicates with Go backend exclusively via REST + WebSocket
- No circular dependencies between internal packages

## Trading-Specific Rules
- Magic number allocation:
  - 1000-4999: Grid trading
  - 5000-5999: Stealth HFT
  - 6000-6999: Signal-based trades
- Balance Guard level transitions require 5-minute stabilization
- Circuit breaker is non-overridable (cannot be disabled via API)
- Every trade command must include a `Reason` string
- All monetary values in account currency (USD), never lots/pips for P&L
- No stoploss on grid positions - loss managed via smart close + hedge

## API Rules
- All mutations require JWT authentication
- Response envelope: `{"data": ..., "error": ..., "timestamp": ...}`
- WebSocket message types: tick, position, account, risk, alert, grid, signal, heartbeat
- Rate limiting on all endpoints
- CORS enabled for dashboard origin

## Agent System
- Before starting work, check `docs/agent-tracking.md` for current status
- After completing work, update `docs/agent-tracking.md` with evidence
- Cross-agent work requires updating both agents' tracking sections
- 9 agents: Architect, Trading Engine, Bridge, EA, API, Dashboard, Risk, Test, DevOps

## Commit Conventions
- Format: `type(scope): description`
- Types: feat, fix, docs, refactor, test, chore, perf
- Scope: engine, bridge, api, dashboard, ea, config, docs
- Examples:
  - `feat(engine): implement grid spacing with ATR-adaptive mode`
  - `fix(bridge): handle SHM disconnection gracefully`
  - `docs(agent): update trading engine agent status`

## Key Configuration
- Go API: port 8090
- gRPC: port 8091
- Dashboard dev: port 3000
- SHM name: "HAYALET_SHM"
- Log file: `logs/hayalet.log` (50MB rotation, 10 backups)

## File Organization
```
cmd/           - Binary entry points (hayaletd, hayalet-cli)
internal/      - Private Go packages
  app/         - Application bootstrap
  config/      - Configuration loading
  model/       - Shared data types
  bridge/      - SHM/IPC bridge layer
  engine/      - Core trading engine
  api/         - REST + WebSocket server
  grpcserver/  - gRPC server
  logging/     - Structured logging
config/        - YAML configuration files
native/shm/    - C++ DLL source
ea/            - MQL4/MQL5 Expert Advisors
web/           - Next.js dashboard
docs/          - Documentation + agent tracking
proto/         - gRPC protobuf definitions
scripts/       - Build and deployment scripts
test/          - E2E tests and fixtures
```
