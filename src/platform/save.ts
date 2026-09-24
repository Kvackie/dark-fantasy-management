/**
 * Save slots.
 *
 * As in the Godot build: every new game takes the next free slot, the game
 * autosaves into its own slot, slots can be named, loaded and deleted, and the
 * last one played is what Continue opens. A small manifest beside the saves
 * keeps the names and which slot was played last.
 *
 * A save is loaded through `normalizeWorld`, which fills anything missing from
 * a fresh world and drops anything that no longer makes sense, so a save from
 * an older build — or one hand-edited — opens rather than failing.
 */

import {
  getBuilding,
  getEnemy,
  getEquipmentDefinition,
  getHeroDefinition,
  getItemDefinition,
} from '@/sim/config';
import { reconcileMarket } from '@/sim/recruitment';
import { settlementSlots } from '@/sim/settlements';
import { createWorld } from '@/sim/state';
import {
  EQUIPMENT_SLOTS,
  STAT_KEYS,
  TRACKED_RESOURCES,
  WORK_STAT_KEYS,
  ZONE_STATES,
  type BaseStats,
  type EquipmentInstance,
  type EquipmentSlot,
  type LogEntry,
  type LogKind,
  type Hero,
  type RecruitOffer,
  type ResourceMap,
  type SettlementDefinition,
  type World,
  type WorkStats,
  type Zone,
} from '@/sim/types';
import {
  applyVisibility,
  generatedSettlementDefinition,
  initializeZones,
  generateEnemies,
  zoneSanityLoss,
} from '@/sim/zones';
import type { KeyValueStore } from './storage';

const PREFIX = 'dark-fantasy-settlement';
const MANIFEST_KEY = `${PREFIX}.manifest`;
const slotKey = (slot: number) => `${PREFIX}.slot.${slot}`;

interface Manifest {
  slots: Record<string, { name?: string; savedAt?: number }>;
  lastPlayedSlot: number;
  lastPlayedAt: number;
}

export interface SlotSummary {
  slot: number;
  name: string;
  /** A player-given name, as opposed to the "Slot 3" default. */
  customName: boolean;
  savedAt: number;
  lastPlayed: boolean;
  lastPlayedAt: number;
  tickCount: number;
  heroCount: number;
  settlementCount: number;
}

export class SaveManager {
  constructor(private store: KeyValueStore) {}

  private manifest(): Manifest {
    const fallback: Manifest = { slots: {}, lastPlayedSlot: 0, lastPlayedAt: 0 };
    const raw = this.store.get(MANIFEST_KEY);
    if (!raw) return fallback;
    try {
      const parsed = JSON.parse(raw) as Partial<Manifest>;
      return {
        slots: typeof parsed.slots === 'object' && parsed.slots ? parsed.slots : {},
        lastPlayedSlot: Number(parsed.lastPlayedSlot) || 0,
        lastPlayedAt: Number(parsed.lastPlayedAt) || 0,
      };
    } catch {
      return fallback;
    }
  }

  private writeManifest(manifest: Manifest): void {
    this.store.set(MANIFEST_KEY, JSON.stringify(manifest));
  }

  exists(slot: number): boolean {
    return slot > 0 && this.store.get(slotKey(slot)) !== null;
  }

  /** Slot numbers with a save in them, in order. */
  slots(): number[] {
    const manifest = this.manifest();
    const known = new Set<number>(Object.keys(manifest.slots).map(Number));
    if (manifest.lastPlayedSlot > 0) known.add(manifest.lastPlayedSlot);
    return [...known].filter((slot) => this.exists(slot)).sort((a, b) => a - b);
  }

  nextNewSlot(): number {
    const manifest = this.manifest();
    const highest = Math.max(
      0,
      manifest.lastPlayedSlot,
      ...Object.keys(manifest.slots).map(Number),
    );
    return highest + 1;
  }

  lastPlayedSlot(): number {
    const slot = this.manifest().lastPlayedSlot;
    return this.exists(slot) ? slot : 0;
  }

  save(slot: number, world: World): boolean {
    if (slot < 1) return false;
    if (!this.store.set(slotKey(slot), JSON.stringify(world))) return false;
    const manifest = this.manifest();
    const now = Date.now();
    manifest.slots[String(slot)] = { ...manifest.slots[String(slot)], savedAt: now };
    manifest.lastPlayedSlot = slot;
    manifest.lastPlayedAt = now;
    this.writeManifest(manifest);
    return true;
  }

