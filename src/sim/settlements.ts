/**
 * Settlements and the plots in them: building, upgrading, tearing down, staffing.
 */

import {
  allBuildings,
  costListToMap,
  getBuilding,
  getCoreSettlement,
  type BuildingDefinition,
} from './config';
import { effectiveWorkStats, heroWorldTask, isHeroIdle, needsChapel, needsTriage } from './heroes';
import { mergeResources, scaleResources, scaledCost, spend, addResources } from './resources';
import type { BuildingSlot, Hero, ResourceMap, SettlementDefinition, World } from './types';

export const DISMANTLE_REFUND = 0.8;

export function settlementDefinition(world: World, id: string): SettlementDefinition | null {
  return getCoreSettlement(id) ?? world.generatedSettlements[id] ?? null;
}

export function settlementName(world: World, id: string): string {
  return settlementDefinition(world, id)?.name ?? id;
}

export function emptySlot(): BuildingSlot {
  return { buildingId: null, level: 0 };
}

/** The plots of a settlement, created or resized to its definition on first ask. */
export function settlementSlots(world: World, id: string): BuildingSlot[] {
  const plotCount = Math.max(1, settlementDefinition(world, id)?.plotCount ?? 1);
  let state = world.settlements[id];
  if (!state) {
    state = { slots: [] };
    world.settlements[id] = state;
  }
  while (state.slots.length < plotCount) state.slots.push(emptySlot());
  if (state.slots.length > plotCount) state.slots.length = plotCount;
  return state.slots;
}

export function slotAt(world: World, settlementId: string, index: number): BuildingSlot | null {
  return settlementSlots(world, settlementId)[index] ?? null;
}

export function buildingAt(world: World, settlementId: string, index: number) {
  return getBuilding(slotAt(world, settlementId, index)?.buildingId ?? null);
}

/** The heroes working a plot, in roster order. */
export function assignedHeroes(world: World, settlementId: string, index: number): Hero[] {
  return world.heroes.filter(
    (hero) => hero.assignment?.settlementId === settlementId && hero.assignment.slot === index,
  );
}

export function buildingCatalog(world: World, settlementId: string): BuildingDefinition[] {
  const allowed = settlementDefinition(world, settlementId)?.allowedBuildings ?? ['ALL'];
  if (allowed.includes('ALL')) return [...allBuildings()];
  return allBuildings().filter((building) => allowed.includes(building.id));
}

export function canBuildHere(world: World, settlementId: string, buildingId: string): boolean {
  return buildingCatalog(world, settlementId).some((building) => building.id === buildingId);
}

export function buildCost(building: BuildingDefinition): ResourceMap {
  return costListToMap(building.buildCost);
}

export function upgradeCost(world: World, settlementId: string, index: number): ResourceMap {
  const slot = slotAt(world, settlementId, index);
  const building = getBuilding(slot?.buildingId ?? null);
  if (!slot || !building) return {};
  return scaledCost(building.upgradeCost, slot.level, building.upgradeGrowth);
}

/** Everything ever paid into a plot: its build cost plus every upgrade it has had. */
export function totalInvestment(world: World, settlementId: string, index: number): ResourceMap {
  const slot = slotAt(world, settlementId, index);
  const building = getBuilding(slot?.buildingId ?? null);
  if (!slot || !building) return {};
  let total = buildCost(building);
  for (let level = 1; level < slot.level; level += 1) {
    total = mergeResources(total, scaledCost(building.upgradeCost, level, building.upgradeGrowth));
  }
  return total;
}

export function dismantleRefund(world: World, settlementId: string, index: number): ResourceMap {
  return scaleResources(totalInvestment(world, settlementId, index), DISMANTLE_REFUND);
}

