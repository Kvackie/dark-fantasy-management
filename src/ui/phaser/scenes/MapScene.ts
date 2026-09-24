/**
 * The world map: every known zone as a tile on a grid centred on home.
 *
 * Drag to pan, wheel or pinch-free buttons to zoom, tap a tile to open it. The
 * scene never decides what a tap means — it says which zone was pressed on the
 * bus, and the shell answers.
 *
 * Each known zone is a painted terrain image (see `terrain.ts`) with an icon
 * for its state and a label, all pooled per zone; outlines and state washes go
 * into one Graphics object on top. The whole map is redrawn only when the world
 * changes; between ticks only the countdowns and the mist move.
 *
 * Icons are from game-icons.net (Lorc, Delapouite), CC BY 3.0. They are bundled
 * into the code rather than fetched, so a missing file fails the build instead
 * of leaving the map without markers.
 */

import Phaser from 'phaser';
import { t, formatClock } from '@/i18n';
import { worldConfig } from '@/sim/config';
import type { Simulation } from '@/sim/sim';
import type { Zone } from '@/sim/types';
import { bus } from '@/ui/bus';
import { settings } from '@/ui/settings';
import { biomeColors, palette, zoneStateColors } from '@/ui/theme';
import castleSvg from '../icons/castle.svg?raw';
import swordsSvg from '../icons/crossed-swords.svg?raw';
import crystalSvg from '../icons/crystal-cluster.svg?raw';
import skullSvg from '../icons/skull-crossed-bones.svg?raw';
import flagSvg from '../icons/tower-flag.svg?raw';
import { MIST_KEY, createTerrainTextures, terrainKey, terrainVariant } from '../terrain';

const ZOOM_MIN = 0.25;
const ZOOM_MAX = 1.6;
const ZOOM_STEP = 1.1;
/** How far a press may travel and still count as a tap rather than a drag. */
const TAP_SLOP = 8;
/** How far the mist layers reach from home, in zones. */
const MIST_REACH = 80;

/** Each marker's SVG source. */
const ICONS = {
  castle: castleSvg,
  swords: swordsSvg,
  crystal: crystalSvg,
  skull: skullSvg,
  flag: flagSvg,
} as const;
type IconId = keyof typeof ICONS;

/** The icon and its tint for a zone, or null for fog. */
function zoneIcon(zone: Zone): [IconId, number] | null {
  switch (zone.state) {
    case 'discovered':
      return ['skull', 0xf0b8ae];
    case 'clearing':
      return ['swords', palette.accentWarm];
    case 'cleared':
      return zone.biome === 'crystal_cavern' ? ['crystal', 0xe0d8ff] : ['flag', palette.accentWarm];
    case 'claimed':
      if (zone.biome === 'crystal_cavern') return ['crystal', 0xe0d8ff];
      return ['castle', zone.biome === 'starting_zone' ? palette.accent : palette.marker];
    default:
      return null;
  }
}

/** A multiply tint on the painted ground, so the state reads at a glance. */
function groundTint(zone: Zone): number {
  if (zone.state === 'discovered') return 0xb88078;
  if (zone.state === 'clearing') return 0xd8a47c;
  if (zone.state === 'cleared') return 0xe4dccf;
  return 0xffffff;
}

export interface MapSceneData {
  sim: Simulation;
  selected: () => string | null;
}

function lighten(color: number, amount: number): number {
  const c = Phaser.Display.Color.IntegerToColor(color);
  c.lighten(amount * 100);
  return c.color;
}

export function zoneFill(zone: Zone): number {
  if (zone.state === 'fog') {
    const hex = worldConfig.zoneColors.fog;
    return hex ? Phaser.Display.Color.HexStringToColor(hex).color : 0x66686f;
  }
  if (zone.state === 'discovered') return zoneStateColors.discovered;
  if (zone.state === 'clearing') return zoneStateColors.clearing;
  const biome = biomeColors[zone.biome] ?? biomeColors.neutral!;
  if (zone.state === 'claimed' && zone.biome !== 'starting_zone') return lighten(biome, 0.08);
  return biome;
}

function biomeLabel(biome: string): string {
  return biome === 'starting_zone' ? '' : t(`biome.${biome}`).toUpperCase();
}

