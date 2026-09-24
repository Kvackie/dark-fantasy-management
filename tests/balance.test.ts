/**
 * The balance harness.
 *
 * Not a correctness suite: a set of measurements that fail when a number
 * drifts outside a range decided to be sane. The simulation is headless and
 * seeded, so rather than guess at balance these play it — thousands of battles,
 * hours of ticks — and read the results. When one fails, look at the number and
 * decide; do not just widen the range.
 */

import { describe, expect, it } from 'vitest';
import {
  allRecipes,
  experienceForLevel,
  getHeroDefinition,
  getItemDefinition,
  worldConfig,
} from '@/sim/config';
import { battle, enemyFighter, heroFighter, localRandom } from '@/sim/combat';
import { createHero, grantExperience } from '@/sim/heroes';
import { canAfford } from '@/sim/resources';
import { buildCost, settlementSlots } from '@/sim/settlements';
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';
import type { Hero, World } from '@/sim/types';
import { generateEnemies, rewardTable } from '@/sim/zones';
import { getBuilding, getEnemy } from '@/sim/config';

const BIOMES = ['forest', 'mountain', 'plains', 'mixed', 'neutral'];
const PARTY = ['ash_smith', 'briar_ranger', 'grave_forager'];

function party(world: World, size: number, level: number): Hero[] {
  return PARTY.slice(0, size).map((id) => {
    const hero = createHero(world, getHeroDefinition(id)!, 1);
    grantExperience(hero, experienceForLevel(level));
    return hero;
  });
}

/** Win rate of an ungeared party against many zones of one ring. */
function winRate(ring: number, level: number, size: number): number {
  const world = createWorld(1, 1);
  const heroes = party(world, size, level);
  const random = localRandom(ring * 131 + level * 7 + size);
  let wins = 0;
  let total = 0;
  for (let seed = 0; seed < 60; seed += 1) {
    const enemies = generateEnemies(
      seed * 7919,
      ring,
      (seed % (2 * ring + 1)) - ring,
      BIOMES[seed % 5]!,
    )
      .map(enemyFighter)
      .filter((f) => f !== null);
    for (let trial = 0; trial < 5; trial += 1) {
      const fighters = heroes.map((hero) => heroFighter(world, hero, heroes));
      if (battle(random, fighters, enemies).victory) wins += 1;
      total += 1;
    }
  }
  return wins / total;
}

describe('combat difficulty', () => {
  it('lets a lone first hero take the nearest zones, but not for free', () => {
    expect(winRate(1, 1, 1)).toBeGreaterThanOrEqual(0.85);
  });

  it('makes a lone hero gamble three rings out', () => {
    const rate = winRate(3, 2, 1);
    expect(rate).toBeGreaterThan(0.4);
    expect(rate).toBeLessThan(0.97);
  });

  it('keeps a levelled party of three comfortable through the middle rings', () => {
    expect(winRate(5, 6, 3)).toBeGreaterThanOrEqual(0.8);
  });

  it('walls off the far rings to heroes without gear', () => {
    expect(winRate(12, 18, 3)).toBeLessThan(0.6);
  });

  it('never gets easier further out at the same level', () => {
    const rates = [2, 4, 6, 8, 10, 12].map((ring) => winRate(ring, 8, 3));
    for (let i = 1; i < rates.length; i += 1)
      expect(rates[i]!).toBeLessThanOrEqual(rates[i - 1]! + 0.05);
  });
});

describe('attrition', () => {
  it('lets a hero clear a handful of near zones before breaking, but not endlessly', () => {
    const world = createWorld(2, 2);
    const hero = party(world, 1, 1)[0]!;
    const zones = [1, 2, 3].flatMap((ring) =>
      [...Array(10).keys()].map((i) => world.zones[`${ring},${i % 3}`] ?? null),
    );
    const sanityPerClear =
      zones.filter((zone) => zone !== null).reduce((sum, zone) => sum + zone!.sanityLoss, 0) /
      zones.filter((zone) => zone !== null).length;
    const clears = hero.stats.max_sanity / sanityPerClear;
    expect(clears).toBeGreaterThanOrEqual(4);
    expect(clears).toBeLessThanOrEqual(30);
  });

  it('restores a broken hero in the Chapel within a few minutes', () => {
    const sim = new Simulation(createWorld(3, 3));
    for (const id of Object.keys(sim.world.resources) as Array<keyof World['resources']>) {
      sim.world.resources[id] = 10_000;
    }
    sim.build(0, 'chapel');
    const hero = party(sim.world, 1, 1)[0]!;
    sim.world.heroes.push(hero);
    hero.stats.current_sanity = 0;
    hero.broken = true;
    sim.assignHero(hero.uid, 0);
    let ticks = 0;
    while (hero.broken && ticks < 10_000) {
      sim.processTick();
      ticks += 1;
    }
    const minutes = (ticks * 2) / 60;
    expect(minutes).toBeGreaterThan(1);
    expect(minutes).toBeLessThan(6);
  });
});

