/**
 * Entry point.
 *
 * Opens on the main menu over a fresh map, as the Godot build did. Starting or
 * loading a game reloads the page into that save — the shell and the scenes
 * hold the simulation they were built with, so a reload is the honest way to
 * swap worlds, and it exercises the load path every time.
 */

import './styles/main.css';
import { SaveManager } from '@/platform/save';
import { createStorage } from '@/platform/storage';
import { AUTOSAVE_INTERVAL_MS } from '@/sim/config';
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';
import { Shell, type ShellDeps } from '@/ui/dom/shell';
import { createGame, type GameHandle } from '@/ui/phaser/game';

const BOOT_KEY = 'dark-fantasy-settlement.boot';

const root = document.getElementById('app');
if (!root) throw new Error('Missing #app root element');

const saves = new SaveManager(createStorage());

/** The slot a reload was asked to open, if any. */
function takeBootSlot(): number {
  try {
    const slot = Number(sessionStorage.getItem(BOOT_KEY));
    sessionStorage.removeItem(BOOT_KEY);
    return Number.isFinite(slot) && slot > 0 ? slot : 0;
  } catch {
    return 0;
  }
}

function reboot(slot: number): void {
  try {
    sessionStorage.setItem(BOOT_KEY, String(slot));
  } catch {
    // Without session storage the menu reopens after the reload, and Continue
    // opens the slot anyway: saving it made it the last one played.
  }
  window.location.reload();
}

const bootSlot = takeBootSlot();
const loaded = bootSlot > 0 ? saves.load(bootSlot) : null;
const sim = new Simulation(loaded ?? createWorld());

// The stage must be in the document before Phaser measures it.
const stage = document.createElement('div');
stage.id = 'stage';
root.append(stage);

let game: GameHandle | null = null;
let lastFrame = performance.now();
let lastSave = lastFrame;
let savedRevision = sim.revision;

const deps: ShellDeps = {
  sim,
  saves,
  activeSlot: loaded ? bootSlot : 0,
  onScreenChange: (screen) => game?.setScreen(screen),
  onForge: (puzzle) => game?.setPuzzle(puzzle),
  onRecenter: () => game?.recenter(),
  onZoom: (factor) => game?.zoomBy(factor),
  onNewGame: () => {
    const slot = saves.nextNewSlot();
    if (saves.save(slot, createWorld())) reboot(slot);
  },
  onLoad: (slot) => reboot(slot),
  onSave: (slot) => {
    const ok = saves.save(slot, sim.world);
    // Saving into a slot makes it this game's slot from then on, as in Godot.
    if (ok) {
      deps.activeSlot = slot;
      savedRevision = sim.revision;
    }
    return ok;
  },
};

const shell = new Shell(deps);
shell.mount(root, stage);

// Only now, with the bars either side of it laid out, does the stage have the
// size Phaser will measure.
game = createGame(stage, sim, () => shell.selectedZone);
game.setScreen(shell.state.screen);
if (deps.activeSlot > 0) shell.set({ menu: null });

// -- the frame loop -----------------------------------------------------------

function persist(): void {
  if (deps.activeSlot <= 0 || sim.revision === savedRevision) return;
  if (saves.save(deps.activeSlot, sim.world)) savedRevision = sim.revision;
}

function frame(now: number): void {
  const delta = Math.max(0, now - lastFrame);
  lastFrame = now;
  // Time only runs in a game that has a slot to keep it in.
  if (deps.activeSlot > 0) sim.advanceBy(delta);
  shell.tick(delta / 1000);
  if (now - lastSave >= AUTOSAVE_INTERVAL_MS) {
    lastSave = now;
    persist();
  }
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') persist();
});
window.addEventListener('pagehide', persist);
