'use client';

import { useStore } from '@/lib/store';
import { t } from '@/lib/i18n';

export default function MetricsCard() {
  const metrics = useStore((s) => s.metrics());
  const status = useStore((s) => s.status);

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <h3 className="text-sm text-gray-400 font-medium mb-3">{t('overview.engine')}</h3>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <div className="text-xs text-gray-500">{t('overview.ticks')}</div>
          <div className="text-sm font-mono text-white">{(metrics?.tickCount ?? 0).toLocaleString()}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.positions')}</div>
          <div className="text-sm font-mono text-white">{status?.positionCount ?? 0}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.commands')}</div>
          <div className="text-sm font-mono text-white">{(metrics?.commandCount ?? 0).toLocaleString()}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.symbols')}</div>
          <div className="text-sm font-mono text-white">{status?.symbolCount ?? 0}</div>
        </div>
      </div>
    </div>
  );
}