  load(slot: number): World | null {
    const raw = this.store.get(slotKey(slot));
    if (!raw) return null;
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return null;
    }
    const world = normalizeWorld(parsed);
    if (!world) return null;
    const manifest = this.manifest();
    manifest.lastPlayedSlot = slot;
    manifest.lastPlayedAt = Date.now();
    this.writeManifest(manifest);
    return world;
  }

  delete(slot: number): void {
    this.store.remove(slotKey(slot));
    const manifest = this.manifest();
    delete manifest.slots[String(slot)];
    if (manifest.lastPlayedSlot === slot) manifest.lastPlayedSlot = 0;
    this.writeManifest(manifest);
  }

  rename(slot: number, name: string): void {
    const manifest = this.manifest();
    const entry = { ...manifest.slots[String(slot)] };
    const trimmed = name.trim();
    if (trimmed) entry.name = trimmed;
    else delete entry.name;
    manifest.slots[String(slot)] = entry;
    this.writeManifest(manifest);
  }

  summary(slot: number): SlotSummary {
    const manifest = this.manifest();
    const meta = manifest.slots[String(slot)] ?? {};
    const summary: SlotSummary = {
      slot,
      name: meta.name ?? '',
      customName: Boolean(meta.name),
      savedAt: meta.savedAt ?? 0,
      lastPlayed: manifest.lastPlayedSlot === slot,
      lastPlayedAt: manifest.lastPlayedSlot === slot ? manifest.lastPlayedAt : 0,
      tickCount: 0,
      heroCount: 0,
      settlementCount: 0,
    };
    const raw = this.store.get(slotKey(slot));
    if (!raw) return summary;
    try {
      const parsed = JSON.parse(raw) as Partial<World>;
      summary.tickCount = Number(parsed.tickCount) || 0;
      summary.heroCount = Array.isArray(parsed.heroes) ? parsed.heroes.length : 0;
      summary.settlementCount = Array.isArray(parsed.ownedSettlementIds)
        ? parsed.ownedSettlementIds.length
        : 0;
    } catch {
      // A summary of an unreadable save is its slot number and nothing else.
    }
    return summary;
  }
}

// -- normalising a loaded world -----------------------------------------------

type Json = Record<string, unknown>;

function record(value: unknown): Json {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Json)
    : {};
}

