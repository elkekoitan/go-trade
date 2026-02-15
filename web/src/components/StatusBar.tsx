'use client';

import { useStore } from '@/lib/store';
import { t } from '@/lib/i18n';

const guardColors: Record<string, string> = {
  GREEN: 'bg-green-500',
  YELLOW: 'bg-yellow-500',
  ORANGE: 'bg-orange-500',
  RED: 'bg-red-500',
  BLACK: 'bg-gray-900',
};

const modeColors: Record<string, string> = {
  RUNNING: 'text-green-400',
  PAUSED: 'text-yellow-400',
  FROZEN: 'text-red-400',
  UNKNOWN: 'text-gray-500',
};

export default function StatusBar() {
  const connected = useStore((s) => s.connected);
  const mode = useStore((s) => s.mode());
  const guard = useStore((s) => s.guardLevel());
  const uptime = useStore((s) => s.uptime());
  const status = useStore((s) => s.status);

  return (
    <div className="flex items-center gap-4 px-4 py-2 bg-gray-900 border-b border-gray-800 text-sm">
      <span className="font-bold text-white">HAYALET</span>

      <span className={`font-mono ${modeColors[mode] || 'text-gray-500'}`}>
        {mode}
      </span>

      <div className="flex items-center gap-1">
        <div className={`w-2 h-2 rounded-full ${guardColors[guard] || 'bg-gray-500'}`} />
        <span className="text-gray-400">{guard}</span>
      </div>

      <span className="text-gray-500">|</span>
      <span className="text-gray-400">{t('overview.bridge')}: {status?.bridgeMode ?? '-'}</span>

      <span className="text-gray-500">|</span>
      <span className="text-gray-400">{t('overview.uptime')}: {uptime}</span>

      <div className="ml-auto flex items-center gap-2">
        <div className={`w-2 h-2 rounded-full ${connected ? 'bg-green-400' : 'bg-red-400'}`} />
        <span className="text-gray-400">
          {connected ? t('overview.connected') : t('overview.disconnected')}
        </span>
      </div>
    </div>
  );
}
