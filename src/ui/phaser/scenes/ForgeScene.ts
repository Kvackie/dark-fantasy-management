/**
 * The forge: the bar and the marker a craft is decided on.
 *
 * This scene only draws. The puzzle it draws is a state machine from
 * `sim/puzzles.ts`, stepped by the shell each frame and pushed by its buttons;
 * the scene reads it back and paints the bar, the marker, and a flash of green
 * or red whenever a hit or a miss lands.
 */

import Phaser from 'phaser';
import {
  BellowsRhythm,
  EdgeSharpening,
  HeatBalance,
  TimingStrike,
  type ForgePuzzle,
} from '@/sim/puzzles';
import { play } from '@/ui/sound';
import { forgeColors, palette } from '@/ui/theme';

type Stop = [offset: number, color: number, alpha: number];

const BAR_WIDTH = 620;
const BAR_HEIGHT = 46;

function mix(a: number, b: number, t: number): number {
  const ar = (a >> 16) & 0xff;
  const ag = (a >> 8) & 0xff;
  const ab = a & 0xff;
  const br = (b >> 16) & 0xff;
  const bg = (b >> 8) & 0xff;
  const bb = b & 0xff;
  const r = Math.round(ar + (br - ar) * t);
  const g = Math.round(ag + (bg - ag) * t);
  const bl = Math.round(ab + (bb - ab) * t);
  return (r << 16) | (g << 8) | bl;
}

/** Colour and alpha at `x` along a list of stops, as a Godot Gradient would give it. */
function sample(stops: Stop[], x: number): [number, number] {
  const first = stops[0]!;
  if (x <= first[0]) return [first[1], first[2]];
  for (let i = 1; i < stops.length; i += 1) {
    const b = stops[i]!;
    const a = stops[i - 1]!;
    if (x <= b[0]) {
      const t = b[0] === a[0] ? 1 : (x - a[0]) / (b[0] - a[0]);
      return [mix(a[1], b[1], t), a[2] + (b[2] - a[2]) * t];
    }
  }
  const last = stops[stops.length - 1]!;
  return [last[1], last[2]];
}

function beatStops(start: number, end: number): Stop[] {
  const centre = (start + end) / 2;
  return [
    [0, forgeColors.cold, 0.62],
    [start, forgeColors.hot, 0.92],
    [centre, forgeColors.core, 1],
    [end, forgeColors.hot, 0.92],
    [1, forgeColors.cold, 0.62],
  ];
}

export class ForgeScene extends Phaser.Scene {
  static readonly KEY = 'forge';

  private puzzle: ForgePuzzle | null = null;
  private g!: Phaser.GameObjects.Graphics;
  private flash!: Phaser.GameObjects.Rectangle;
  private seen = { hits: 0, misses: 0, done: false };

  constructor() {
    super(ForgeScene.KEY);
  }

  create(): void {
    this.cameras.main.setBackgroundColor(0x120d0c);
    this.g = this.add.graphics();
    this.flash = this.add.rectangle(0, 0, 10, 10, palette.good, 0).setOrigin(0);
  }

  setPuzzle(puzzle: ForgePuzzle | null): void {
    this.puzzle = puzzle;
    this.seen = {
      hits: this.hits(),
      misses: puzzle?.failures ?? 0,
      done: puzzle?.completed ?? false,
    };
  }

  private hits(): number {
    const p = this.puzzle;
    if (p instanceof TimingStrike) return p.strikes;
    if (p instanceof BellowsRhythm) return p.pumps;
    return 0;
  }

  override update(): void {
    const g = this.g;
    g.clear();
    const puzzle = this.puzzle;
    const { width, height } = this.scale;
    this.drawEmbers(width, height);
    if (!puzzle) return;

    const scale = Math.min(1, (width - 32) / BAR_WIDTH);
    const barW = BAR_WIDTH * scale;
    const x = (width - barW) / 2;
    const y = height * 0.52 - BAR_HEIGHT / 2;

    if (puzzle instanceof TimingStrike) this.drawStrike(puzzle, x, y, barW, scale);
    else if (puzzle instanceof HeatBalance)
      this.drawBand(x, y, barW, BAR_HEIGHT, this.heatStops(), puzzle.heat);
    else if (puzzle instanceof EdgeSharpening) {
      const half = EdgeSharpening.EDGE / 2;
      this.drawBand(
        x,
        y,
        barW,
        BAR_HEIGHT,
        beatStops(0.5 - half, 0.5 + half),
        (puzzle.position + 1) / 2,
        12,
      );
    } else if (puzzle instanceof BellowsRhythm) {
      const pulse = 1 - Math.min(Math.abs(puzzle.phase - 0.5) / 0.5, 1);
      const w = barW * (1 + pulse * 0.04);
      const h = BAR_HEIGHT * (1 + pulse * 0.22);
      const stops = beatStops(0.5 - BellowsRhythm.WINDOW, 0.5 + BellowsRhythm.WINDOW);
      this.drawBand((width - w) / 2, y + (BAR_HEIGHT - h) / 2, w, h, stops, puzzle.phase);
    }

    this.flashOnChange(width, height);
  }

