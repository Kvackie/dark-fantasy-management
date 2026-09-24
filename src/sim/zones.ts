/**
 * The world map: a grid of zones fanning out from the first settlement.
 *
 * A zone moves `fog → discovered → clearing → cleared → claimed`. Claiming or
 * clearing a zone lifts the fog around it — the ring next to it becomes
 * discovered and the ring beyond appears as fog. Danger, loot and claim cost
 * rise with distance from the origin, measured in rings (Chebyshev distance).
 *
 * Everything about a zone that is not a choice the player made — its biome, its
 * name, its claim cost, the enemies holding it — is hashed from the world seed
 * and its coordinates, so the same seed draws the same map however it is
 * explored. What a fight goes like, and what it drops, is rolled when it happens.
 *
 * Clearing a zone means beating what holds it: the party marches for the
 * zone's clear time, then fights (see `combat.ts`). Win, and the zone is
 * cleared and pays out; lose, and the party limps home with half the
 * experience, more of its nerve gone, and the zone as it was.
 */

import { battle, enemyFighter, heroFighter, winChance, type BattleResult } from './combat';
import {
  allEnemies,
  defaultSettlementId,
  getCoreSettlement,
  getEnemy,
  getEquipmentDefinition,
  getItemDefinition,
  worldConfig,
  type RewardEntry,
  type RewardTable,
} from './config';
import { findHero, grantExperience, isHeroAvailable, updateCondition } from './heroes';
import { addEquipment, addItem } from './inventory';
import { addLog } from './log';
import { seedZoneBonusOffer } from './recruitment';
import { addResources, hasNonZero, spend } from './resources';
import { coordIndex, coordRange, nextRandom, randomInt, stringHash } from './rng';
import { settlementSlots } from './settlements';
import { partyEffect } from './skills';
import type {
  Hero,
  LogEntry,
  ResourceMap,
  SettlementDefinition,
  World,
  Zone,
  ZoneEnemy,
  ZoneState,
} from './types';

export function zoneKey(x: number, y: number): string {
  return `${x},${y}`;
}

const STATE_PRIORITY: Record<ZoneState, number> = {
  fog: 1,
  discovered: 2,
  clearing: 3,
  cleared: 4,
  claimed: 5,
};

export function zoneDistance(x: number, y: number): number {
  return Math.max(Math.abs(x), Math.abs(y));
}

/** Rings beyond the safe radius: what danger and reward scale with. */
function dangerRings(x: number, y: number): number {
  return Math.max(0, zoneDistance(x, y) - worldConfig.clearRequirements.safeRadius);
}

/**
 * The enemies holding a zone.
 *
 * More of them further out, and of harder tiers; which ones is down to the
 * zone's biome. Their stats scale with distance, so a Bog Ghoul four rings out
 * hits harder than one next door.
 */
export function generateEnemies(seed: number, x: number, y: number, biome: string): ZoneEnemy[] {
  const distance = zoneDistance(x, y);
  if (distance === 0) return [];
  const config = worldConfig.enemyGroups;
  const extra = coordRange(seed, x, y, 97, 1, 100) <= config.extraCountChance ? 1 : 0;
  const count = Math.min(
    config.maxCount,
    config.baseCount + Math.floor((distance - 1) / config.countPerRings) + extra,
  );
  const band = config.tierRings.find(([from, to]) => distance >= from && distance <= to);
  const tiers = band?.[2] ?? [1];
  let pool = allEnemies().filter((e) => tiers.includes(e.tier) && e.biomes.includes(biome));
  if (pool.length === 0) pool = allEnemies().filter((e) => tiers.includes(e.tier));
  if (pool.length === 0) pool = [...allEnemies()];
  const power = Math.round((1 + (distance - 1) * config.powerPerRing) * 100) / 100;
  const out: ZoneEnemy[] = [];
  for (let i = 0; i < count && pool.length > 0; i += 1) {
    const pick = pool[coordIndex(seed, x, y, 101 + i, pool.length)];
    if (pick) out.push({ id: pick.id, power });
  }
  return out;
}

