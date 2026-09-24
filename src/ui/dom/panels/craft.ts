/**
 * The smithy's recipe book, and the forge a craft is decided at.
 */

import { formatNumber, t } from '@/i18n';
import { getItemDefinition, type Recipe } from '@/sim/config';
import {
  availableRecipes,
  canAffordRecipe,
  hasRecipeCost,
  highestSmithyLevel,
} from '@/sim/crafting';
import {
  BellowsRhythm,
  EdgeSharpening,
  HeatBalance,
  MAX_FAILURES,
  TimingStrike,
  createPuzzle,
  randomPuzzleKind,
} from '@/sim/puzzles';
import { EQUIPMENT_SLOTS, STAT_KEYS, WORK_STAT_KEYS, type BonusValue } from '@/sim/types';
import { iconSvg } from '@/ui/icons';
import { resourceColors } from '@/ui/theme';
import {
  button,
  card,
  el,
  heading,
  icon,
  muted,
  resourceName,
  statName,
  statRow,
} from '../components';
import type { Ui } from '../context';

function sortedRecipes(ui: Ui): Recipe[] {
  const ascending = ui.state.craftAscending;
  return availableRecipes(ui.sim.world)
    .filter((recipe) => recipe.result.slot === ui.state.craftSlot)
    .sort((a, b) => {
      if (a.level === b.level) return a.name.localeCompare(b.name);
      return ascending ? a.level - b.level : b.level - a.level;
    });
}

export function renderCraft(ui: Ui): Node[] {
  const world = ui.sim.world;
  const recipes = sortedRecipes(ui);
  const selected =
    recipes.find((recipe) => recipe.id === ui.state.craftRecipe) ?? recipes[0] ?? null;

  const tabs = el(
    'div',
    { class: 'tabs wrap' },
    EQUIPMENT_SLOTS.map((slot) => {
      const active = slot === ui.state.craftSlot;
      const arrow = active ? (ui.state.craftAscending ? ' ↑' : ' ↓') : '';
      return button(
        `${t(`slot.${slot}`)}${arrow}`,
        () =>
          ui.set({
            craftSlot: slot,
            craftAscending: active ? !ui.state.craftAscending : true,
            craftRecipe: null,
          }),
        { variant: 'tab', selected: active, title: active ? t('craft.sort_hint') : undefined },
      );
    }),
  );

  const list = el(
    'div',
    { class: 'recipe-list' },
    recipes.length
      ? recipes.map((recipe) => {
          const row = el(
            'button',
            { type: 'button', class: `recipe-row${recipe === selected ? ' selected' : ''}` },
            [
              icon(recipe.result.slot, 22),
              el('span', { class: 'recipe-name', text: recipe.name }),
              el('span', {
                class: 'recipe-level',
                text: t('common.level', { level: recipe.level }),
              }),
            ],
          );
          row.addEventListener('click', () => ui.set({ craftRecipe: recipe.id }));
          return row;
        })
      : [muted(t('craft.no_recipes'))],
  );

  return [
    el('div', { class: 'page-header' }, [
      el('div', {}, [
        el('h2', { text: t('page.craft') }),
        el('p', {
          class: 'muted small',
          text: t('craft.smithy_level', { level: highestSmithyLevel(world) }),
        }),
      ]),
    ]),
    el('div', { class: 'craft-layout' }, [
      el('div', { class: 'craft-list' }, [tabs, list]),
      el(
        'div',
        { class: 'craft-detail' },
        selected ? recipeDetail(ui, selected) : [muted(t('craft.select'))],
      ),
    ]),
  ];
}

function formatBonus(value: BonusValue): string {
  return typeof value === 'number' ? `+${value}` : `+${value.min} – ${value.max}`;
}