describe('materials', () => {
  it('makes every level-5 recipe reachable within forty far clears', () => {
    // Expected yield of each item per victory at ring 6+, table and drops together.
    const table = rewardTable(6, 0)!;
    const expected = new Map<string, number>();
    const add = (id: string | undefined, chance = 100, min = 0, max = min) => {
      if (!id) return;
      expected.set(id, (expected.get(id) ?? 0) + (chance / 100) * ((min + max) / 2));
    };
    for (const entry of table.items) add(entry.definition_id, entry.chance, entry.min, entry.max);
    // Enemy drops, averaged over the far-ring enemy pool.
    const far = BIOMES.flatMap((biome) => generateEnemies(17, 7, 0, biome));
    for (const enemy of far) {
      for (const drop of getEnemy(enemy.id)?.drops ?? []) {
        const share = 1 / BIOMES.length;
        expected.set(
          drop.definition_id!,
          (expected.get(drop.definition_id!) ?? 0) +
            share * ((drop.chance ?? 100) / 100) * (((drop.min ?? 0) + (drop.max ?? 0)) / 2),
        );
      }
    }
    for (const recipe of allRecipes().filter((r) => r.level === 5)) {
      for (const cost of recipe.cost.filter((c) => c.kind === 'item')) {
        expect(getItemDefinition(cost.id), cost.id).not.toBeNull();
        const perClear = expected.get(cost.id) ?? 0;
        expect(perClear, `${cost.id} for ${recipe.id}`).toBeGreaterThan(0);
        expect(cost.amount / perClear, `clears for ${cost.id} in ${recipe.id}`).toBeLessThanOrEqual(
          40,
        );
      }
    }
  });

  it('names only real items and equipment in every reward table', () => {
    for (const table of worldConfig.clearRewards.tables) {
      for (const entry of table.items)
        expect(getItemDefinition(entry.definition_id!), entry.definition_id).not.toBeNull();
    }
  });
});

describe('economy', () => {
  it('lets a simple build order afford its whole first settlement within half an hour', () => {
    const sim = new Simulation(createWorld(4, 4));
    const order = [
      'gathering_lodge',
      'lumber_camp',
      'quarry',
      'farm',
      'tavern',
      'smithy',
      'barracks',
      'chapel',
    ];
    const built: string[] = [];
    let tick = 0;
    for (; tick < 900 && built.length < order.length; tick += 1) {
      const next = order[built.length]!;
      const building = getBuilding(next)!;
      if (canAfford(sim.world, buildCost(building)) && sim.build(built.length, next))
        built.push(next);
      sim.processTick();
    }
    expect(built).toEqual(order);
    expect((tick * 2) / 60).toBeLessThan(30);
    expect(
      settlementSlots(sim.world, sim.world.activeSettlementId).every((slot) => slot.buildingId),
    ).toBe(true);
  });

  it('trains a Barracks recruit to a sensible level in an hour', () => {
    const sim = new Simulation(createWorld(5, 5));
    for (const id of Object.keys(sim.world.resources) as Array<keyof World['resources']>) {
      sim.world.resources[id] = 10_000;
    }
    sim.build(0, 'barracks');
    const hero = party(sim.world, 1, 1)[0]!;
    sim.world.heroes.push(hero);
    sim.assignHero(hero.uid, 0);
    for (let i = 0; i < 1800; i += 1) sim.processTick();
    expect(hero.level).toBeGreaterThanOrEqual(6);
    expect(hero.level).toBeLessThanOrEqual(20);
  });
});

describe('performance', () => {
  it('catches up eight hours of a busy settlement in a few seconds', () => {
    const sim = new Simulation(createWorld(6, 6));
    for (const id of Object.keys(sim.world.resources) as Array<keyof World['resources']>) {
      sim.world.resources[id] = 100_000;
    }
    [
      'gathering_lodge',
      'farm',
      'quarry',
      'lumber_camp',
      'tavern',
      'barracks',
      'chapel',
      'triage',
    ].forEach((id, i) => sim.build(i, id));
    for (let i = 0; i < 12; i += 1) sim.world.heroes.push(party(sim.world, 1, 3)[0]!);
    const now = 20_000_000_000;
    sim.world.savedAt = now - 8 * 60 * 60 * 1000;
    const started = performance.now();
    const summary = sim.catchUp(now);
    const elapsed = performance.now() - started;
    expect(summary.ticks).toBe(14_400);
    expect(elapsed).toBeLessThan(4000);
  });
});