/** Sanity each hero loses on an expedition: distance, and the dread of what they faced. */
export function zoneSanityLoss(x: number, y: number, enemies: ZoneEnemy[]): number {
  const config = worldConfig.clearRequirements;
  const dread = enemies.reduce((sum, enemy) => sum + (getEnemy(enemy.id)?.dread ?? 0), 0);
  return Math.max(0, config.sanityLossBase + dangerRings(x, y) * config.sanityLossGrowth + dread);
}

export function zoneExperience(x: number, y: number): number {
  const config = worldConfig.clearRewards;
  return Math.max(0, config.experienceBase + dangerRings(x, y) * config.experienceGrowth);
}

export function rewardTable(x: number, y: number): RewardTable | null {
  const distance = zoneDistance(x, y);
  return (
    worldConfig.clearRewards.tables.find(
      (table) => distance >= table.min_distance && distance <= table.max_distance,
    ) ?? null
  );
}

function rewardSucceeds(world: World, entry: RewardEntry): boolean {
  const chance = Math.max(0, Math.min(100, entry.chance ?? 100));
  if (chance >= 100) return true;
  if (chance <= 0) return false;
  return nextRandom(world) * 100 < chance;
}

function rollQuantity(world: World, entry: RewardEntry, multiplier = 1): number {
  const min = Math.max(0, entry.min ?? entry.amount ?? 0);
  const max = Math.max(min, entry.max ?? min);
  return Math.round(randomInt(world, min, max) * multiplier);
}

/** Pick a special biome by the roll, if one's spawn chance divides it. */
function rollSpecialBiome(roll: number): string {
  for (const id of Object.keys(worldConfig.specialBiomes).sort()) {
    const chance = worldConfig.specialBiomes[id]?.spawn_chance ?? 0;
    if (chance > 0 && roll % chance === 0) return id;
  }
  return '';
}

export function determineBiome(seed: number, x: number, y: number): string {
  if (x === 0 && y === 0) return 'neutral';
  // Plain arithmetic rather than 32-bit: every term fits in a double exactly.
  const roll = Math.abs(x * 92821 + y * 68917 + seed * 13);
  const special = rollSpecialBiome(roll);
  if (special) return special;
  if (roll % 20 <= 2) return 'neutral';
  return (['forest', 'mountain', 'plains', 'mixed'] as const)[Math.floor(roll / 10) % 4] ?? 'mixed';
}

export function generateZoneName(seed: number, x: number, y: number): string {
  const { prefixes, suffixes, articles } = worldConfig.names;
  const prefix = prefixes[coordIndex(seed, x, y, 11, prefixes.length)] ?? 'Ashen';
  const suffix = suffixes[coordIndex(seed, x, y, 23, suffixes.length)] ?? 'Reach';
  const article = articles[coordIndex(seed, x, y, 37, articles.length)] ?? '';
  return [article, prefix, suffix].filter(Boolean).join(' ');
}

export function generateClaimCost(seed: number, x: number, y: number): ResourceMap {
  const { base, distanceStep, variance } = worldConfig.claimCost;
  const distance = zoneDistance(x, y);
  const cost: ResourceMap = {};
  for (const [resource, amount] of Object.entries(base)) {
    let total = amount + (distanceStep[resource] ?? 0) * distance;
    const spread = variance[resource] ?? 0;
    if (spread > 0) total += coordRange(seed, x, y, stringHash(resource), 0, spread);
    cost[resource] = Math.max(0, total);
  }
  return cost;
}

export function biomePlotCount(biome: string): number {
  switch (biome) {
    case 'starting_zone':
      return 8;
    case 'neutral':
      return 5;
    case 'forest':
    case 'mountain':
    case 'plains':
    case 'mixed':
      return 3;
    default:
      return 8;
  }
}

export function biomeAllowedBuildings(biome: string): string[] {
  switch (biome) {
    case 'forest':
      return ['lumber_camp'];
    case 'mountain':
      return ['quarry'];
    case 'plains':
      return ['farm'];
    case 'mixed':
      return ['farm', 'lumber_camp', 'quarry'];
    default:
      return ['ALL'];
  }
}

function clearDurationFor(key: string): number {
  const override = worldConfig.overrides[key];
  if (override?.clear_duration !== undefined) return Math.max(1, override.clear_duration);
  return worldConfig.defaultClearDuration;
}

