/**
 * Procedural map art: a painted tile for every biome, and a tileable mist.
 *
 * Everything is drawn once into canvas textures when the map scene starts, so
 * there are no image files to ship. Each biome gets a few variants from a
 * seeded generator; a zone picks one by its coordinates, so the same zone
 * always looks the same and neighbours rarely match.
 *
 * Tiles are drawn at twice their display size and shown scaled down, which
 * keeps them crisp at the map's highest zoom.
 */

import Phaser from 'phaser';
import { localRandom } from '@/sim/combat';
import { biomeColors } from '@/ui/theme';

export const TERRAIN_VARIANTS = 3;
const SCALE = 2;
const RADIUS = 8;
export const MIST_KEY = 'terrain-mist';
const MIST_SIZE = 256;

type Ctx = CanvasRenderingContext2D;
type Random = () => number;

export function terrainKey(biome: string, variant: number): string {
  return `terrain-${biome}-${variant}`;
}

/** Which variant a zone shows, stable for its coordinates. */
export function terrainVariant(x: number, y: number): number {
  const hash = Math.imul(x, 73_856_093) ^ Math.imul(y, 19_349_663);
  return Math.abs(hash) % TERRAIN_VARIANTS;
}

function rgb(color: number, shift = 0, alpha = 1): string {
  const clamp = (v: number) => Math.max(0, Math.min(255, Math.round(v)));
  const r = clamp(((color >> 16) & 0xff) * (1 + shift));
  const g = clamp(((color >> 8) & 0xff) * (1 + shift));
  const b = clamp((color & 0xff) * (1 + shift));
  return `rgba(${r},${g},${b},${alpha})`;
}

function roundedRect(ctx: Ctx, size: number, radius: number): void {
  ctx.beginPath();
  ctx.moveTo(radius, 0);
  ctx.arcTo(size, 0, size, size, radius);
  ctx.arcTo(size, size, 0, size, radius);
  ctx.arcTo(0, size, 0, 0, radius);
  ctx.arcTo(0, 0, size, 0, radius);
  ctx.closePath();
}

function speckle(ctx: Ctx, random: Random, size: number, base: number, count: number): void {
  for (let i = 0; i < count; i += 1) {
    const light = random() < 0.5;
    ctx.fillStyle = rgb(base, light ? 0.25 : -0.35, 0.18 + random() * 0.2);
    const r = 1 + random() * 2.5;
    ctx.fillRect(random() * size, random() * size, r, r);
  }
}

/** Spread points over the tile, nudged so they do not clump. */
function scatter(random: Random, size: number, count: number, margin: number): [number, number][] {
  const cols = Math.ceil(Math.sqrt(count));
  const cell = (size - margin * 2) / cols;
  const points: [number, number][] = [];
  for (let i = 0; i < cols * cols; i += 1) {
    if (random() > count / (cols * cols)) continue;
    const cx = margin + (i % cols) * cell + random() * cell;
    const cy = margin + Math.floor(i / cols) * cell + random() * cell;
    points.push([cx, cy]);
  }
  return points.sort((a, b) => a[1] - b[1]);
}

