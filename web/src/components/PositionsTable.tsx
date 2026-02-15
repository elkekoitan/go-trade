'use client';

import { useStore } from '@/lib/store';
import { t } from '@/lib/i18n';

export default function PositionsTable() {
  const positions = useStore((s) => s.positions());

  if (positions.length === 0) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <h3 className="text-sm text-gray-400 font-medium mb-2">{t('positions.title')}</h3>
        <p className="text-gray-600 text-sm">{t('positions.noPositions')}</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm text-gray-400 font-medium">{t('positions.title')}</h3>
        <span className="text-xs text-gray-600">{positions.length} open</span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-500 text-xs">
              <th className="text-left pb-2">{t('positions.symbol')}</th>
              <th className="text-left pb-2">{t('positions.side')}</th>
              <th className="text-right pb-2">{t('positions.volume')}</th>
              <th className="text-right pb-2">{t('positions.price')}</th>
              <th className="text-right pb-2">{t('positions.magic')}</th>
              <th className="text-right pb-2">{t('positions.profit')}</th>
            </tr>
          </thead>
          <tbody>
            {positions.map((pos) => (
              <tr key={pos.id} className="border-t border-gray-800">
                <td className="py-1 font-mono text-white">{pos.symbol}</td>
                <td className={`py-1 font-mono ${pos.side === 'BUY' ? 'text-green-400' : 'text-red-400'}`}>
                  {pos.side}
                </td>
                <td className="py-1 text-right font-mono text-gray-300">{pos.volume.toFixed(2)}</td>
                <td className="py-1 text-right font-mono text-gray-300">{pos.price.toFixed(5)}</td>
                <td className="py-1 text-right font-mono text-gray-500">{pos.magic}</td>
                <td className={`py-1 text-right font-mono ${pos.profitLoss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                  {pos.profitLoss >= 0 ? '+' : ''}{pos.profitLoss.toFixed(2)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
