/**
 * Where saves live: the browser's localStorage, or memory when there is none.
 *
 * The game is a static site, so the save is per-browser and per-origin — the
 * GitHub Pages copy and a local `npm run dev` copy are different games.
 * Private windows and locked-down browsers can refuse storage outright; the
 * game still runs then, it just forgets on reload.
 */

export interface KeyValueStore {
  get(key: string): string | null;
  set(key: string, value: string): boolean;
  remove(key: string): void;
}

export class MemoryStore implements KeyValueStore {
  private data = new Map<string, string>();

  get(key: string): string | null {
    return this.data.get(key) ?? null;
  }

  set(key: string, value: string): boolean {
    this.data.set(key, value);
    return true;
  }

  remove(key: string): void {
    this.data.delete(key);
  }
}

class LocalStore implements KeyValueStore {
  constructor(private storage: Storage) {}

  get(key: string): string | null {
    try {
      return this.storage.getItem(key);
    } catch {
      return null;
    }
  }

  set(key: string, value: string): boolean {
    try {
      this.storage.setItem(key, value);
      return true;
    } catch {
      return false;
    }
  }

  remove(key: string): void {
    try {
      this.storage.removeItem(key);
    } catch {
      // Nothing to do: a store that cannot be written cannot be cleared either.
    }
  }
}

export function createStorage(): KeyValueStore {
  try {
    if (typeof localStorage !== 'undefined') {
      const probe = '__dfs_probe__';
      localStorage.setItem(probe, '1');
      localStorage.removeItem(probe);
      return new LocalStore(localStorage);
    }
  } catch {
    // Fall through to memory.
  }
  return new MemoryStore();
}
