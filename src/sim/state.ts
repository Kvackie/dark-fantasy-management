/**
 * A new game.
 */

import { STARTING_RESOURCES, defaultSettlementId } from './config';
import { randomSeed } from './rng';
import { settlementSlots } from './settlements';
import type { World } from './types';
import { initializeZones } from './zones';

export function createWorld(seed: number = randomSeed(), rngSeed: number = randomSeed()): World {
  const home = defaultSettlementId();
  const world: World = {
    schemaVersion: 1,
    resources: { ...STARTING_RESOURCES },
    settlements: {},
    generatedSettlements: {},
    ownedSettlementIds: home ? [home] : [],
    activeSettlementId: home,
    heroes: [],
    items: [],
    equipment: [],
    recruitOffers: [],
    queuedBonusOffers: [],
    recruitMarketInitialized: false,
    worldSeed: seed >>> 0,
    zones: {},
    tickCount: 0,
    tickProgressMs: 0,
    nextHeroUid: 1,
    nextEquipmentUid: 1,
    nextOfferId: 1,
    rng: rngSeed | 0,
  };
  if (home) settlementSlots(world, home);
  initializeZones(world);
  return world;
}