export function build(
  world: World,
  settlementId: string,
  index: number,
  buildingId: string,
): boolean {
  const slot = slotAt(world, settlementId, index);
  const building = getBuilding(buildingId);
  if (!slot || slot.buildingId || !building) return false;
  if (!canBuildHere(world, settlementId, buildingId)) return false;
  if (!spend(world, buildCost(building))) return false;
  slot.buildingId = buildingId;
  slot.level = 1;
  return true;
}

export function upgrade(world: World, settlementId: string, index: number): boolean {
  const slot = slotAt(world, settlementId, index);
  const building = getBuilding(slot?.buildingId ?? null);
  if (!slot || !building || slot.level >= building.maxLevel) return false;
  if (!spend(world, upgradeCost(world, settlementId, index))) return false;
  slot.level += 1;
  return true;
}

/** Tear a building down: its workers go idle and four-fifths of what it cost comes back. */
export function dismantle(world: World, settlementId: string, index: number): boolean {
  const slot = slotAt(world, settlementId, index);
  if (!slot?.buildingId) return false;
  const refund = dismantleRefund(world, settlementId, index);
  for (const hero of assignedHeroes(world, settlementId, index)) hero.assignment = null;
  slot.buildingId = null;
  slot.level = 0;
  addResources(world, refund);
  return true;
}

export function meetsAssignmentRequirements(
  world: World,
  hero: Hero,
  building: BuildingDefinition,
): boolean {
  const stats = effectiveWorkStats(world, hero);
  return Object.entries(building.assignmentRequirements).every(
    ([key, needed]) => stats[key as keyof typeof stats] >= (needed ?? 0),
  );
}

/**
 * Whether a hero may work a building at all, leaving capacity aside.
 *
 * The Triage takes anyone hurt and the Chapel anyone shaken — wounded and
 * broken heroes included, since that is what those buildings are for. Anywhere
 * else wants a fit hero strong enough in the building's work stat.
 */
export function mayWork(world: World, hero: Hero, building: BuildingDefinition): boolean {
  if (building.id === 'triage') return needsTriage(world, hero);
  if (building.id === 'chapel') return needsChapel(world, hero);
  if (hero.broken || hero.wounded) return false;
  return meetsAssignmentRequirements(world, hero, building);
}

/** Heroes who could be put to work on a plot now: idle, and allowed there. */
export function eligibleHeroes(world: World, settlementId: string, index: number): Hero[] {
  const building = buildingAt(world, settlementId, index);
  if (!building) return [];
  return world.heroes.filter((hero) => isHeroIdle(world, hero) && mayWork(world, hero, building));
}

/**
 * Put a hero to work.
 *
 * A hero already working elsewhere is moved rather than refused. A hero away
 * clearing a zone cannot be reached.
 */
export function assignHero(world: World, hero: Hero, settlementId: string, index: number): boolean {
  const building = buildingAt(world, settlementId, index);
  if (!building) return false;
  if (!mayWork(world, hero, building)) return false;
  const here = hero.assignment?.settlementId === settlementId && hero.assignment.slot === index;
  if (here) return true;
  if (assignedHeroes(world, settlementId, index).length >= building.workerSlots) return false;
  if (heroWorldTask(world, hero.uid) !== null) return false;
  hero.assignment = { settlementId, slot: index };
  return true;
}

export function unassignHero(hero: Hero): boolean {
  if (!hero.assignment) return false;
  hero.assignment = null;
  return true;
}

/** How many of a building stand across every owned settlement, and the highest level among them. */
export function buildingCensus(
  world: World,
  buildingId: string,
): { count: number; highest: number } {
  let count = 0;
  let highest = 0;
  for (const settlementId of world.ownedSettlementIds) {
    for (const slot of settlementSlots(world, settlementId)) {
      if (slot.buildingId !== buildingId) continue;
      count += 1;
      highest = Math.max(highest, slot.level);
    }
  }
  return { count, highest };
}

export function builtPlotCount(world: World, settlementId: string): number {
  return settlementSlots(world, settlementId).filter((slot) => slot.buildingId).length;
}
