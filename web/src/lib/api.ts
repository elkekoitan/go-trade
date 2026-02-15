import type { Command, EngineStatus } from './types';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

export async function fetchStatus(): Promise<EngineStatus> {
  const res = await fetch(`${API_BASE}/api/status`);
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchHealth(): Promise<{ data: { status: string } }> {
  const res = await fetch(`${API_BASE}/api/health`);
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function sendCommand(cmd: Command): Promise<void> {
  const res = await fetch(`${API_BASE}/api/command`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(cmd),
  });
  if (!res.ok) throw new Error(`Command error: ${res.status}`);
}

export function connectWebSocket(
  onMessage: (data: unknown) => void,
  onOpen: () => void,
  onClose: () => void,
): WebSocket {
  const wsUrl = API_BASE.replace(/^http/, 'ws') + '/ws';
  const ws = new WebSocket(wsUrl);

  ws.onopen = onOpen;
  ws.onclose = onClose;
  ws.onerror = () => onClose();

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      onMessage(msg);
    } catch {
      // ignore parse errors
    }
  };

  return ws;
}