function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function num(value: unknown, fallback = 0): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function text(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function numberMap(value: unknown): ResourceMap {
  const out: ResourceMap = {};
  for (const [key, amount] of Object.entries(record(value))) out[key] = num(amount);
  return out;
}

function statBlock<K extends string>(value: unknown, keys: readonly K[]): Record<K, number> {
  const source = record(value);
  return Object.fromEntries(keys.map((key) => [key, num(source[key])])) as Record<K, number>;
}

function isSlot(value: unknown): value is EquipmentSlot {
  return typeof value === 'string' && (EQUIPMENT_SLOTS as readonly string[]).includes(value);
}

function normalizeHero(value: unknown): Hero | null {
  const source = record(value);
  const uid = num(source.uid);
  if (uid <= 0) return null;
  const definition = getHeroDefinition(text(source.definitionId));
  const stats = record(source.stats);
  const base = statBlock(stats, STAT_KEYS) as BaseStats;
  const level = Math.max(1, num(source.level, 1));
  const equipmentSource = record(source.equipment);
  const assignment = record(source.assignment);
  return {
    uid,
    definitionId: text(source.definitionId),
    name: text(source.name) || definition?.name || 'Unknown Hero',
    heroClass: text(source.heroClass) || definition?.heroClass || 'Supporter',
    level,
    experience: Math.max(num(source.experience), (level - 1) * 10),
    statGrowth: statBlock(source.statGrowth, STAT_KEYS),
    workStatGrowth: statBlock(source.workStatGrowth, WORK_STAT_KEYS),
    stats: {
      ...base,
      max_health: num(stats.max_health, base.health),
      // Not capped at the stored maximum: gear raises the cap the Triage heals up to.
      current_health: Math.max(0, num(stats.current_health, base.health)),
      max_sanity: num(stats.max_sanity, base.sanity),
      current_sanity: Math.min(
        num(stats.current_sanity, base.sanity),
        num(stats.max_sanity, base.sanity),
      ),
    },
    workStats: statBlock(source.workStats, WORK_STAT_KEYS) as WorkStats,
    equipment: Object.fromEntries(
      EQUIPMENT_SLOTS.map((slot) => {
        const uidValue = equipmentSource[slot];
        return [slot, typeof uidValue === 'number' && uidValue > 0 ? uidValue : null];
      }),
    ) as Hero['equipment'],
    assignment:
      typeof assignment.settlementId === 'string' && num(assignment.slot, -1) >= 0
        ? { settlementId: assignment.settlementId, slot: num(assignment.slot) }
        : null,
    broken: source.broken === true,
    wounded: source.wounded === true,
  };
}

function normalizeEquipment(value: unknown): EquipmentInstance | null {
  const source = record(value);
  const uid = num(source.uid);
  const embedded = record(source.definition);
  const definition =
    isSlot(embedded.slot) && typeof embedded.name === 'string'
      ? {
          id: text(embedded.id, text(source.definitionId)),
          name: embedded.name,
          slot: embedded.slot,
          bonuses: {
            stats: statBlock(record(embedded.bonuses).stats, STAT_KEYS),
            work_stats: statBlock(record(embedded.bonuses).work_stats, WORK_STAT_KEYS),
          },
        }
      : null;
  const definitionId = text(source.definitionId);
  if (uid <= 0 || (!definition && !getEquipmentDefinition(definitionId))) return null;
  const heroUid = num(source.equippedHeroUid, 0);
  return {
    uid,
    definitionId,
    definition,
    equippedHeroUid: heroUid > 0 ? heroUid : null,
    equippedSlot: heroUid > 0 && isSlot(source.equippedSlot) ? source.equippedSlot : null,
  };
}

function normalizeOffer(value: unknown): RecruitOffer | null {
  const source = record(value);
  const definition = getHeroDefinition(text(source.definitionId));
  if (!definition) return null;
  return {
    offerId: Math.max(1, num(source.offerId, 1)),
    definitionId: definition.id,
    name: text(source.name) || definition.name,
    heroClass: text(source.heroClass) || definition.heroClass,
    level: Math.max(1, num(source.level, 1)),
    recruitCost: numberMap(source.recruitCost),
    stats: { ...definition.stats, ...statBlock(source.stats, STAT_KEYS) },
    workStats: { ...definition.workStats, ...statBlock(source.workStats, WORK_STAT_KEYS) },
    source: source.source === 'zone_bonus' ? 'zone_bonus' : 'market',
  };
}

function normalizeZone(value: unknown, fallback: Zone | undefined): Zone | null {
  const source = record(value);
  const x = num(source.x);
  const y = num(source.y);
  const state = (ZONE_STATES as readonly string[]).includes(text(source.state))
    ? (source.state as Zone['state'])
    : 'fog';
  const reward = record(source.claimedReward);
  return {
    key: `${x},${y}`,
    x,
    y,
    state,
    ticksRemaining: Math.max(0, num(source.ticksRemaining)),
    clearDuration: Math.max(0, num(source.clearDuration, fallback?.clearDuration ?? 3)),
    assignedHeroUids: list(source.assignedHeroUids)
      .map((uid) => num(uid))
      .filter((uid) => uid > 0),
    generatedName: text(source.generatedName),
    biome: text(source.biome) || fallback?.biome || 'neutral',
    enemies: list(source.enemies).flatMap((value) => {
      const enemy = record(value);
      return typeof enemy.id === 'string' && getEnemy(enemy.id)
        ? [{ id: enemy.id, power: Math.max(0.1, Number(enemy.power) || 1) }]
        : [];
    }),
    sanityLoss: Math.max(0, num(source.sanityLoss, fallback?.sanityLoss ?? 0)),
    noSettlement: source.noSettlement === true,
    claimedReward:
      typeof reward.resource === 'string'
        ? {
            resource: reward.resource,
            amount: num(reward.amount),
            interval: Math.max(1, num(reward.interval, 1)),
          }
        : null,
    claimCost: numberMap(source.claimCost),
    settlementId: text(source.settlementId),
    settlementName: text(source.settlementName),
  };
}

/** Turn whatever was in a save into a world the game can run, or null if it is not a save at all. */
export function normalizeWorld(value: unknown): World | null {
  const source = record(value);
  if (source.schemaVersion !== 1) return null;

  const seed = num(source.worldSeed) >>> 0;
  const world = createWorld(seed, num(source.rng, 1));

  const resources = record(source.resources);
  for (const id of TRACKED_RESOURCES) world.resources[id] = Math.max(0, num(resources[id]));

  for (const [id, definitionValue] of Object.entries(record(source.generatedSettlements))) {
    const definition = record(definitionValue);
    if (typeof definition.name !== 'string') continue;
    world.generatedSettlements[id] = {
      id,
      name: definition.name,
      biome: text(definition.biome, 'neutral'),
      plotCount: Math.max(1, num(definition.plotCount, 3)),
      allowedBuildings: list(definition.allowedBuildings).map(String),
      generated: true,
    } satisfies SettlementDefinition;
  }

  const zoneSource = record(source.zones);
  if (Object.keys(zoneSource).length > 0) {
    world.zones = {};
    for (const zoneValue of Object.values(zoneSource)) {
      const zone = normalizeZone(zoneValue, undefined);
      if (!zone) continue;
      // A save from before zones had defenders gets them now.
      if (zone.enemies.length === 0 && zone.key !== '0,0' && zone.state !== 'claimed') {
        zone.enemies = generateEnemies(seed, zone.x, zone.y, zone.biome);
        zone.sanityLoss = zoneSanityLoss(zone.x, zone.y, zone.enemies);
      }
      world.zones[zone.key] = zone;
    }
    if (!world.zones['0,0']) initializeZones(world);
  }

  // Every claimed zone that founded a settlement should have a definition for it.
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'claimed' || zone.noSettlement) continue;
    const definition = generatedSettlementDefinition(zone);
    if (definition && !world.generatedSettlements[definition.id] && zone.key !== '0,0') {
      world.generatedSettlements[definition.id] = definition;
    }
  }

  const owned = list(source.ownedSettlementIds)
    .map((id) => text(id))
    .filter((id, index, all) => id && all.indexOf(id) === index);
  if (owned.length > 0) world.ownedSettlementIds = owned;

  for (const [id, stateValue] of Object.entries(record(source.settlements))) {
    const slots = list(record(stateValue).slots).map((slotValue) => {
      const slot = record(slotValue);
      const buildingId =
        typeof slot.buildingId === 'string' && slot.buildingId ? slot.buildingId : null;
      return { buildingId, level: buildingId ? Math.max(1, num(slot.level, 1)) : 0 };
    });
    world.settlements[id] = { slots };
  }
  for (const id of world.ownedSettlementIds) settlementSlots(world, id);

  const active = text(source.activeSettlementId);
  if (world.ownedSettlementIds.includes(active)) world.activeSettlementId = active;

  world.heroes = list(source.heroes)
    .map(normalizeHero)
    .filter((hero): hero is Hero => hero !== null);
  world.items = list(source.items).flatMap((stackValue) => {
    const stack = record(stackValue);
    const id = text(stack.definitionId);
    const quantity = num(stack.quantity);
    return getItemDefinition(id) && quantity > 0 ? [{ definitionId: id, quantity }] : [];
  });
  world.equipment = list(source.equipment)
    .map(normalizeEquipment)
    .filter((piece): piece is EquipmentInstance => piece !== null);
  world.recruitOffers = list(source.recruitOffers)
    .map(normalizeOffer)
    .filter((offer): offer is RecruitOffer => offer !== null);
  world.queuedBonusOffers = list(source.queuedBonusOffers)
    .map(normalizeOffer)
    .filter((offer): offer is RecruitOffer => offer !== null);
  world.recruitMarketInitialized =
    source.recruitMarketInitialized === true || world.recruitOffers.length > 0;

  world.tickCount = Math.max(0, num(source.tickCount));
  world.tickProgressMs = Math.max(0, Number(source.tickProgressMs) || 0);
  world.rng = num(source.rng, world.rng) | 0;
  world.savedAt = Math.max(0, Number(source.savedAt) || 0);
  world.recruitRefreshTick = Math.min(world.tickCount, Math.max(0, num(source.recruitRefreshTick)));
  world.log = list(source.log).flatMap((value): LogEntry[] => {
    const entry = record(value);
    if (typeof entry.key !== 'string' || typeof entry.kind !== 'string') return [];
    return [
      {
        id: num(entry.id),
        tick: num(entry.tick),
        kind: entry.kind as LogKind,
        key: entry.key,
        params: record(entry.params) as LogEntry['params'],
        details: list(entry.details).flatMap((d) => {
          const detail = record(d);
          return typeof detail.key === 'string'
            ? [{ key: detail.key, params: record(detail.params) as LogEntry['params'] }]
            : [];
        }),
      },
    ];
  });
  world.nextLogId = Math.max(num(source.nextLogId, 1), ...world.log.map((e) => e.id + 1), 1);

  repairLinks(world);

  world.nextHeroUid = Math.max(
    num(source.nextHeroUid, 1),
    ...world.heroes.map((h) => h.uid + 1),
    1,
  );
  world.nextEquipmentUid = Math.max(
    num(source.nextEquipmentUid, 1),
    ...world.equipment.map((e) => e.uid + 1),
    1,
  );
  world.nextOfferId = Math.max(
    num(source.nextOfferId, 1),
    ...[...world.recruitOffers, ...world.queuedBonusOffers].map((o) => o.offerId + 1),
    1,
  );

  applyVisibility(world);
  reconcileMarket(world, true);
  return world;
}

