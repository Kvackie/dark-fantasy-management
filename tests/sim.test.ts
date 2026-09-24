import { describe, expect, it } from 'vitest';
import {
  allBuildings,
  allRecipes,
  getBuilding,
  getHeroDefinition,
  worldConfig,
} from '@/sim/config';
import { craftQuality, rollBonuses } from '@/sim/crafting';
import { createHero, effectiveStats, effectiveWorkStats, needsTriage } from '@/sim/heroes';
import { addEquipment, addItem, itemQuantity } from '@/sim/inventory';
import { slotProduction, yieldPreview } from '@/sim/production';
import { offerCapacity } from '@/sim/recruitment';
import {
  assignedHeroes,
  dismantleRefund,
  eligibleHeroes,
  settlementSlots,
  upgradeCost,
} from '@/sim/settlements';
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';
import type { Hero, World } from '@/sim/types';
import {
  determineBiome,
  generateClaimCost,
  generateZoneName,
  partyPreview,
  zoneDistance,
} from '@/sim/zones';

const HOME = 'hollow_march';

function rich(world: World): World {
  for (const id of Object.keys(world.resources) as Array<keyof World['resources']>) {
    world.resources[id] = 100_000;
  }
  return world;
}

function hireHero(sim: Simulation, definitionId = 'ash_smith'): Hero {
  const definition = getHeroDefinition(definitionId);
  if (!definition) throw new Error(`no hero ${definitionId}`);
  const hero = createHero(sim.world, definition);
  sim.world.heroes.push(hero);
  return hero;
}

describe('data', () => {
  it('loads every building, and the home settlement has eight plots', () => {
    expect(allBuildings().map((b) => b.id)).toEqual(
      expect.arrayContaining(['gathering_lodge', 'farm', 'quarry', 'smithy', 'tavern', 'triage']),
    );
    const world = createWorld(1, 1);
    expect(settlementSlots(world, HOME)).toHaveLength(8);
    expect(world.resources).toMatchObject({ wood: 200, food: 200, stone: 200, gold: 200 });
  });

  it('keeps recipe results as ranges', () => {
    const recipe = allRecipes()[0];
    expect(recipe).toBeDefined();
    const values = Object.values(recipe!.result.bonuses.stats);
    expect(values.some((value) => typeof value === 'object')).toBe(true);
  });
});

describe('settlement', () => {
  it('builds, produces each tick, upgrades on the growth curve and refunds 80%', () => {
    const sim = new Simulation(createWorld(7, 7));
    expect(sim.build(0, 'gathering_lodge')).toBe(true);
    expect(sim.world.resources.wood).toBe(170);
    expect(sim.world.resources.stone).toBe(190);
    expect(slotProduction(sim.world, HOME, 0)).toEqual({ gold: 3 });

    const gold = sim.world.resources.gold;
    sim.advanceBy(2000);
    expect(sim.world.tickCount).toBe(1);
    expect(sim.world.resources.gold).toBe(gold + 3);

    expect(upgradeCost(sim.world, HOME, 0)).toEqual({ wood: 20, stone: 10 });
    expect(sim.upgrade(0)).toBe(true);
    expect(upgradeCost(sim.world, HOME, 0)).toEqual({ wood: 27, stone: 14 });
    // Level 2: 1 + 1 × 1.35 = 2.35 × 3 gold ≈ 7.
    expect(slotProduction(sim.world, HOME, 0)).toEqual({ gold: 7 });

    // Build 30/10 + upgrade 20/10 = 50/20; 80% back.
    expect(dismantleRefund(sim.world, HOME, 0)).toEqual({ wood: 40, stone: 16 });
    expect(sim.dismantle(0)).toBe(true);
    expect(settlementSlots(sim.world, HOME)[0]?.buildingId).toBeNull();
  });

  it('refuses what it cannot afford and plots already built', () => {
    const sim = new Simulation(createWorld(3, 3));
    expect(sim.build(0, 'tavern')).toBe(true);
    expect(sim.build(0, 'farm')).toBe(false);
    sim.world.resources.wood = 0;
    expect(sim.build(1, 'farm')).toBe(false);
  });

  it('staffs plots by work stat, capacity and idleness, and staff raise output', () => {
    const sim = new Simulation(rich(createWorld(5, 5)));
    sim.build(0, 'quarry');
    const miner = hireHero(sim, 'ash_smith'); // mining 4
    const forager = hireHero(sim, 'grave_forager'); // mining 1
    const third = hireHero(sim, 'pit_delver');
    expect(eligibleHeroes(sim.world, HOME, 0).map((h) => h.uid)).toContain(miner.uid);

    const before = slotProduction(sim.world, HOME, 0).stone ?? 0;
    expect(sim.assignHero(miner.uid, 0)).toBe(true);
    expect(sim.assignHero(forager.uid, 0)).toBe(true);
    expect(sim.assignHero(third.uid, 0)).toBe(false); // two worker slots
    const work =
      effectiveWorkStats(sim.world, miner).mining + effectiveWorkStats(sim.world, forager).mining;
    expect(slotProduction(sim.world, HOME, 0).stone).toBe(Math.round(8 * (1 + work * 0.03)));
    expect(slotProduction(sim.world, HOME, 0).stone).toBeGreaterThan(before);

    sim.dismantle(0);
    expect(miner.assignment).toBeNull();
    expect(assignedHeroes(sim.world, HOME, 0)).toHaveLength(0);
  });

  it('trains heroes in the barracks and heals the hurt in the triage, for gold', () => {
    const sim = new Simulation(rich(createWorld(9, 9)));
    sim.build(0, 'barracks');
    sim.build(1, 'triage');
    const recruit = hireHero(sim);
    const patient = hireHero(sim, 'grave_forager');
    expect(sim.assignHero(recruit.uid, 0)).toBe(true);

    // Healthy heroes are not admitted.
    expect(sim.assignHero(patient.uid, 1)).toBe(false);
    patient.stats.current_health -= 5;
    expect(needsTriage(sim.world, patient)).toBe(true);
    expect(sim.assignHero(patient.uid, 1)).toBe(true);

    const gold = sim.world.resources.gold;
    sim.processTick();
    expect(recruit.experience).toBe(1);
    expect(patient.stats.current_health).toBe(patient.stats.max_health - 2);
    // Charged once per treatment, not twice.
    expect(sim.world.resources.gold).toBe(gold - 3);

    sim.processTick();
    expect(patient.stats.current_health).toBe(patient.stats.max_health);
    expect(patient.assignment).toBeNull();

    for (let i = 0; i < 20; i += 1) sim.processTick();
    expect(recruit.level).toBeGreaterThan(1);
  });
});