function applyBiomeDefaults(zone: Zone): void {
  const biome = worldConfig.specialBiomes[zone.biome];
  if (!biome) return;
  if (biome.no_settlement) zone.noSettlement = true;
  if (!zone.claimedReward && biome.claimed_reward) zone.claimedReward = { ...biome.claimed_reward };
  if (zone.clearDuration <= 0 && biome.clear_duration !== undefined) {
    zone.clearDuration = Math.max(0, biome.clear_duration);
  }
}

function applyOverride(zone: Zone): void {
  const override = worldConfig.overrides[zone.key];
  if (!override) return;
  if (override.state && override.state in STATE_PRIORITY) zone.state = override.state as ZoneState;
  if (override.name !== undefined) zone.generatedName = override.name;
  if (override.biome !== undefined) zone.biome = override.biome;
  if (override.no_settlement !== undefined) zone.noSettlement = override.no_settlement;
  if (override.claimed_reward) zone.claimedReward = { ...override.claimed_reward };
  if (override.clear_duration !== undefined)
    zone.clearDuration = Math.max(0, override.clear_duration);
  if (override.sanity_loss !== undefined) zone.sanityLoss = Math.max(0, override.sanity_loss);
  if (override.claim_cost) zone.claimCost = { ...override.claim_cost };
  if (override.settlement_id !== undefined) zone.settlementId = override.settlement_id;
  if (override.settlement_name !== undefined) zone.settlementName = override.settlement_name;
}

export function createZone(world: World, x: number, y: number, state: ZoneState): Zone {
  const key = zoneKey(x, y);
  const zone: Zone = {
    key,
    x,
    y,
    state,
    ticksRemaining: 0,
    clearDuration: clearDurationFor(key),
    assignedHeroUids: [],
    generatedName: '',
    biome: determineBiome(world.worldSeed, x, y),
    enemies: [],
    sanityLoss: 0,
    noSettlement: false,
    claimedReward: null,
    claimCost: {},
    settlementId: '',
    settlementName: '',
  };
  applyBiomeDefaults(zone);
  applyOverride(zone);
  applyBiomeDefaults(zone);
  zone.enemies = generateEnemies(world.worldSeed, x, y, zone.biome);
  const override = worldConfig.overrides[key]?.sanity_loss;
  zone.sanityLoss = override ?? zoneSanityLoss(x, y, zone.enemies);
  return zone;
}

function ensureVisible(world: World, x: number, y: number, desired: ZoneState): void {
  const key = zoneKey(x, y);
  const zone = world.zones[key];
  if (!zone) {
    world.zones[key] = createZone(world, x, y, desired);
    return;
  }
  if (STATE_PRIORITY[desired] > STATE_PRIORITY[zone.state]) zone.state = desired;
}

/** Lift the fog around every cleared and claimed zone. */
export function applyVisibility(world: World): void {
  const radius = worldConfig.revealRadius;
  for (const zone of Object.values(world.zones)) {
    if (zone.state === 'claimed' && !worldConfig.revealFromClaimed) continue;
    if (zone.state === 'cleared' && !worldConfig.revealFromCleared) continue;
    if (zone.state !== 'claimed' && zone.state !== 'cleared') continue;
    for (let dx = -radius; dx <= radius; dx += 1) {
      for (let dy = -radius; dy <= radius; dy += 1) {
        if (dx === 0 && dy === 0) continue;
        const ring = Math.max(Math.abs(dx), Math.abs(dy));
        ensureVisible(world, zone.x + dx, zone.y + dy, ring === 1 ? 'discovered' : 'fog');
      }
    }
  }
}

export function startingSettlementName(): string {
  return getCoreSettlement(defaultSettlementId())?.name ?? 'The Hollow March';
}

/** A fresh map: the home settlement at the origin, and the fog lifted around it. */
export function initializeZones(world: World): void {
  world.zones = {};
  const start = createZone(world, 0, 0, 'claimed');
  start.biome = 'starting_zone';
  start.enemies = [];
  start.settlementId = defaultSettlementId();
  start.settlementName = startingSettlementName();
  start.generatedName = start.settlementName;
  world.zones[start.key] = start;
  applyVisibility(world);
}

