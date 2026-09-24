import { describe, expect, it } from 'vitest';
import { SaveManager } from '@/platform/save';
import { MemoryStore } from '@/platform/storage';
import {
  experienceCeiling,
  experienceForLevel,
  getHeroDefinition,
  getItemDefinition,
  worldConfig,
} from '@/sim/config';
import { createHero, effectiveStats, grantExperience } from '@/sim/heroes';
import { LOG_LIMIT, addLog } from '@/sim/log';
import { RECRUIT_REFRESH_TICKS } from '@/sim/recruitment';
import { unlockedSkills } from '@/sim/skills';
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';
import type { Hero, World } from '@/sim/types';
import { partyPreview } from '@/sim/zones';

function rich(world: World): World {
  for (const id of Object.keys(world.resources) as Array<keyof World['resources']>) {
    world.resources[id] = 100_000;
  }
  return world;
}

function hire(sim: Simulation, id: string, level = 1): Hero {
  const hero = createHero(sim.world, getHeroDefinition(id)!, level);
  sim.world.heroes.push(hero);
  return hero;
}

describe('broken heroes and the Chapel', () => {
  it('breaks a hero at zero sanity, keeps them out of work, and restores them slowly', () => {
    const sim = new Simulation(rich(createWorld(1, 1)));
    sim.build(0, 'chapel');
    sim.build(1, 'quarry');
    const hero = hire(sim, 'ash_smith');
    hero.stats.current_sanity = 0;
    sim.processTick();
    // Nothing had checked them yet; a zone battle or a recovery tick does.
    hero.broken = true;

    expect(sim.assignHero(hero.uid, 1)).toBe(false);
    expect(sim.startClearing('1,0', [hero.uid])).toBe(false);
    expect(sim.assignHero(hero.uid, 0)).toBe(true);

    const max = effectiveStats(sim.world, hero).max_sanity;
    sim.processTick();
    // One sanity per tick at level 1: a low rate, as asked.
    expect(hero.stats.current_sanity).toBe(1);
    expect(hero.broken).toBe(true);

    for (let i = 0; i < max; i += 1) sim.processTick();
    expect(hero.stats.current_sanity).toBe(max);
    expect(hero.broken).toBe(false);
    expect(hero.assignment).toBeNull();
    expect(sim.world.log.some((entry) => entry.kind === 'restored')).toBe(true);
    expect(sim.assignHero(hero.uid, 1)).toBe(true);
  });

  it('restores faster at a higher level', () => {
    const sim = new Simulation(rich(createWorld(2, 2)));
    sim.build(0, 'chapel');
    sim.upgrade(0);
    sim.upgrade(0);
    const hero = hire(sim, 'ash_smith');
    hero.stats.current_sanity = 10;
    sim.assignHero(hero.uid, 0);
    sim.processTick();
    expect(hero.stats.current_sanity).toBe(12);
  });
});

describe('wounded heroes and the Triage', () => {
  it('heals a wounded hero for gold until whole, and only then lets them work', () => {
    const sim = new Simulation(rich(createWorld(3, 3)));
    sim.build(0, 'triage');
    sim.build(1, 'quarry');
    const hero = hire(sim, 'ash_smith');
    hero.stats.current_health = 0;
    hero.wounded = true;
    expect(sim.assignHero(hero.uid, 1)).toBe(false);
    expect(sim.assignHero(hero.uid, 0)).toBe(true);
    const gold = sim.world.resources.gold;
    sim.processTick();
    expect(hero.stats.current_health).toBe(3);
    expect(sim.world.resources.gold).toBe(gold - 3);
    for (let i = 0; i < 100 && hero.wounded; i += 1) sim.processTick();
    expect(hero.wounded).toBe(false);
    expect(sim.world.log.some((entry) => entry.kind === 'healed')).toBe(true);
  });
});

describe('passive skills', () => {
  it('unlocks class skills by level and applies their stat effects', () => {
    const world = createWorld(4, 4);
    const defender = createHero(world, getHeroDefinition('ash_smith')!);
    expect(unlockedSkills(defender).map((skill) => skill.id)).toEqual(['bulwark']);
    // Bulwark: +15% defense.
    expect(effectiveStats(world, defender).defense).toBe(Math.round(defender.stats.defense * 1.15));

    grantExperience(defender, experienceForLevel(8));
    expect(defender.level).toBe(8);
    expect(unlockedSkills(defender).map((skill) => skill.id)).toEqual([
      'bulwark',
      'taunt',
      'stalwart',
    ]);
    // Stalwart: +20% maximum health.
    expect(effectiveStats(world, defender).max_health).toBe(
      Math.round(defender.stats.max_health * 1.2),
    );
  });

  it("lets a Supporter's Steady Nerves cut the party's sanity loss", () => {
    const sim = new Simulation(createWorld(5, 5));
    const attacker = hire(sim, 'briar_ranger');
    const supporter = hire(sim, 'grave_forager');
    const zone = sim.world.zones['1,0']!;
    const alone = partyPreview(sim.world, zone.key, [attacker.uid]).sanityLoss;
    const together = partyPreview(sim.world, zone.key, [attacker.uid, supporter.uid]).sanityLoss;
    expect(alone).toBe(zone.sanityLoss);
    expect(together).toBe(Math.round(zone.sanityLoss * 0.75));
  });
});

