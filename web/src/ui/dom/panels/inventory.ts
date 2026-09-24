/**
 * The stores: recovered supplies and every piece of gear, worn or not.
 */

import { formatNumber, t } from '@/i18n';
import { getItemDefinition } from '@/sim/config';
import { findHero } from '@/sim/heroes';
import { equipmentDefinitionOf } from '@/sim/inventory';
import { button, el, icon, muted } from '../components';
import type { Ui } from '../context';

export function renderInventory(ui: Ui): Node[] {
  const world = ui.sim.world;
  const tab = ui.state.inventoryTab;
  const tabs = el('div', { class: 'tabs' }, [
    button(
      t('inventory.tab_items', { count: world.items.length }),
      () => ui.set({ inventoryTab: 'items' }),
      {
        variant: 'tab',
        selected: tab === 'items',
      },
    ),
    button(
      t('inventory.tab_equipment', { count: world.equipment.length }),
      () => ui.set({ inventoryTab: 'equipment' }),
      { variant: 'tab', selected: tab === 'equipment' },
    ),
  ]);

  const out: Node[] = [muted(t('inventory.intro')), tabs];

  if (tab === 'items') {
    if (world.items.length === 0) return [...out, muted(t('inventory.no_items'))];
    out.push(
      el(
        'div',
        { class: 'tile-grid' },
        world.items.map((stack) =>
          el('div', { class: 'item-tile' }, [
            icon('item', 28),
            el('span', {
              class: 'item-name',
              text: getItemDefinition(stack.definitionId)?.name ?? stack.definitionId,
            }),
            el('span', { class: 'item-count', text: `×${formatNumber(stack.quantity)}` }),
          ]),
        ),
      ),
    );
    return out;
  }

  if (world.equipment.length === 0) return [...out, muted(t('inventory.no_equipment'))];
  out.push(
    el(
      'div',
      { class: 'tile-grid' },
      world.equipment.map((piece) => {
        const definition = equipmentDefinitionOf(piece);
        const owner =
          piece.equippedHeroUid !== null ? findHero(world, piece.equippedHeroUid) : null;
        return el('div', { class: `item-tile${owner ? ' worn' : ''}` }, [
          icon(definition?.slot ?? 'item', 28),
          el('span', { class: 'item-name', text: definition?.name ?? piece.definitionId }),
          el('span', { class: 'item-meta', text: definition ? t(`slot.${definition.slot}`) : '' }),
          owner
            ? el('span', { class: 'item-meta', text: t('inventory.worn_by', { name: owner.name }) })
            : null,
          piece.definition ? el('span', { class: 'badge', text: t('inventory.crafted') }) : null,
        ]);
      }),
    ),
  );
  return out;
}