// -- clearing -----------------------------------------------------------------

export interface PartyPreview {
  party: Hero[];
  /** Estimated share of battles this party wins, 0–1. */
  winChance: number;
  /** Sanity each member would lose on a victory. */
  sanityLoss: number;
}

function partyOf(
  world: World,
  uids: readonly number[],
  limit = worldConfig.maxClearingParty,
): Hero[] {
  const party: Hero[] = [];
  for (const uid of uids) {
    if (party.length >= limit) break;
    const hero = findHero(world, uid);
    if (hero && !party.includes(hero)) party.push(hero);
  }
  return party;
}

function partySanityLoss(zone: Zone, party: Hero[]): number {
  const reduction = partyEffect(party, 'party_sanity_loss_pct');
  return Math.max(0, Math.round(zone.sanityLoss * (1 + reduction / 100)));
}

/**
 * How a party would fare against a zone.
 *
 * The win chance comes from simulating the battle a couple of hundred times on
 * a generator of its own, seeded from the zone and the party, so the estimate
 * is steady while the dialog is open and costs the world's dice nothing.
 */
export function partyPreview(world: World, key: string, uids: readonly number[]): PartyPreview {
  const zone = world.zones[key];
  const party = partyOf(world, uids);
  if (!zone || party.length === 0)
    return { party, winChance: 0, sanityLoss: zone?.sanityLoss ?? 0 };
  const heroes = party.map((hero) => heroFighter(world, hero, party));
  const enemies = zone.enemies.map(enemyFighter).filter((f) => f !== null);
  const seed = stringHash(
    `${zone.key}|${party.map((h) => `${h.uid}:${h.stats.current_health}`).join(',')}`,
  );
  return {
    party,
    winChance: winChance(heroes, enemies, seed),
    sanityLoss: partySanityLoss(zone, party),
  };
}

/** Send up to `maxClearingParty` fit, idle heroes to clear a discovered zone. */
export function startClearing(world: World, key: string, uids: readonly number[]): boolean {
  const zone = world.zones[key];
  if (!zone || zone.state !== 'discovered') return false;
  const party = partyOf(world, uids).filter((hero) => isHeroAvailable(world, hero));
  if (party.length === 0) return false;
  const duration = clearDurationFor(key);
  zone.state = 'clearing';
  zone.assignedHeroUids = party.map((hero) => hero.uid);
  zone.ticksRemaining = duration;
  zone.clearDuration = duration;
  return true;
}

/** Pull a hero out of any party; a party left empty abandons its zone. */
export function removeHeroFromZones(world: World, uid: number): boolean {
  let changed = false;
  for (const zone of Object.values(world.zones)) {
    if (!zone.assignedHeroUids.includes(uid)) continue;
    zone.assignedHeroUids = zone.assignedHeroUids.filter((id) => id !== uid);
    if (zone.state === 'clearing' && zone.assignedHeroUids.length === 0) {
      zone.state = 'discovered';
      zone.ticksRemaining = 0;
    }
    changed = true;
  }
  return changed;
}

export function ensureZoneName(zone: Zone, seed: number): string {
  if (zone.generatedName) return zone.generatedName;
  const override = worldConfig.overrides[zone.key];
  if (override?.name) return override.name;
  return generateZoneName(seed, zone.x, zone.y);
}

export function ensureClaimCost(zone: Zone, seed: number): ResourceMap {
  if (hasNonZero(zone.claimCost)) return { ...zone.claimCost };
  const override = worldConfig.overrides[zone.key]?.claim_cost;
  if (override && hasNonZero(override)) return { ...override };
  return generateClaimCost(seed, zone.x, zone.y);
}

type Detail = LogEntry['details'][number];