export class MapScene extends Phaser.Scene {
  static readonly KEY = 'map';

  private sim!: Simulation;
  private selected!: () => string | null;
  private tiles!: Phaser.GameObjects.Graphics;
  private labels = new Map<string, Phaser.GameObjects.Text>();
  private grounds = new Map<string, Phaser.GameObjects.Image>();
  private icons = new Map<string, Phaser.GameObjects.Image>();
  private mist: Phaser.GameObjects.TileSprite[] = [];
  private drawn = '';
  private sinceClock = 0;
  private press: {
    x: number;
    y: number;
    scrollX: number;
    scrollY: number;
    dragging: boolean;
  } | null = null;
  private centred = false;

  constructor() {
    super(MapScene.KEY);
  }

  init(data: MapSceneData): void {
    this.sim = data.sim;
    this.selected = data.selected;
  }

  /**
   * The loader wants a URL, so each bundled SVG gets a blob URL for the length
   * of the load. Should one still fail, its zones simply show no marker: the
   * icons are looked up by `textures.exists` before use.
   */
  preload(): void {
    const urls = Object.entries(ICONS).map(([id, svg]) => {
      const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
      this.load.svg(`icon-${id}`, url, { width: 96, height: 96 });
      return url;
    });
    this.load.once(Phaser.Loader.Events.COMPLETE, () => urls.forEach(URL.revokeObjectURL));
  }

  create(): void {
    this.cameras.main.setBackgroundColor(palette.bgPage);
    createTerrainTextures(this, worldConfig.zoneSize);
    this.createMist();
    this.tiles = this.add.graphics().setDepth(2);
    this.enableInput();
    this.scale.on('resize', () => {
      if (!this.centred) this.recenter();
    });
    this.recenter();
    this.redraw(true);
  }

  private get step(): number {
    return worldConfig.zoneSize + worldConfig.zoneGap;
  }

