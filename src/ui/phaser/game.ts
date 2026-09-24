/**
 * Phaser bootstrap, and the only place that knows both halves of the UI exist.
 *
 * Two scenes: the world map behind the World screen, and the forge behind a
 * craft. Every other screen is a page over a sleeping canvas.
 */

import Phaser from 'phaser';
import type { ForgePuzzle } from '@/sim/puzzles';
import type { Simulation } from '@/sim/sim';
import type { ScreenId } from '@/ui/bus';
import { palette } from '@/ui/theme';
import { ForgeScene } from './scenes/ForgeScene';
import { MapScene } from './scenes/MapScene';

export interface GameHandle {
  setScreen: (screen: ScreenId) => void;
  setPuzzle: (puzzle: ForgePuzzle | null) => void;
  recenter: () => void;
  zoomBy: (factor: number) => void;
}

export function createGame(
  parent: HTMLElement,
  sim: Simulation,
  selectedZone: () => string | null,
): GameHandle {
  const game = new Phaser.Game({
    type: Phaser.AUTO,
    parent,
    backgroundColor: palette.bgPage,
    scale: {
      mode: Phaser.Scale.RESIZE,
      autoCenter: Phaser.Scale.NO_CENTER,
      width: '100%',
      height: '100%',
    },
    render: { antialias: true, powerPreference: 'low-power' },
    // The scenes are added below with their start data; none start on their own.
    scene: [],
  });

  game.scene.add(MapScene.KEY, MapScene, true, { sim, selected: selectedZone });
  game.scene.add(ForgeScene.KEY, ForgeScene, true);

  const map = () => {
    const scene = game.scene.getScene(MapScene.KEY) as MapScene | null;
    return scene?.sys.settings.active || scene?.sys.isSleeping() ? scene : null;
  };
  const forge = () => {
    const scene = game.scene.getScene(ForgeScene.KEY) as ForgeScene | null;
    return scene?.sys.settings.active || scene?.sys.isSleeping() ? scene : null;
  };

  /*
   * Phaser boots asynchronously, so the first screen and puzzle can be asked
   * for before either scene exists. They are held here and applied on the
   * first step after the scenes are up.
   */
  let screen: ScreenId = 'world';
  let puzzle: ForgePuzzle | null = null;
  let dirty = true;

  const apply = () => {
    const mapScene = map();
    const forgeScene = forge();
    if (!mapScene || !forgeScene) return false;
    forgeScene.setPuzzle(puzzle);
    const wantMap = screen === 'world';
    const wantForge = screen === 'forge';
    if (wantMap && mapScene.sys.isSleeping()) game.scene.wake(MapScene.KEY);
    if (!wantMap && !mapScene.sys.isSleeping()) game.scene.sleep(MapScene.KEY);
    if (wantForge && forgeScene.sys.isSleeping()) game.scene.wake(ForgeScene.KEY);
    if (!wantForge && !forgeScene.sys.isSleeping()) game.scene.sleep(ForgeScene.KEY);
    return true;
  };

  game.events.on(Phaser.Core.Events.POST_STEP, () => {
    if (dirty && apply()) dirty = false;
  });

  return {
    setScreen: (next) => {
      screen = next;
      dirty = true;
    },
    setPuzzle: (next) => {
      puzzle = next;
      dirty = true;
    },
    recenter: () => map()?.recenter(),
    zoomBy: (factor) => map()?.zoomAt(factor),
  };
}
