/**
 * The roster, and one hero at a time: their record, their gear, their story.
 */

import { t } from '@/i18n';
import { experienceCeiling, getBuilding, getHeroDefinition } from '@/sim/config';
import { effectiveStats, effectiveWorkStats, findHero, heroWorldTask } from '@/sim/heroes';
import { equipmentDefinitionOf } from '@/sim/inventory';
import { settlementName, settlementSlots } from '@/sim/settlements';
import { EQUIPMENT_SLOTS, STAT_KEYS, WORK_STAT_KEYS, type Hero, type World } from '@/sim/types';
import {
  button,
  card,
  el,
  heading,
  heroAvatar,
  icon,
  modal,
  muted,
  statName,
  statRow,
} from '../components';
import type { HeroTab, Ui } from '../context';

/** Where a hero is: on a plot, out on the map, or idle. */
export function heroStatus(world: World, hero: Hero): string {
  const zoneKey = heroWorldTask(world, hero.uid);
  if (zoneKey) {
    const zone = world.zones[zoneKey];
    return t('hero.status_clearing', { zone: zone?.generatedName || t('world.title_discovered') });
  }
  if (hero.assignment) {
    const slot = settlementSlots(world, hero.assignment.settlementId)[hero.assignment.slot];
    const building = getBuilding(slot?.buildingId ?? null)?.name ?? t('hero.status_site');
    if (hero.assignment.settlementId === world.activeSettlementId) return building;
    return `${building} (${settlementName(world, hero.assignment.settlementId)})`;
  }
  return t('hero.status_idle');
}

export function renderHeroes(ui: Ui): Node[] {
  const world = ui.sim.world;
  if (world.heroes.length === 0) return [muted(t('heroes.empty'))];
  return [
    muted(t('heroes.intro')),
    el(
      'div',
      { class: 'card-grid heroes' },
      world.heroes.map((hero) => {
        const stats = effectiveStats(world, hero);
        const tile = el('button', { type: 'button', class: 'card hero-card' }, [
          el('div', { class: 'card-title' }, [
            heroAvatar(hero.name, hero.heroClass, 'large'),
            el('div', {}, [
              el('strong', { text: hero.name }),
              el('p', {
                class: 'muted small',
                text: t('recruit.meta', { level: hero.level, heroClass: hero.heroClass }),
              }),
            ]),
          ]),
          meter(t('stat.health'), stats.current_health, stats.max_health, 'health'),
          meter(t('stat.sanity'), stats.current_sanity, stats.max_sanity, 'sanity'),
          el('p', { class: 'muted small', text: heroStatus(world, hero) }),
        ]);
        tile.addEventListener('click', () => ui.openHero(hero.uid));
        return tile;
      }),
    ),
  ];
}

function meter(label: string, value: number, max: number, kind: string): HTMLElement {
  const fill = el('span', { class: `meter-fill ${kind}` });
  fill.style.width = `${Math.max(0, Math.min(1, max > 0 ? value / max : 0)) * 100}%`;
  return el('div', { class: 'meter-row' }, [
    el('span', { class: 'meter-label', text: label }),
    el('span', { class: 'meter' }, [fill]),
    el('span', { class: 'meter-value', text: `${value}/${max}` }),
  ]);
}

const TABS: HeroTab[] = ['info', 'equipment', 'skills', 'lore'];

