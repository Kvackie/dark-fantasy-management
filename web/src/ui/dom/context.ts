/**
 * What the panels share: the simulation, the saves, and the UI's own state —
 * which screen is open, what is selected, which dialog is up.
 *
 * None of this is game state. It is not saved, and it is safe to lose.
 */

import type { SaveManager } from '@/platform/save';
import type { ForgePuzzle } from '@/sim/puzzles';
import type { Simulation } from '@/sim/sim';
import type { EquipmentSlot } from '@/sim/types';
import type { ScreenId } from '@/ui/bus';

export type HeroTab = 'info' | 'equipment' | 'skills' | 'lore';

export interface ForgeState {
  recipeId: string;
  puzzle: ForgePuzzle;
  /** Set once the puzzle ends and the craft has been paid for. */
  outcome: { success: boolean; pieceName: string | null } | null;
}

export interface ConfirmRequest {
  title: string;
  body: string;
  confirm: string;
  danger?: boolean;
  onConfirm: () => void;
}

export interface UiState {
  screen: ScreenId;
  /** The open plot in the active settlement, or -1. */
  selectedSlot: number;
  /** The Assign Heroes dialog: which plot, and who is ticked. */
  assign: { slot: number; selected: number[] } | null;
  /** The zone dialog on the world map, and the party being picked for it. */
  zone: { key: string; party: number[] } | null;
  heroUid: number;
  heroTab: HeroTab;
  /** The gear slot open in the hero's equipment browser. */
  heroSlot: EquipmentSlot | null;
  /** The piece open in the equipment dialog. */
  heroPiece: number | null;
  dismissConfirm: boolean;
  inventoryTab: 'items' | 'equipment';
  craftSlot: EquipmentSlot;
  craftAscending: boolean;
  craftRecipe: string | null;
  forge: ForgeState | null;
  confirm: ConfirmRequest | null;
  /** The main menu overlay, or null while playing. */
  menu: 'root' | 'saves' | null;
}

export function initialUiState(): UiState {
  return {
    screen: 'world',
    selectedSlot: -1,
    assign: null,
    zone: null,
    heroUid: -1,
    heroTab: 'info',
    heroSlot: null,
    heroPiece: null,
    dismissConfirm: false,
    inventoryTab: 'items',
    craftSlot: 'head',
    craftAscending: true,
    craftRecipe: null,
    forge: null,
    confirm: null,
    menu: 'root',
  };
}

export interface Ui {
  readonly sim: Simulation;
  readonly saves: SaveManager;
  readonly state: UiState;
  /** The save slot this game writes to. */
  readonly activeSlot: number;
  /** Change UI state and redraw. */
  set(patch: Partial<UiState>): void;
  /** Run a game action and redraw. */
  act(action: () => unknown): void;
  go(screen: ScreenId, patch?: Partial<UiState>): void;
  openSettlement(settlementId: string): void;
  openHero(uid: number): void;
  ask(request: ConfirmRequest): void;
  startNewGame(): void;
  loadSlot(slot: number): void;
  saveTo(slot: number): void;
  recenterMap(): void;
  zoomMap(factor: number): void;
}