describe('recruitment', () => {
  it('opens with a tavern, sized by tavern count, without gem heroes before tavern level 3', () => {
    const sim = new Simulation(rich(createWorld(11, 11)));
    expect(sim.world.recruitOffers).toHaveLength(0);
    sim.build(0, 'tavern');
    expect(sim.world.recruitOffers).toHaveLength(3);
    sim.build(1, 'tavern');
    expect(offerCapacity(sim.world)).toBe(4);
    expect(sim.world.recruitOffers).toHaveLength(4);
    for (const offer of sim.world.recruitOffers) expect(offer.recruitCost.gems).toBeUndefined();

    const offer = sim.world.recruitOffers[0]!;
    const hero = sim.recruit(offer.offerId);
    expect(hero?.definitionId).toBe(offer.definitionId);
    expect(sim.world.heroes).toHaveLength(1);
    expect(sim.world.recruitOffers).toHaveLength(3);

    expect(sim.refreshRecruits()).toBe(true);
    expect(sim.world.recruitOffers).toHaveLength(4);
  });
});

describe('world map', () => {
  it('starts with the home zone claimed and the fog lifted two rings out', () => {
    const world = createWorld(42, 42);
    expect(world.zones['0,0']?.state).toBe('claimed');
    expect(world.zones['1,0']?.state).toBe('discovered');
    expect(world.zones['2,2']?.state).toBe('fog');
    expect(Object.keys(world.zones)).toHaveLength(25);
  });

  it('draws the same map from the same seed', () => {
    expect(determineBiome(99, 3, -2)).toBe(determineBiome(99, 3, -2));
    expect(generateZoneName(99, 3, -2)).toBe(generateZoneName(99, 3, -2));
    expect(generateClaimCost(99, 3, -2)).toEqual(generateClaimCost(99, 3, -2));
    const cost = generateClaimCost(99, 1, 0);
    expect(cost.wood).toBeGreaterThanOrEqual(35 + 10);
    expect(cost.wood).toBeLessThanOrEqual(35 + 10 + 6);
  });

  it('clears a zone with a party, rewards it, and claims it as a new settlement', () => {
    const sim = new Simulation(rich(createWorld(1234, 1234)));
    const hero = hireHero(sim);
    const key = '1,0';
    const zone = sim.world.zones[key]!;
    zone.biome = 'plains';
    zone.noSettlement = false;
    zone.claimedReward = null;
    expect(partyPreview(sim.world, key, [hero.uid]).meets).toBe(true);
    expect(sim.startClearing(key, [hero.uid])).toBe(true);
    expect(sim.world.zones[key]?.state).toBe('clearing');
    // Away heroes cannot be put to work.
    sim.build(0, 'lumber_camp');
    expect(sim.assignHero(hero.uid, 0)).toBe(false);

    const xp = hero.experience;
    sim.advanceBy(worldConfig.defaultClearDuration * 2000);
    expect(sim.world.zones[key]?.state).toBe('cleared');
    expect(hero.experience).toBe(xp + worldConfig.clearRewards.experienceBase);
    const [report] = sim.takeReports();
    expect(report?.heroNames).toEqual([hero.name]);
    expect(report?.bonusRecruit).toBe(true);
    // No tavern yet: the bonus hero waits.
    expect(sim.world.queuedBonusOffers).toHaveLength(1);
    // The fog lifts around the cleared zone.
    expect(sim.world.zones['3,0']?.state).toBe('fog');
    expect(sim.world.zones['2,0']?.state).toBe('discovered');

    expect(sim.claimZone(key)).toBe(true);
    const settlementId = sim.world.zones[key]!.settlementId;
    expect(settlementId).toBe('zone_p1_p0');
    expect(sim.world.ownedSettlementIds).toContain(settlementId);
    expect(settlementSlots(sim.world, settlementId)).toHaveLength(3);
    expect(sim.setActiveSettlement(settlementId)).toBe(true);
    expect(sim.build(0, 'farm')).toBe(true);
    expect(sim.build(1, 'tavern')).toBe(false); // plains allow only farms
  });

  it('asks more of a party the further out a zone lies', () => {
    const world = createWorld(5, 5);
    const near = world.zones['1,1']!;
    expect(zoneDistance(near.x, near.y)).toBe(1);
    expect(near.requirements.attack).toBe(0);
    // Four rings out is two past the safe radius.
    const far = { x: 4, y: 0 };
    const rings = zoneDistance(far.x, far.y) - worldConfig.clearRequirements.safeRadius;
    expect(rings).toBe(2);
  });

  it('pays a claimed crystal cavern on its interval', () => {
    const sim = new Simulation(createWorld(8, 8));
    const zone = sim.world.zones['1,1']!;
    zone.state = 'claimed';
    zone.claimedReward = { resource: 'gems', amount: 1, interval: 10 };
    expect(yieldPreview(sim.world).gems).toBeCloseTo(0.1);
    for (let i = 0; i < 10; i += 1) sim.processTick();
    expect(sim.world.resources.gems).toBe(1);
  });
});

