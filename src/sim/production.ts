/**
 * What every plot makes per tick.
 *
 * A building's output is its base production, multiplied by its level and by
 * the work its staff bring: each point of the matching work stat adds 3%, and
 * every hero in a Lodge adds 10% to its gold.
 *
 * Levels count for a lot: each level past the first adds the building's whole
 * `upgrade_growth` to the multiplier, so a level-3 Lodge (growth 1.35) makes
 * 3.7× what it made at level 1.
 */

import {
  GATHERING_LODGE_GOLD_BONUS_PER_HERO,
  RESOURCE_WORK_STAT,
  buildingEffect,
  WORK_STAT_PRODUCTION_BONUS_PER_POINT,
  getBuilding,
} from './config';
import { effectiveWorkStats } from './heroes';
import { assignedHeroes, settlementSlots } from './settlements';
import type { ResourceMap, World } from './types';

export function slotProduction(world: World, settlementId: string, index: number): ResourceMap {
  const slot = settlementSlots(world, settlementId)[index];
  const building = getBuilding(slot?.buildingId ?? null);
  if (!slot || !building) return {};
  const staff = assignedHeroes(world, settlementId, index);

  // The Triage makes nothing; it costs gold for each patient it holds.
  if (building.id === 'triage') {
    const cost = buildingEffect(building, 'gold_per_hero', '', slot.level);
    return staff.length > 0 && cost > 0 ? { gold: -cost * staff.length } : {};
  }

  const levelMultiplier = 1 + Math.max(slot.level - 1, 0) * building.upgradeGrowth;
  const out: ResourceMap = {};
  for (const entry of building.baseProduction) {
    const workStat = RESOURCE_WORK_STAT[entry.resource];
    const work = workStat
      ? staff.reduce((sum, hero) => sum + effectiveWorkStats(world, hero)[workStat], 0)
      : 0;
    let workMultiplier = 1 + work * WORK_STAT_PRODUCTION_BONUS_PER_POINT;
    if (building.id === 'gathering_lodge' && entry.resource === 'gold') {
      workMultiplier += staff.length * GATHERING_LODGE_GOLD_BONUS_PER_HERO;
    }
    out[entry.resource] = Math.round(entry.amount * levelMultiplier * workMultiplier);
  }
  return out;
}

function addInto(target: ResourceMap, delta: ResourceMap): void {
  for (const [id, amount] of Object.entries(delta)) target[id] = (target[id] ?? 0) + amount;
}

/** Every owned settlement's output for one tick. */
export function settlementProduction(world: World, includeTriage = true): ResourceMap {
  const total: ResourceMap = {};
  for (const settlementId of world.ownedSettlementIds) {
    const slots = settlementSlots(world, settlementId);
    slots.forEach((slot, index) => {
      if (!includeTriage && slot.buildingId === 'triage') return;
      addInto(total, slotProduction(world, settlementId, index));
    });
  }
  return total;
}

/** Claimed special areas, spread per tick — a gem every ten ticks shows as 0.1. */
export function specialZoneYield(world: World): ResourceMap {
  const total: ResourceMap = {};
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'claimed' || !zone.claimedReward) continue;
    const { resource, amount, interval } = zone.claimedReward;
    total[resource] = (total[resource] ?? 0) + amount / Math.max(1, interval);
  }
  return total;
}

/** The per-tick figure beside each resource in the HUD. */
export function yieldPreview(world: World): ResourceMap {
  const total = settlementProduction(world);
  addInto(total, specialZoneYield(world));
  return total;
}
