'use client';

import { useStore } from '@/lib/store';
import { t } from '@/lib/i18n';

export default function GridsTable() {
  const grids = useStore((s) => s.grids());

  if (grids.length === 0) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <h3 className="text-sm text-gray-400 font-medium mb-2">{t('grids.title')}</h3>
        <p className="text-gray-600 text-sm">{t('grids.noGrids')}</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <h3 className="text-sm text-gray-400 font-medium mb-3">{t('grids.title')}</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-500 text-xs">
              <th className="text-left pb-2">{t('grids.symbol')}</th>
              <th className="text-left pb-2">{t('grids.active')}</th>
              <th className="text-left pb-2">{t('grids.direction')}</th>
              <th className="text-right pb-2">{t('grids.anchor')}</th>
              <th className="text-right pb-2">{t('grids.level')}</th>
              <th className="text-right pb-2">{t('grids.lots')}</th>
              <th className="text-right pb-2">{t('grids.pl')}</th>
            </tr>
          </thead>
          <tbody>
            {grids.map((grid) => (
              <tr key={grid.symbol + grid.accountId} className="border-t border-gray-800">
                <td className="py-1 font-mono text-white">{grid.symbol}</td>
                <td className="py-1">
                  <span className={`text-xs px-1 rounded ${grid.active ? 'bg-green-900 text-green-400' : 'bg-gray-800 text-gray-500'}`}>
                    {grid.active ? 'ON' : 'OFF'}
                  </span>
                </td>
                <td className={`py-1 font-mono ${grid.direction === 'BUY' ? 'text-green-400' : grid.direction === 'SELL' ? 'text-red-400' : 'text-gray-500'}`}>
                  {grid.direction || 'BOTH'}
                </td>
                <td className="py-1 text-right font-mono text-gray-300">
                  {grid.anchorPrice > 0 ? grid.anchorPrice.toFixed(5) : '-'}
                </td>
                <td className="py-1 text-right font-mono text-gray-400">
                  {grid.currentLevel}/{grid.maxLevel}
                </td>
                <td className="py-1 text-right font-mono text-gray-300">{grid.totalLots.toFixed(2)}</td>
                <td className={`py-1 text-right font-mono ${grid.floatingPl >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                  {grid.floatingPl >= 0 ? '+' : ''}{grid.floatingPl.toFixed(2)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