/**
 * Make every cross-reference agree.
 *
 * Gear worn by a hero who is gone goes back in the stores; a hero on a plot that
 * no longer has a building (or that is overstaffed) is sent home; a clearing
 * party loses members who no longer exist, and a party left empty abandons its
 * zone.
 */
function repairLinks(world: World): void {
  const heroUids = new Set(world.heroes.map((hero) => hero.uid));

  for (const piece of world.equipment) {
    if (piece.equippedHeroUid !== null && !heroUids.has(piece.equippedHeroUid)) {
      piece.equippedHeroUid = null;
      piece.equippedSlot = null;
    }
  }
  for (const hero of world.heroes) {
    for (const slot of EQUIPMENT_SLOTS) {
      const uid = hero.equipment[slot];
      if (uid === null) continue;
      const piece = world.equipment.find((entry) => entry.uid === uid);
      if (!piece || piece.equippedHeroUid !== hero.uid || piece.equippedSlot !== slot) {
        hero.equipment[slot] = null;
      }
    }
  }
  for (const piece of world.equipment) {
    if (piece.equippedHeroUid === null || piece.equippedSlot === null) continue;
    const hero = world.heroes.find((entry) => entry.uid === piece.equippedHeroUid);
    if (!hero || hero.equipment[piece.equippedSlot] !== piece.uid) {
      piece.equippedHeroUid = null;
      piece.equippedSlot = null;
    }
  }

  const staffing = new Map<string, number>();
  for (const hero of world.heroes) {
    const assignment = hero.assignment;
    if (!assignment) continue;
    const slots = world.ownedSettlementIds.includes(assignment.settlementId)
      ? settlementSlots(world, assignment.settlementId)
      : [];
    const slot = slots[assignment.slot];
    if (!slot?.buildingId) {
      hero.assignment = null;
      continue;
    }
    const key = `${assignment.settlementId}#${assignment.slot}`;
    const count = (staffing.get(key) ?? 0) + 1;
    if (count > (getBuilding(slot.buildingId)?.workerSlots ?? 0)) {
      hero.assignment = null;
      continue;
    }
    staffing.set(key, count);
  }

  const onTask = new Set<number>();
  for (const zone of Object.values(world.zones)) {
    if (zone.state !== 'clearing') {
      zone.assignedHeroUids = [];
      zone.ticksRemaining = 0;
      continue;
    }
    zone.assignedHeroUids = zone.assignedHeroUids.filter(
      (uid) => heroUids.has(uid) && !onTask.has(uid),
    );
    zone.assignedHeroUids.forEach((uid) => onTask.add(uid));
    if (zone.assignedHeroUids.length === 0) {
      zone.state = 'discovered';
      zone.ticksRemaining = 0;
    } else {
      zone.clearDuration = Math.max(1, zone.clearDuration);
      zone.ticksRemaining = Math.max(1, zone.ticksRemaining);
    }
  }
  // A hero cannot be on a plot and in a party at once; the party wins.
  for (const hero of world.heroes) if (onTask.has(hero.uid)) hero.assignment = null;
}
