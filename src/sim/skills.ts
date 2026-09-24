/**
 * Passive skills.
 *
 * Each class has four, unlocked at hero levels 1, 4, 8 and 12. A skill is only
 * ever a bundle of effects, and every effect type is read in exactly one place:
 * stat effects in `heroes.effectiveStats`, the combat ones in `combat.ts`, the
 * party ones where an expedition is resolved, recovery where the Triage and
 * Chapel tick.
 */

import { classSkills, type SkillDefinition, type SkillEffect } from './config';
import type { Hero } from './types';

export function unlockedSkills(hero: Hero): SkillDefinition[] {
  return classSkills(hero.heroClass).filter((skill) => skill.level <= hero.level);
}

export function heroEffects(hero: Hero): SkillEffect[] {
  return unlockedSkills(hero).flatMap((skill) => skill.effects);
}

/** The sum of one effect type across a hero's skills. */
export function effectTotal(hero: Hero, type: SkillEffect['type']): number {
  return heroEffects(hero)
    .filter((effect) => effect.type === type)
    .reduce((sum, effect) => sum + effect.value, 0);
}

/**
 * A party effect: the strongest one any member brings.
 *
 * Party effects do not stack across heroes — two Supporters calm a party no
 * more than one does — so a party is not simply three copies of its best hero.
 */
export function partyEffect(party: Hero[], type: SkillEffect['type']): number {
  let best = 0;
  for (const hero of party) {
    const value = effectTotal(hero, type);
    if (Math.abs(value) > Math.abs(best)) best = value;
  }
  return best;
}
