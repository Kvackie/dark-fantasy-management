/**
 * The recruit market at the Veil Tavern.
 */

import { t } from '@/i18n';
import {
  areGemRecruitsUnlocked,
  isRecruitmentUnlocked,
  offerCapacity,
  refreshCost,
  tavernCount,
} from '@/sim/recruitment';
import { canAfford, resourceAmount } from '@/sim/resources';
import { STAT_KEYS } from '@/sim/types';
import {
  button,
  card,
  el,
  heroAvatar,
  muted,
  resourceList,
  statName,
  workStatsLine,
} from '../components';
import { RECRUIT_CLOCK, type Ui } from '../context';
import { statColors } from '@/ui/theme';

export function renderRecruit(ui: Ui): Node[] {
  const world = ui.sim.world;
  if (!isRecruitmentUnlocked(world)) return [muted(t('recruit.locked'))];
  const canPay = (id: string, amount: number) => resourceAmount(world, id) >= amount;
  const cost = refreshCost();

  const summary = card(
    [
      el('div', { class: 'summary-row' }, [
        el('div', {}, [
          el('h2', { text: t('page.recruit') }),
          el('p', { text: t('recruit.available_heroes', { count: offerCapacity(world) }) }),
          el('p', {
            class: 'muted small',
            text: t('recruit.taverns_owned', { count: tavernCount(world) }),
          }),
          el('p', {
            class: 'muted small',
            text: areGemRecruitsUnlocked(world) ? t('recruit.gems_open') : t('recruit.gems_locked'),
          }),
          el('p', { class: 'small' }, [
            `${t('recruit.free_refresh')} `,
            el('strong', { class: 'live-clock', 'data-clock': RECRUIT_CLOCK }),
          ]),
        ]),
        el('div', { class: 'summary-actions' }, [
          el('div', { class: 'cost-line' }, [
            el('span', { class: 'label', text: t('recruit.refresh_label') }),
            resourceList(cost, 'cost', canPay),
          ]),
          button(t('recruit.refresh_heroes'), () => ui.act(() => ui.sim.refreshRecruits()), {
            variant: 'primary',
            disabled: !canAfford(world, cost),
          }),
        ]),
      ]),
    ],
    'summary',
  );

  if (world.recruitOffers.length === 0) return [summary, muted(t('recruit.empty'))];

  return [
    summary,
    el(
      'div',
      { class: 'card-grid' },
      world.recruitOffers.map((offer) =>
        card(
          [
            el('div', { class: 'card-title' }, [
              heroAvatar(offer.name, offer.heroClass, 'large'),
              el('div', {}, [
                el('strong', { text: offer.name }),
                el('p', {
                  class: 'muted small',
                  text: t('recruit.meta', { level: offer.level, heroClass: offer.heroClass }),
                }),
                offer.source === 'zone_bonus'
                  ? el('span', { class: 'badge', text: t('recruit.bonus') })
                  : null,
              ]),
            ]),
            el(
              'div',
              { class: 'stat-chips' },
              STAT_KEYS.map((key) => {
                const suffix = key.startsWith('critical') ? '%' : '';
                const node = el('span', { text: `${statName(key)} ${offer.stats[key]}${suffix}` });
                node.style.color = statColors[key] ?? '';
                return node;
              }),
            ),
            workStatsLine(offer.workStats),
            el('div', { class: 'cost-line' }, [
              el('span', { class: 'label', text: t('common.cost') }),
              resourceList(offer.recruitCost, 'cost', canPay),
            ]),
            button(
              t('settlement.recruit_button'),
              () => ui.act(() => ui.sim.recruit(offer.offerId)),
              {
                variant: 'primary',
                small: true,
                disabled: !canAfford(world, offer.recruitCost),
              },
            ),
          ],
          'offer',
        ),
      ),
    ),
  ];
}
