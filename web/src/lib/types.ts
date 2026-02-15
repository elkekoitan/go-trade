export type Side = 'BUY' | 'SELL';
export type GuardLevel = 'GREEN' | 'YELLOW' | 'ORANGE' | 'RED' | 'BLACK';
export type EngineMode = 'RUNNING' | 'PAUSED' | 'FROZEN';
export type CommandType = 'OPEN' | 'CLOSE' | 'MODIFY' | 'PAUSE' | 'RESUME' | 'HEDGE_ALL' | 'CLOSE_ALL' | 'FREEZE';

export interface Tick {
  symbol: string;
  bid: number;
  ask: number;
  time: string;
}

export interface Position {
  id: number;
  symbol: string;
  side: Side;
  volume: number;
  price: number;
  openTime: string;
  magic: number;
  accountId: string;
  pending: boolean;
  profitLoss: number;
  swap: number;
  comment: string;
}

export interface AccountState {
  accountId: string;
  balance: number;
  equity: number;
  margin: number;
  freeMargin: number;
  marginLevel: number;
  peakEquity: number;
  drawdownPct: number;
  guardLevel: GuardLevel;
  time: string;
}

export interface GridState {
  symbol: string;
  accountId: string;
  active: boolean;
  direction: Side | '';
  anchorPrice: number;
  currentLevel: number;
  maxLevel: number;
  totalLots: number;
  floatingPl: number;
  createdAt: string;
}

export interface SymbolSnapshot {
  symbol: string;
  bid: number;
  ask: number;
  time: string;
  positionCount: number;
  hasTick: boolean;
}

export interface EngineMetrics {
  tickCount: number;
  positionCount: number;
  commandCount: number;
  signalCount: number;
  lastTickAt: string;
  lastCommandAt: string;
  lastSignalAt: string;
}

export interface EngineStatus {
  time: string;
  startedAt: string;
  bridgeMode: string;
  mode: EngineMode;
  snapshot: {
    symbols: SymbolSnapshot[];
    accounts: AccountState[];
    positions: Position[];
  };
  symbolCount: number;
  accountCount: number;
  positionCount: number;
  lastSignals: unknown[];
  lastCommands: unknown[];
  metrics: EngineMetrics;
  config: {
    bridgeName: string;
    defaultPreset: string;
  };
  latestTickAt: string;
  latestSymbol: string;
  gridStates: GridState[];
  guardLevel: GuardLevel;
}

export interface Command {
  type: CommandType;
  symbol?: string;
  side?: Side;
  volume?: number;
  price?: number;
  tp?: number;
  sl?: number;
  ticket?: number;
  magic?: number;
  accountId?: string;
  reason?: string;
}

export interface WSMessage {
  type: string;
  data: unknown;
  timestamp: string;
}
