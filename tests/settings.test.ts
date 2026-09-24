import { beforeEach, describe, expect, it, vi } from 'vitest';

/** A stand-in for the browser's localStorage, fresh for each test. */
function stubStorage(initial: Record<string, string> = {}): Map<string, string> {
  const map = new Map(Object.entries(initial));
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => void map.set(key, value),
    removeItem: (key: string) => void map.delete(key),
  });
  return map;
}

// The module reads storage once on load, so each test imports a fresh copy.
async function fresh() {
  vi.resetModules();
  return import('@/ui/settings');
}

describe('settings', () => {
  beforeEach(() => vi.unstubAllGlobals());

  it('starts from the defaults when nothing is stored', async () => {
    stubStorage();
    const { settings, defaultSettings } = await fresh();
    expect(settings()).toEqual(defaultSettings());
    expect(settings().autosaveSeconds).toBe(12);
  });

  it('keeps a change for the next visit', async () => {
    const map = stubStorage();
    const first = await fresh();
    first.updateSettings({ music: 25, showDebug: false });
    const second = await fresh();
    expect(second.settings().music).toBe(25);
    expect(second.settings().showDebug).toBe(false);
    expect(map.size).toBe(1);
  });

  it('drops stored values that no longer make sense', async () => {
    stubStorage({
      'dark-fantasy-settlement.settings': JSON.stringify({
        music: 400,
        effects: 'loud',
        autosaveSeconds: 7,
        toasts: 'no',
        mist: false,
      }),
    });
    const { settings, defaultSettings } = await fresh();
    const defaults = defaultSettings();
    expect(settings().music).toBe(defaults.music);
    expect(settings().effects).toBe(defaults.effects);
    expect(settings().autosaveSeconds).toBe(defaults.autosaveSeconds);
    expect(settings().toasts).toBe(true);
    expect(settings().mist).toBe(false);
  });

  it('carries over the old mute switch, then forgets it', async () => {
    const map = stubStorage({ 'dark-fantasy-settlement.muted': '1' });
    const { settings, updateSettings } = await fresh();
    expect(settings().sound).toBe(false);
    updateSettings({ music: 40 });
    expect(map.has('dark-fantasy-settlement.muted')).toBe(false);
  });

  it('resets to the defaults and tells its listeners', async () => {
    stubStorage();
    const { settings, updateSettings, resetSettings, onSettingsChange, defaultSettings } =
      await fresh();
    updateSettings({ toasts: false });
    const seen: boolean[] = [];
    onSettingsChange((next) => seen.push(next.toasts));
    resetSettings();
    expect(settings()).toEqual(defaultSettings());
    expect(seen).toEqual([true]);
  });
});