function recipeDetail(ui: Ui, recipe: Recipe): Node[] {
  const world = ui.sim.world;
  const stats = STAT_KEYS.filter((key) => recipe.result.bonuses.stats[key] !== undefined);
  const work = WORK_STAT_KEYS.filter((key) => recipe.result.bonuses.work_stats[key] !== undefined);
  const affordable = canAffordRecipe(world, recipe);

  return [
    card([
      el('div', { class: 'card-title' }, [
        icon(recipe.result.slot, 28),
        el('div', {}, [
          el('strong', { text: recipe.result.name }),
          el('p', {
            class: 'muted small',
            text: `${t(`slot.${recipe.result.slot}`)}  ·  ${t('common.level', { level: recipe.level })}`,
          }),
        ]),
      ]),
      muted(recipe.description || t('craft.no_description'), 'small'),
      button(
        t('craft.craft_button'),
        () => {
          const puzzle = createPuzzle(randomPuzzleKind());
          ui.go('forge', { forge: { recipeId: recipe.id, puzzle, outcome: null } });
        },
        { variant: 'primary', disabled: !affordable },
      ),
    ]),
    card([
      heading(t('common.cost'), 4),
      el(
        'div',
        { class: 'cost-chips' },
        recipe.cost.map((entry) => {
          const ok = hasRecipeCost(world, entry);
          const name =
            entry.kind === 'resource'
              ? resourceName(entry.id)
              : (getItemDefinition(entry.id)?.name ?? entry.id);
          const chip = el('span', { class: `cost-chip${ok ? ' ok' : ' short'}` }, [
            el('span', {
              class: 'amount-icon',
              html: iconSvg(entry.kind === 'resource' ? entry.id : 'item', 16),
            }),
            el('span', { text: name }),
            el('strong', { text: `×${formatNumber(entry.amount)}` }),
          ]);
          if (entry.kind === 'resource') chip.style.color = resourceColors[entry.id] ?? '';
          return chip;
        }),
      ),
    ]),
    card([
      heading(t('craft.result_ranges'), 4),
      muted(t('craft.quality_note'), 'small'),
      heading(t('hero.combat_stats'), 4),
      ...(stats.length
        ? stats.map((key) =>
            statRow(statName(key), formatBonus(recipe.result.bonuses.stats[key]!), key),
          )
        : [muted(t('common.none'))]),
      heading(t('hero.work_stats_title'), 4),
      ...(work.length
        ? work.map((key) =>
            statRow(t(`work.${key}`), formatBonus(recipe.result.bonuses.work_stats[key]!), key),
          )
        : [muted(t('common.none'))]),
    ]),
  ];
}

/**
 * The forge: title, instructions, the live feedback line, and the controls.
 *
 * The bar itself is drawn by the forge scene behind this panel. The feedback
 * and progress lines move every frame, so they are left empty here and filled
 * in place by the shell — see `forgeLive`.
 */
export function renderForge(ui: Ui): Node[] {
  const forge = ui.state.forge;
  if (!forge) return [muted(t('craft.select'))];
  const puzzle = forge.puzzle;
  const leave = () => ui.go('craft', { forge: null });

  const controls: Node[] = [];
  if (forge.outcome) {
    controls.push(button(t('puzzle.return'), leave, { variant: 'primary' }));
  } else if (!puzzle.started) {
    controls.push(
      button(t('puzzle.start'), () => ui.act(() => puzzle.start()), {
        variant: 'primary',
        onPress: true,
      }),
    );
  } else if (puzzle instanceof TimingStrike) {
    controls.push(
      button(t('puzzle.strike'), () => puzzle.strike(), { variant: 'primary', onPress: true }),
    );
  } else if (puzzle instanceof BellowsRhythm) {
    controls.push(
      button(t('puzzle.pump'), () => puzzle.pump(), { variant: 'primary', onPress: true }),
    );
  } else if (puzzle instanceof HeatBalance) {
    controls.push(
      button(t('puzzle.vent'), () => puzzle.vent(), { onPress: true }),
      button(t('puzzle.stoke'), () => puzzle.stoke(), { variant: 'primary', onPress: true }),
    );
  } else if (puzzle instanceof EdgeSharpening) {
    controls.push(
      button(t('puzzle.nudge_left'), () => puzzle.nudge(-1), { onPress: true }),
      button(t('puzzle.nudge_right'), () => puzzle.nudge(1), { onPress: true }),
    );
  }

  // A failure already says so on the feedback line; a success names what was made.
  const outcome = forge.outcome?.success
    ? el('p', {
        class: 'forge-outcome ok',
        text: t('puzzle.crafted', { name: forge.outcome.pieceName ?? '' }),
      })
    : null;

  return [
    el('div', { class: 'forge-top' }, [
      el('div', {}, [
        el('h2', { text: t(`puzzle.${puzzle.kind}.title`) }),
        el('p', {
          class: 'muted',
          text: t(`puzzle.${puzzle.kind}.help`, { max: MAX_FAILURES }),
        }),
      ]),
      forge.outcome ? null : button(t('puzzle.leave'), leave, { variant: 'ghost', small: true }),
    ]),
    el('div', { class: 'forge-bottom' }, [
      el('p', { class: 'forge-feedback', 'data-live': 'forge-feedback' }),
      el('p', { class: 'forge-progress', 'data-live': 'forge-progress' }),
      outcome,
      el('div', { class: 'forge-controls' }, controls),
      el('p', { class: 'muted small forge-keys', text: t('puzzle.keys') }),
    ]),
  ];
}
