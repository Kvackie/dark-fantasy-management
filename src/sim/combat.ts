/**
 * Battles: a party against the enemies holding a zone.
 *
 * Resolved all at once when a clearing party reaches the end of its march, in
 * rounds: every standing hero strikes, then every standing enemy. An attacker
 * picks a target among the standing opposition, weighted by taunt, so a
 * Defender with Taunt draws the blows it is built to take.
 *
 * A strike is the attacker's attack with a little spread, cut by the target's
 * defense (`60 / (60 + defense)`, so defense never makes anyone untouchable),
 * multiplied on a critical hit and by the few skills that bend damage. A battle
 * that runs thirty rounds without a winner is a retreat: the zone holds.
 *
 * Pure: the random source is passed in, so a battle can be replayed or
 * estimated without touching the world's generator.
 */

import { getEnemy, type SkillEffect } from './config';
import { effectiveStats } from './heroes';
import { effectTotal, heroEffects, partyEffect } from './skills';
import type { Hero, World, ZoneEnemy } from './types';

export const MAX_ROUNDS = 30;
const DEFENSE_SCALE = 60;

export interface Fighter {
  side: 'hero' | 'enemy';
  name: string;
  heroUid: number | null;
  maxHealth: number;
  health: number;
  attack: number;
  defense: number;
  critChance: number;
  critDamage: number;
  /** Relative chance of being picked as a target; 1 is ordinary. */
  weight: number;
  execute: { threshold: number; bonus: number } | null;
  /** Percentage change to damage this fighter takes. */
  damageTakenPct: number;
}

export interface FighterReport {
  side: 'hero' | 'enemy';
  name: string;
  heroUid: number | null;
  damageDealt: number;
  damageTaken: number;
  crits: number;
  fell: boolean;
  healthLeft: number;
}

export interface BattleResult {
  victory: boolean;
  rounds: number;
  fighters: FighterReport[];
}

export function heroFighter(world: World, hero: Hero, party: Hero[]): Fighter {
  const stats = effectiveStats(world, hero);
  const execute = heroEffects(hero).find(
    (effect): effect is Extract<SkillEffect, { type: 'execute' }> => effect.type === 'execute',
  );
  return {
    side: 'hero',
    name: hero.name,
    heroUid: hero.uid,
    maxHealth: stats.max_health,
    health: Math.max(0, stats.current_health),
    attack: stats.attack,
    defense: stats.defense,
    critChance: stats.critical_chance,
    critDamage: stats.critical_damage,
    weight: 1 + effectTotal(hero, 'taunt') / 100,
    execute: execute ? { threshold: execute.threshold, bonus: execute.value } : null,
    damageTakenPct: partyEffect(party, 'party_damage_taken_pct'),
  };
}

export function enemyFighter(enemy: ZoneEnemy): Fighter | null {
  const definition = getEnemy(enemy.id);
  if (!definition) return null;
  const scale = (value: number) => Math.round(value * enemy.power);
  const health = scale(definition.stats.health);
  return {
    side: 'enemy',
    name: definition.name,
    heroUid: null,
    maxHealth: health,
    health,
    attack: scale(definition.stats.attack),
    defense: scale(definition.stats.defense),
    critChance: definition.stats.critical_chance,
    critDamage: definition.stats.critical_damage,
    weight: 1,
    execute: null,
    damageTakenPct: 0,
  };
}

function pickTarget(random: () => number, targets: Fighter[]): Fighter | null {
  const total = targets.reduce((sum, fighter) => sum + fighter.weight, 0);
  let roll = random() * total;
  for (const fighter of targets) {
    roll -= fighter.weight;
    if (roll <= 0) return fighter;
  }
  return targets[targets.length - 1] ?? null;
}

export function strikeDamage(
  random: () => number,
  attacker: Fighter,
  target: Fighter,
): [number, boolean] {
  let damage = attacker.attack * (0.85 + 0.3 * random());
  damage *= DEFENSE_SCALE / (DEFENSE_SCALE + Math.max(0, target.defense));
  const crit = random() * 100 < attacker.critChance;
  if (crit) damage *= attacker.critDamage / 100;
  if (attacker.execute && (target.health / target.maxHealth) * 100 < attacker.execute.threshold) {
    damage *= 1 + attacker.execute.bonus / 100;
  }
  damage *= 1 + target.damageTakenPct / 100;
  return [Math.max(1, Math.round(damage)), crit];
}

export function battle(random: () => number, heroes: Fighter[], enemies: Fighter[]): BattleResult {
  const all = [...heroes, ...enemies].map((fighter) => ({ ...fighter }));
  const reports = new Map<Fighter, FighterReport>();
  for (const fighter of all) {
    reports.set(fighter, {
      side: fighter.side,
      name: fighter.name,
      heroUid: fighter.heroUid,
      damageDealt: 0,
      damageTaken: 0,
      crits: 0,
      fell: fighter.health <= 0,
      healthLeft: fighter.health,
    });
  }
  const standing = (side: Fighter['side']) => all.filter((f) => f.side === side && f.health > 0);

  let rounds = 0;
  while (rounds < MAX_ROUNDS && standing('hero').length > 0 && standing('enemy').length > 0) {
    rounds += 1;
    for (const side of ['hero', 'enemy'] as const) {
      for (const attacker of standing(side)) {
        if (attacker.health <= 0) continue;
        const target = pickTarget(random, standing(side === 'hero' ? 'enemy' : 'hero'));
        if (!target) break;
        const [damage, crit] = strikeDamage(random, attacker, target);
        const dealt = Math.min(damage, target.health);
        target.health -= dealt;
        const from = reports.get(attacker)!;
        const to = reports.get(target)!;
        from.damageDealt += dealt;
        if (crit) from.crits += 1;
        to.damageTaken += dealt;
        if (target.health <= 0) to.fell = true;
      }
    }
  }

  for (const fighter of all) reports.get(fighter)!.healthLeft = Math.max(0, fighter.health);
  return {
    victory: standing('enemy').length === 0 && standing('hero').length > 0,
    rounds,
    fighters: [...reports.values()],
  };
}

/** A small seeded generator, for estimates that must not disturb the world's own. */
export function localRandom(seed: number): () => number {
  let state = seed | 0;
  return () => {
    let t = (state = (state + 0x6d2b79f5) | 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The share of `trials` simulated battles the party wins, 0–1. */
export function winChance(
  heroes: Fighter[],
  enemies: Fighter[],
  seed: number,
  trials = 200,
): number {
  if (heroes.length === 0) return 0;
  if (enemies.length === 0) return 1;
  const random = localRandom(seed);
  let wins = 0;
  for (let i = 0; i < trials; i += 1) if (battle(random, heroes, enemies).victory) wins += 1;
  return wins / trials;
}
