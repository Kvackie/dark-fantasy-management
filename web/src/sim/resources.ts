/**
 * Resource arithmetic: paying, receiving, and the cost curves.
 *
 * Stockpiles never go below zero. A cost naming something the settlement does
 * not track counts as unaffordable rather than free.
 */

import type { CostEntry } from './config';
import { TRACKED_RESOURCES, type ResourceId, type ResourceMap, type World } from './types';

function isTracked(id: string): id is ResourceId {
  return (TRACKED_RESOURCES as readonly string[]).includes(id);
}

export function resourceAmount(world: World, id: string): number {
  return isTracked(id) ? world.resources[id] : 0;
}

export function canAfford(world: World, cost: ResourceMap): boolean {
  return Object.entries(cost).every(([id, amount]) => resourceAmount(world, id) >= amount);
}

/** Pay `cost` if every part of it can be paid; otherwise change nothing. */
export function spend(world: World, cost: ResourceMap): boolean {
  if (!canAfford(world, cost)) return false;
  for (const [id, amount] of Object.entries(cost)) {
    if (isTracked(id)) world.resources[id] = Math.max(0, world.resources[id] - amount);
  }
  return true;
}

/** Add a delta, which may be negative. Untracked resources are ignored. */
export function addResources(world: World, delta: ResourceMap): void {
  for (const [id, amount] of Object.entries(delta)) {
    if (isTracked(id)) world.resources[id] = Math.max(0, world.resources[id] + Math.trunc(amount));
  }
}

/** The price of the step from `level` to `level + 1`: the base, compounded per level already paid. */
export function scaledCost(entries: CostEntry[], level: number, growth: number): ResourceMap {
  const out: ResourceMap = {};
  const steps = Math.max(level - 1, 0);
  for (const entry of entries) out[entry.resource] = Math.round(entry.amount * growth ** steps);
  return out;
}

export function mergeResources(a: ResourceMap, b: ResourceMap): ResourceMap {
  const out: ResourceMap = { ...a };
  for (const [id, amount] of Object.entries(b)) out[id] = (out[id] ?? 0) + amount;
  return out;
}

export function scaleResources(values: ResourceMap, multiplier: number): ResourceMap {
  const out: ResourceMap = {};
  for (const [id, amount] of Object.entries(values)) out[id] = Math.round(amount * multiplier);
  return out;
}

export function hasNonZero(values: ResourceMap): boolean {
  return Object.values(values).some((amount) => amount !== 0);
}