  /**
   * Drag to pan, wheel to zoom, tap to open — and on a touch screen, two
   * fingers to pinch. A pinch takes over from any drag in progress and cancels
   * the tap, so lifting the fingers never opens a zone by accident.
   */
  private enableInput(): void {
    this.input.addPointer(1);
    this.input.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
      if (this.pinchPointers().length >= 2) {
        this.startPinch();
        return;
      }
      const cam = this.cameras.main;
      this.press = {
        x: pointer.x,
        y: pointer.y,
        scrollX: cam.scrollX,
        scrollY: cam.scrollY,
        dragging: false,
      };
    });
    this.input.on('pointermove', (pointer: Phaser.Input.Pointer) => {
      if (this.pinch) {
        this.updatePinch();
        return;
      }
      if (!this.press || !pointer.isDown) return;
      const dx = pointer.x - this.press.x;
      const dy = pointer.y - this.press.y;
      if (!this.press.dragging && Math.hypot(dx, dy) < TAP_SLOP) return;
      this.press.dragging = true;
      this.centred = false;
      const cam = this.cameras.main;
      cam.scrollX = this.press.scrollX - dx / cam.zoom;
      cam.scrollY = this.press.scrollY - dy / cam.zoom;
    });
    const release = (pointer: Phaser.Input.Pointer) => {
      if (this.pinch) {
        // The pinch ends when either finger lifts; what is left must not read as a tap.
        if (this.pinchPointers().length < 2) this.pinch = null;
        this.press = null;
        return;
      }
      const press = this.press;
      this.press = null;
      if (!press || press.dragging) return;
      const key = this.zoneAt(pointer.x, pointer.y);
      if (key) bus.emit({ type: 'zone:pressed', key });
    };
    this.input.on('pointerup', release);
    this.input.on('pointerupoutside', () => {
      this.press = null;
      if (this.pinchPointers().length < 2) this.pinch = null;
    });
    this.input.on(
      'wheel',
      (pointer: Phaser.Input.Pointer, _objects: unknown, _dx: number, dy: number) => {
        this.zoomAt(dy > 0 ? 1 / ZOOM_STEP : ZOOM_STEP, pointer.x, pointer.y);
      },
    );
  }

  private pinch: { distance: number; zoom: number } | null = null;

  private pinchPointers(): Phaser.Input.Pointer[] {
    return [this.input.pointer1, this.input.pointer2].filter((p): p is Phaser.Input.Pointer =>
      Boolean(p?.isDown),
    );
  }

  private startPinch(): void {
    const [a, b] = this.pinchPointers();
    if (!a || !b) return;
    this.press = null;
    this.pinch = {
      distance: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)),
      zoom: this.cameras.main.zoom,
    };
  }

  private updatePinch(): void {
    const [a, b] = this.pinchPointers();
    if (!a || !b || !this.pinch) return;
    const distance = Math.max(1, Math.hypot(a.x - b.x, a.y - b.y));
    const target = Phaser.Math.Clamp(
      (this.pinch.zoom * distance) / this.pinch.distance,
      ZOOM_MIN,
      ZOOM_MAX,
    );
    this.zoomAt(target / this.cameras.main.zoom, (a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  /** Which zone is under a screen point, if the point is on a tile rather than in a gap. */
  private zoneAt(screenX: number, screenY: number): string | null {
    const point = this.cameras.main.getWorldPoint(screenX, screenY);
    const gx = Math.floor(point.x / this.step);
    const gy = Math.floor(point.y / this.step);
    const inTileX = point.x - gx * this.step;
    const inTileY = point.y - gy * this.step;
    if (inTileX > worldConfig.zoneSize || inTileY > worldConfig.zoneSize) return null;
    const key = `${gx},${gy}`;
    const zone = this.sim.world.zones[key];
    return zone && zone.state !== 'fog' ? key : null;
  }

  zoomAt(factor: number, screenX = this.scale.width / 2, screenY = this.scale.height / 2): void {
    const cam = this.cameras.main;
    const before = cam.getWorldPoint(screenX, screenY);
    cam.setZoom(Phaser.Math.Clamp(cam.zoom * factor, ZOOM_MIN, ZOOM_MAX));
    const after = cam.getWorldPoint(screenX, screenY);
    cam.scrollX += before.x - after.x;
    cam.scrollY += before.y - after.y;
    this.centred = false;
  }

  /** Put home in the middle, at a zoom that shows the fog around it. */
  recenter(): void {
    const cam = this.cameras.main;
    const span = this.step * 5;
    const fit = Math.min(this.scale.width, this.scale.height) / span;
    cam.setZoom(Phaser.Math.Clamp(fit, ZOOM_MIN, 1));
    cam.centerOn(worldConfig.zoneSize / 2, worldConfig.zoneSize / 2);
    this.centred = true;
  }

  /**
   * Two layers of drifting mist at different scales and speeds: one under the
   * tiles, which is all the fog of war shows, and a fainter one over them.
   */
  private createMist(): void {
    const span = this.step * MIST_REACH * 2;
    const centre = worldConfig.zoneSize / 2;
    const under = this.add
      .tileSprite(centre, centre, span, span, MIST_KEY)
      .setDepth(0)
      .setAlpha(0.9);
    const over = this.add
      .tileSprite(centre, centre, span, span, MIST_KEY)
      .setDepth(3)
      .setAlpha(0.3)
      .setTileScale(1.8, 1.8);
    this.mist = [under, over];
  }

  private driftMist(delta: number): void {
    const [under, over] = this.mist;
    if (under) {
      under.tilePositionX += delta * 0.008;
      under.tilePositionY += delta * 0.003;
    }
    if (over) {
      over.tilePositionX -= delta * 0.005;
      over.tilePositionY += delta * 0.002;
    }
  }

  override update(_time: number, delta: number): void {
    this.redraw(false);
    if (settings().mist) this.driftMist(delta);
    this.sinceClock += delta;
    if (this.sinceClock >= 250) {
      this.sinceClock = 0;
      this.updateClocks();
    }
  }

  private labelText(zone: Zone): string {
    switch (zone.state) {
      case 'claimed':
        return [zone.settlementName || zone.generatedName, biomeLabel(zone.biome)]
          .filter(Boolean)
          .join('\n');
      case 'cleared':
        return [zone.generatedName, biomeLabel(zone.biome)].filter(Boolean).join('\n');
      case 'clearing':
        return `${t('map.clearing')}\n${formatClock(this.sim.clearingSecondsLeft(zone.key))}`;
      case 'discovered': {
        const count = zone.enemies.length;
        const foes = count === 1 ? t('map.foe') : t('map.foes', { count });
        return `${biomeLabel(zone.biome) || t('map.unknown')}\n${foes}`;
      }
      default:
        return '';
    }
  }

  private updateClocks(): void {
    for (const zone of Object.values(this.sim.world.zones)) {
      if (zone.state !== 'clearing') continue;
      this.labels.get(zone.key)?.setText(this.labelText(zone));
    }
  }

  /** Redraw the tiles if the world or the selection changed since the last draw. */
  redraw(force: boolean): void {
    const selected = this.selected();
    const shape = `${this.sim.revision}|${selected ?? ''}`;
    if (!force && shape === this.drawn) return;
    this.drawn = shape;

    const size = worldConfig.zoneSize;
    const g = this.tiles;
    g.clear();
    const seen = new Set<string>();
    for (const zone of Object.values(this.sim.world.zones)) {
      const x = zone.x * this.step;
      const y = zone.y * this.step;
      const isSelected = zone.key === selected;
      seen.add(zone.key);
      this.placeGround(zone, x, y, size);

      if (zone.state === 'fog') {
        // The mist beneath shows through; only a faint edge marks the zone.
        g.fillStyle(zoneFill(zone), 0.06);
        g.fillRoundedRect(x, y, size, size, 8);
        g.lineStyle(1.5, zoneFill(zone), 0.18);
        g.strokeRoundedRect(x, y, size, size, 8);
      } else {
        const edge = zone.state === 'claimed' ? palette.borderStrong : zoneFill(zone);
        g.lineStyle(isSelected ? 4 : 2, isSelected ? palette.accent : lighten(edge, 0.12), 1);
        g.strokeRoundedRect(x, y, size, size, 8);
      }

      const icon = zoneIcon(zone);
      this.placeIcon(zone.key, icon, x + size / 2, y + size * 0.36);

      let label = this.labels.get(zone.key);
      if (!label) {
        label = this.add
          .text(0, 0, '', {
            fontFamily: 'Georgia, "Times New Roman", serif',
            fontSize: '14px',
            color: '#f4f1e8',
            align: 'center',
            wordWrap: { width: size - 10 },
            stroke: '#1a1210',
            strokeThickness: 4,
          })
          .setOrigin(0.5)
          .setResolution(2)
          .setDepth(5);
        this.labels.set(zone.key, label);
      }
      label.setPosition(x + size / 2, icon ? y + size * 0.74 : y + size / 2);
      label.setText(this.labelText(zone));
    }
    for (const pool of [this.labels, this.grounds, this.icons]) {
      for (const [key, object] of pool) {
        if (seen.has(key)) continue;
        object.destroy();
        pool.delete(key);
      }
    }
  }

  /** The painted terrain under a revealed zone; fog zones have none. */
  private placeGround(zone: Zone, x: number, y: number, size: number): void {
    let ground = this.grounds.get(zone.key);
    if (zone.state === 'fog') {
      ground?.setVisible(false);
      return;
    }
    const key = terrainKey(zone.biome, terrainVariant(zone.x, zone.y));
    const texture = this.textures.exists(key) ? key : terrainKey('neutral', 0);
    if (!ground) {
      ground = this.add.image(x, y, texture).setOrigin(0).setDepth(1);
      this.grounds.set(zone.key, ground);
    } else if (ground.texture.key !== texture) {
      ground.setTexture(texture);
    }
    ground.setVisible(true).setPosition(x, y).setDisplaySize(size, size).setTint(groundTint(zone));
  }

  private placeIcon(key: string, icon: [IconId, number] | null, x: number, y: number): void {
    let image = this.icons.get(key);
    const texture = icon ? `icon-${icon[0]}` : null;
    if (!icon || !texture || !this.textures.exists(texture)) {
      image?.setVisible(false);
      return;
    }
    if (!image) {
      image = this.add.image(x, y, texture).setDepth(4);
      this.icons.set(key, image);
    } else if (image.texture.key !== texture) {
      image.setTexture(texture);
    }
    image.setVisible(true).setPosition(x, y).setDisplaySize(30, 30).setTint(icon[1]);
  }
}
