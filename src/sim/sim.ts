/**
 * The simulation: one world, the clock that drives it, and every action the
 * player can take on it.
 *
 * Headless — no Phaser, no DOM, no wall clock. The frame loop hands it elapsed
 * milliseconds and it turns them into two-second ticks; the panels call its
 * methods and redraw. Every method that changes the world bumps `revision`,
 * which is how the rest of the game knows to save and redraw.
 */

import {
  TICK_MS,
  allEquipment,
  allHeroes,
  allItems,
  buildingEffect,
  getBuilding,
  getRecipe,
} from './config';
import { completeCraft } from './crafting';
import { createHero, effectiveStats, findHero, grantExperience, updateCondition } from './heroes';
import {
  addEquipment,
  addItem,
  equip,
  equipmentDefinitionOf,
  stripHero,
  unequip,
} from './inventory';
import { addLog } from './log';
import { settlementProduction } from './production';
import {
  autoRefreshOffers,
  reconcileMarket,
  recruitFromOffer,
  refreshOffers,
  rollWeighted,
  ticksToFreeRefresh,
} from './recruitment';
import { addResources } from './resources';
import { randomInt } from './rng';
import {
  assignHero,
  assignedHeroes,
  build,
  dismantle,
  settlementDefinition,
  settlementSlots,
  slotAt,
  unassignHero,
  upgrade,
} from './settlements';
import { effectTotal } from './skills';
import {
  TRACKED_RESOURCES,
  type EquipmentInstance,
  type EquipmentSlot,
  type Hero,
  type ResourceMap,
  type World,
} from './types';
import {
  claimZone,
  removeHeroFromZones,
  startClearing,
  tickClaimedRewards,
  tickZones,
} from './zones';

/**
 * The most time a single catch-up will run.
 *
 * A closed tab or a reopened save is caught up on the time it missed, as if
 * the settlement had carried on without the player. Eight hours covers a night
 * away; past that the settlement simply waits, which keeps a save opened after
 * a month from being a month of instant production — and keeps the catch-up
 * itself quick.
 */
export const MAX_CATCH_UP_MS = 8 * 60 * 60 * 1000;

/** What happened while the player was away, for the welcome-back dialog. */
export interface AwaySummary {
  awayMs: number;
  /** How much of that was simulated; less than `awayMs` past the cap. */
  simulatedMs: number;
  ticks: number;
  resources: ResourceMap;
  /** Log entries written while away. */
  events: number;
}

export class Simulation {
  /** Bumped on every change, so observers can tell cheaply whether to redraw or save. */
  revision = 0;

  constructor(public world: World) {
    reconcileMarket(this.world, true);
  }

  private touch<T>(result: T): T {
    if (result) this.revision += 1;
    return result;
  }

  // -- time -------------------------------------------------------------------

  /** Advance by real elapsed time, running every tick it pays for. */
  advanceBy(ms: number): number {
    if (ms <= 0) return 0;
    this.world.tickProgressMs += Math.min(ms, MAX_CATCH_UP_MS);
    let ticks = 0;
    while (this.world.tickProgressMs >= TICK_MS) {
      this.world.tickProgressMs -= TICK_MS;
      this.processTick();
      ticks += 1;
    }
    return ticks;
  }

  /** Run the time since the game was last saved, and say what it came to. */
  catchUp(now: number): AwaySummary {
    const awayMs = this.world.savedAt > 0 ? Math.max(0, now - this.world.savedAt) : 0;
    const simulatedMs = Math.min(awayMs, MAX_CATCH_UP_MS);
    const before = { ...this.world.resources };
    const firstLog = this.world.nextLogId;
    const ticks = this.advanceBy(simulatedMs);
    const resources: ResourceMap = {};
    for (const id of TRACKED_RESOURCES) {
      const delta = this.world.resources[id] - before[id];
      if (delta !== 0) resources[id] = delta;
    }
    return { awayMs, simulatedMs, ticks, resources, events: this.world.nextLogId - firstLog };
  }

  /** Milliseconds until the next tick lands. */
  get msToNextTick(): number {
    return Math.max(0, TICK_MS - this.world.tickProgressMs);
  }

  /** Seconds left on a clearing party, counting the part-tick already run. */
  clearingSecondsLeft(zoneKey: string): number {
    const zone = this.world.zones[zoneKey];
    if (!zone || zone.state !== 'clearing') return 0;
    return (Math.max(0, zone.ticksRemaining - 1) * TICK_MS + this.msToNextTick) / 1000;
  }

  /** Seconds until the tavern slate renews itself. */
  secondsToFreeRefresh(): number {
    const ticks = ticksToFreeRefresh(this.world);
    return (Math.max(0, ticks - 1) * TICK_MS + this.msToNextTick) / 1000;
  }