describe('equipment and crafting', () => {
  it('adds gear bonuses to effective stats and moves a piece between heroes', () => {
    const sim = new Simulation(createWorld(2, 2));
    const a = hireHero(sim);
    const b = hireHero(sim, 'grave_forager');
    const piece = addEquipment(sim.world, 'amulet_1');
    expect(piece).not.toBeNull();
    const sanity = effectiveStats(sim.world, a).max_sanity;
    expect(sim.equip(a.uid, 'amulet', piece!.uid)).toBe(true);
    expect(effectiveStats(sim.world, a).max_sanity).toBe(sanity + 15);
    expect(effectiveWorkStats(sim.world, a).farming).toBe(a.workStats.farming + 3);
    expect(sim.equip(a.uid, 'head', piece!.uid)).toBe(false); // wrong slot

    expect(sim.equip(b.uid, 'amulet', piece!.uid)).toBe(true);
    expect(a.equipment.amulet).toBeNull();
    expect(piece!.equippedHeroUid).toBe(b.uid);

    expect(sim.dismissHero(b.uid)).toBe(true);
    expect(piece!.equippedHeroUid).toBeNull();
  });

  it('stacks items up to their stack size and ignores unknown ids', () => {
    const world = createWorld(1, 1);
    expect(addItem(world, 'iron', 5)).toBe(true);
    expect(addItem(world, 'iron', 7)).toBe(true);
    expect(world.items).toHaveLength(1);
    expect(itemQuantity(world, 'iron')).toBe(12);
    expect(addItem(world, 'rations', 3)).toBe(false);
  });

  it('rolls crafted stats inside the range, lower with more misses', () => {
    const world = createWorld(3, 3);
    const range = { stats: { defense: { min: 1, max: 30 } }, work_stats: {} };
    for (let i = 0; i < 50; i += 1) {
      const clean = rollBonuses(world, range, 0, 5).stats.defense!;
      const botched = rollBonuses(world, range, 5, 5).stats.defense!;
      expect(clean).toBeGreaterThanOrEqual(1);
      expect(clean).toBeLessThanOrEqual(30);
      expect(botched).toBe(1);
    }
    expect(craftQuality(2, 5)).toBeCloseTo(0.6);
  });

  it('needs a smithy of the recipe level, spends materials, and stores the piece', () => {
    const sim = new Simulation(rich(createWorld(4, 4)));
    sim.build(0, 'smithy');
    const piece = sim.craft('placeholder_ember_amulet', true, 0, 5);
    expect(piece?.definition?.slot).toBe('amulet');
    expect(piece?.definition?.bonuses.work_stats.mining).toBeGreaterThan(0);
    expect(sim.world.resources.gold).toBe(100_000 - 18 - 14);

    const wood = sim.world.resources.wood;
    expect(sim.craft('placeholder_ember_amulet', false, 5, 5)).toBeNull();
    expect(sim.world.resources.wood).toBe(wood - 8); // a failed craft still costs
    expect(getBuilding('smithy')?.workerSlots).toBe(0);
  });
});

describe('clock', () => {
  it('turns elapsed time into ticks and keeps the remainder', () => {
    const sim = new Simulation(createWorld(1, 1));
    expect(sim.advanceBy(4999)).toBe(2);
    expect(sim.world.tickProgressMs).toBe(999);
    expect(sim.msToNextTick).toBe(1001);
  });
});
