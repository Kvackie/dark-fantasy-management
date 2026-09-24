/**
 * Heroes: joining, growing, and what they come to with their gear on.
 */

import { experienceCeiling, getHeroDefinition, type Amount, type HeroDefinition } from './config';
import { equipmentDefinitionOf } from './inventory';
import { randomInt } from './rng';
import {
  EQUIPMENT_SLOTS,
  STAT_KEYS,
  WORK_STAT_KEYS,
  type BaseStats,
  type EquipmentBonuses,
  type EquipmentSlot,
  type Hero,
  type HeroStats,
  type RecruitOffer,
  type WorkStats,
  type World,
} from './types';

function rollGrowth<K extends string>(world: World, block: Record<K, Amount>): Record<K, number> {
  const out = {} as Record<K, number>;
  for (const key of Object.keys(block) as K[]) {
    const value = block[key];
    out[key] = typeof value === 'number' ? value : randomInt(world, value.min, value.max);
  }
  return out;
}

function emptyEquipment(): Record<EquipmentSlot, number | null> {
  return Object.fromEntries(EQUIPMENT_SLOTS.map((slot) => [slot, null])) as Record<
    EquipmentSlot,
    number | null
  >;
}

function grownStats(base: BaseStats, growth: BaseStats, level: number): HeroStats {
  const stats = { ...base };
  for (const key of STAT_KEYS) stats[key] += Math.max(level - 1, 0) * growth[key];
  return {
    ...stats,
    max_health: stats.health,
    current_health: stats.health,
    max_sanity: stats.sanity,
    current_sanity: stats.sanity,
  };
}

function grownWorkStats(base: WorkStats, growth: WorkStats, level: number): WorkStats {
  const stats = { ...base };
  for (const key of WORK_STAT_KEYS) stats[key] += Math.max(level - 1, 0) * growth[key];
  return stats;
}

/** A hero straight from the roster, at the definition's own level. */
export function createHero(
  world: World,
  definition: HeroDefinition,
  level = definition.level,
): Hero {
  const statGrowth = rollGrowth(world, definition.statGrowth);
  const workStatGrowth = rollGrowth(world, definition.workStatGrowth);
  const hero: Hero = {
    uid: world.nextHeroUid,
    definitionId: definition.id,
    name: definition.name,
    heroClass: definition.heroClass,
    level,
    experience: Math.max(level - 1, 0) * 10,
    statGrowth,
    workStatGrowth,
    stats: grownStats(definition.stats, statGrowth, level),
    workStats: grownWorkStats(definition.workStats, workStatGrowth, level),
    equipment: emptyEquipment(),
    assignment: null,
  };
  world.nextHeroUid += 1;
  return hero;
}

/** A hero from a tavern offer: the offer's name and level on the roster entry's numbers. */
export function createHeroFromOffer(world: World, offer: RecruitOffer): Hero {
  const definition = getHeroDefinition(offer.definitionId);
  if (definition) {
    const hero = createHero(world, definition, offer.level);
    hero.name = offer.name;
    hero.heroClass = offer.heroClass;
    return hero;
  }
  // The roster entry has gone (a changed data file); fall back on what the offer recorded.
  const hero: Hero = {
    uid: world.nextHeroUid,
    definitionId: offer.definitionId,
    name: offer.name,
    heroClass: offer.heroClass,
    level: offer.level,
    experience: Math.max(offer.level - 1, 0) * 10,
    statGrowth: zeroStats(),
    workStatGrowth: { farming: 0, mining: 0, lumbering: 0 },
    stats: grownStats(offer.stats, zeroStats(), 1),
    workStats: { ...offer.workStats },
    equipment: emptyEquipment(),
    assignment: null,
  };
  world.nextHeroUid += 1;
  return hero;
}

function zeroStats(): BaseStats {
  return Object.fromEntries(STAT_KEYS.map((key) => [key, 0])) as BaseStats;
}

