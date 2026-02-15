import { create } from 'zustand';
import type { EngineStatus, GuardLevel, Position, AccountState, GridState, SymbolSnapshot, EngineMetrics } from './types';

interface DashboardState {
  connected: boolean;
  status: EngineStatus | null;
  lastUpdate: number;

  // Derived accessors
  mode: () => string;
  guardLevel: () => GuardLevel;
  positions: () => Position[];
  accounts: () => AccountState[];
  grids: () => GridState[];
  symbols: () => SymbolSnapshot[];
  metrics: () => EngineMetrics | null;
  uptime: () => string;

  // Actions
  setStatus: (status: EngineStatus) => void;
  setConnected: (connected: boolean) => void;
}

export const useStore = create<DashboardState>((set, get) => ({
  connected: false,
  status: null,
  lastUpdate: 0,

  mode: () => get().status?.mode ?? 'UNKNOWN',
  guardLevel: () => get().status?.guardLevel ?? 'GREEN',
  positions: () => get().status?.snapshot?.positions?.filter(p => !p.pending) ?? [],
  accounts: () => get().status?.snapshot?.accounts ?? [],
  grids: () => get().status?.gridStates ?? [],
  symbols: () => get().status?.snapshot?.symbols?.filter(s => s.hasTick && s.bid > 0) ?? [],
  metrics: () => get().status?.metrics ?? null,

  uptime: () => {
    const status = get().status;
    if (!status) return '0s';
    const start = new Date(status.startedAt).getTime();
    const now = Date.now();
    const secs = Math.floor((now - start) / 1000);
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  },

  setStatus: (status) => set({ status, lastUpdate: Date.now() }),
  setConnected: (connected) => set({ connected }),
}));
