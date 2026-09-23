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
  SPECIAL_BUILDING_EFFECTS,
  allEquipment,
  allHeroes,
  allItems,
} from './config';
import { completeCraft } from './crafting';
import {
  createHero,
  effectiveStats,
  findHero,
  grantExperience,
} from './heroes';
import { addEquipment, addItem, equip, stripHero, unequip } from './inventory';
import { settlementProduction } from './production';
import {
  reconcileMarket,
  recruitFromOffer,
  refreshOffers,
  rollWeighted,
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
  unassignHero,
  upgrade,
} from './settlements';
import {
  TRACKED_RESOURCES,
  type EquipmentInstance,
  type EquipmentSlot,
  type Hero,
  type World,
  type ZoneClearReport,
} from './types';
import { claimZone, removeHeroFromZones, startClearing, tickClaimedRewards, tickZones } from './zones';

/**
 * How much missed time a returning tab may catch up on.
 *
 * A browser stops the frame loop in a background tab, so without catch-up a
 * settlement would sit frozen while the player is in another tab — unlike the
 * desktop build, which kept ticking when it lost focus. An hour covers that
 * without turning a reopened save into a week of instant production.
 */
export const MAX_CATCH_UP_MS = 60 * 60 * 1000;

export class Simulation {
  /** Bumped on every change, so observers can tell cheaply whether to redraw or save. */
  revision = 0;
  /** Parties home since the shell last looked, for the toast. */
  private reports: ZoneClearReport[] = [];

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

  processTick(): void {
    const world = this.world;
    world.tickCount += 1;
    /*
     * The Triage's gold is taken by `tickSpecialBuildings`, per patient actually
     * treated. The production preview shows it as a cost too, and the Godot build
     * charged it from both places — every patient cost double what the panel
     * said. It is left out of the production step here so it is charged once.
     */
    addResources(world, settlementProduction(world, false));
    tickClaimedRewards(world);
    this.tickSpecialBuildings();
    this.reports.push(...tickZones(world));
    this.revision += 1;
  }

  /** The Triage heals, the Barracks trains. */
  private tickSpecialBuildings(): void {
    const world = this.world;
    const { goldCostPerHero, healPerHero } = SPECIAL_BUILDING_EFFECTS.triage;
    const { experiencePerHero } = SPECIAL_BUILDING_EFFECTS.barracks;
    for (const settlementId of world.ownedSettlementIds) {
      settlementSlots(world, settlementId).forEach((slot, index) => {
        if (slot.buildingId === 'triage') {
          for (const hero of assignedHeroes(world, settlementId, index)) {
            const stats = effectiveStats(world, hero);
            if (stats.current_health >= stats.max_health) {
              hero.assignment = null;
              continue;
            }
            // No gold, no treatment — for this patient and everyone after them.
            if (goldCostPerHero <= 0 || world.resources.gold < goldCostPerHero) break;
            world.resources.gold -= goldCostPerHero;
            hero.stats.current_health = Math.min(
              hero.stats.current_health + healPerHero,
              stats.max_health,
            );
            if (stats.current_health + healPerHero >= stats.max_health) hero.assignment = null;
          }
        } else if (slot.buildingId === 'barracks' && experiencePerHero > 0) {
          for (const hero of assignedHeroes(world, settlementId, index)) {
            grantExperience(hero, experiencePerHero);
          }
        }
      });
    }
  }

  /** Reports of parties that came home, oldest first. Taking them empties the list. */
  takeReports(): ZoneClearReport[] {
    const out = this.reports;
    this.reports = [];
    return out;
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

  build(index: number, buildingId: string): boolean {
    return this.afterSettlementChange(
      build(this.world, this.world.activeSettlementId, index, buildingId),
    );
  }

  upgrade(index: number): boolean {
    return this.afterSettlementChange(upgrade(this.world, this.world.activeSettlementId, index));
  }

  dismantle(index: number): boolean {
    return this.afterSettlementChange(dismantle(this.world, this.world.activeSettlementId, index));
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
    return this.touch(recruitFromOffer(this.world, offerId));
  }

  /** Let a hero go for good: off their plot, out of their party, out of their gear. */
  dismissHero(uid: number): boolean {
    const hero = findHero(this.world, uid);
    if (!hero) return false;
    hero.assignment = null;
    stripHero(this.world, hero);
    removeHeroFromZones(this.world, uid);
    this.world.heroes = this.world.heroes.filter((entry) => entry.uid !== uid);
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
    for (const hero of this.world.heroes) grantExperience(hero, amount);
    this.touch(this.world.heroes.length > 0);
  }

  debugProgressTicks(count = 100): void {
    for (let i = 0; i < count; i += 1) this.processTick();
  }
}