function pine(ctx: Ctx, x: number, y: number, h: number, base: number): void {
  ctx.fillStyle = 'rgba(0,0,0,0.25)';
  ctx.beginPath();
  ctx.ellipse(x + h * 0.08, y + 2, h * 0.28, h * 0.08, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#3b2a1c';
  ctx.fillRect(x - h * 0.04, y - h * 0.18, h * 0.08, h * 0.2);
  for (let tier = 0; tier < 3; tier += 1) {
    const top = y - h * (0.45 + tier * 0.22);
    const bottom = y - h * (0.12 + tier * 0.2);
    const half = h * (0.3 - tier * 0.07);
    ctx.fillStyle = rgb(base, -0.45 + tier * 0.1);
    ctx.beginPath();
    ctx.moveTo(x, top - h * 0.12);
    ctx.lineTo(x + half, bottom);
    ctx.lineTo(x - half, bottom);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = rgb(base, -0.1 + tier * 0.1, 0.8);
    ctx.beginPath();
    ctx.moveTo(x, top - h * 0.12);
    ctx.lineTo(x - half, bottom);
    ctx.lineTo(x - half * 0.3, bottom);
    ctx.closePath();
    ctx.fill();
  }
}

function drawForest(ctx: Ctx, random: Random, size: number, base: number): void {
  for (const [x, y] of scatter(random, size, 16, 18)) pine(ctx, x, y, 34 + random() * 22, base);
}

function drawMountain(ctx: Ctx, random: Random, size: number, base: number): void {
  const peaks = 3 + Math.floor(random() * 2);
  const list = [...Array(peaks).keys()]
    .map((i) => ({
      x: size * (0.15 + (0.7 * (i + random() * 0.6)) / peaks),
      h: size * (0.35 + random() * 0.35),
      w: size * (0.3 + random() * 0.15),
      y: size * (0.62 + random() * 0.3),
    }))
    .sort((a, b) => a.y - b.y);
  for (const peak of list) {
    const top = peak.y - peak.h;
    ctx.fillStyle = rgb(base, -0.3);
    ctx.beginPath();
    ctx.moveTo(peak.x, top);
    ctx.lineTo(peak.x + peak.w / 2, peak.y);
    ctx.lineTo(peak.x - peak.w / 2, peak.y);
    ctx.closePath();
    ctx.fill();
    // The lit face.
    ctx.fillStyle = rgb(base, 0.35);
    ctx.beginPath();
    ctx.moveTo(peak.x, top);
    ctx.lineTo(peak.x - peak.w / 2, peak.y);
    ctx.lineTo(peak.x - peak.w * 0.05, peak.y);
    ctx.closePath();
    ctx.fill();
    // Snow.
    const cap = 0.28;
    ctx.fillStyle = 'rgba(240,238,232,0.92)';
    ctx.beginPath();
    ctx.moveTo(peak.x, top);
    ctx.lineTo(peak.x + (peak.w / 2) * cap, top + peak.h * cap);
    ctx.lineTo(peak.x + (peak.w / 8) * cap, top + peak.h * cap * 0.8);
    ctx.lineTo(peak.x - (peak.w / 6) * cap, top + peak.h * cap * 1.05);
    ctx.lineTo(peak.x - (peak.w / 2) * cap, top + peak.h * cap);
    ctx.closePath();
    ctx.fill();
  }
}

function drawPlains(ctx: Ctx, random: Random, size: number, base: number): void {
  // A worn track across the field.
  ctx.strokeStyle = rgb(base, -0.3, 0.5);
  ctx.lineWidth = 7;
  ctx.beginPath();
  const from = random() * size;
  ctx.moveTo(-10, from);
  ctx.bezierCurveTo(
    size * 0.3,
    random() * size,
    size * 0.7,
    random() * size,
    size + 10,
    random() * size,
  );
  ctx.stroke();
  ctx.lineWidth = 1.6;
  for (let i = 0; i < 220; i += 1) {
    const x = random() * size;
    const y = random() * size;
    const h = 4 + random() * 8;
    ctx.strokeStyle = rgb(base, random() < 0.5 ? -0.35 : 0.2, 0.55);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (random() - 0.5) * 4, y - h);
    ctx.stroke();
  }
  for (const [x, y] of scatter(random, size, 5, 20)) {
    ctx.fillStyle = rgb(0x4f8a4f, -0.35);
    ctx.beginPath();
    ctx.arc(x, y, 5 + random() * 4, 0, Math.PI * 2);
    ctx.fill();
  }
}

function drawMarsh(ctx: Ctx, random: Random, size: number, base: number): void {
  // Pools of dark water, with ripples, between reedy banks.
  for (const [x, y] of scatter(random, size, 4, 30)) {
    const rx = 22 + random() * 26;
    const ry = rx * (0.45 + random() * 0.2);
    ctx.fillStyle = rgb(base, -0.45, 0.85);
    ctx.beginPath();
    ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = rgb(base, 0.3, 0.5);
    ctx.lineWidth = 1.5;
    for (let r = 0; r < 2; r += 1) {
      ctx.beginPath();
      ctx.ellipse(
        x,
        y,
        rx * (0.35 + r * 0.25),
        ry * (0.35 + r * 0.25),
        0,
        Math.PI * 1.1,
        Math.PI * 1.7,
      );
      ctx.stroke();
    }
  }
  ctx.lineWidth = 2;
  for (let i = 0; i < 60; i += 1) {
    const x = random() * size;
    const y = random() * size;
    ctx.strokeStyle = rgb(0x6f7f3a, random() * 0.3 - 0.2, 0.8);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x - 2 + random() * 4, y - 8 - random() * 8);
    ctx.stroke();
  }
  for (const [x, y] of scatter(random, size, 3, 24)) pine(ctx, x, y, 26 + random() * 10, 0x4f8a4f);
}