/** Roll a zone's loot table and its enemies' drops into the stores. */
function rollLoot(world: World, zone: Zone, multiplier: number): Detail[] {
  const table = rewardTable(zone.x, zone.y);
  const resources: ResourceMap = {};
  const items = new Map<string, number>();
  const equipment: string[] = [];
  for (const entry of table?.resources ?? []) {
    if (!entry.resource || !rewardSucceeds(world, entry)) continue;
    const quantity = rollQuantity(world, entry);
    if (quantity > 0) resources[entry.resource] = (resources[entry.resource] ?? 0) + quantity;
  }
  const itemEntries = [
    ...(table?.items ?? []),
    ...zone.enemies.flatMap((enemy) => getEnemy(enemy.id)?.drops ?? []),
  ];
  for (const entry of itemEntries) {
    if (!entry.definition_id || !rewardSucceeds(world, entry)) continue;
    const quantity = rollQuantity(world, entry, multiplier);
    if (quantity > 0 && addItem(world, entry.definition_id, quantity)) {
      items.set(entry.definition_id, (items.get(entry.definition_id) ?? 0) + quantity);
    }
  }
  for (const entry of table?.equipment ?? []) {
    if (!entry.definition_id || !rewardSucceeds(world, entry)) continue;
    if (addEquipment(world, entry.definition_id)) {
      equipment.push(getEquipmentDefinition(entry.definition_id)?.name ?? entry.definition_id);
    }
  }
  addResources(world, resources);

  const details: Detail[] = [];
  const resourceList = Object.entries(resources).map(([id, amount]) => `${id}:${amount}`);
  if (resourceList.length)
    details.push({ key: 'log.detail.resources', params: { list: resourceList.join(',') } });
  const itemList = [...items].map(([id, qty]) => `${getItemDefinition(id)?.name ?? id} ×${qty}`);
  if (itemList.length)
    details.push({ key: 'log.detail.items', params: { list: itemList.join(', ') } });
  if (equipment.length)
    details.push({ key: 'log.detail.equipment', params: { list: equipment.join(', ') } });
  return details;
}

/** The fight at the end of a march, and everything that follows from it. */
function resolveExpedition(world: World, zone: Zone, party: Hero[]): void {
  const heroes = party.map((hero) => heroFighter(world, hero, party));
  const enemies = zone.enemies.map(enemyFighter).filter((f) => f !== null);
  const result: BattleResult = battle(() => nextRandom(world), heroes, enemies);
  const victory = enemies.length === 0 || result.victory;
  const details: Detail[] = [];

  const faced = zone.enemies.map((enemy) => getEnemy(enemy.id)?.name ?? enemy.id);
  if (faced.length)
    details.push({
      key: 'log.detail.faced',
      params: { list: faced.join(', '), rounds: result.rounds },
    });

  for (const report of result.fighters) {
    if (report.side !== 'hero') continue;
    const hero = party.find((member) => member.uid === report.heroUid);
    if (!hero) continue;
    hero.stats.current_health = report.healthLeft;
    details.push({
      key: report.fell ? 'log.detail.hero_fell' : 'log.detail.hero',
      params: {
        name: hero.name,
        dealt: report.damageDealt,
        taken: report.damageTaken,
        crits: report.crits,
      },
    });
  }

  if (victory) {
    const heal = partyEffect(party, 'party_heal_after_battle_pct');
    if (heal > 0) {
      for (const hero of party) {
        if (hero.stats.current_health <= 0) continue;
        const max = heroFighter(world, hero, party).maxHealth;
        hero.stats.current_health = Math.min(
          max,
          hero.stats.current_health + Math.round((max * heal) / 100),
        );
      }
    }
  }

  const slain = result.fighters.filter((f) => f.side === 'enemy' && f.fell).length;
  const tierXp = zone.enemies.reduce((sum, enemy) => sum + (getEnemy(enemy.id)?.tier ?? 1), 0) * 2;
  const fullXp =
    zoneExperience(zone.x, zone.y) +
    (victory ? tierXp : Math.round((tierXp * slain) / Math.max(1, zone.enemies.length)));
  const experience = victory ? fullXp : Math.floor(fullXp / 2);
  const sanityLoss = Math.round(partySanityLoss(zone, party) * (victory ? 1 : 1.5));
  details.push({ key: 'log.detail.xp', params: { amount: experience } });
  if (sanityLoss > 0) details.push({ key: 'log.detail.sanity', params: { amount: sanityLoss } });

  for (const hero of party) {
    hero.stats.current_sanity = Math.max(0, hero.stats.current_sanity - sanityLoss);
    const levels = grantExperience(hero, experience);
    if (levels > 0) addLog(world, 'level', 'log.level', { name: hero.name, level: hero.level });
  }

  if (victory) {
    zone.state = 'cleared';
    zone.generatedName = ensureZoneName(zone, world.worldSeed);
    zone.claimCost = ensureClaimCost(zone, world.worldSeed);
    const loot = partyEffect(party, 'party_loot_pct');
    details.push(...rollLoot(world, zone, 1 + loot / 100));
    if (seedZoneBonusOffer(world)) details.push({ key: 'log.detail.recruit', params: {} });
    addLog(world, 'victory', 'log.victory', { zone: zone.generatedName, key: zone.key }, details);
  } else {
    zone.state = 'discovered';
    const name = ensureZoneName(zone, world.worldSeed);
    addLog(world, 'defeat', 'log.defeat', { zone: name, key: zone.key }, details);
  }

  for (const hero of party) {
    for (const change of updateCondition(world, hero)) {
      addLog(world, change, `log.${change}`, { name: hero.name });
    }
  }
}