  /** A slow drift of sparks behind the bar, so the forge feels lit. */
  private drawEmbers(width: number, height: number): void {
    const time = this.time.now / 1000;
    for (let i = 0; i < 28; i += 1) {
      const seed = (i * 97.13) % 1;
      const px = ((i * 0.618 + seed) % 1) * width;
      const rise = (time * (0.04 + seed * 0.05) + i * 0.137) % 1;
      const py = height * (1 - rise);
      this.g.fillStyle(i % 3 === 0 ? forgeColors.hot : forgeColors.ember, 0.25 * (1 - rise));
      this.g.fillCircle(px, py, 1.5 + seed * 2);
    }
    this.g.fillStyle(forgeColors.ember, 0.08);
    this.g.fillEllipse(width / 2, height * 0.95, width * 1.2, height * 0.5);
  }

  private heatStops(): Stop[] {
    return [
      [0, forgeColors.danger, 1],
      [HeatBalance.SAFE_MIN, forgeColors.warm, 1],
      [0.5, forgeColors.safe, 1],
      [HeatBalance.SAFE_MAX, forgeColors.warm, 1],
      [1, forgeColors.danger, 1],
    ];
  }

  private drawGradient(x: number, y: number, w: number, h: number, stops: Stop[]): void {
    const strips = Math.max(32, Math.ceil(w / 3));
    const stripW = w / strips;
    for (let i = 0; i < strips; i += 1) {
      const [color, alpha] = sample(stops, (i + 0.5) / strips);
      this.g.fillStyle(color, alpha);
      this.g.fillRect(x + i * stripW, y, stripW + 0.6, h);
    }
  }

  /** A gradient bar with a tall marker at `t` along it. */
  private drawBand(
    x: number,
    y: number,
    w: number,
    h: number,
    stops: Stop[],
    t: number,
    markerW = 10,
  ): void {
    this.g.fillStyle(0x000000, 0.35);
    this.g.fillRoundedRect(x - 6, y - 6, w + 12, h + 12, 10);
    this.drawGradient(x, y, w, h, stops);
    this.g.lineStyle(2, palette.borderStrong, 0.8);
    this.g.strokeRect(x, y, w, h);
    this.g.fillStyle(palette.marker, 1);
    this.g.fillRect(x + t * w - markerW / 2, y - 9, markerW, h + 18);
  }

  private drawStrike(p: TimingStrike, x: number, y: number, w: number, scale: number): void {
    const bar = TimingStrike.BAR;
    const [redStart, redEnd] = p.redZone().map((v) => v / bar) as [number, number];
    const redCentre = (p.targetX + TimingStrike.TARGET / 2) / bar;
    const orangeStart = Math.max(0, redStart - 0.16);
    const orangeEnd = Math.min(1, redEnd + 0.16);
    this.g.fillStyle(0x000000, 0.35);
    this.g.fillRoundedRect(x - 6, y - 6, w + 12, BAR_HEIGHT + 12, 10);
    this.g.fillStyle(0x211819, 0.92);
    this.g.fillRect(x, y, w, BAR_HEIGHT);
    this.drawGradient(x, y, w, BAR_HEIGHT, [
      [0, forgeColors.warm, 0.34],
      [orangeStart, forgeColors.warm, 0.5],
      [redStart, forgeColors.ember, 0.68],
      [redCentre, forgeColors.red, 0.96],
      [redEnd, forgeColors.ember, 0.68],
      [orangeEnd, forgeColors.warm, 0.5],
      [1, forgeColors.warm, 0.34],
    ]);
    this.g.lineStyle(2, palette.borderStrong, 0.8);
    this.g.strokeRect(x, y, w, BAR_HEIGHT);
    const radius = (TimingStrike.MARKER / 2) * scale;
    const cx = x + p.markerT * w;
    const cy = y + BAR_HEIGHT / 2;
    this.g.fillStyle(palette.marker, p.ready || !p.started ? 1 : 0.6);
    this.g.fillCircle(cx, cy, radius);
    this.g.lineStyle(3, forgeColors.red, 1);
    this.g.strokeCircle(cx, cy, radius);
  }

  private flashOnChange(width: number, height: number): void {
    const puzzle = this.puzzle;
    if (!puzzle) return;
    const hits = this.hits();
    const misses = puzzle.failures;
    let color: number | null = null;
    if (misses > this.seen.misses) color = palette.danger;
    else if (hits > this.seen.hits) color = palette.good;
    else if (puzzle.completed && !this.seen.done)
      color = puzzle.success ? palette.good : palette.danger;
    this.seen = { hits, misses, done: puzzle.completed };
    if (color === null) return;
    play(color === palette.good ? 'hit' : 'miss');
    this.flash.setSize(width, height).setFillStyle(color, 1).setAlpha(0.34);
    this.tweens.killTweensOf(this.flash);
    this.tweens.add({ targets: this.flash, alpha: 0, duration: 220 });
  }
}
