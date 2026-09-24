/**
 * A settlement: its plots, the one that is open, and the Assign Heroes dialog.
 */

import { t } from '@/i18n';
import {
  RESOURCE_WORK_STAT,
  buildingEffect,
  getBuilding,
  type BuildingDefinition,
} from '@/sim/config';
import { effectiveStats, effectiveWorkStats } from '@/sim/heroes';
import { slotProduction } from '@/sim/production';
import { canAfford, resourceAmount } from '@/sim/resources';
import {
  assignedHeroes,
  buildCost,
  buildingCatalog,
  builtPlotCount,
  dismantleRefund,
  eligibleHeroes,
  mayWork,
  settlementDefinition,
  settlementSlots,
  upgradeCost,
} from '@/sim/settlements';
import type { Hero, WorkStatKey, World } from '@/sim/types';
import {
  button,
  card,
  checkRow,
  el,
  heading,
  heroAvatar,
  icon,
  infoChip,
  modal,
  muted,
  resourceList,
  workStatsLine,
} from '../components';
import type { Ui } from '../context';
import { conditionBadges } from './heroes';

export function renderSettlement(ui: Ui): Node[] {
  const world = ui.sim.world;
  const id = world.activeSettlementId;
  const definition = settlementDefinition(world, id);
  const slots = settlementSlots(world, id);
  const selected = ui.state.selectedSlot;

  const header = el('div', { class: 'page-header' }, [
    el('div', {}, [
      el('h2', { text: definition?.name ?? t('common.settlement') }),
      el('p', {
        class: 'muted small',
        text: `${t(`biome.${definition?.biome ?? 'neutral'}`)}  ·  ${t('overview.plots', {
          built: builtPlotCount(world, id),
          total: slots.length,
        })}`,
      }),
    ]),
    button(t('nav.settlements'), () => ui.go('overview'), { variant: 'ghost', small: true }),
  ]);

  const grid = el(
    'div',
    { class: 'plot-grid' },
    slots.map((slot, index) => {
      const building = getBuilding(slot.buildingId);
      const staff = building ? assignedHeroes(world, id, index).length : 0;
      const plot = el(
        'button',
        {
          type: 'button',
          class: `plot${index === selected ? ' selected' : ''}${building ? '' : ' empty'}`,
          'aria-pressed': String(index === selected),
        },
        [
          icon(building?.id ?? 'empty_plot', 44, 'plot-icon'),
          el('span', {
            class: 'plot-name',
            text: building?.name ?? t('settlement.empty_plot_short'),
          }),
          el('span', {
            class: 'plot-meta',
            text: building
              ? t('common.level', { level: slot.level })
              : t('settlement.build_structure'),
          }),
          building && building.workerSlots > 0
            ? el('span', {
                class: 'plot-meta',
                text: t('settlement.workers', { assigned: staff, capacity: building.workerSlots }),
              })
            : null,
        ],
      );
      plot.addEventListener('click', () =>
        ui.set({ selectedSlot: index === selected ? -1 : index }),
      );
      return plot;
    }),
  );

  const detail = selected >= 0 && selected < slots.length ? plotDetail(ui, selected) : null;
  const out: Node[] = [
    header,
    el('div', { class: `settlement-layout${detail ? ' with-detail' : ''}` }, [
      grid,
      detail ? el('aside', { class: 'detail-panel' }, detail) : null,
    ]),
  ];
  const dialog = assignDialog(ui);
  if (dialog) out.push(dialog);
  return out;
}

function detailHeader(ui: Ui, title: string): HTMLElement {
  return el('div', { class: 'detail-header' }, [
    el('h3', { text: title }),
    button('', () => ui.set({ selectedSlot: -1 }), {
      variant: 'ghost',
      icon: 'close',
      small: true,
      title: t('common.close'),
    }),
  ]);
}

