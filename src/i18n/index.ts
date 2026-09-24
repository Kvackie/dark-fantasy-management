/** Every user-facing string, keyed, in `en.json`. */

import en from './en.json';

const strings: Record<string, string> = en as Record<string, string>;

export type Params = Record<string, string | number>;

export function t(key: string, params: Params = {}): string {
  let text = strings[key] ?? key;
  for (const [name, value] of Object.entries(params)) {
    text = text.split(`{${name}}`).join(String(value));
  }
  return text;
}

export function has(key: string): boolean {
  return key in strings;
}

const numberFormat = new Intl.NumberFormat('en');

export function formatNumber(value: number): string {
  return numberFormat.format(Math.trunc(value));
}

/** A per-tick yield: whole numbers plain, fractions to one decimal, always signed. */
export function formatYield(value: number): string {
  const rounded = Math.abs(value) < 1 && value !== 0 ? value.toFixed(1) : String(Math.round(value));
  return value > 0 ? `+${rounded}` : rounded;
}

/** `mm:ss`, or `hh:mm:ss` past the hour — as the Godot map labels were. */
export function formatClock(totalSeconds: number): string {
  const whole = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const seconds = whole % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return hours > 0
    ? `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
    : `${pad(minutes)}:${pad(seconds)}`;
}

export function formatDate(timestamp: number): string {
  if (!timestamp) return '';
  return new Date(timestamp).toLocaleString('en', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** `critical_chance` → `Critical Chance`. */
export function titleCase(id: string): string {
  return id
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}
