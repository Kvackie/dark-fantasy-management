/**
 * Game content, read from the repository's `data/` folder and normalised once.
 *
 * The JSON is shared with the Godot build, so it is taken as it is written there
 * and tidied here: missing fields get the same defaults the Godot loader gave
 * them, ranges written as `"8-14"` become `{ min, max }`, and entries that name
 * no id are dropped.
 */

import buildingsJson from '@data/buildings.json';
import settlementsJson from '@data/settlements.json';
import worldJson from '@data/world.json';
import recruitmentJson from '@data/recruitment.json';
import heroesJson from '@data/heroes.json';
import itemsJson from '@data/items.json';
import equipmentJson from '@data/equipment.json';
import recipesJson from '@data/crafting_recipes.json';
import {
  EQUIPMENT_SLOTS,
  STAT_KEYS,
  WORK_STAT_KEYS,
  type BaseStats,
  type BonusValue,
  type EquipmentBonuses,
  type EquipmentDefinition,
  type EquipmentSlot,
  type ResourceMap,
  type SettlementDefinition,
  type StatKey,
  type WorkStatKey,
  type WorkStats,
} from './types';

// -- rules that live in code in the original, not in data ---------------------

export const TICK_MS = 2000;
export const AUTOSAVE_INTERVAL_MS = 12_000;
export const DEFAULT_PLOT_COUNT = 8;
export const DEFAULT_MAX_BUILDING_LEVEL = 5;

export const STARTING_RESOURCES = {
  wood: 200,
  food: 200,
  stone: 200,
  gold: 200,
  gems: 0,
  crystals: 0,
} as const;

export const DEFAULT_HERO_STATS: BaseStats = {
  health: 100,
  sanity: 100,
  attack: 10,
  defense: 10,
  critical_chance: 5,
  critical_damage: 150,
};

export const DEFAULT_HERO_STAT_GROWTH: BaseStats = {
  health: 3,
  sanity: 2,
  attack: 1,
  defense: 1,
  critical_chance: 1,
  critical_damage: 1,
};

export const DEFAULT_HERO_WORK_STATS: WorkStats = { farming: 0, mining: 0, lumbering: 0 };
export const DEFAULT_HERO_WORK_STAT_GROWTH: WorkStats = { farming: 1, mining: 1, lumbering: 1 };

export const HERO_CLASSES = ['Attacker', 'Defender', 'Supporter'] as const;

export const SPECIAL_BUILDING_EFFECTS = {
  triage: { goldCostPerHero: 3, healPerHero: 3 },
  barracks: { experiencePerHero: 1 },
} as const;

/** Which work stat speeds up which resource. */
export const RESOURCE_WORK_STAT: Record<string, WorkStatKey> = {
  food: 'farming',
  wood: 'lumbering',
  stone: 'mining',
  crystals: 'mining',
};
export const WORK_STAT_PRODUCTION_BONUS_PER_POINT = 0.03;
export const GATHERING_LODGE_GOLD_BONUS_PER_HERO = 0.1;

/** Experience needed to leave a level: ten per level, cumulative. */
export function experienceCeiling(level: number): number {
  return Math.max(1, level) * 10;
}

// -- helpers ------------------------------------------------------------------

type Json = Record<string, unknown>;

function asRecord(value: unknown): Json {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Json)
    : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function int(value: unknown, fallback = 0): number {
  const n = typeof value === 'string' ? Number.parseInt(value, 10) : Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value.trim() : fallback;
}