export function renderHero(ui: Ui): Node[] {
  const world = ui.sim.world;
  const hero = findHero(world, ui.state.heroUid);
  const back = button(t('hero.back'), () => ui.go('heroes'), { variant: 'ghost', small: true });
  if (!hero) return [back, muted(t('hero.unavailable'))];

  const tabs = el(
    'div',
    { class: 'tabs', role: 'tablist' },
    TABS.map((tab) =>
      button(
        t(`hero.tab_${tab}`),
        () => ui.set({ heroTab: tab, heroSlot: null, heroPiece: null, dismissConfirm: false }),
        {
          variant: 'tab',
          selected: ui.state.heroTab === tab,
        },
      ),
    ),
  );

  let body: Node[];
  switch (ui.state.heroTab) {
    case 'equipment':
      body = equipmentTab(ui, hero);
      break;
    case 'skills':
      body = [
        heading(t('hero.tab_skills')),
        muted(t('hero.skills_placeholder')),
        muted(t('hero.no_skills')),
      ];
      break;
    case 'lore':
      body = loreTab(ui, hero);
      break;
    default:
      body = infoTab(world, hero);
  }

  return [
    el('div', { class: 'page-header' }, [
      el('div', { class: 'card-title' }, [
        heroAvatar(hero.name, hero.heroClass, 'large'),
        el('div', {}, [
          el('h2', { text: hero.name }),
          el('p', {
            class: 'muted small',
            text: t('recruit.meta', { level: hero.level, heroClass: hero.heroClass }),
          }),
        ]),
      ]),
      back,
    ]),
    tabs,
    el('div', { class: 'tab-body' }, body),
  ];
}

function infoTab(world: World, hero: Hero): Node[] {
  const stats = effectiveStats(world, hero);
  const work = effectiveWorkStats(world, hero);
  return [
    el('div', { class: 'card-grid' }, [
      card([
        heading(t('hero.record')),
        statRow(t('hero.name'), hero.name),
        statRow(t('hero.class'), hero.heroClass),
        statRow(t('hero.level'), String(hero.level)),
        statRow(t('hero.experience'), `${hero.experience}/${experienceCeiling(hero.level)}`),
        statRow(t('hero.assignment'), heroStatus(world, hero)),
        statRow(t('hero.source'), t('hero.source_core')),
      ]),
      card([
        heading(t('hero.combat_stats')),
        statRow(statName('health'), `${stats.current_health}/${stats.max_health}`, 'health'),
        statRow(statName('sanity'), `${stats.current_sanity}/${stats.max_sanity}`, 'sanity'),
        ...(['attack', 'defense', 'critical_chance', 'critical_damage'] as const).map((key) =>
          statRow(statName(key), String(stats[key]), key),
        ),
      ]),
      card([
        heading(t('hero.work_stats_title')),
        ...WORK_STAT_KEYS.map((key) => statRow(t(`work.${key}`), String(work[key]), key)),
      ]),
    ]),
  ];
}

function bonusLines(bonuses: {
  stats: Record<string, number | undefined>;
  work_stats: Record<string, number | undefined>;
}): Node[] {
  const lines: Node[] = [];
  for (const key of STAT_KEYS) {
    const value = bonuses.stats[key];
    if (value) lines.push(statRow(statName(key), `+${value}`, key));
  }
  for (const key of WORK_STAT_KEYS) {
    const value = bonuses.work_stats[key];
    if (value) lines.push(statRow(t(`work.${key}`), `+${value}`, key));
  }
  return lines.length ? lines : [muted(t('common.none'))];
}