/** One tick of every clearing party: a step of the march, and the battle at the end of it. */
export function tickZones(world: World): void {
  let changed = false;
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'clearing') continue;
    changed = true;
    zone.ticksRemaining = Math.max(0, zone.ticksRemaining - 1);
    if (zone.ticksRemaining > 0) continue;
    const party = zone.assignedHeroUids
      .map((uid) => findHero(world, uid))
      .filter((hero): hero is Hero => hero !== null);
    zone.assignedHeroUids = [];
    if (party.length === 0) {
      zone.state = 'discovered';
      continue;
    }
    resolveExpedition(world, zone, party);
  }
  if (changed) applyVisibility(world);
}

// -- claiming -----------------------------------------------------------------

function coordId(value: number): string {
  return value < 0 ? `n${Math.abs(value)}` : `p${value}`;
}

export function generatedSettlementId(x: number, y: number): string {
  return `zone_${coordId(x)}_${coordId(y)}`;
}

export function generatedSettlementDefinition(zone: Zone): SettlementDefinition | null {
  const name = zone.settlementName || zone.generatedName;
  if (!zone.settlementId || !name) return null;
  return {
    id: zone.settlementId,
    name,
    biome: zone.biome || 'neutral',
    plotCount: biomePlotCount(zone.biome),
    allowedBuildings: biomeAllowedBuildings(zone.biome),
    generated: true,
  };
}

/**
 * Pay to claim a cleared zone.
 *
 * An ordinary zone becomes a settlement with plots of its own, shaped by its
 * biome. A special area — a crystal cavern — founds nothing, and pays out on
 * its own schedule instead.
 */
export function claimZone(world: World, key: string): boolean {
  const zone = world.zones[key];
  if (!zone || zone.state !== 'cleared') return false;
  if (!spend(world, zone.claimCost)) return false;
  zone.state = 'claimed';
  addLog(world, 'claimed', zone.noSettlement ? 'log.claimed_area' : 'log.claimed', {
    zone: zone.generatedName || zone.key,
  });
  if (!zone.settlementId) zone.settlementId = generatedSettlementId(zone.x, zone.y);
  if (!zone.settlementName) {
    zone.settlementName = zone.generatedName || generateZoneName(world.worldSeed, zone.x, zone.y);
  }
  if (!zone.noSettlement) {
    zone.generatedName = zone.settlementName;
    const definition = generatedSettlementDefinition(zone);
    if (definition && !getCoreSettlement(definition.id)) {
      world.generatedSettlements[definition.id] = definition;
    }
    if (!world.ownedSettlementIds.includes(zone.settlementId)) {
      world.ownedSettlementIds.push(zone.settlementId);
    }
    settlementSlots(world, zone.settlementId);
  }
  applyVisibility(world);
  return true;
}

/** Claimed special areas pay out on the ticks their interval divides. */
export function tickClaimedRewards(world: World): boolean {
  let changed = false;
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'claimed' || !zone.claimedReward) continue;
    const { resource, amount, interval } = zone.claimedReward;
    if (world.tickCount % Math.max(1, interval) !== 0) continue;
    addResources(world, { [resource]: amount });
    changed = true;
  }
  return changed;
}
