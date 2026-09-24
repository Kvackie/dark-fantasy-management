/**
 * Player preferences: sound, notices, motion, autosave.
 *
 * Kept per browser in localStorage, apart from the save slots, so they carry
 * across every game and survive a new one. Losing them is harmless: every
 * value has a default, and a stored value that no longer makes sense is
 * dropped for it.
 */

const KEY = 'dark-fantasy-settlement.settings';
/** Where the mute switch lived before there was a settings page. */
const LEGACY_MUTE_KEY = 'dark-fantasy-settlement.muted';

export const AUTOSAVE_CHOICES = [12, 30, 60] as const;

export interface Settings {
  sound: boolean;
  /** 0–100. */
  music: number;
  /** 0–100. */
  effects: number;
  toasts: boolean;
  awaySummary: boolean;
  mist: boolean;
  autosaveSeconds: (typeof AUTOSAVE_CHOICES)[number];
  showDebug: boolean;
}

function prefersReducedMotion(): boolean {
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    return false;
  }
}

export function defaultSettings(): Settings {
  return {
    sound: true,
    music: 60,
    effects: 80,
    toasts: true,
    awaySummary: true,
    mist: !prefersReducedMotion(),
    autosaveSeconds: 12,
    showDebug: true,
  };
}

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function load(): Settings {
  const settings = defaultSettings();
  if (read(LEGACY_MUTE_KEY) === '1') settings.sound = false;
  let stored: Record<string, unknown> = {};
  try {
    stored = JSON.parse(read(KEY) ?? '{}') as Record<string, unknown>;
  } catch {
    stored = {};
  }
  const flag = (name: keyof Settings) => {
    if (typeof stored[name] === 'boolean') (settings[name] as boolean) = stored[name];
  };
  const level = (name: 'music' | 'effects') => {
    const value = stored[name];
    if (typeof value === 'number' && value >= 0 && value <= 100) settings[name] = Math.round(value);
  };
  (['sound', 'toasts', 'awaySummary', 'mist', 'showDebug'] as const).forEach(flag);
  level('music');
  level('effects');
  const autosave = AUTOSAVE_CHOICES.find((choice) => choice === stored.autosaveSeconds);
  if (autosave) settings.autosaveSeconds = autosave;
  return settings;
}

let current = load();
const listeners = new Set<(settings: Settings) => void>();

export function settings(): Readonly<Settings> {
  return current;
}

export function updateSettings(patch: Partial<Settings>): void {
  current = { ...current, ...patch };
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
    localStorage.removeItem(LEGACY_MUTE_KEY);
  } catch {
    // A preference that cannot be stored lasts for this visit only.
  }
  listeners.forEach((listener) => listener(current));
}

/** Put every preference back to its default, and forget the stored copy. */
export function resetSettings(): void {
  try {
    localStorage.removeItem(KEY);
    localStorage.removeItem(LEGACY_MUTE_KEY);
  } catch {
    // Nothing stored to forget.
  }
  current = defaultSettings();
  listeners.forEach((listener) => listener(current));
}

export function onSettingsChange(listener: (settings: Settings) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
