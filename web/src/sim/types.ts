/**
 * The shape of a game.
 *
 * Everything the player owns lives in one `World` object, which is exactly what
 * gets saved. Anything that can be worked out from it — which heroes stand in a
 * building, who is away clearing a zone, what a hero's stats come to with their
 * gear on — is derived rather than stored, so there is only ever one answer.
 */

export const TRACKED_RESOURCES = ['wood', 'food', 'stone', 'gold', 'gems', 'crystals'] as const;
export type ResourceId = (typeof TRACKED_RESOURCES)[number];

/** The HUD order. `heroes` is a count rather than a resource, but it rides in the same bar. */
export const RESOURCE_ORDER = [
  'wood',
  'food',
  'stone',
  'gold',
  'heroes',
  'gems',
  'crystals',
] as const;
export type DisplayResourceId = (typeof RESOURCE_ORDER)[number];

/** A bag of resource amounts: a cost, a refund, a yield. Keys outside the tracked set are allowed. */
export type ResourceMap = Record<string, number>;

export const STAT_KEYS = [
  'health',
  'sanity',
  'attack',
  'defense',
  'critical_chance',
  'critical_damage',
] as const;
export type StatKey = (typeof STAT_KEYS)[number];

export const WORK_STAT_KEYS = ['farming', 'mining', 'lumbering'] as const;
export type WorkStatKey = (typeof WORK_STAT_KEYS)[number];

export const EQUIPMENT_SLOTS = ['head', 'chest', 'gloves', 'boots', 'amulet', 'ring'] as const;
export type EquipmentSlot = (typeof EQUIPMENT_SLOTS)[number];

export type BaseStats = Record<StatKey, number>;
export type WorkStats = Record<WorkStatKey, number>;

/** A hero's stored combat stats: the base block plus the two pools that go up and down. */
export interface HeroStats extends BaseStats {
  max_health: number;
  current_health: number;
  max_sanity: number;
  current_sanity: number;
}

export interface HeroAssignment {
  settlementId: string;
  slot: number;
}

export interface Hero {
  uid: number;
  definitionId: string;
  name: string;
  heroClass: string;
  level: number;
  /** Lifetime experience. A level costs `level × 10` of it, and it is never spent. */
  experience: number;
  /** Rolled once when the hero joins, so a ranged growth stays that hero's for good. */
  statGrowth: BaseStats;
  workStatGrowth: WorkStats;
  stats: HeroStats;
  workStats: WorkStats;
  /** Equipment instance uid per slot, or null for an empty slot. */
  equipment: Record<EquipmentSlot, number | null>;
  /** The building plot this hero works, if any. */
  assignment: HeroAssignment | null;
}

export interface BuildingSlot {
  buildingId: string | null;
  level: number;
}

export interface SettlementState {
  slots: BuildingSlot[];
}

export interface SettlementDefinition {
  id: string;
  name: string;
  biome: string;
  plotCount: number;
  /** Building ids that may be raised here, or `['ALL']`. */
  allowedBuildings: string[];
  /** Made when a zone was claimed, rather than read from `data/settlements.json`. */
  generated: boolean;
}

export const ZONE_STATES = ['fog', 'discovered', 'clearing', 'cleared', 'claimed'] as const;
export type ZoneState = (typeof ZONE_STATES)[number];

export interface ZoneRequirements {
  level: number;
  sanity: number;
  attack: number;
  defense: number;
  farming: number;
  mining: number;
  lumbering: number;
}

export interface ClaimedReward {
  resource: string;
  amount: number;
  /** Paid every `interval` ticks. */
  interval: number;
}

export interface Zone {
  key: string;
  x: number;
  y: number;
  state: ZoneState;
  /** Ticks left on a clearing party's work. Zero unless clearing. */
  ticksRemaining: number;
  clearDuration: number;
  /** The party out clearing this zone. Empty unless clearing. */
  assignedHeroUids: number[];
  generatedName: string;
  biome: string;
  requirements: ZoneRequirements;
  sanityLoss: number;
  noSettlement: boolean;
  claimedReward: ClaimedReward | null;
  claimCost: ResourceMap;
  settlementId: string;
  settlementName: string;
}

export interface ItemStack {
  definitionId: string;
  quantity: number;
}

/** A bonus value: a flat amount, or — on a recipe's result, before rolling — a range. */
export type BonusValue = number | { min: number; max: number };

export interface EquipmentBonuses<V = number> {
  stats: Partial<Record<StatKey, V>>;
  work_stats: Partial<Record<WorkStatKey, V>>;
}

export interface EquipmentDefinition {
  id: string;
  name: string;
  slot: EquipmentSlot;
  bonuses: EquipmentBonuses;
}

export interface EquipmentInstance {
  uid: number;
  definitionId: string;
  /**
   * A definition carried by the instance itself.
   *
   * Crafted gear rolls its own numbers, so there is no catalogue entry to look
   * it up in — the rolled definition travels with the piece.
   */
  definition: EquipmentDefinition | null;
  equippedHeroUid: number | null;
  equippedSlot: EquipmentSlot | null;
}

export interface RecruitOffer {
  offerId: number;
  definitionId: string;
  name: string;
  heroClass: string;
  level: number;
  /** Rolled when the offer was drawn, so a ranged cost does not change under the player. */
  recruitCost: ResourceMap;
  stats: BaseStats;
  workStats: WorkStats;
  /** `zone_bonus` for the extra hero a cleared zone sends to the tavern. */
  source: 'market' | 'zone_bonus';
}

export interface World {
  schemaVersion: 1;
  resources: Record<ResourceId, number>;
  settlements: Record<string, SettlementState>;
  generatedSettlements: Record<string, SettlementDefinition>;
  ownedSettlementIds: string[];
  activeSettlementId: string;
  heroes: Hero[];
  items: ItemStack[];
  equipment: EquipmentInstance[];
  recruitOffers: RecruitOffer[];
  /** Bonus recruits a cleared zone sent before any tavern stood to receive them. */
  queuedBonusOffers: RecruitOffer[];
  recruitMarketInitialized: boolean;
  /** Fixes zone biomes, names, claim costs and reward rolls for the whole map. */
  worldSeed: number;
  zones: Record<string, Zone>;
  tickCount: number;
  /** Real milliseconds banked toward the next tick. */
  tickProgressMs: number;
  nextHeroUid: number;
  nextEquipmentUid: number;
  nextOfferId: number;
  /** State of the seeded generator every other roll comes from — see `rng.ts`. */
  rng: number;
}

/** What a finished clearing party brought home, for the toast. */
export interface ZoneClearReport {
  zoneKey: string;
  zoneName: string;
  heroNames: string[];
  experience: number;
  sanityLoss: number;
  resources: ResourceMap;
  items: ItemStack[];
  equipmentNames: string[];
  bonusRecruit: boolean;
}