function drawNeutral(ctx: Ctx, random: Random, size: number, base: number): void {
  // Cracked, dry ground and scattered stones.
  ctx.lineWidth = 1.5;
  for (let i = 0; i < 9; i += 1) {
    let x = random() * size;
    let y = random() * size;
    ctx.strokeStyle = rgb(base, -0.45, 0.5);
    ctx.beginPath();
    ctx.moveTo(x, y);
    for (let s = 0; s < 4; s += 1) {
      x += (random() - 0.5) * 30;
      y += (random() - 0.5) * 30;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  for (const [x, y] of scatter(random, size, 12, 14)) {
    const r = 4 + random() * 8;
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath();
    ctx.ellipse(x + 2, y + 2, r, r * 0.7, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = rgb(0x9a9187, random() * 0.3 - 0.15);
    ctx.beginPath();
    ctx.ellipse(x, y, r, r * 0.7, random(), 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    ctx.beginPath();
    ctx.ellipse(x - r * 0.3, y - r * 0.25, r * 0.4, r * 0.25, 0, 0, Math.PI * 2);
    ctx.fill();
  }
}

function crystal(ctx: Ctx, x: number, y: number, h: number, tilt: number, base: number): void {
  const w = h * 0.28;
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(tilt);
  ctx.fillStyle = rgb(base, -0.2);
  ctx.beginPath();
  ctx.moveTo(0, -h);
  ctx.lineTo(w, -h * 0.75);
  ctx.lineTo(w, 0);
  ctx.lineTo(-w, 0);
  ctx.lineTo(-w, -h * 0.75);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = rgb(base, 0.45, 0.9);
  ctx.beginPath();
  ctx.moveTo(0, -h);
  ctx.lineTo(0, 0);
  ctx.lineTo(-w, 0);
  ctx.lineTo(-w, -h * 0.75);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function drawCrystals(ctx: Ctx, random: Random, size: number, base: number): void {
  const glow = ctx.createRadialGradient(size / 2, size / 2, 4, size / 2, size / 2, size * 0.55);
  glow.addColorStop(0, rgb(base, 0.6, 0.55));
  glow.addColorStop(1, rgb(base, 0, 0));
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, size, size);
  for (const [x, y] of scatter(random, size, 9, 22)) {
    const cluster = 2 + Math.floor(random() * 3);
    for (let c = 0; c < cluster; c += 1) {
      crystal(ctx, x + (c - cluster / 2) * 7, y, 18 + random() * 22, (random() - 0.5) * 0.9, base);
    }
  }
}

function hut(ctx: Ctx, x: number, y: number, w: number): void {
  const h = w * 0.6;
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.fillRect(x - w / 2 + 3, y - h + 3, w, h);
  ctx.fillStyle = '#6b5039';
  ctx.fillRect(x - w / 2, y - h, w, h);
  ctx.fillStyle = '#f0b060';
  ctx.fillRect(x - w * 0.12, y - h * 0.55, w * 0.24, h * 0.3);
  ctx.fillStyle = '#2e1d14';
  ctx.beginPath();
  ctx.moveTo(x - w / 2 - 4, y - h);
  ctx.lineTo(x, y - h - w * 0.55);
  ctx.lineTo(x + w / 2 + 4, y - h);
  ctx.closePath();
  ctx.fill();
}

function drawHome(ctx: Ctx, random: Random, size: number, base: number): void {
  const fire = ctx.createRadialGradient(size / 2, size / 2, 2, size / 2, size / 2, size * 0.5);
  fire.addColorStop(0, 'rgba(255,170,80,0.55)');
  fire.addColorStop(1, 'rgba(255,120,40,0)');
  ctx.fillStyle = fire;
  ctx.fillRect(0, 0, size, size);
  // Cobbles.
  for (let i = 0; i < 120; i += 1) {
    ctx.fillStyle = rgb(base, 0.1 + random() * 0.4, 0.35);
    ctx.beginPath();
    ctx.ellipse(
      random() * size,
      random() * size,
      3 + random() * 3,
      2 + random() * 2,
      random(),
      0,
      Math.PI * 2,
    );
    ctx.fill();
  }
  const ring = [
    [0.22, 0.32],
    [0.78, 0.3],
    [0.2, 0.82],
    [0.8, 0.84],
    [0.5, 0.18],
  ] as const;
  for (const [fx, fy] of ring)
    hut(ctx, size * fx + (random() - 0.5) * 8, size * fy, 26 + random() * 8);
}

const PAINTERS: Record<string, (ctx: Ctx, random: Random, size: number, base: number) => void> = {
  forest: drawForest,
  mountain: drawMountain,
  plains: drawPlains,
  mixed: drawMarsh,
  neutral: drawNeutral,
  crystal_cavern: drawCrystals,
  starting_zone: drawHome,
};

function paintTile(ctx: Ctx, biome: string, variant: number, size: number): void {
  const base = biomeColors[biome] ?? biomeColors.neutral!;
  const random = localRandom(biome.length * 7919 + variant * 104_729 + biome.charCodeAt(0));
  ctx.save();
  roundedRect(ctx, size, RADIUS * SCALE);
  ctx.clip();
  const ground = ctx.createLinearGradient(0, 0, size, size);
  ground.addColorStop(0, rgb(base, 0.12));
  ground.addColorStop(1, rgb(base, -0.28));
  ctx.fillStyle = ground;
  ctx.fillRect(0, 0, size, size);
  speckle(ctx, random, size, base, 500);
  PAINTERS[biome]?.(ctx, random, size, base);
  const vignette = ctx.createRadialGradient(
    size / 2,
    size / 2,
    size * 0.3,
    size / 2,
    size / 2,
    size * 0.75,
  );
  vignette.addColorStop(0, 'rgba(0,0,0,0)');
  vignette.addColorStop(1, 'rgba(0,0,0,0.45)');
  ctx.fillStyle = vignette;
  ctx.fillRect(0, 0, size, size);
  ctx.restore();
}

/** A soft, tileable cloud texture: blobs drawn with wraparound so the edges meet. */
function paintMist(ctx: Ctx): void {
  const random = localRandom(4242);
  const size = MIST_SIZE;
  for (let i = 0; i < 26; i += 1) {
    const x = random() * size;
    const y = random() * size;
    const r = 24 + random() * 60;
    const alpha = 0.05 + random() * 0.09;
    for (const dx of [-size, 0, size]) {
      for (const dy of [-size, 0, size]) {
        const g = ctx.createRadialGradient(x + dx, y + dy, 0, x + dx, y + dy, r);
        g.addColorStop(0, `rgba(214,210,204,${alpha})`);
        g.addColorStop(1, 'rgba(214,210,204,0)');
        ctx.fillStyle = g;
        ctx.fillRect(x + dx - r, y + dy - r, r * 2, r * 2);
      }
    }
  }
}

/** Create every terrain texture and the mist, once per game. */
export function createTerrainTextures(scene: Phaser.Scene, zoneSize: number): void {
  const size = Math.round(zoneSize * SCALE);
  for (const biome of Object.keys(PAINTERS)) {
    for (let variant = 0; variant < TERRAIN_VARIANTS; variant += 1) {
      const key = terrainKey(biome, variant);
      if (scene.textures.exists(key)) continue;
      const texture = scene.textures.createCanvas(key, size, size);
      if (!texture) continue;
      paintTile(texture.getContext(), biome, variant, size);
      texture.refresh();
    }
  }
  if (!scene.textures.exists(MIST_KEY)) {
    const mist = scene.textures.createCanvas(MIST_KEY, MIST_SIZE, MIST_SIZE);
    if (mist) {
      paintMist(mist.getContext());
      mist.refresh();
    }
  }
}
