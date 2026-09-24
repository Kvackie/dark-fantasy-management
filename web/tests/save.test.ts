import { describe, expect, it } from 'vitest';
import { SaveManager, normalizeWorld } from '@/platform/save';
import { MemoryStore } from '@/platform/storage';
import { getHeroDefinition } from '@/sim/config';
import { createHero } from '@/sim/heroes';
import { addEquipment } from '@/sim/inventory';
import { Simulation } from '@/sim/sim';
import { createWorld } from '@/sim/state';

describe('save slots', () => {
  it('round-trips a world and remembers the last slot played', () => {
    const saves = new SaveManager(new MemoryStore());
    const sim = new Simulation(createWorld(77, 77));
    sim.build(0, 'tavern');
    const hero = createHero(sim.world, getHeroDefinition('ash_smith')!);
    sim.world.heroes.push(hero);
    const piece = addEquipment(sim.world, 'amulet_1')!;
    sim.equip(hero.uid, 'amulet', piece.uid);
    sim.startClearing('1,0', [hero.uid]);
    sim.advanceBy(2500);

    const slot = saves.nextNewSlot();
    expect(slot).toBe(1);
    expect(saves.save(slot, sim.world)).toBe(true);
    expect(saves.nextNewSlot()).toBe(2);
    expect(saves.lastPlayedSlot()).toBe(1);

    const loaded = saves.load(slot);
    expect(loaded).not.toBeNull();
    expect(loaded).toEqual(JSON.parse(JSON.stringify(sim.world)));

    saves.rename(slot, '  Ashfall  ');
    expect(saves.summary(slot)).toMatchObject({
      name: 'Ashfall',
      heroCount: 1,
      settlementCount: 1,
    });
    saves.delete(slot);
    expect(saves.exists(slot)).toBe(false);
    expect(saves.lastPlayedSlot()).toBe(0);
  });

  it('repairs broken links instead of refusing the save', () => {
    const world = createWorld(5, 5);
    const raw = JSON.parse(JSON.stringify(world));
    raw.heroes = [
      {
        uid: 3,
        definitionId: 'ash_smith',
        name: 'Orsik',
        level: 2,
        stats: { health: 100, sanity: 80 },
        equipment: { head: 99 },
        assignment: { settlementId: 'hollow_march', slot: 0 },
      },
    ];
    raw.zones['1,0'].state = 'clearing';
    raw.zones['1,0'].assignedHeroUids = [42];
    const repaired = normalizeWorld(raw)!;
    expect(repaired.heroes[0]?.equipment.head).toBeNull();
    // Plot 0 is empty, so the assignment goes.
    expect(repaired.heroes[0]?.assignment).toBeNull();
    // A party of nobody abandons its zone.
    expect(repaired.zones['1,0']?.state).toBe('discovered');
    expect(repaired.nextHeroUid).toBe(4);
  });

  it('rejects something that is not a save', () => {
    expect(normalizeWorld({ hello: 'world' })).toBeNull();
    expect(normalizeWorld('nope')).toBeNull();
  });
});
