/**
 * The intent bus.
 *
 * The Phaser scenes and the DOM panels never call each other. Both talk to the
 * simulation and both listen here, which keeps the canvas replaceable and the
 * panels out of scene internals.
 */

export type ScreenId =
  | 'world'
  | 'settlement'
  | 'overview'
  | 'recruit'
  | 'heroes'
  | 'hero'
  | 'inventory'
  | 'craft'
  | 'forge'
  | 'saves'
  | 'debug';

export type GameEvent =
  /** A tile on the world map was pressed. */
  | { type: 'zone:pressed'; key: string }
  /** Something changed that the panels should redraw for. */
  | { type: 'changed' }
  | { type: 'toast'; title: string; lines: string[] };

type Handler = (event: GameEvent) => void;

class Bus {
  private handlers = new Set<Handler>();

  on(handler: Handler): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  emit(event: GameEvent): void {
    // Copy first: a handler may unsubscribe during dispatch.
    for (const handler of [...this.handlers]) handler(event);
  }
}

export const bus = new Bus();

let pending = false;

/**
 * Ask for a redraw on the next frame.
 *
 * Deferred rather than immediate so the button that was pressed is still in the
 * document for the rest of its own click, and so a burst of changes redraws once.
 */
export function changed(): void {
  if (pending) return;
  pending = true;
  const flush = () => {
    pending = false;
    bus.emit({ type: 'changed' });
  };
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(flush);
  else flush();
}

export function toast(title: string, lines: string[] = []): void {
  bus.emit({ type: 'toast', title, lines });
}