describe('loot', () => {
  it('brings home materials that exist in the item catalogue', () => {
    const sim = new Simulation(createWorld(6, 6));
    const party = [hire(sim, 'ash_smith', 10), hire(sim, 'briar_ranger', 10)];
    for (const [x, y] of [
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
    ] as const) {
      const zone = sim.world.zones[`${x},${y}`]!;
      zone.enemies = [{ id: 'bog_ghoul', power: 0.5 }];
      party.forEach((hero) => {
        hero.stats.current_health = hero.stats.max_health;
        hero.stats.current_sanity = hero.stats.max_sanity;
      });
      expect(
        sim.startClearing(
          zone.key,
          party.map((hero) => hero.uid),
        ),
      ).toBe(true);
      sim.advanceBy(worldConfig.defaultClearDuration * 2000);
      expect(zone.state).toBe('cleared');
    }
    expect(sim.world.items.length).toBeGreaterThan(0);
    for (const stack of sim.world.items)
      expect(getItemDefinition(stack.definitionId)).not.toBeNull();
  });
});

describe('the tavern slate', () => {
  it('renews itself on a timer, keeping heroes a cleared zone sent', () => {
    const sim = new Simulation(rich(createWorld(7, 7)));
    sim.build(0, 'tavern');
    sim.world.recruitOffers[0]!.source = 'zone_bonus';
    const kept = sim.world.recruitOffers[0]!.offerId;
    const before = sim.world.recruitOffers.map((offer) => offer.offerId);
    for (let i = 0; i < RECRUIT_REFRESH_TICKS; i += 1) sim.processTick();
    const after = sim.world.recruitOffers.map((offer) => offer.offerId);
    expect(after).toContain(kept);
    expect(after.filter((id) => before.includes(id))).toEqual([kept]);
    expect(sim.world.log.some((entry) => entry.kind === 'slate')).toBe(true);
  });
});

describe('experience', () => {
  it('asks more of every level than the one before', () => {
    expect(experienceCeiling(1)).toBe(10);
    expect(experienceCeiling(2)).toBe(30);
    expect(experienceCeiling(3)).toBe(60);
    expect(experienceForLevel(1)).toBe(0);
    expect(experienceForLevel(4)).toBe(60);
  });
});

describe('the log', () => {
  it('keeps the newest entries up to its cap', () => {
    const world = createWorld(8, 8);
    for (let i = 0; i < LOG_LIMIT + 20; i += 1) addLog(world, 'slate', 'log.slate');
    expect(world.log).toHaveLength(LOG_LIMIT);
    expect(world.log[world.log.length - 1]!.id).toBe(LOG_LIMIT + 20);
  });
});

describe('time away', () => {
  it('catches up on the time since the last save, up to the cap', () => {
    const sim = new Simulation(createWorld(9, 9));
    sim.build(0, 'gathering_lodge');
    const now = 10_000_000_000;
    sim.world.savedAt = now - 60 * 60 * 1000;
    const gold = sim.world.resources.gold;
    const summary = sim.catchUp(now);
    expect(summary.ticks).toBe(1800);
    expect(summary.resources.gold).toBe(1800 * 3);
    expect(sim.world.resources.gold).toBe(gold + 1800 * 3);

    sim.world.savedAt = now - 48 * 60 * 60 * 1000;
    const long = sim.catchUp(now);
    expect(long.simulatedMs).toBe(8 * 60 * 60 * 1000);
    expect(long.awayMs).toBe(48 * 60 * 60 * 1000);
  });

  it('does nothing for a game that was never saved', () => {
    const sim = new Simulation(createWorld(10, 10));
    expect(sim.catchUp(Date.now()).ticks).toBe(0);
  });
});

describe('saves', () => {
  it('keeps conditions, the log and zone defenders across a save', () => {
    const saves = new SaveManager(new MemoryStore());
    const sim = new Simulation(createWorld(11, 11));
    const hero = hire(sim, 'ash_smith');
    hero.broken = true;
    addLog(sim.world, 'broken', 'log.broken', { name: hero.name });
    saves.save(1, sim.world);
    const loaded = saves.load(1)!;
    expect(loaded.heroes[0]?.broken).toBe(true);
    expect(loaded.log).toHaveLength(1);
    expect(loaded.zones['1,0']?.enemies).toEqual(sim.world.zones['1,0']?.enemies);
  });
});