  processTick(): void {
    const world = this.world;
    world.tickCount += 1;
    // The Triage's gold is taken per patient actually treated, in `tickSpecialBuildings`.
    addResources(world, settlementProduction(world, false));
    tickClaimedRewards(world);
    this.tickSpecialBuildings();
    tickZones(world);
    autoRefreshOffers(world);
    this.revision += 1;
  }

  /** Log a hero's recovery or collapse, if their condition just changed. */
  private checkCondition(hero: Hero): void {
    for (const change of updateCondition(this.world, hero)) {
      addLog(this.world, change, `log.${change}`, { name: hero.name });
    }
  }

  /**
   * The Triage heals health for gold, the Chapel restores sanity for nothing but
   * time, and the Barracks trains. A patient leaves on their own once whole.
   */
  private tickSpecialBuildings(): void {
    const world = this.world;
    for (const settlementId of world.ownedSettlementIds) {
      settlementSlots(world, settlementId).forEach((slot, index) => {
        const building = getBuilding(slot.buildingId);
        if (!building) return;
        const staff = assignedHeroes(world, settlementId, index);
        if (building.id === 'triage') {
          const heal = buildingEffect(
            building,
            'heal_health_per_hero',
            'heal_per_level',
            slot.level,
          );
          const cost = buildingEffect(building, 'gold_per_hero', '', slot.level);
          for (const hero of staff) {
            const stats = effectiveStats(world, hero);
            if (stats.current_health >= stats.max_health) {
              hero.assignment = null;
              this.checkCondition(hero);
              continue;
            }
            // No gold, no treatment — for this patient and everyone after them.
            if (cost > 0 && world.resources.gold < cost) break;
            world.resources.gold -= cost;
            const amount = Math.round(heal * (1 + effectTotal(hero, 'recovery_pct') / 100));
            hero.stats.current_health = Math.min(stats.current_health + amount, stats.max_health);
            if (hero.stats.current_health >= stats.max_health) hero.assignment = null;
            this.checkCondition(hero);
          }
        } else if (building.id === 'chapel') {
          const restore = buildingEffect(
            building,
            'restore_sanity_per_hero',
            'restore_per_level',
            slot.level,
          );
          for (const hero of staff) {
            const stats = effectiveStats(world, hero);
            const amount = Math.round(restore * (1 + effectTotal(hero, 'recovery_pct') / 100));
            hero.stats.current_sanity = Math.min(stats.current_sanity + amount, stats.max_sanity);
            if (hero.stats.current_sanity >= stats.max_sanity) hero.assignment = null;
            this.checkCondition(hero);
          }
        } else if (building.id === 'barracks') {
          const xp = buildingEffect(
            building,
            'experience_per_hero',
            'experience_per_level',
            slot.level,
          );
          if (xp <= 0) return;
          for (const hero of staff) {
            if (grantExperience(hero, xp) > 0) {
              addLog(world, 'level', 'log.level', { name: hero.name, level: hero.level });
            }
          }
        }
      });
    }
  }

  // -- settlements ------------------------------------------------------------

  setActiveSettlement(id: string): boolean {
    if (!this.world.ownedSettlementIds.includes(id) || !settlementDefinition(this.world, id)) {
      return false;
    }
    if (this.world.activeSettlementId === id) return true;
    this.world.activeSettlementId = id;
    return this.touch(true);
  }

  private buildingName(index: number): string {
    return (
      getBuilding(slotAt(this.world, this.world.activeSettlementId, index)?.buildingId ?? null)
        ?.name ?? ''
    );
  }

  build(index: number, buildingId: string): boolean {
    const ok = build(this.world, this.world.activeSettlementId, index, buildingId);
    if (ok) this.logSettlement('built', 'log.built', index);
    return this.afterSettlementChange(ok);
  }

  upgrade(index: number): boolean {
    const ok = upgrade(this.world, this.world.activeSettlementId, index);
    if (ok) this.logSettlement('upgraded', 'log.upgraded', index);
    return this.afterSettlementChange(ok);
  }

  dismantle(index: number): boolean {
    const name = this.buildingName(index);
    const ok = dismantle(this.world, this.world.activeSettlementId, index);
    if (ok) {
      addLog(this.world, 'dismantled', 'log.dismantled', {
        building: name,
        settlement: settlementDefinition(this.world, this.world.activeSettlementId)?.name ?? '',
      });
    }
    return this.afterSettlementChange(ok);
  }

  private logSettlement(kind: 'built' | 'upgraded', key: string, index: number): void {
    addLog(this.world, kind, key, {
      building: this.buildingName(index),
      level: slotAt(this.world, this.world.activeSettlementId, index)?.level ?? 1,
      settlement: settlementDefinition(this.world, this.world.activeSettlementId)?.name ?? '',
    });
  }

