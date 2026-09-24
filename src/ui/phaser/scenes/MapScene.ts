/**
 * The world map: every known zone as a tile on a grid centred on home.
 *
 * Drag to pan, wheel or pinch-free buttons to zoom, tap a tile to open it. The
 * scene never decides what a tap means — it says which zone was pressed on the
 * bus, and the shell answers.
 *
 * Tiles are drawn into one Graphics object and labelled with a pooled Text per
 * zone. The whole map is redrawn only when the world changes; between ticks
 * only the countdowns on clearing zones move.
 */

import Phaser from 'phaser';
import { t, formatClock } from '@/i18n';
import { worldConfig } from '@/sim/config';
import type { Simulation } from '@/sim/sim';
import type { Zone } from '@/sim/types';
import { bus } from '@/ui/bus';
import { biomeColors, palette, zoneStateColors } from '@/ui/theme';

const ZOOM_MIN = 0.25;
const ZOOM_MAX = 1.6;
const ZOOM_STEP = 1.1;
/** How far a press may travel and still count as a tap rather than a drag. */
const TAP_SLOP = 8;

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

  create(): void {
    this.cameras.main.setBackgroundColor(palette.bgPage);
    this.tiles = this.add.graphics();
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

  override update(_time: number, delta: number): void {
    this.redraw(false);
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
      case 'discovered':
        return `${t('map.unknown')}\n${biomeLabel(zone.biome)}`;
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
      const fill = zoneFill(zone);
      const isSelected = zone.key === selected;
      g.fillStyle(fill, zone.state === 'fog' ? 0.55 : 1);
      g.fillRoundedRect(x, y, size, size, 8);
      g.lineStyle(isSelected ? 4 : 2, isSelected ? palette.accent : lighten(fill, 0.18), 1);
      g.strokeRoundedRect(x, y, size, size, 8);

      seen.add(zone.key);
      let label = this.labels.get(zone.key);
      if (!label) {
        label = this.add
          .text(x + size / 2, y + size / 2, '', {
            fontFamily: 'Georgia, "Times New Roman", serif',
            fontSize: '15px',
            color: '#f4f1e8',
            align: 'center',
            wordWrap: { width: size - 12 },
            stroke: '#1a1210',
            strokeThickness: 3,
          })
          .setOrigin(0.5)
          .setResolution(2);
        this.labels.set(zone.key, label);
      }
      label.setText(this.labelText(zone));
    }
    for (const [key, label] of this.labels) {
      if (seen.has(key)) continue;
      label.destroy();
      this.labels.delete(key);
    }
  }
}
