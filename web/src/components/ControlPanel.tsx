'use client';

import { useStore } from '@/lib/store';
import { sendCommand } from '@/lib/api';
import { t } from '@/lib/i18n';

export default function ControlPanel() {
  const mode = useStore((s) => s.mode());

  const handleCommand = async (type: string) => {
    try {
      await sendCommand({ type: type as 'PAUSE' | 'RESUME' | 'HEDGE_ALL' | 'CLOSE_ALL' | 'FREEZE' });
    } catch (err) {
      console.error('Command failed:', err);
    }
  };

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <h3 className="text-sm text-gray-400 font-medium mb-3">{t('controls.pause')}/{t('controls.resume')}</h3>
      <div className="flex flex-wrap gap-2">
        {mode === 'RUNNING' ? (
          <button
            onClick={() => handleCommand('PAUSE')}
            className="px-3 py-1.5 bg-yellow-600 hover:bg-yellow-500 text-white text-sm rounded transition-colors"
          >
            {t('controls.pause')}
          </button>
        ) : (
          <button
            onClick={() => handleCommand('RESUME')}
            className="px-3 py-1.5 bg-green-600 hover:bg-green-500 text-white text-sm rounded transition-colors"
          >
            {t('controls.resume')}
          </button>
        )}
        <button
          onClick={() => handleCommand('HEDGE_ALL')}
          className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded transition-colors"
        >
          {t('controls.hedgeAll')}
        </button>
        <button
          onClick={() => {
            if (confirm('Close ALL positions?')) handleCommand('CLOSE_ALL');
          }}
          className="px-3 py-1.5 bg-red-600 hover:bg-red-500 text-white text-sm rounded transition-colors"
        >
          {t('controls.closeAll')}
        </button>
        <button
          onClick={() => handleCommand('FREEZE')}
          className="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 text-white text-sm rounded transition-colors"
        >
          {t('controls.freeze')}
        </button>
      </div>
    </div>
  );
}
