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
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';
import { Shell, type ShellDeps } from '@/ui/dom/shell';
import { createGame, type GameHandle } from '@/ui/phaser/game';
import { resetSettings, settings } from '@/ui/settings';
import { unlockAudio } from '@/ui/sound';

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
// The settlement carried on while the game was closed: run that time now,
// before anything is drawn, so the first frame already shows it.
const awayOnLoad = loaded ? sim.catchUp(Date.now()) : null;

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
  onImport: (world) => {
    const slot = saves.nextNewSlot();
    world.savedAt = Date.now();
    if (saves.save(slot, world)) reboot(slot);
  },
  onWipe: () => {
    // Detach from the slot first, so the save on the way out has nowhere to write.
    deps.activeSlot = 0;
    for (const slot of saves.slots()) saves.delete(slot);
    resetSettings();
    try {
      sessionStorage.removeItem(BOOT_KEY);
    } catch {
      // Nothing to forget.
    }
    window.location.reload();
  },
  onSave: (slot) => {
    sim.world.savedAt = Date.now();
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
// Browsers only let audio start from a gesture; the first press anywhere is it.
document.addEventListener('pointerdown', unlockAudio, { capture: true });
document.addEventListener('keydown', unlockAudio, { capture: true });
shell.mount(root, stage);

// Only now, with the bars either side of it laid out, does the stage have the
// size Phaser will measure.
game = createGame(stage, sim, () => shell.selectedZone);
game.setScreen(shell.state.screen);
if (deps.activeSlot > 0) shell.set({ menu: null });
if (awayOnLoad) shell.showAway(awayOnLoad);

// -- the frame loop -----------------------------------------------------------

/** Save if anything changed — or regardless, when the page is going away. */
function persist(force = false): void {
  if (deps.activeSlot <= 0 || (!force && sim.revision === savedRevision)) return;
  sim.world.savedAt = Date.now();
  if (saves.save(deps.activeSlot, sim.world)) savedRevision = sim.revision;
}

function frame(now: number): void {
  const delta = Math.max(0, now - lastFrame);
  lastFrame = now;
  // Time only runs in a game that has a slot to keep it in.
  if (deps.activeSlot > 0) sim.advanceBy(delta);
  shell.tick(delta / 1000);
  if (now - lastSave >= settings().autosaveSeconds * 1000) {
    lastSave = now;
    persist();
  }
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);

/*
 * A hidden tab gets no frames. Rather than let the first frame back swallow the
 * whole gap as one long step, the time away is caught up here, in one go, and
 * reported — the same path a reopened save takes.
 */
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') {
    persist(true);
    return;
  }
  if (deps.activeSlot <= 0) return;
  shell.showAway(sim.catchUp(Date.now()));
  sim.world.savedAt = Date.now();
  lastFrame = performance.now();
});
window.addEventListener('pagehide', () => persist(true));
