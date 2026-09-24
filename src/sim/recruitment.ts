/**
 * The recruit market.
 *
 * A Veil Tavern opens it. The slate holds three heroes, plus one for each
 * further tavern, drawn by roster weight without repeats. Heroes whose price
 * includes gems stay off it until a tavern reaches level 3. A cleared zone
 * sends one extra hero to the slate — held back until there is a tavern to
 * receive them.
 */

import { allHeroes, getHeroDefinition, recruitmentConfig, type HeroDefinition } from './config';
import { createHeroFromOffer } from './heroes';
import { addLog } from './log';
import { spend } from './resources';
import { randomInt } from './rng';
import { buildingCensus } from './settlements';
import type { Hero, RecruitOffer, ResourceMap, World } from './types';

export const GEM_RECRUIT_TAVERN_LEVEL = 3;

export function tavernCount(world: World): number {
  return buildingCensus(world, 'tavern').count;
}

export function isRecruitmentUnlocked(world: World): boolean {
  return tavernCount(world) > 0;
}

export function areGemRecruitsUnlocked(world: World): boolean {
  return buildingCensus(world, 'tavern').highest >= GEM_RECRUIT_TAVERN_LEVEL;
}

export function offerCapacity(world: World): number {
  const taverns = tavernCount(world);
  if (taverns <= 0) return 0;
  return (
    recruitmentConfig.baseOfferCount +
    Math.max(taverns - 1, 0) * recruitmentConfig.extraOfferPerTavern
  );
}

export function refreshCost(): ResourceMap {
  return { ...recruitmentConfig.refreshCost };
}

export function hasGemCost(definition: HeroDefinition | null): boolean {
  return definition?.recruitCost.some((entry) => entry.resource === 'gems') ?? false;
}

export function recruitablePool(world: World): HeroDefinition[] {
  const gems = areGemRecruitsUnlocked(world);
  return allHeroes().filter((definition) => gems || !hasGemCost(definition));
}

export function rollWeighted(world: World, pool: readonly HeroDefinition[]): HeroDefinition | null {
  if (pool.length === 0) return null;
  const total = pool.reduce((sum, definition) => sum + definition.recruitmentWeight, 0);
  const roll = randomInt(world, 1, total);
  let cursor = 0;
  for (const definition of pool) {
    cursor += definition.recruitmentWeight;
    if (roll <= cursor) return definition;
  }
  return pool[0] ?? null;
}

/** A hero's price at a level, with any ranged part rolled now. */
export function resolveRecruitCost(
  world: World,
  definition: HeroDefinition,
  level: number,
): ResourceMap {
  const cost: ResourceMap = {};
  for (const entry of definition.recruitCost) {
    const base =
      typeof entry.amount === 'number'
        ? entry.amount
        : randomInt(world, entry.amount.min, entry.amount.max);
    const amount = Math.max(0, base + Math.max(level - 1, 0) * entry.perLevel);
    if (amount > 0) cost[entry.resource] = (cost[entry.resource] ?? 0) + amount;
  }
  return cost;
}

export function createOffer(
  world: World,
  definition: HeroDefinition,
  source: RecruitOffer['source'] = 'market',
): RecruitOffer {
  const offer: RecruitOffer = {
    offerId: world.nextOfferId,
    definitionId: definition.id,
    name: definition.name,
    heroClass: definition.heroClass,
    level: definition.level,
    recruitCost: resolveRecruitCost(world, definition, definition.level),
    stats: { ...definition.stats },
    workStats: { ...definition.workStats },
    source,
  };
  world.nextOfferId += 1;
  return offer;
}

/** Draw `count` offers, avoiding heroes already on offer until the roster runs out. */
export function drawOffers(
  world: World,
  pool: readonly HeroDefinition[],
  count: number,
  excluded: readonly string[] = [],
  source: RecruitOffer['source'] = 'market',
): RecruitOffer[] {
  const offers: RecruitOffer[] = [];
  if (count <= 0 || pool.length === 0) return offers;
  const used = new Set(excluded);
  while (offers.length < count) {
    const fresh = pool.filter((definition) => !used.has(definition.id));
    const definition = rollWeighted(world, fresh.length > 0 ? fresh : pool);
    if (!definition) break;
    offers.push(createOffer(world, definition, source));
    used.add(definition.id);
  }
  return offers;
}