/** Ids are lower-case words joined by underscores, as the Godot loader made them. */
function sanitizeId(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/** A range written as `{ min, max }`, `{ min_amount, max_amount }` or `"8-14"`, or a flat number. */
export type Amount = number | { min: number; max: number };

function readAmount(value: unknown, fallback: number): Amount {
  if (typeof value === 'string') {
    const match = /^\s*(-?\d+)\s*-\s*(-?\d+)\s*$/.exec(value);
    if (match) return orderedRange(int(match[1]), int(match[2]));
    return int(value, fallback);
  }
  if (value !== null && typeof value === 'object') {
    const range = value as Json;
    const min = int(range.min ?? range.min_amount, fallback);
    const max = int(range.max ?? range.max_amount, min);
    return orderedRange(min, max);
  }
  return value === undefined ? fallback : int(value, fallback);
}

function orderedRange(a: number, b: number): { min: number; max: number } {
  return a <= b ? { min: a, max: b } : { min: b, max: a };
}

// -- resources ----------------------------------------------------------------

export interface CostEntry {
  resource: string;
  amount: number;
}

function readCostList(value: unknown): CostEntry[] {
  const out: CostEntry[] = [];
  for (const entry of asArray(value)) {
    const record = asRecord(entry);
    const resource = str(record.resource);
    if (!resource) continue;
    out.push({ resource, amount: int(record.amount) });
  }
  return out;
}

export function costListToMap(entries: CostEntry[]): ResourceMap {
  const map: ResourceMap = {};
  for (const entry of entries) map[entry.resource] = entry.amount;
  return map;
}

// -- buildings ----------------------------------------------------------------

export interface BuildingDefinition {
  id: string;
  name: string;
  description: string;
  buildCost: CostEntry[];
  upgradeCost: CostEntry[];
  upgradeGrowth: number;
  baseProduction: CostEntry[];
  workerSlots: number;
  assignmentRequirements: Partial<Record<WorkStatKey, number>>;
  maxLevel: number;
}

const buildings: BuildingDefinition[] = asArray(asRecord(buildingsJson).buildings).flatMap(
  (entry) => {
    const record = asRecord(entry);
    const id = sanitizeId(str(record.id));
    const name = str(record.name);
    if (!id || !name) return [];
    const requirements: Partial<Record<WorkStatKey, number>> = {};
    for (const [key, value] of Object.entries(asRecord(record.assignment_requirements))) {
      if ((WORK_STAT_KEYS as readonly string[]).includes(key)) {
        requirements[key as WorkStatKey] = Math.max(0, int(value));
      }
    }
    return [
      {
        id,
        name,
        description: str(record.description),
        buildCost: readCostList(record.build_cost),
        upgradeCost: readCostList(record.upgrade_cost),
        upgradeGrowth: Number(record.upgrade_growth ?? 1) || 1,
        baseProduction: readCostList(record.base_production),
        workerSlots: Math.max(0, int(record.worker_slots)),
        assignmentRequirements: requirements,
        maxLevel: Math.max(1, int(record.max_level, 1)),
      },
    ];
  },
);

const buildingById = new Map(buildings.map((b) => [b.id, b]));

export function allBuildings(): readonly BuildingDefinition[] {
  return buildings;
}

export function getBuilding(id: string | null): BuildingDefinition | null {
  return id ? (buildingById.get(id) ?? null) : null;
}

// -- settlements --------------------------------------------------------------

function readAllowedBuildings(value: unknown): string[] {
  if (!Array.isArray(value)) return ['ALL'];
  const out: string[] = [];
  for (const entry of value) {
    const key = str(entry);
    if (!key) continue;
    if (key.toUpperCase() === 'ALL') return ['ALL'];
    out.push(key);
  }
  return out.length ? out : ['ALL'];
}

const settlements: SettlementDefinition[] = asArray(asRecord(settlementsJson).settlements).flatMap(
  (entry) => {
    const record = asRecord(entry);
    const id = sanitizeId(str(record.id));
    const name = str(record.name);
    if (!id || !name) return [];
    return [
      {
        id,
        name,
        biome: str(record.biome, 'neutral').toLowerCase() || 'neutral',
        plotCount: Math.max(1, int(record.plot_count, DEFAULT_PLOT_COUNT)),
        allowedBuildings: readAllowedBuildings(record.allowed_buildings),
        generated: false,
      },
    ];
  },
);

const settlementById = new Map(settlements.map((s) => [s.id, s]));

export function getCoreSettlement(id: string): SettlementDefinition | null {
  return settlementById.get(id) ?? null;
}

export function defaultSettlementId(): string {
  return settlements[0]?.id ?? '';
}

// -- world --------------------------------------------------------------------

export interface RewardEntry {
  resource?: string;
  definition_id?: string;
  chance?: number;
  min?: number;
  max?: number;
  amount?: number;
}

export interface RewardTable {
  min_distance: number;
  max_distance: number;
  resources: RewardEntry[];
  items: RewardEntry[];
  equipment: RewardEntry[];
}

export interface SpecialBiome {
  spawn_chance: number;
  no_settlement: boolean;
  claimed_reward?: { resource: string; amount: number; interval: number };
  clear_duration?: number;
}

export interface ZoneOverride {
  state?: string;
  name?: string;
  biome?: string;
  no_settlement?: boolean;
  claimed_reward?: { resource: string; amount: number; interval: number };
  clear_duration?: number;
  sanity_loss?: number;
  claim_cost?: ResourceMap;
  settlement_id?: string;
  settlement_name?: string;
  requirements?: Record<string, number>;
}

export interface WorldConfig {
  revealRadius: number;
  revealFromClaimed: boolean;
  revealFromCleared: boolean;
  defaultClearDuration: number;
  maxClearingParty: number;
  clearRequirements: {
    safeRadius: number;
    attackBase: number;
    attackGrowth: number;
    defenseBase: number;
    defenseGrowth: number;
    sanityLossBase: number;
    sanityLossGrowth: number;
  };
  clearRewards: { experienceBase: number; experienceGrowth: number; tables: RewardTable[] };
  zoneSize: number;
  zoneGap: number;
  zoneColors: Record<string, string>;
  claimCost: { base: ResourceMap; distanceStep: ResourceMap; variance: ResourceMap };
  names: { prefixes: string[]; suffixes: string[]; articles: string[] };
  specialBiomes: Record<string, SpecialBiome>;
  overrides: Record<string, ZoneOverride>;
}

function numberMap(value: unknown): ResourceMap {
  const out: ResourceMap = {};
  for (const [key, amount] of Object.entries(asRecord(value))) out[key] = int(amount);
  return out;
}

function readRewardEntries(value: unknown): RewardEntry[] {
  return asArray(value).map((entry) => {
    const record = asRecord(entry);
    const out: RewardEntry = {};
    if (typeof record.resource === 'string') out.resource = record.resource.trim();
    if (typeof record.definition_id === 'string') out.definition_id = record.definition_id.trim();
    if (record.chance !== undefined) out.chance = int(record.chance, 100);
    if (record.min !== undefined) out.min = int(record.min);
    if (record.max !== undefined) out.max = int(record.max);
    if (record.amount !== undefined) out.amount = int(record.amount);
    return out;
  });
}

function readClaimedReward(value: unknown): SpecialBiome['claimed_reward'] | undefined {
  const record = asRecord(value);
  const resource = str(record.resource);
  if (!resource) return undefined;
  return {
    resource,
    amount: int(record.amount),
    interval: Math.max(1, int(record.interval, 1)),
  };
}

const worldRecord = asRecord(asRecord(worldJson).config);
const requirementRecord = asRecord(worldRecord.clear_requirements);
const rewardRecord = asRecord(worldRecord.clear_rewards);
const claimRecord = asRecord(worldRecord.claim_cost);
const nameRecord = asRecord(worldRecord.name_generation);

export const worldConfig: WorldConfig = {
  revealRadius: Math.max(1, int(worldRecord.reveal_radius, 2)),
  revealFromClaimed: worldRecord.reveal_from_claimed !== false,
  revealFromCleared: worldRecord.reveal_from_cleared !== false,
  defaultClearDuration: Math.max(1, int(worldRecord.default_clear_duration, 3)),
  maxClearingParty: Math.max(1, int(worldRecord.max_clearing_party, 3)),
  clearRequirements: {
    safeRadius: Math.max(0, int(requirementRecord.safe_radius, 2)),
    attackBase: int(requirementRecord.attack_base, 0),
    attackGrowth: int(requirementRecord.attack_growth, 3),
    defenseBase: int(requirementRecord.defense_base, 0),
    defenseGrowth: int(requirementRecord.defense_growth, 2),
    sanityLossBase: int(requirementRecord.sanity_loss_base, 0),
    sanityLossGrowth: int(requirementRecord.sanity_loss_growth, 1),
  },
  clearRewards: {
    experienceBase: int(rewardRecord.experience_base, 2),
    experienceGrowth: int(rewardRecord.experience_growth, 1),
    tables: asArray(rewardRecord.tables).map((entry) => {
      const table = asRecord(entry);
      return {
        min_distance: int(table.min_distance, 0),
        max_distance: int(table.max_distance, 999_999),
        resources: readRewardEntries(table.resources),
        items: readRewardEntries(table.items),
        equipment: readRewardEntries(table.equipment),
      };
    }),
  },
  zoneSize: int(worldRecord.zone_size, 104),
  zoneGap: int(worldRecord.zone_gap, 10),
  zoneColors: Object.fromEntries(
    Object.entries(asRecord(worldRecord.zone_colors)).map(([k, v]) => [k, str(v)]),
  ),
  claimCost: {
    base: numberMap(claimRecord.base),
    distanceStep: numberMap(claimRecord.distance_step),
    variance: numberMap(claimRecord.variance),
  },
  names: {
    prefixes: asArray(nameRecord.prefixes).map((v) => String(v)),
    suffixes: asArray(nameRecord.suffixes).map((v) => String(v)),
    articles: asArray(nameRecord.articles).map((v) => String(v)),
  },
  specialBiomes: Object.fromEntries(
    Object.entries(asRecord(worldRecord.special_biomes)).map(([id, value]) => {
      const record = asRecord(value);
      const biome: SpecialBiome = {
        spawn_chance: Math.max(0, int(record.spawn_chance)),
        no_settlement: record.no_settlement === true,
      };
      const reward = readClaimedReward(record.claimed_reward);
      if (reward) biome.claimed_reward = reward;
      if (record.clear_duration !== undefined) biome.clear_duration = int(record.clear_duration);
      return [id.trim().toLowerCase(), biome];
    }),
  ),
  overrides: Object.fromEntries(
    Object.entries(asRecord(worldRecord.overrides)).map(([key, value]) => {
      const record = asRecord(value);
      const override: ZoneOverride = {};
      if (typeof record.state === 'string') override.state = record.state.trim();
      if (typeof record.name === 'string') override.name = record.name.trim();
      if (typeof record.biome === 'string') override.biome = record.biome.trim().toLowerCase();
      if (typeof record.no_settlement === 'boolean') override.no_settlement = record.no_settlement;
      const reward = readClaimedReward(record.claimed_reward);
      if (reward) override.claimed_reward = reward;
      if (record.clear_duration !== undefined) override.clear_duration = int(record.clear_duration);
      if (record.sanity_loss !== undefined) override.sanity_loss = int(record.sanity_loss);
      if (record.claim_cost !== undefined) override.claim_cost = numberMap(record.claim_cost);
      if (typeof record.settlement_id === 'string') override.settlement_id = record.settlement_id;
      if (typeof record.settlement_name === 'string') {
        override.settlement_name = record.settlement_name.trim();
      }
      if (record.requirements !== undefined) override.requirements = numberMap(record.requirements);
      return [key, override];
    }),
  ),
};

// -- recruitment --------------------------------------------------------------

const recruitmentRecord = asRecord(asRecord(recruitmentJson).config);

export const recruitmentConfig = {
  baseOfferCount: Math.max(1, int(recruitmentRecord.base_offer_count, 3)),
  extraOfferPerTavern: Math.max(0, int(recruitmentRecord.extra_offer_per_tavern, 1)),
  refreshCost: costListToMap(readCostList(recruitmentRecord.refresh_cost)),
};

// -- heroes -------------------------------------------------------------------

export interface RecruitCostEntry {
  resource: string;
  amount: Amount;
  perLevel: number;
}

export interface HeroDefinition {
  id: string;
  name: string;
  heroClass: string;
  description: string;
  level: number;
  recruitmentWeight: number;
  recruitCost: RecruitCostEntry[];
  stats: BaseStats;
  statGrowth: Record<StatKey, Amount>;
  workStats: WorkStats;
  workStatGrowth: Record<WorkStatKey, Amount>;
}

export function normalizeHeroClass(value: string): string {
  const lower = value.trim().toLowerCase();
  const match = HERO_CLASSES.find((c) => c.toLowerCase() === lower);
  return match ?? 'Supporter';
}

function readStatBlock<K extends string>(
  value: unknown,
  defaults: Record<K, number>,
): Record<K, number> {
  const record = asRecord(value);
  const out = { ...defaults };
  for (const key of Object.keys(defaults) as K[]) {
    if (record[key] !== undefined) out[key] = int(record[key], defaults[key]);
  }
  return out;
}

function readGrowthBlock<K extends string>(
  value: unknown,
  defaults: Record<K, number>,
): Record<K, Amount> {
  const record = asRecord(value);
  const out = {} as Record<K, Amount>;
  for (const key of Object.keys(defaults) as K[]) out[key] = readAmount(record[key], defaults[key]);
  return out;
}

const heroes: HeroDefinition[] = asArray(asRecord(heroesJson).heroes).flatMap((entry) => {
  const record = asRecord(entry);
  const id = sanitizeId(str(record.id));
  const name = str(record.name);
  if (!id || !name) return [];
  return [
    {
      id,
      name,
      heroClass: normalizeHeroClass(str(record.class)),
      description: str(record.description),
      level: Math.max(1, int(record.level, 1)),
      recruitmentWeight: Math.max(1, int(record.recruitment_weight, 1)),
      recruitCost: asArray(record.recruit_cost).flatMap((costValue) => {
        const cost = asRecord(costValue);
        const resource = str(cost.resource);
        if (!resource) return [];
        const hasRange = cost.min_amount !== undefined || cost.max_amount !== undefined;
        return [
          {
            resource,
            amount: hasRange ? readAmount(cost, 0) : readAmount(cost.amount, 0),
            perLevel: int(cost.per_level),
          },
        ];
      }),
      stats: readStatBlock(record.stats, DEFAULT_HERO_STATS),
      statGrowth: readGrowthBlock(record.stat_growth, DEFAULT_HERO_STAT_GROWTH),
      workStats: readStatBlock(record.work_stats, DEFAULT_HERO_WORK_STATS),
      workStatGrowth: readGrowthBlock(record.work_stat_growth, DEFAULT_HERO_WORK_STAT_GROWTH),
    },
  ];
});

const heroById = new Map(heroes.map((h) => [h.id, h]));

export function allHeroes(): readonly HeroDefinition[] {
  return heroes;
}

export function getHeroDefinition(id: string): HeroDefinition | null {
  return heroById.get(id) ?? null;
}

// -- items --------------------------------------------------------------------

export const DEFAULT_ITEM_MAX_STACK = 100_000;

export interface ItemDefinition {
  id: string;
  name: string;
  maxStack: number;
}

const items: ItemDefinition[] = asArray(asRecord(itemsJson).items).flatMap((entry) => {
  const record = asRecord(entry);
  const id = sanitizeId(str(record.id));
  const name = str(record.name);
  if (!id || !name) return [];
  return [{ id, name, maxStack: Math.max(1, int(record.max_stack, DEFAULT_ITEM_MAX_STACK)) }];
});

const itemById = new Map(items.map((i) => [i.id, i]));

export function allItems(): readonly ItemDefinition[] {
  return items;
}

export function getItemDefinition(id: string): ItemDefinition | null {
  return itemById.get(id) ?? null;
}

// -- equipment ----------------------------------------------------------------

function readBonusBlock<K extends string>(
  value: unknown,
  keys: readonly K[],
  keepRanges: boolean,
): Partial<Record<K, BonusValue>> {
  const record = asRecord(value);
  const out: Partial<Record<K, BonusValue>> = {};
  for (const key of keys) {
    const raw = record[key];
    if (raw === undefined) continue;
    if (keepRanges && raw !== null && typeof raw === 'object') {
      const range = asRecord(raw);
      const min = int(range.min);
      out[key] = { min, max: int(range.max, min) };
      continue;
    }
    const amount = int(raw);
    if (amount !== 0) out[key] = amount;
  }
  return out;
}

function readBonuses(value: unknown, keepRanges: boolean): EquipmentBonuses<BonusValue> {
  const record = asRecord(value);
  let stats = asRecord(record.stats);
  let work = asRecord(record.work_stats);
  // An old flat bonus block names stats and work stats side by side.
  if (Object.keys(stats).length === 0 && Object.keys(work).length === 0) {
    stats = record;
    work = record;
  }
  return {
    stats: readBonusBlock(stats, STAT_KEYS, keepRanges),
    work_stats: readBonusBlock(work, WORK_STAT_KEYS, keepRanges),
  };
}

function readSlot(value: unknown): EquipmentSlot | null {
  const slot = str(value).toLowerCase();
  return (EQUIPMENT_SLOTS as readonly string[]).includes(slot) ? (slot as EquipmentSlot) : null;
}

const equipment: EquipmentDefinition[] = asArray(asRecord(equipmentJson).equipment).flatMap(
  (entry) => {
    const record = asRecord(entry);
    const id = sanitizeId(str(record.id));
    const name = str(record.name);
    const slot = readSlot(record.slot);
    if (!id || !name || !slot) return [];
    return [{ id, name, slot, bonuses: readBonuses(record.bonuses, false) as EquipmentBonuses }];
  },
);

const equipmentById = new Map(equipment.map((e) => [e.id, e]));

export function allEquipment(): readonly EquipmentDefinition[] {
  return equipment;
}

export function getEquipmentDefinition(id: string): EquipmentDefinition | null {
  return equipmentById.get(id) ?? null;
}

// -- crafting -----------------------------------------------------------------

export interface RecipeCostEntry {
  kind: 'resource' | 'item';
  id: string;
  amount: number;
}

export interface Recipe {
  id: string;
  name: string;
  description: string;
  /** The smithy level that makes this recipe available. */
  level: number;
  cost: RecipeCostEntry[];
  result: {
    id: string;
    name: string;
    slot: EquipmentSlot;
    bonuses: EquipmentBonuses<BonusValue>;
  };
}

const recipes: Recipe[] = asArray(asRecord(recipesJson).recipes).flatMap((entry) => {
  const record = asRecord(entry);
  const id = sanitizeId(str(record.id));
  const name = str(record.name);
  const result = asRecord(record.result_equipment);
  const slot = readSlot(result.slot);
  const resultName = str(result.name);
  if (!id || !name || !slot || !resultName) return [];
  const cost: RecipeCostEntry[] = asArray(record.cost).flatMap((costValue): RecipeCostEntry[] => {
    const costRecord = asRecord(costValue);
    const amount = int(costRecord.amount);
    const resource = str(costRecord.resource);
    if (resource) return [{ kind: 'resource' as const, id: resource, amount }];
    const item = str(costRecord.item);
    if (item) return [{ kind: 'item' as const, id: item, amount }];
    return [];
  });
  return [
    {
      id,
      name,
      description: str(record.description),
      level: Math.max(1, int(record.level, 1)),
      cost,
      result: {
        id: sanitizeId(str(result.id)) || id,
        name: resultName,
        slot,
        bonuses: readBonuses(result.bonuses, true),
      },
    },
  ];
});

const recipeById = new Map(recipes.map((r) => [r.id, r]));

export function allRecipes(): readonly Recipe[] {
  return recipes;
}

export function getRecipe(id: string): Recipe | null {
  return recipeById.get(id) ?? null;
}