function plotDetail(ui: Ui, index: number): Node[] {
  const world = ui.sim.world;
  const id = world.activeSettlementId;
  const slot = settlementSlots(world, id)[index];
  const building = getBuilding(slot?.buildingId ?? null);
  const canPay = (resource: string, amount: number) => resourceAmount(world, resource) >= amount;

  if (!slot || !building) {
    return [
      detailHeader(ui, t('settlement.empty_plot', { index: index + 1 })),
      muted(t('settlement.choose_structure')),
      heading(t('settlement.available_buildings'), 4),
      ...buildingCatalog(world, id).map((option) => {
        const cost = buildCost(option);
        return card(
          [
            el('div', { class: 'card-title' }, [
              icon(option.id, 22),
              el('strong', { text: option.name }),
            ]),
            muted(option.description, 'small'),
            el('div', { class: 'cost-line' }, [
              el('span', { class: 'label', text: t('common.cost') }),
              resourceList(cost, 'cost', canPay),
            ]),
            button(
              t('settlement.build_named', { name: option.name }),
              () => ui.act(() => ui.sim.build(index, option.id)),
              { variant: 'primary', small: true, disabled: !canAfford(world, cost) },
            ),
          ],
          'build-option',
        );
      }),
    ];
  }

  const staff = assignedHeroes(world, id, index).filter((hero) => mayWork(world, hero, building));
  const atMax = slot.level >= building.maxLevel;
  const upgrade = upgradeCost(world, id, index);
  const production = slotProduction(world, id, index);
  const refund = dismantleRefund(world, id, index);

  return [
    detailHeader(ui, building.name),
    card([
      muted(building.description, 'small'),
      el('div', { class: 'chip-row' }, [
        infoChip(t('common.level_label'), `${slot.level} / ${building.maxLevel}`),
        infoChip(t('common.workers_label'), `${staff.length} / ${building.workerSlots}`),
      ]),
      Object.keys(production).length
        ? el('div', { class: 'cost-line' }, [
            el('span', { class: 'label', text: t('settlement.production_label') }),
            resourceList(production, 'yield'),
          ])
        : null,
      requirementsNote(building.assignmentRequirements),
      specialEffect(building, slot.level),
    ]),
    card([
      el('div', { class: 'cost-line' }, [
        el('span', { class: 'label', text: t('settlement.upgrade_cost_label') }),
        atMax ? muted(t('settlement.max_level')) : resourceList(upgrade, 'cost', canPay),
      ]),
      button(t('settlement.upgrade_button'), () => ui.act(() => ui.sim.upgrade(index)), {
        variant: 'primary',
        small: true,
        disabled: atMax || !canAfford(world, upgrade),
      }),
      el('div', { class: 'cost-line' }, [
        el('span', { class: 'label', text: t('settlement.dismantle_refund_label') }),
        resourceList(refund, 'refund'),
      ]),
      button(
        t('settlement.dismantle_button'),
        () =>
          ui.ask({
            title: t('settlement.dismantle_confirm_title', { name: building.name }),
            body: t('settlement.dismantle_confirm_body'),
            confirm: t('settlement.dismantle_button'),
            danger: true,
            onConfirm: () => {
              ui.act(() => ui.sim.dismantle(index));
              ui.set({ selectedSlot: -1 });
            },
          }),
        { variant: 'danger', small: true },
      ),
    ]),
    building.workerSlots > 0
      ? card([
          heading(t('settlement.assigned_heroes'), 4),
          staff.length
            ? el(
                'ul',
                { class: 'staff-list' },
                staff.map((hero) =>
                  el('li', {}, [
                    heroAvatar(hero.name, hero.heroClass),
                    el('span', { class: 'check-main' }, [
                      el('strong', { text: hero.name }),
                      workStatsLine(effectiveWorkStats(world, hero)),
                    ]),
                  ]),
                ),
              )
            : muted(t('settlement.no_assigned_heroes')),
          button(
            t('settlement.assign_button'),
            () => ui.set({ assign: { slot: index, selected: staff.map((hero) => hero.uid) } }),
            { variant: 'primary', small: true },
          ),
        ])
      : null,
  ].filter(Boolean) as Node[];
}

/** What a Triage, Chapel or Barracks does per tick at its level. */
function specialEffect(building: BuildingDefinition, level: number): HTMLElement | null {
  let text = '';
  if (building.id === 'triage') {
    text = t('settlement.effect_triage', {
      heal: buildingEffect(building, 'heal_health_per_hero', 'heal_per_level', level),
      gold: buildingEffect(building, 'gold_per_hero', '', level),
    });
  } else if (building.id === 'chapel') {
    text = t('settlement.effect_chapel', {
      amount: buildingEffect(building, 'restore_sanity_per_hero', 'restore_per_level', level),
    });
  } else if (building.id === 'barracks') {
    text = t('settlement.effect_barracks', {
      amount: buildingEffect(building, 'experience_per_hero', 'experience_per_level', level),
    });
  }
  return text ? el('p', { class: 'small note', text }) : null;
}

function requirementsNote(requirements: Record<string, number | undefined>): HTMLElement | null {
  const parts = Object.entries(requirements)
    .filter(([, value]) => (value ?? 0) > 0)
    .map(([key, value]) => `${t(`work.${key}`)} ${value}`);
  if (parts.length === 0) return null;
  return el('p', {
    class: 'muted small',
    text: t('settlement.requires', { list: parts.join(', ') }),
  });
}

