/**
 * The event log: every battle, recovery, recruit, craft and building, newest first.
 */

import { t } from '@/i18n';
import { TICK_MS } from '@/sim/config';
import type { LogEntry, LogKind, World } from '@/sim/types';
import { button, el, muted, resourceName } from '../components';
import type { Ui } from '../context';

type Filter = 'all' | 'battles' | 'heroes' | 'settlement';

const FILTERS: Record<Filter, LogKind[] | null> = {
  all: null,
  battles: ['victory', 'defeat'],
  heroes: ['broken', 'restored', 'wounded', 'healed', 'level', 'recruit', 'dismissed'],
  settlement: ['built', 'upgraded', 'dismantled', 'claimed', 'crafted', 'craft_failed', 'slate'],
};

/** A detail line's text. Resource lists are stored as ids, so they are named here. */
export function detailText(detail: LogEntry['details'][number]): string {
  if (detail.key === 'log.detail.resources') {
    const list = String(detail.params.list ?? '')
      .split(',')
      .filter(Boolean)
      .map((part) => {
        const [id, amount] = part.split(':');
        return `${resourceName(id ?? '')} +${amount ?? 0}`;
      })
      .join(', ');
    return t(detail.key, { list });
  }
  return t(detail.key, detail.params);
}

export function entryTitle(entry: LogEntry): string {
  return t(entry.key, entry.params);
}

/** "just now", "4 min ago", "2 h ago" — from ticks, since the log has no wall clock. */
export function ago(world: World, entry: LogEntry): string {
  const seconds = ((world.tickCount - entry.tick) * TICK_MS) / 1000;
  if (seconds < 60) return t('log.just_now');
  if (seconds < 3600) return t('log.minutes_ago', { minutes: Math.floor(seconds / 60) });
  return t('log.hours_ago', { hours: Math.floor(seconds / 3600) });
}

let filter: Filter = 'all';
/** Entries the player has opened, so a redraw does not fold them shut again. */
const opened = new Set<number>();

export function renderLog(ui: Ui): Node[] {
  const world = ui.sim.world;
  const kinds = FILTERS[filter];
  const entries = world.log
    .filter((entry) => !kinds || kinds.includes(entry.kind))
    .slice()
    .reverse();
  const tabs = el(
    'div',
    { class: 'tabs' },
    (Object.keys(FILTERS) as Filter[]).map((id) =>
      button(
        t(`log.filter_${id}`),
        () => {
          filter = id;
          ui.set({});
        },
        { variant: 'tab', selected: filter === id },
      ),
    ),
  );
  if (entries.length === 0) return [tabs, muted(t('log.empty'))];
  return [
    tabs,
    el(
      'ol',
      { class: 'log-list' },
      entries.map((entry) => {
        const head = el('div', { class: 'log-head' }, [
          el('span', { class: `log-kind kind-${entry.kind}`, text: t(`log.kind_${entry.kind}`) }),
          el('strong', { text: entryTitle(entry) }),
          el('span', { class: 'muted small log-ago', text: ago(world, entry) }),
        ]);
        if (entry.details.length === 0) return el('li', { class: 'log-entry' }, [head]);
        const summary = el('summary', {}, [head]);
        const details = el('details', opened.has(entry.id) ? { open: '' } : {}, [
          summary,
          el(
            'ul',
            { class: 'log-details' },
            entry.details.map((detail) => el('li', { text: detailText(detail) })),
          ),
        ]);
        details.addEventListener('toggle', () => {
          if (details.open) opened.add(entry.id);
          else opened.delete(entry.id);
        });
        return el('li', { class: 'log-entry' }, [details]);
      }),
    ),
  ];
}
