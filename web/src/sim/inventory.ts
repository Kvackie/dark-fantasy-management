/**
 * The stores: stacked items and individual pieces of equipment, and who wears what.
 *
 * A worn piece is linked from both ends — the hero's slot names the piece, the
 * piece names the hero — and every change here moves both ends together.
 */

import { getEquipmentDefinition, getItemDefinition } from './config';
import type { EquipmentDefinition, EquipmentInstance, EquipmentSlot, Hero, World } from './types';

export function equipmentDefinitionOf(instance: EquipmentInstance): EquipmentDefinition | null {
  return instance.definition ?? getEquipmentDefinition(instance.definitionId);
}

export function itemQuantity(world: World, itemId: string): number {
  return world.items
    .filter((stack) => stack.definitionId === itemId)
    .reduce((sum, stack) => sum + stack.quantity, 0);
}

/**
 * Add items, topping up existing stacks before starting new ones.
 *
 * An id with no definition is ignored — some reward tables in the data name
 * items that are not in `items.json`, and the Godot build dropped those too.
 */
export function addItem(world: World, itemId: string, quantity: number): boolean {
  if (quantity <= 0) return false;
  const definition = getItemDefinition(itemId);
  if (!definition) return false;
  let remaining = quantity;
  for (const stack of world.items) {
    if (remaining <= 0) break;
    if (stack.definitionId !== itemId || stack.quantity >= definition.maxStack) continue;
    const added = Math.min(definition.maxStack - stack.quantity, remaining);
    stack.quantity += added;
    remaining -= added;
  }
  while (remaining > 0) {
    const size = Math.min(definition.maxStack, remaining);
    world.items.push({ definitionId: itemId, quantity: size });
    remaining -= size;
  }
  return true;
}

export function removeItem(world: World, itemId: string, quantity: number): void {
  let remaining = quantity;
  world.items = world.items.filter((stack) => {
    if (stack.definitionId !== itemId || remaining <= 0) return true;
    const removed = Math.min(stack.quantity, remaining);
    stack.quantity -= removed;
    remaining -= removed;
    return stack.quantity > 0;
  });
}

/** A new piece from the catalogue, or from a definition rolled on the spot. */
export function addEquipment(
  world: World,
  definitionId: string,
  embedded: EquipmentDefinition | null = null,
): EquipmentInstance | null {
  if (!embedded && !getEquipmentDefinition(definitionId)) return null;
  const instance: EquipmentInstance = {
    uid: world.nextEquipmentUid,
    definitionId,
    definition: embedded,
    equippedHeroUid: null,
    equippedSlot: null,
  };
  world.nextEquipmentUid += 1;
  world.equipment.push(instance);
  return instance;
}

function findInstance(world: World, uid: number): EquipmentInstance | null {
  return world.equipment.find((entry) => entry.uid === uid) ?? null;
}

/** Take a piece off whoever wears it, from both ends of the link. */
function detach(world: World, uid: number): void {
  for (const hero of world.heroes) {
    for (const slot of Object.keys(hero.equipment) as EquipmentSlot[]) {
      if (hero.equipment[slot] === uid) hero.equipment[slot] = null;
    }
  }
  const instance = findInstance(world, uid);
  if (instance) {
    instance.equippedHeroUid = null;
    instance.equippedSlot = null;
  }
}

/** Put a piece on a hero, moving it off anyone else and off whatever held the slot. */
export function equip(world: World, hero: Hero, slot: EquipmentSlot, uid: number): boolean {
  const instance = findInstance(world, uid);
  const definition = instance ? equipmentDefinitionOf(instance) : null;
  if (!instance || !definition || definition.slot !== slot) return false;
  unequip(world, hero, slot);
  detach(world, uid);
  hero.equipment[slot] = uid;
  instance.equippedHeroUid = hero.uid;
  instance.equippedSlot = slot;
  return true;
}

export function unequip(world: World, hero: Hero, slot: EquipmentSlot): boolean {
  const uid = hero.equipment[slot];
  if (uid === null) return false;
  hero.equipment[slot] = null;
  const instance = findInstance(world, uid);
  if (instance) {
    instance.equippedHeroUid = null;
    instance.equippedSlot = null;
  }
  return true;
}

export function stripHero(world: World, hero: Hero): void {
  for (const slot of Object.keys(hero.equipment) as EquipmentSlot[]) unequip(world, hero, slot);
}
