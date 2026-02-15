'use client';

import WSProvider from '@/components/WSProvider';
import StatusBar from '@/components/StatusBar';
import AccountCard from '@/components/AccountCard';
import MetricsCard from '@/components/MetricsCard';
import SymbolsTable from '@/components/SymbolsTable';
import PositionsTable from '@/components/PositionsTable';
import GridsTable from '@/components/GridsTable';
import ControlPanel from '@/components/ControlPanel';
import LocaleSwitcher from '@/components/LocaleSwitcher';

export default function Home() {
  return (
    <WSProvider>
      <div className="min-h-screen bg-black">
        <StatusBar />
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between mb-4">
            <h1 className="text-lg font-bold text-white">HAYALET</h1>
            <LocaleSwitcher />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
            <AccountCard />
            <MetricsCard />
            <ControlPanel />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
            <SymbolsTable />
            <GridsTable />
          </div>

          <PositionsTable />
        </div>
      </div>
    </WSProvider>
  );
}