function equipmentTab(ui: Ui, hero: Hero): Node[] {
  const world = ui.sim.world;
  const slots = el(
    'div',
    { class: 'slot-grid' },
    EQUIPMENT_SLOTS.map((slot) => {
      const uid = hero.equipment[slot];
      const piece = uid !== null ? world.equipment.find((entry) => entry.uid === uid) : undefined;
      const definition = piece ? equipmentDefinitionOf(piece) : null;
      const tile = el(
        'button',
        {
          type: 'button',
          class: `slot-tile${ui.state.heroSlot === slot ? ' selected' : ''}${definition ? ' filled' : ''}`,
        },
        [
          el('span', { class: 'slot-label', text: t(`slot.${slot}`) }),
          icon(slot, 32),
          el('span', { class: 'slot-item', text: definition?.name ?? t('hero.slot_empty') }),
        ],
      );
      tile.addEventListener('click', () =>
        ui.set({ heroSlot: ui.state.heroSlot === slot ? null : slot, heroPiece: null }),
      );
      return tile;
    }),
  );

  const out: Node[] = [heading(t('hero.tab_equipment')), slots];
  const slot = ui.state.heroSlot;
  if (!slot) {
    out.push(muted(t('hero.pick_slot')));
    return out;
  }

  const pieces = world.equipment.filter((piece) => equipmentDefinitionOf(piece)?.slot === slot);
  out.push(heading(t('hero.loadout', { slot: t(`slot.${slot}`) }), 4));
  if (pieces.length === 0) {
    out.push(muted(t('hero.no_matching')));
  } else {
    out.push(
      el(
        'div',
        { class: 'tile-grid' },
        pieces.map((piece) => {
          const definition = equipmentDefinitionOf(piece)!;
          const owner =
            piece.equippedHeroUid !== null ? findHero(world, piece.equippedHeroUid) : null;
          const tile = el(
            'button',
            {
              type: 'button',
              class: `item-tile${ui.state.heroPiece === piece.uid ? ' selected' : ''}`,
            },
            [
              icon(slot, 28),
              el('span', { class: 'item-name', text: definition.name }),
              owner
                ? el('span', {
                    class: 'item-meta',
                    text: t('inventory.worn_by', { name: owner.name }),
                  })
                : null,
            ],
          );
          tile.addEventListener('click', () => ui.set({ heroPiece: piece.uid }));
          return tile;
        }),
      ),
    );
  }

  const selected = pieces.find((piece) => piece.uid === ui.state.heroPiece);
  if (selected) {
    const definition = equipmentDefinitionOf(selected)!;
    const wornHere = selected.equippedHeroUid === hero.uid && selected.equippedSlot === slot;
    const owner =
      selected.equippedHeroUid !== null ? findHero(world, selected.equippedHeroUid) : null;
    const close = () => ui.set({ heroPiece: null });
    out.push(
      modal(
        definition.name,
        [
          el('p', {
            class: 'muted small',
            text: owner ? t('inventory.worn_by', { name: owner.name }) : t('inventory.stored'),
          }),
          heading(t('hero.combat_bonuses'), 4),
          ...bonusLines({ stats: definition.bonuses.stats, work_stats: {} }),
          heading(t('hero.work_bonuses'), 4),
          ...bonusLines({ stats: {}, work_stats: definition.bonuses.work_stats }),
        ],
        [
          wornHere
            ? button(t('hero.unequip'), () => ui.act(() => ui.sim.unequip(hero.uid, slot)), {
                variant: 'ghost',
              })
            : null,
          button(t('hero.equip'), () => ui.act(() => ui.sim.equip(hero.uid, slot, selected.uid)), {
            variant: 'primary',
            disabled: wornHere,
          }),
        ],
        close,
      ),
    );
  }
  return out;
}

function loreTab(ui: Ui, hero: Hero): Node[] {
  const description = getHeroDefinition(hero.definitionId)?.description || t('hero.no_lore');
  const dismiss = ui.state.dismissConfirm
    ? card(
        [
          el('p', { class: 'warning', text: t('hero.dismiss_warning') }),
          el('div', { class: 'button-row' }, [
            button(t('common.cancel'), () => ui.set({ dismissConfirm: false }), {
              variant: 'ghost',
              small: true,
            }),
            button(
              t('hero.dismiss_confirm'),
              () => {
                ui.act(() => ui.sim.dismissHero(hero.uid));
                ui.go('heroes');
              },
              { variant: 'danger', small: true },
            ),
          ]),
        ],
        'danger-zone',
      )
    : button(t('hero.dismiss'), () => ui.set({ dismissConfirm: true }), {
        variant: 'danger',
        small: true,
      });
  return [heading(t('hero.tab_lore')), el('p', { class: 'lore', text: description }), dismiss];
}