/**
 * Bring the market in line with the settlements.
 *
 * Drops gem-priced heroes while no tavern is high enough for them, seeds the
 * first slate the moment a tavern stands, tops the slate up when a new tavern
 * raises the capacity, and releases any bonus recruits that were waiting.
 */
export function reconcileMarket(world: World, seedIfUnlocked = true): boolean {
  if (!isRecruitmentUnlocked(world)) return false;
  let changed = false;

  if (!areGemRecruitsUnlocked(world)) {
    const keep = (offer: RecruitOffer) => !hasGemCost(getHeroDefinition(offer.definitionId));
    const before = world.recruitOffers.length + world.queuedBonusOffers.length;
    world.recruitOffers = world.recruitOffers.filter(keep);
    world.queuedBonusOffers = world.queuedBonusOffers.filter(keep);
    changed ||= before !== world.recruitOffers.length + world.queuedBonusOffers.length;
  }

  if (world.recruitOffers.length > 0) world.recruitMarketInitialized = true;

  if (seedIfUnlocked && !world.recruitMarketInitialized) {
    world.recruitOffers = drawOffers(world, recruitablePool(world), offerCapacity(world));
    world.recruitMarketInitialized = true;
    changed = true;
  }

  const shortfall = offerCapacity(world) - world.recruitOffers.length;
  if (world.recruitMarketInitialized && shortfall > 0) {
    const excluded = world.recruitOffers.map((offer) => offer.definitionId);
    world.recruitOffers.push(...drawOffers(world, recruitablePool(world), shortfall, excluded));
    changed = true;
  }

  if (world.queuedBonusOffers.length > 0) {
    world.recruitOffers.push(...world.queuedBonusOffers);
    world.queuedBonusOffers = [];
    changed = true;
  }
  return changed;
}

/** Pay for a fresh slate. Waiting bonus recruits are lost with the old one. */
export function refreshOffers(world: World): boolean {
  if (!isRecruitmentUnlocked(world)) return false;
  if (!spend(world, refreshCost())) return false;
  world.queuedBonusOffers = [];
  world.recruitOffers = drawOffers(world, recruitablePool(world), offerCapacity(world));
  world.recruitMarketInitialized = true;
  world.recruitRefreshTick = world.tickCount;
  return true;
}

/** How often the slate renews itself for free: 150 ticks, five minutes. */
export const RECRUIT_REFRESH_TICKS = 150;

export function ticksToFreeRefresh(world: World): number {
  return Math.max(0, world.recruitRefreshTick + RECRUIT_REFRESH_TICKS - world.tickCount);
}

/**
 * Renew the slate on its own every few minutes.
 *
 * Heroes a cleared zone sent are kept — they were a reward, not a draw — and
 * the ordinary offers are replaced. Paying for a refresh restarts the clock.
 */
export function autoRefreshOffers(world: World): boolean {
  if (!isRecruitmentUnlocked(world) || ticksToFreeRefresh(world) > 0) return false;
  const bonus = world.recruitOffers.filter((offer) => offer.source === 'zone_bonus');
  const excluded = bonus.map((offer) => offer.definitionId);
  const count = Math.max(0, offerCapacity(world));
  world.recruitOffers = [...drawOffers(world, recruitablePool(world), count, excluded), ...bonus];
  world.recruitMarketInitialized = true;
  world.recruitRefreshTick = world.tickCount;
  addLog(world, 'slate', 'log.slate', {});
  return true;
}

export function recruitFromOffer(world: World, offerId: number): Hero | null {
  const index = world.recruitOffers.findIndex((offer) => offer.offerId === offerId);
  const offer = world.recruitOffers[index];
  if (!offer) return null;
  if (!spend(world, offer.recruitCost)) return null;
  const hero = createHeroFromOffer(world, offer);
  world.heroes.push(hero);
  world.recruitOffers.splice(index, 1);
  return hero;
}

/** The extra hero a cleared zone sends: onto the slate if there is a tavern, else into the queue. */
export function seedZoneBonusOffer(world: World): RecruitOffer | null {
  const excluded = [...world.recruitOffers, ...world.queuedBonusOffers].map((o) => o.definitionId);
  const [offer] = drawOffers(world, recruitablePool(world), 1, excluded, 'zone_bonus');
  if (!offer) return null;
  if (isRecruitmentUnlocked(world)) world.recruitOffers.push(offer);
  else world.queuedBonusOffers.push(offer);
  return offer;
}
