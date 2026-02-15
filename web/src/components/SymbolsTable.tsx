'use client';

import { useStore } from '@/lib/store';

export default function SymbolsTable() {
  const symbols = useStore((s) => s.symbols());

  if (symbols.length === 0) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <h3 className="text-sm text-gray-400 font-medium mb-2">Symbols</h3>
        <p className="text-gray-600 text-sm">No active symbols</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <h3 className="text-sm text-gray-400 font-medium mb-3">Symbols</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-500 text-xs">
              <th className="text-left pb-2">Symbol</th>
              <th className="text-right pb-2">Bid</th>
              <th className="text-right pb-2">Ask</th>
              <th className="text-right pb-2">Spread</th>
              <th className="text-right pb-2">Pos</th>
            </tr>
          </thead>
          <tbody>
            {symbols.map((sym) => (
              <tr key={sym.symbol} className="border-t border-gray-800">
                <td className="py-1 font-mono text-white">{sym.symbol}</td>
                <td className="py-1 text-right font-mono text-gray-300">{sym.bid.toFixed(5)}</td>
                <td className="py-1 text-right font-mono text-gray-300">{sym.ask.toFixed(5)}</td>
                <td className="py-1 text-right font-mono text-gray-500">
                  {((sym.ask - sym.bid) * 100000).toFixed(1)}
                </td>
                <td className="py-1 text-right font-mono text-gray-400">{sym.positionCount}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
