/**
 * The Cinder Smithy's recipes.
 *
 * A smithy unlocks crafting; the highest smithy's level decides which recipes
 * are on offer. A recipe's result names ranges rather than numbers, and the
 * forge puzzle decides where in them the piece lands: every miss lowers the
 * ceiling, and a clean run also nudges the roll toward the top of it. The
 * materials are spent when the puzzle ends, whether it succeeded or not.
 */

import { allRecipes, getRecipe, type Recipe } from './config';
import { addEquipment, itemQuantity, removeItem } from './inventory';
import { resourceAmount, spend } from './resources';
import { nextRandom } from './rng';
import { buildingCensus } from './settlements';
import type {
  BonusValue,
  EquipmentBonuses,
  EquipmentDefinition,
  EquipmentInstance,
  World,
} from './types';

export function highestSmithyLevel(world: World): number {
  return buildingCensus(world, 'smithy').highest;
}

export function isCraftingUnlocked(world: World): boolean {
  return buildingCensus(world, 'smithy').count > 0;
}

export function availableRecipes(world: World): Recipe[] {
  const level = highestSmithyLevel(world);
  return allRecipes().filter((recipe) => recipe.level <= level);
}

export function hasRecipeCost(world: World, entry: Recipe['cost'][number]): boolean {
  const have = entry.kind === 'resource' ? resourceAmount(world, entry.id) : itemQuantity(world, entry.id);
  return have >= entry.amount;
}

export function canAffordRecipe(world: World, recipe: Recipe): boolean {
  return recipe.cost.every((entry) => hasRecipeCost(world, entry));
}

function payRecipe(world: World, recipe: Recipe): boolean {
  if (!canAffordRecipe(world, recipe)) return false;
  const resources: Record<string, number> = {};
  for (const entry of recipe.cost) {
    if (entry.kind === 'resource') resources[entry.id] = (resources[entry.id] ?? 0) + entry.amount;
    else removeItem(world, entry.id, entry.amount);
  }
  return spend(world, resources);
}

/** How well the puzzle went, from 1 (no misses) to 0 (every miss allowed). */
export function craftQuality(failures: number, maxFailures: number): number {
  if (maxFailures <= 0) return 1;
  return Math.max(0, Math.min(1, 1 - Math.max(0, failures) / maxFailures));
}

function rollBlock<K extends string>(
  world: World,
  block: Partial<Record<K, BonusValue>>,
  quality: number,
): Partial<Record<K, number>> {
  const out: Partial<Record<K, number>> = {};
  for (const key of Object.keys(block) as K[]) {
    const value = block[key];
    if (value === undefined) continue;
    if (typeof value === 'number') {
      out[key] = value;
      continue;
    }
    const min = Math.min(value.min, value.max);
    const max = Math.max(value.min, value.max);
    const ceiling = min + Math.round((max - min) * quality);
    // A plain roll, bent toward the ceiling by up to a quarter for a clean run.
    const plain = nextRandom(world);
    const high = 1 - nextRandom(world) ** 1.35;
    const t = plain + (high - plain) * quality * 0.25;
    out[key] = min + Math.round((ceiling - min) * t);
  }
  return out;
}

export function rollBonuses(
  world: World,
  bonuses: EquipmentBonuses<BonusValue>,
  failures: number,
  maxFailures: number,
): EquipmentBonuses {
  const quality = craftQuality(failures, maxFailures);
  return {
    stats: rollBlock(world, bonuses.stats, quality),
    work_stats: rollBlock(world, bonuses.work_stats, quality),
  };
}

/**
 * Finish a craft.
 *
 * Pays the recipe either way; on a success, rolls the piece and puts it in the
 * stores. Returns the new piece, or null when the craft failed or could no
 * longer be paid for.
 */
export function completeCraft(
  world: World,
  recipeId: string,
  success: boolean,
  failures: number,
  maxFailures: number,
): EquipmentInstance | null {
  const recipe = getRecipe(recipeId);
  if (!recipe || !payRecipe(world, recipe)) return null;
  if (!success) return null;
  const id = `crafted_${recipe.id}_${world.nextEquipmentUid}`;
  const definition: EquipmentDefinition = {
    id,
    name: recipe.result.name,
    slot: recipe.result.slot,
    bonuses: rollBonuses(world, recipe.result.bonuses, failures, maxFailures),
  };
  return addEquipment(world, id, definition);
}
