/**
 * The world screen: the map is the Phaser scene behind; this is what floats on
 * it — the zoom controls, the hint, and the dialog a pressed zone opens.
 */

import { formatClock, t } from '@/i18n';
import { TICK_MS, worldConfig } from '@/sim/config';
import { effectiveStats, findHero, isHeroIdle } from '@/sim/heroes';
import { canAfford, resourceAmount } from '@/sim/resources';
import { partyPreview } from '@/sim/zones';
import type { Zone, ZoneRequirements } from '@/sim/types';
import {
  button,
  checkRow,
  el,
  heroAvatar,
  modal,
  muted,
  resourceList,
  resourceName,
} from '../components';
import type { Ui } from '../context';

export function renderWorld(ui: Ui): Node[] {
  const controls = el('div', { class: 'map-controls' }, [
    button('', () => ui.zoomMap(1.2), {
      icon: 'plus',
      variant: 'ghost',
      title: t('world.zoom_in'),
    }),
    button('', () => ui.zoomMap(1 / 1.2), {
      icon: 'minus',
      variant: 'ghost',
      title: t('world.zoom_out'),
    }),
    button('', () => ui.recenterMap(), {
      icon: 'target',
      variant: 'ghost',
      title: t('world.recenter'),
    }),
  ]);
  const hint = el('p', { class: 'map-hint', text: t('world.pan_hint_web') });
  const out: Node[] = [controls, hint];
  const dialog = zoneDialog(ui);
  if (dialog) out.push(dialog);
  return out;
}

function requirementsText(requirements: ZoneRequirements): string {
  return t('world.requirements', { attack: requirements.attack, defense: requirements.defense });
}

function zoneDialog(ui: Ui): HTMLElement | null {
  const selection = ui.state.zone;
  if (!selection) return null;
  const zone = ui.sim.world.zones[selection.key];
  const close = () => ui.set({ zone: null });
  if (!zone) return null;
  switch (zone.state) {
    case 'discovered':
      return discoveredDialog(ui, zone, selection.party, close);
    case 'clearing':
      return clearingDialog(ui, zone, close);
    case 'cleared':
      return clearedDialog(ui, zone, close);
    case 'claimed':
      return zone.noSettlement ? claimedAreaDialog(zone, close) : null;
    default:
      return null;
  }
}

function discoveredDialog(ui: Ui, zone: Zone, party: number[], close: () => void): HTMLElement {
  const world = ui.sim.world;
  const max = worldConfig.maxClearingParty;
  const idle = world.heroes.filter((hero) => isHeroIdle(world, hero));
  const preview = partyPreview(world, zone.key, party);
  const seconds = (zone.clearDuration * TICK_MS) / 1000;

  const toggle = (uid: number, on: boolean) => {
    const next = on ? [...party, uid] : party.filter((id) => id !== uid);
    ui.set({ zone: { key: zone.key, party: next.slice(0, max) } });
  };

  const rows = idle.map((hero) => {
    const stats = effectiveStats(world, hero);
    const checked = party.includes(hero.uid);
    return checkRow(checked, !checked && party.length >= max, (on) => toggle(hero.uid, on), [
      heroAvatar(hero.name, hero.heroClass),
      el('span', { class: 'check-main' }, [
        el('strong', { text: hero.name }),
        el('span', {
          class: 'muted small',
          text: t('world.hero_line', {
            heroClass: hero.heroClass,
            level: hero.level,
            health: `${stats.current_health}/${stats.max_health}`,
            sanity: `${stats.current_sanity}/${stats.max_sanity}`,
            attack: stats.attack,
            defense: stats.defense,
          }),
        }),
      ]),
    ]);
  });

  const status = el('p', {
    class: `party-status${preview.meets ? ' ok' : ''}`,
    text: t('world.party_status', {
      attack: preview.totals.attack,
      needAttack: preview.requirements.attack,
      defense: preview.totals.defense,
      needDefense: preview.requirements.defense,
    }),
  });

  return modal(
    t('world.title_discovered'),
    [
      el('p', { class: 'muted', text: t('world.biome_line', { biome: t(`biome.${zone.biome}`) }) }),
      el('p', { class: 'small', text: t('world.sanity_cost', { amount: zone.sanityLoss }) }),
      el('p', { class: 'small', text: t('world.party_limit', { count: max }) }),
      rows.length
        ? el('div', { class: 'check-list' }, rows)
        : muted(t('world.no_available_heroes')),
      status,
    ],
    [
      button(t('world.button_close'), close, { variant: 'ghost' }),
      button(
        t('world.button_begin_clearing'),
        () => {
          ui.act(() => ui.sim.startClearing(zone.key, party));
          ui.set({ zone: { key: zone.key, party: [] } });
        },
        { variant: 'primary', disabled: party.length === 0 || !preview.meets },
      ),
    ],
    close,
    {
      subtitle: `${t('world.clearing_seconds', { seconds })}  ·  ${requirementsText(zone.requirements)}`,
    },
  );
}

