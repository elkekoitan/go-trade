'use client';

import { useState } from 'react';
import { getLocale, setLocale, type Locale } from '@/lib/i18n';

export default function LocaleSwitcher() {
  const [locale, setCurrentLocale] = useState<Locale>(getLocale());

  const toggle = () => {
    const next: Locale = locale === 'tr' ? 'en' : 'tr';
    setLocale(next);
    setCurrentLocale(next);
    window.location.reload();
  };

  return (
    <button
      onClick={toggle}
      className="px-2 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border border-gray-700 transition-colors"
    >
      {locale === 'tr' ? 'EN' : 'TR'}
    </button>
  );
}