/**
 * How well a hero suits a building, and the figure that says so.
 *
 * Production buildings want the work stat their output scales with; the Triage
 * wants the most hurt first, the Chapel the most shaken, and the Barracks the
 * greenest recruits, who have the most to gain.
 */
function suitability(
  world: World,
  hero: Hero,
  building: BuildingDefinition,
): { score: number; label: string } {
  const stats = effectiveStats(world, hero);
  if (building.id === 'triage') {
    return {
      score: stats.max_health - stats.current_health,
      label: `${t('stat.health')} ${stats.current_health}/${stats.max_health}`,
    };
  }
  if (building.id === 'chapel') {
    return {
      score: stats.max_sanity - stats.current_sanity,
      label: `${t('stat.sanity')} ${stats.current_sanity}/${stats.max_sanity}`,
    };
  }
  if (building.id === 'barracks') {
    return { score: -hero.level, label: t('common.level', { level: hero.level }) };
  }
  const work = effectiveWorkStats(world, hero);
  const keys = [
    ...new Set(
      building.baseProduction
        .map((entry) => RESOURCE_WORK_STAT[entry.resource])
        .filter((key): key is WorkStatKey => key !== undefined),
    ),
  ];
  if (keys.length === 0) {
    const total = work.farming + work.mining + work.lumbering;
    return { score: total, label: t('settlement.total_work', { amount: total }) };
  }
  const score = keys.reduce((sum, key) => sum + work[key], 0);
  return { score, label: keys.map((key) => `${t(`work.${key}`)} ${work[key]}`).join(' · ') };
}

function assignDialog(ui: Ui): HTMLElement | null {
  const state = ui.state.assign;
  if (!state) return null;
  const world = ui.sim.world;
  const id = world.activeSettlementId;
  const building = getBuilding(settlementSlots(world, id)[state.slot]?.buildingId ?? null);
  if (!building) return null;
  const close = () => ui.set({ assign: null });

  const here = assignedHeroes(world, id, state.slot).filter((hero) =>
    mayWork(world, hero, building),
  );
  const seen = new Set(here.map((hero) => hero.uid));
  const rows = [...here, ...eligibleHeroes(world, id, state.slot).filter((h) => !seen.has(h.uid))]
    .map((hero) => ({ hero, ...suitability(world, hero, building) }))
    .sort((a, b) => b.score - a.score || a.hero.name.localeCompare(b.hero.name));
  const full = state.selected.length >= building.workerSlots;

  const toggle = (uid: number, on: boolean) => {
    const selected = on
      ? [...state.selected, uid].slice(0, building.workerSlots)
      : state.selected.filter((entry) => entry !== uid);
    ui.set({ assign: { slot: state.slot, selected } });
  };

  const best = () =>
    ui.set({
      assign: {
        slot: state.slot,
        selected: rows.slice(0, building.workerSlots).map((row) => row.hero.uid),
      },
    });

  const apply = () => {
    ui.act(() => {
      for (const hero of here)
        if (!state.selected.includes(hero.uid)) ui.sim.unassignHero(hero.uid);
      for (const uid of state.selected) ui.sim.assignHero(uid, state.slot);
    });
    close();
  };

  const empty =
    building.id === 'triage'
      ? t('settlement.no_patients')
      : building.id === 'chapel'
        ? t('settlement.no_shaken')
        : t('settlement.no_eligible');

  return modal(
    t('settlement.assign_title', { name: building.name }),
    [
      el('div', { class: 'summary-row' }, [
        el('p', {
          class: 'muted small',
          text: t('settlement.assign_status', {
            count: state.selected.length,
            capacity: building.workerSlots,
          }),
        }),
        rows.length
          ? button(t('settlement.assign_best'), best, { small: true, variant: 'ghost' })
          : null,
      ]),
      rows.length
        ? el(
            'div',
            { class: 'check-list' },
            rows.map(({ hero, label }) => {
              const checked = state.selected.includes(hero.uid);
              return checkRow(checked, full && !checked, (on) => toggle(hero.uid, on), [
                heroAvatar(hero.name, hero.heroClass),
                el('span', { class: 'check-main' }, [
                  el('strong', { text: hero.name }),
                  el('span', { class: 'small suit', text: label }),
                ]),
                ...conditionBadges(hero),
              ]);
            }),
          )
        : muted(empty),
    ],
    [
      button(t('common.cancel'), close, { variant: 'ghost' }),
      button(t('common.apply'), apply, { variant: 'primary' }),
    ],
    close,
  );
}