  /** A new or lost tavern changes the recruit market, so it is squared up after any building change. */
  private afterSettlementChange(ok: boolean): boolean {
    if (ok) reconcileMarket(this.world, true);
    return this.touch(ok);
  }

  assignHero(uid: number, index: number): boolean {
    const hero = findHero(this.world, uid);
    if (!hero) return false;
    return this.touch(assignHero(this.world, hero, this.world.activeSettlementId, index));
  }

  unassignHero(uid: number): boolean {
    const hero = findHero(this.world, uid);
    return this.touch(hero ? unassignHero(hero) : false);
  }

  // -- recruitment ------------------------------------------------------------

  refreshRecruits(): boolean {
    return this.touch(refreshOffers(this.world));
  }

  recruit(offerId: number): Hero | null {
    const hero = recruitFromOffer(this.world, offerId);
    if (hero)
      addLog(this.world, 'recruit', 'log.recruit', { name: hero.name, heroClass: hero.heroClass });
    return this.touch(hero);
  }

  /** Let a hero go for good: off their plot, out of their party, out of their gear. */
  dismissHero(uid: number): boolean {
    const hero = findHero(this.world, uid);
    if (!hero) return false;
    hero.assignment = null;
    stripHero(this.world, hero);
    removeHeroFromZones(this.world, uid);
    this.world.heroes = this.world.heroes.filter((entry) => entry.uid !== uid);
    addLog(this.world, 'dismissed', 'log.dismissed', { name: hero.name });
    return this.touch(true);
  }

  // -- equipment --------------------------------------------------------------

  equip(uid: number, slot: EquipmentSlot, equipmentUid: number): boolean {
    const hero = findHero(this.world, uid);
    return this.touch(hero ? equip(this.world, hero, slot, equipmentUid) : false);
  }

  unequip(uid: number, slot: EquipmentSlot): boolean {
    const hero = findHero(this.world, uid);
    return this.touch(hero ? unequip(this.world, hero, slot) : false);
  }

  craft(
    recipeId: string,
    success: boolean,
    failures: number,
    maxFailures: number,
  ): EquipmentInstance | null {
    const piece = completeCraft(this.world, recipeId, success, failures, maxFailures);
    const recipe = getRecipe(recipeId);
    if (piece) {
      addLog(this.world, 'crafted', 'log.crafted', {
        name: equipmentDefinitionOf(piece)?.name ?? recipe?.name ?? recipeId,
      });
    } else if (recipe) {
      addLog(this.world, 'craft_failed', 'log.craft_failed', { name: recipe.name });
    }
    // A failed craft still spent its materials, which is a change worth saving.
    this.revision += 1;
    return piece;
  }

  // -- world ------------------------------------------------------------------

  startClearing(zoneKey: string, uids: readonly number[]): boolean {
    return this.touch(startClearing(this.world, zoneKey, uids));
  }

  claimZone(zoneKey: string): boolean {
    return this.afterSettlementChange(claimZone(this.world, zoneKey));
  }

  // -- debug ------------------------------------------------------------------

  debugGrantResources(): void {
    const delta = Object.fromEntries(TRACKED_RESOURCES.map((id) => [id, 100_000]));
    addResources(this.world, delta);
    this.touch(true);
  }

  debugRecruitRandomHero(): Hero | null {
    const definition = rollWeighted(this.world, allHeroes());
    if (!definition) return null;
    const hero = createHero(this.world, definition);
    this.world.heroes.push(hero);
    return this.touch(hero);
  }

  debugGrantRandomItems(draws = 100): void {
    const pool = allItems();
    for (let i = 0; i < draws && pool.length > 0; i += 1) {
      const item = pool[randomInt(this.world, 0, pool.length - 1)];
      if (item) addItem(this.world, item.id, 1);
    }
    this.touch(true);
  }

  debugGrantRandomEquipment(draws = 10): void {
    const pool = allEquipment();
    for (let i = 0; i < draws && pool.length > 0; i += 1) {
      const piece = pool[randomInt(this.world, 0, pool.length - 1)];
      if (piece) addEquipment(this.world, piece.id);
    }
    this.touch(true);
  }

  debugGrantHeroExperience(amount = 100): void {
    for (const hero of this.world.heroes) {
      if (grantExperience(hero, amount) > 0) {
        addLog(this.world, 'level', 'log.level', { name: hero.name, level: hero.level });
      }
    }
    this.touch(this.world.heroes.length > 0);
  }

  debugProgressTicks(count = 100): void {
    for (let i = 0; i < count; i += 1) this.processTick();
  }
}