function clearingDialog(ui: Ui, zone: Zone, close: () => void): HTMLElement {
  const names = zone.assignedHeroUids
    .map((uid) => findHero(ui.sim.world, uid)?.name)
    .filter((name): name is string => Boolean(name));
  const clock = el('strong', { class: 'live-clock', 'data-clock': zone.key });
  return modal(
    t('world.title_clearing'),
    [
      el('p', {}, [`${t('world.time_remaining')} `, clock]),
      el('p', { class: 'muted', text: t('world.assigned_heroes', { count: names.length }) }),
      el(
        'ul',
        { class: 'plain-list' },
        names.map((name) => el('li', { text: name })),
      ),
    ],
    [button(t('world.button_close'), close, { variant: 'ghost' })],
    close,
    { subtitle: requirementsText(zone.requirements) },
  );
}

function clearedDialog(ui: Ui, zone: Zone, close: () => void): HTMLElement {
  const world = ui.sim.world;
  const affordable = canAfford(world, zone.claimCost);
  return modal(
    t('world.title_cleared'),
    [
      el('h4', { text: zone.generatedName }),
      el('p', { class: 'muted', text: t('world.biome_line', { biome: t(`biome.${zone.biome}`) }) }),
      zone.noSettlement ? el('p', { class: 'note', text: t('world.special_area') }) : null,
      !zone.noSettlement ? el('p', { class: 'small', text: t('world.settlement_preview') }) : null,
      el('p', { class: 'label', text: t('world.claim_cost') }),
      resourceList(zone.claimCost, 'cost', (id, amount) => resourceAmount(world, id) >= amount),
    ].filter(Boolean) as Node[],
    [
      button(t('world.button_close'), close, { variant: 'ghost' }),
      button(
        zone.noSettlement ? t('world.button_claim_area') : t('world.button_claim'),
        () => {
          ui.act(() => ui.sim.claimZone(zone.key));
          ui.set({ zone: null });
        },
        { variant: 'primary', disabled: !affordable },
      ),
    ],
    close,
    { subtitle: requirementsText(zone.requirements) },
  );
}

function claimedAreaDialog(zone: Zone, close: () => void): HTMLElement {
  const reward = zone.claimedReward;
  return modal(
    zone.generatedName || t('world.claimed_area'),
    [
      el('p', { class: 'note', text: t('world.special_area') }),
      el('p', {
        text: reward
          ? t('world.claimed_reward', {
              amount: reward.amount,
              resource: resourceName(reward.resource),
              interval: reward.interval,
            })
          : t('world.no_reward'),
      }),
    ],
    [button(t('world.button_close'), close, { variant: 'ghost' })],
    close,
    { subtitle: t('world.claimed_area') },
  );
}

/** The text of a live clock, for the shell to patch in each frame. */
export function zoneClockText(ui: Ui, key: string): string {
  return formatClock(ui.sim.clearingSecondsLeft(key));
}
