'use client';

import { useEffect, useRef } from 'react';
import { useStore } from '@/lib/store';
import { connectWebSocket, fetchStatus } from '@/lib/api';
import type { EngineStatus, WSMessage } from '@/lib/types';

export default function WSProvider({ children }: { children: React.ReactNode }) {
  const setStatus = useStore((s) => s.setStatus);
  const setConnected = useStore((s) => s.setConnected);
  const wsRef = useRef<WebSocket | null>(null);
  const retryRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    // Initial fetch via REST
    fetchStatus()
      .then((data) => setStatus(data))
      .catch(() => {});

    function connect() {
      if (wsRef.current?.readyState === WebSocket.OPEN) return;

      wsRef.current = connectWebSocket(
        (msg: unknown) => {
          const m = msg as WSMessage;
          if (m.type === 'status') {
            setStatus(m.data as EngineStatus);
          }
        },
        () => {
          setConnected(true);
        },
        () => {
          setConnected(false);
          // Retry after 3 seconds
          retryRef.current = setTimeout(connect, 3000);
        },
      );
    }

    connect();

    // Fallback: poll via REST every 5 seconds if WS fails
    const pollInterval = setInterval(() => {
      if (wsRef.current?.readyState !== WebSocket.OPEN) {
        fetchStatus()
          .then((data) => setStatus(data))
          .catch(() => {});
      }
    }, 5000);

    return () => {
      clearInterval(pollInterval);
      clearTimeout(retryRef.current);
      wsRef.current?.close();
    };
  }, [setStatus, setConnected]);

  return <>{children}</>;
}
