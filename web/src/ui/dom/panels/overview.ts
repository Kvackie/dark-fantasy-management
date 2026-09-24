/**
 * Settlements: every settlement held, and a way into each.
 */

import { t } from '@/i18n';
import { yieldPreview } from '@/sim/production';
import { builtPlotCount, settlementDefinition, settlementSlots } from '@/sim/settlements';
import { button, card, el, icon, muted, resourceList } from '../components';
import type { Ui } from '../context';

export function renderOverview(ui: Ui): Node[] {
  const world = ui.sim.world;
  const owned = world.ownedSettlementIds.filter((id) => settlementDefinition(world, id));
  if (owned.length === 0) return [muted(t('overview.no_settlements'))];

  return [
    el('div', { class: 'page-header' }, [
      el('div', {}, [
        el('h2', { text: t('page.settlements') }),
        el('p', { class: 'muted small' }, [
          `${t('overview.total_yield')} `,
          resourceList(yieldPreview(world), 'yield'),
        ]),
      ]),
    ]),
    el(
      'div',
      { class: 'card-grid' },
      owned.map((id) => {
        const definition = settlementDefinition(world, id)!;
        const active = id === world.activeSettlementId;
        return card(
          [
            el('div', { class: 'card-title' }, [
              icon('settlements', 22),
              el('strong', { text: definition.name }),
              active ? el('span', { class: 'badge', text: t('overview.active') }) : null,
            ]),
            muted(t(`biome.${definition.biome}`), 'small'),
            el('p', {
              text: t('overview.plots', {
                built: builtPlotCount(world, id),
                total: settlementSlots(world, id).length,
              }),
            }),
            definition.allowedBuildings.includes('ALL')
              ? null
              : muted(
                  t('overview.allowed', { list: definition.allowedBuildings.join(', ') }),
                  'small',
                ),
            button(t('overview.open'), () => ui.openSettlement(id), {
              variant: 'primary',
              small: true,
            }),
          ],
          active ? 'active' : '',
        );
      }),
    ),
  ];
}
