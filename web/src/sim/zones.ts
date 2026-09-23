/**
 * The world map: a grid of zones fanning out from the first settlement.
 *
 * A zone moves `fog → discovered → clearing → cleared → claimed`. Claiming or
 * clearing a zone lifts the fog around it — the ring next to it becomes
 * discovered and the ring beyond appears as fog. Danger, loot and claim cost
 * rise with distance from the origin, measured in rings (Chebyshev distance).
 *
 * Everything about a zone that is not a choice the player made — its biome, its
 * name, its claim cost, what it drops — is hashed from the world seed and its
 * coordinates, so the same seed draws the same map however it is explored.
 */

import {
  defaultSettlementId,
  getCoreSettlement,
  getEquipmentDefinition,
  worldConfig,
  type RewardEntry,
  type RewardTable,
} from './config';
import { effectiveStats, effectiveWorkStats, findHero, grantExperience, isHeroIdle } from './heroes';
import { addEquipment, addItem } from './inventory';
import { seedZoneBonusOffer } from './recruitment';
import { addResources, hasNonZero, spend } from './resources';
import { coordIndex, coordRange, stringHash } from './rng';
import { settlementSlots } from './settlements';
import {
  WORK_STAT_KEYS,
  type ResourceMap,
  type SettlementDefinition,
  type World,
  type Zone,
  type ZoneClearReport,
  type ZoneRequirements,
  type ZoneState,
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

export function normalizeRequirements(source: Partial<Record<string, number>>): ZoneRequirements {
  const read = (key: string) => Math.max(0, Math.trunc(source[key] ?? 0));
  return {
    level: read('level'),
    sanity: read('sanity'),
    attack: read('attack'),
    defense: read('defense'),
    farming: read('farming'),
    mining: read('mining'),
    lumbering: read('lumbering'),
  };
}

export function generateRequirements(x: number, y: number): ZoneRequirements {
  const config = worldConfig.clearRequirements;
  const rings = dangerRings(x, y);
  return normalizeRequirements({
    attack: config.attackBase + rings * config.attackGrowth,
    defense: config.defenseBase + rings * config.defenseGrowth,
  });
}

export function zoneSanityLoss(x: number, y: number): number {
  const config = worldConfig.clearRequirements;
  return Math.max(0, config.sanityLossBase + dangerRings(x, y) * config.sanityLossGrowth);
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

function rewardSucceeds(seed: number, zone: Zone, entry: RewardEntry): boolean {
  const chance = Math.max(0, Math.min(100, entry.chance ?? 100));
  if (chance >= 100) return true;
  if (chance <= 0) return false;
  const salt = stringHash(JSON.stringify(entry));
  return coordRange(seed, zone.x, zone.y, salt, 1, 100) <= chance;
}

function rollQuantity(seed: number, zone: Zone, entry: RewardEntry, salt: number): number {
  const min = Math.max(0, entry.min ?? entry.amount ?? 0);
  const max = Math.max(min, entry.max ?? min);
  return coordRange(seed, zone.x, zone.y, salt, min, max);
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
  if (override.clear_duration !== undefined) zone.clearDuration = Math.max(0, override.clear_duration);
  if (override.requirements) zone.requirements = normalizeRequirements(override.requirements);
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
    requirements: generateRequirements(x, y),
    sanityLoss: zoneSanityLoss(x, y),
    noSettlement: false,
    claimedReward: null,
    claimCost: {},
    settlementId: '',
    settlementName: '',
  };
  applyBiomeDefaults(zone);
  applyOverride(zone);
  applyBiomeDefaults(zone);
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
  start.settlementId = defaultSettlementId();
  start.settlementName = startingSettlementName();
  start.generatedName = start.settlementName;
  world.zones[start.key] = start;
  applyVisibility(world);
}

// -- clearing -----------------------------------------------------------------

export interface PartyPreview {
  requirements: ZoneRequirements;
  totals: ZoneRequirements;
  meets: boolean;
  /** Each unmet requirement as `[key, have, need]`. */
  shortfalls: Array<[keyof ZoneRequirements, number, number]>;
}

/** The party's summed stats against a zone's requirements. */
export function partyPreview(world: World, key: string, uids: readonly number[]): PartyPreview {
  const zone = world.zones[key];
  const totals = normalizeRequirements({});
  const requirements = zone ? zone.requirements : normalizeRequirements({});
  const seen = new Set<number>();
  for (const uid of uids) {
    if (uid <= 0 || seen.has(uid)) continue;
    seen.add(uid);
    const hero = findHero(world, uid);
    if (!hero) continue;
    const stats = effectiveStats(world, hero);
    const work = effectiveWorkStats(world, hero);
    totals.level += Math.max(1, hero.level);
    totals.sanity += Math.max(0, stats.current_sanity);
    totals.attack += Math.max(0, stats.attack);
    totals.defense += Math.max(0, stats.defense);
    for (const workKey of WORK_STAT_KEYS) totals[workKey] += Math.max(0, work[workKey]);
  }
  const shortfalls: PartyPreview['shortfalls'] = [];
  for (const requirementKey of Object.keys(requirements) as Array<keyof ZoneRequirements>) {
    const need = requirements[requirementKey];
    if (need > 0 && totals[requirementKey] < need) {
      shortfalls.push([requirementKey, totals[requirementKey], need]);
    }
  }
  return { requirements, totals, meets: zone !== undefined && shortfalls.length === 0, shortfalls };
}

/** Send up to `maxClearingParty` idle heroes to clear a discovered zone. */
export function startClearing(world: World, key: string, uids: readonly number[]): boolean {
  const zone = world.zones[key];
  if (!zone || zone.state !== 'discovered') return false;
  const party: number[] = [];
  for (const uid of uids) {
    if (party.length >= worldConfig.maxClearingParty) break;
    if (uid <= 0 || party.includes(uid)) continue;
    const hero = findHero(world, uid);
    if (hero && isHeroIdle(world, hero)) party.push(uid);
  }
  if (party.length === 0) return false;
  if (!partyPreview(world, key, party).meets) return false;
  const duration = clearDurationFor(key);
  zone.state = 'clearing';
  zone.assignedHeroUids = party;
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

/** Pay a returning party: experience and sanity loss for the heroes, loot for the stores. */
function resolveClearRewards(world: World, zone: Zone, party: number[]): ZoneClearReport {
  const experience = zoneExperience(zone.x, zone.y);
  const sanityLoss = Math.max(0, zone.sanityLoss);
  const heroNames: string[] = [];
  for (const uid of party) {
    const hero = findHero(world, uid);
    if (!hero) continue;
    hero.stats.current_sanity = Math.max(0, hero.stats.current_sanity - sanityLoss);
    grantExperience(hero, experience);
    heroNames.push(hero.name);
  }

  const seed = world.worldSeed;
  const table = rewardTable(zone.x, zone.y);
  const resources: ResourceMap = {};
  const items: ZoneClearReport['items'] = [];
  const equipmentNames: string[] = [];
  for (const entry of table?.resources ?? []) {
    if (!entry.resource || !rewardSucceeds(seed, zone, entry)) continue;
    const quantity = rollQuantity(seed, zone, entry, stringHash(entry.resource));
    if (quantity > 0) resources[entry.resource] = (resources[entry.resource] ?? 0) + quantity;
  }
  for (const entry of table?.items ?? []) {
    if (!entry.definition_id || !rewardSucceeds(seed, zone, entry)) continue;
    const quantity = rollQuantity(seed, zone, entry, stringHash(entry.definition_id));
    if (quantity > 0 && addItem(world, entry.definition_id, quantity)) {
      items.push({ definitionId: entry.definition_id, quantity });
    }
  }
  for (const entry of table?.equipment ?? []) {
    if (!entry.definition_id || !rewardSucceeds(seed, zone, entry)) continue;
    if (addEquipment(world, entry.definition_id)) {
      equipmentNames.push(getEquipmentDefinition(entry.definition_id)?.name ?? entry.definition_id);
    }
  }
  addResources(world, resources);

  const bonus = seedZoneBonusOffer(world);
  return {
    zoneKey: zone.key,
    zoneName: zone.generatedName,
    heroNames,
    experience,
    sanityLoss,
    resources,
    items,
    equipmentNames,
    bonusRecruit: bonus !== null,
  };
}

/** One tick of every clearing party. Returns a report for each party that finished. */
export function tickZones(world: World): ZoneClearReport[] {
  const reports: ZoneClearReport[] = [];
  let changed = false;
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'clearing') continue;
    changed = true;
    zone.ticksRemaining = Math.max(0, zone.ticksRemaining - 1);
    if (zone.ticksRemaining > 0) continue;
    const party = zone.assignedHeroUids;
    zone.state = 'cleared';
    zone.assignedHeroUids = [];
    zone.generatedName = ensureZoneName(zone, world.worldSeed);
    zone.claimCost = ensureClaimCost(zone, world.worldSeed);
    reports.push(resolveClearRewards(world, zone, party));
  }
  if (changed) applyVisibility(world);
  return reports;
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