/** One level: every stat grows by the hero's own growth, and the pools grow with their caps. */
export function levelUp(hero: Hero): void {
  const stats = hero.stats;
  for (const key of STAT_KEYS) stats[key] += hero.statGrowth[key];
  stats.max_health = stats.health;
  stats.current_health = Math.min(stats.current_health + hero.statGrowth.health, stats.max_health);
  stats.max_sanity = stats.sanity;
  stats.current_sanity = Math.min(stats.current_sanity + hero.statGrowth.sanity, stats.max_sanity);
  for (const key of WORK_STAT_KEYS) hero.workStats[key] += hero.workStatGrowth[key];
  hero.level += 1;
}

/** Add experience and take every level it pays for. */
export function grantExperience(hero: Hero, amount: number): void {
  hero.experience += amount;
  while (hero.experience >= experienceCeiling(hero.level)) levelUp(hero);
}

export function findHero(world: World, uid: number): Hero | null {
  return world.heroes.find((hero) => hero.uid === uid) ?? null;
}

// -- derived state ------------------------------------------------------------

/** The zone this hero is out clearing, if any. */
export function heroWorldTask(world: World, uid: number): string | null {
  for (const zone of Object.values(world.zones)) {
    if (zone.state === 'clearing' && zone.assignedHeroUids.includes(uid)) return zone.key;
  }
  return null;
}

/** Idle: neither working a plot nor away clearing a zone. */
export function isHeroIdle(world: World, hero: Hero): boolean {
  return hero.assignment === null && heroWorldTask(world, hero.uid) === null;
}

/** The sum of every bonus on the gear this hero is actually wearing. */
export function equipmentBonuses(world: World, hero: Hero): EquipmentBonuses {
  const bonuses: EquipmentBonuses = { stats: {}, work_stats: {} };
  for (const slot of EQUIPMENT_SLOTS) {
    const uid = hero.equipment[slot];
    if (uid === null) continue;
    const instance = world.equipment.find((entry) => entry.uid === uid);
    if (!instance || instance.equippedHeroUid !== hero.uid) continue;
    const definition = equipmentDefinitionOf(instance);
    if (!definition) continue;
    for (const key of STAT_KEYS) {
      const added = definition.bonuses.stats[key] ?? 0;
      if (added !== 0) bonuses.stats[key] = (bonuses.stats[key] ?? 0) + added;
    }
    for (const key of WORK_STAT_KEYS) {
      const added = definition.bonuses.work_stats[key] ?? 0;
      if (added !== 0) bonuses.work_stats[key] = (bonuses.work_stats[key] ?? 0) + added;
    }
  }
  return bonuses;
}

/**
 * Combat stats with gear.
 *
 * Gear raises the caps of the two pools but not what is in them: a helm with
 * +10 health gives a hero ten more to lose, not ten more to spend, which is
 * what the Triage is for.
 */
export function effectiveStats(world: World, hero: Hero): HeroStats {
  const bonus = equipmentBonuses(world, hero).stats;
  const stats = { ...hero.stats };
  for (const key of STAT_KEYS) stats[key] = hero.stats[key] + (bonus[key] ?? 0);
  stats.max_health = hero.stats.max_health + (bonus.health ?? 0);
  stats.current_health = hero.stats.current_health;
  stats.max_sanity = hero.stats.max_sanity + (bonus.sanity ?? 0);
  stats.current_sanity = Math.min(hero.stats.current_sanity, stats.max_sanity);
  return stats;
}

export function effectiveWorkStats(world: World, hero: Hero): WorkStats {
  const bonus = equipmentBonuses(world, hero).work_stats;
  const stats = { ...hero.workStats };
  for (const key of WORK_STAT_KEYS) stats[key] += bonus[key] ?? 0;
  return stats;
}

export function needsTriage(world: World, hero: Hero): boolean {
  const stats = effectiveStats(world, hero);
  return stats.current_health < stats.max_health;
}
