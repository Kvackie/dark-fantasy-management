/**
 * Seeded randomness.
 *
 * Every roll the simulation makes — recruit offers, ranged costs, crafted
 * stats, debug grants — comes from the generator whose state lives in the save,
 * so a game replays the same way from the same save. `Math.random` appears only
 * where a brand-new world picks its seeds.
 *
 * The map itself does not draw from this stream at all: a zone's biome, name,
 * claim cost and loot are hashed from the world seed and its coordinates, so the
 * same seed always yields the same map no matter what order it was explored in.
 */

import type { World } from './types';

/** mulberry32: tiny, fast, and good enough for a game. */
export function nextRandom(world: World): number {
  let t = (world.rng = (world.rng + 0x6d2b79f5) | 0);
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

/** An integer in `[min, max]`, both ends included. */
export function randomInt(world: World, min: number, max: number): number {
  if (max <= min) return min;
  return min + Math.floor(nextRandom(world) * (max - min + 1));
}

export function randomSeed(): number {
  return Math.floor(Math.random() * 4294967296) >>> 0;
}

/** A 32-bit djb2 hash of a string, for salting coordinate hashes. */
export function stringHash(text: string): number {
  let hash = 5381;
  for (let i = 0; i < text.length; i += 1) hash = (Math.imul(hash, 33) + text.charCodeAt(i)) | 0;
  return hash;
}

/** A hash of a map coordinate under the world seed, salted per question asked of it. */
export function coordHash(seed: number, x: number, y: number, salt: number): number {
  return (seed ^ Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(salt, 83492791)) >>> 0;
}

export function coordIndex(seed: number, x: number, y: number, salt: number, size: number): number {
  if (size <= 0) return 0;
  return coordHash(seed, x, y, salt) % size;
}

export function coordRange(
  seed: number,
  x: number,
  y: number,
  salt: number,
  min: number,
  max: number,
): number {
  if (max <= min) return min;
  return min + (coordHash(seed, x, y, salt) % (max - min + 1));
}
