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
  /** Lifetime experience; see `experienceCeiling`. It is never spent. */
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
  /**
   * Sanity ran out. A broken hero can do nothing but sit in the Chapel until
   * their sanity is whole again.
   */
  broken: boolean;
  /**
   * Health ran out in a fight. A wounded hero can do nothing but lie in the
   * Triage until their health is whole again.
   */
  wounded: boolean;
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

/** One enemy holding a zone: a roster entry, scaled by how far out the zone is. */
export interface ZoneEnemy {
  id: string;
  /** Stat multiplier; 1 at the first ring. */
  power: number;
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
  /** What holds the zone. A party must beat them to clear it; they return whole after a defeat. */
  enemies: ZoneEnemy[];
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
  /** Newest last, capped — see `log.ts`. */
  log: LogEntry[];
  nextLogId: number;
  /** The tick the tavern slate last renewed itself on. */
  recruitRefreshTick: number;
  /** Real time the game was last saved, for catching up on the time away. 0 before the first save. */
  savedAt: number;
}

export type LogKind =
  | 'victory'
  | 'defeat'
  | 'broken'
  | 'restored'
  | 'wounded'
  | 'healed'
  | 'level'
  | 'recruit'
  | 'slate'
  | 'crafted'
  | 'craft_failed'
  | 'built'
  | 'upgraded'
  | 'dismantled'
  | 'claimed'
  | 'dismissed';

/**
 * A line in the event log.
 *
 * Stamped with the tick rather than a wall-clock time, because the simulation
 * has no wall clock; the log turns ticks back into "how long ago" when it draws.
 * Text is stored as an i18n key and its parameters, so it reads in whatever
 * language the page is in.
 */
export interface LogEntry {
  id: number;
  tick: number;
  kind: LogKind;
  key: string;
  params: Record<string, string | number>;
  /** Further lines, each a key and its parameters: a battle's blow-by-blow, a loot list. */
  details: Array<{ key: string; params: Record<string, string | number> }>;
}
