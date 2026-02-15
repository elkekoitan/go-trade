import tr from '@/messages/tr.json';
import en from '@/messages/en.json';

export type Locale = 'tr' | 'en';

const messages: Record<Locale, typeof tr> = { tr, en };

let currentLocale: Locale = 'tr';

export function setLocale(locale: Locale) {
  currentLocale = locale;
  if (typeof window !== 'undefined') {
    localStorage.setItem('hayalet-locale', locale);
  }
}

export function getLocale(): Locale {
  if (typeof window !== 'undefined') {
    const saved = localStorage.getItem('hayalet-locale') as Locale | null;
    if (saved && (saved === 'tr' || saved === 'en')) {
      currentLocale = saved;
    }
  }
  return currentLocale;
}

export function t(key: string): string {
  const parts = key.split('.');
  let obj: unknown = messages[currentLocale];
  for (const part of parts) {
    if (obj && typeof obj === 'object' && part in obj) {
      obj = (obj as Record<string, unknown>)[part];
    } else {
      return key;
    }
  }
  return typeof obj === 'string' ? obj : key;
}
