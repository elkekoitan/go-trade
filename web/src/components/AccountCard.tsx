'use client';

import { useStore } from '@/lib/store';
import { t } from '@/lib/i18n';

export default function AccountCard() {
  const accounts = useStore((s) => s.accounts());
  const acct = accounts[0];

  if (!acct) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <h3 className="text-sm text-gray-500 mb-2">{t('overview.accounts')}</h3>
        <p className="text-gray-600 text-sm">-</p>
      </div>
    );
  }

  const ddColor =
    acct.drawdownPct >= 30 ? 'text-red-400' :
    acct.drawdownPct >= 20 ? 'text-orange-400' :
    acct.drawdownPct >= 10 ? 'text-yellow-400' : 'text-green-400';

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm text-gray-400 font-medium">{t('overview.accounts')}</h3>
        <span className="text-xs text-gray-600 font-mono">{acct.accountId}</span>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <div className="text-xs text-gray-500">{t('overview.balance')}</div>
          <div className="text-lg font-mono text-white">${acct.balance.toFixed(2)}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.equity')}</div>
          <div className="text-lg font-mono text-white">${acct.equity.toFixed(2)}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.margin')}</div>
          <div className="text-sm font-mono text-gray-300">${acct.margin.toFixed(2)}</div>
        </div>
        <div>
          <div className="text-xs text-gray-500">{t('overview.drawdown')}</div>
          <div className={`text-sm font-mono ${ddColor}`}>{acct.drawdownPct.toFixed(1)}%</div>
        </div>
      </div>
    </div>
  );
}
