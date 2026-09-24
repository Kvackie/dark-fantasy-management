/**
 * The DOM shell: resource bar, navigation, the panel over the stage, dialogs,
 * toasts and the main menu.
 *
 * The shell never touches Phaser. It talks to the simulation and the bus, and
 * `main.ts` wires the two halves together.
 *
 * Panels are rebuilt from scratch and swapped in only when their markup
 * actually changed. A tick lands every two seconds and most ticks change
 * nothing a panel shows except the resource counts, which live in the bar and
 * are written in place — so a panel is almost never torn down under the
 * pointer, and scrolling and focus survive. The few things that move on their
 * own (a clearing countdown, the forge's feedback line) are left empty in the
 * markup and filled in each frame.
 */

import { formatClock, formatNumber, formatYield, t } from '@/i18n';
import { logSince } from '@/sim/log';
import { isCraftingUnlocked } from '@/sim/crafting';
import { yieldPreview } from '@/sim/production';
import {
  MAX_FAILURES,
  type ForgePuzzle,
  BellowsRhythm,
  EdgeSharpening,
  HeatBalance,
  TimingStrike,
} from '@/sim/puzzles';
import { isRecruitmentUnlocked } from '@/sim/recruitment';
import type { Simulation } from '@/sim/sim';
import { RESOURCE_ORDER, type LogEntry, type ResourceMap } from '@/sim/types';
import type { AwaySummary } from '@/sim/sim';
import type { SaveManager } from '@/platform/save';
import { bus, changed, type ScreenId } from '@/ui/bus';
import { iconSvg } from '@/ui/icons';
import { resourceColors } from '@/ui/theme';
import { button, el, modal, resourceList, resourceName } from './components';
import { detailText, entryTitle, renderLog } from './panels/log';
import { onSettingsChange, settings } from '@/ui/settings';
import { isMuted, playFor, setMuted } from '@/ui/sound';
import { normalizeWorld } from '@/platform/save';
import type { World } from '@/sim/types';
import {
  RECRUIT_CLOCK,
  initialUiState,
  type ConfirmRequest,
  type Ui,
  type UiState,
} from './context';
import { renderCraft, renderForge } from './panels/craft';
import { renderHero, renderHeroes } from './panels/heroes';
import { renderInventory } from './panels/inventory';
import { renderOverview } from './panels/overview';
import { renderRecruit } from './panels/recruit';
import { renderDebug, renderMenu, renderSaves } from './panels/saves';
import { renderSettings } from './panels/settings';
import { renderSettlement } from './panels/settlement';
import { renderWorld } from './panels/world';

export interface ShellDeps {
  sim: Simulation;
  saves: SaveManager;
  /** The slot this game autosaves into; 0 before the player has started or loaded one. */
  activeSlot: number;
  onScreenChange: (screen: ScreenId) => void;
  onForge: (puzzle: ForgePuzzle | null) => void;
  onRecenter: () => void;
  onZoom: (factor: number) => void;
  onNewGame: () => void;
  onLoad: (slot: number) => void;
  /** Start playing an imported save, in a slot of its own. */
  onImport: (world: World) => void;
  /** Delete every save and preference, then reload into a fresh start. */
  onWipe: () => void;
  onSave: (slot: number) => boolean;
}

/** Screens that are pages over a hidden canvas, as opposed to overlays on a live one. */
const CANVAS_SCREENS = new Set<ScreenId>(['world', 'forge']);

const NAV: Array<{ screen: ScreenId | 'menu'; icon: string; label: string }> = [
  { screen: 'world', icon: 'world', label: 'nav.world' },
  { screen: 'overview', icon: 'settlements', label: 'nav.settlements' },
  { screen: 'recruit', icon: 'recruit', label: 'nav.recruit' },
  { screen: 'heroes', icon: 'heroes', label: 'nav.heroes' },
  { screen: 'inventory', icon: 'inventory', label: 'nav.inventory' },
  { screen: 'craft', icon: 'craft', label: 'nav.craft' },
  { screen: 'debug', icon: 'debug', label: 'nav.debug' },
  { screen: 'log', icon: 'log', label: 'nav.log' },
  { screen: 'saves', icon: 'saves', label: 'nav.saves' },
  { screen: 'settings', icon: 'settings', label: 'nav.settings' },
  { screen: 'menu', icon: 'menu', label: 'nav.home' },
];

const TOAST_MS = 4200;

export class Shell implements Ui {
  readonly state: UiState = initialUiState();
  private hud = el('header', { class: 'hud' });
  private hudValues = new Map<string, { value: HTMLElement; yieldNode: HTMLElement }>();
  private hudShown = new Map<string, string>();
  private nav = el('nav', { class: 'nav', 'aria-label': t('nav.label') });
  private panels = el('div', { id: 'panels' });
  private page = el('div', { class: 'page' });
  private overlay = el('div', { class: 'overlay-layer' });
  private toasts = el('div', { class: 'toasts', 'aria-live': 'polite' });
  private stage: HTMLElement | null = null;
  private lastHtml = new WeakMap<HTMLElement, string>();
  private drawnRevision = -1;
  private yields: ResourceMap = {};
  private liveClocks: HTMLElement[] = [];
  /** The newest log entry already toasted; older ones are history, not news. */
  private lastLogSeen = 0;
  private liveForge: { feedback: HTMLElement | null; progress: HTMLElement | null } = {
    feedback: null,
    progress: null,
  };
  private forgeShape = '';

  constructor(private deps: ShellDeps) {
    this.lastLogSeen = deps.sim.world.nextLogId - 1;
  }

  get sim(): Simulation {
    return this.deps.sim;
  }

  get saves(): SaveManager {
    return this.deps.saves;
  }

  get activeSlot(): number {
    return this.deps.activeSlot;
  }

  // -- Ui ---------------------------------------------------------------------

  set(patch: Partial<UiState>): void {
    Object.assign(this.state, patch);
    this.render();
  }

  act(action: () => unknown): void {
    action();
    changed();
  }

  go(screen: ScreenId, patch: Partial<UiState> = {}): void {
    const leaving = this.state.screen;
    Object.assign(this.state, {
      zone: null,
      assign: null,
      confirm: null,
      ...(screen !== 'settlement' ? { selectedSlot: -1 } : {}),
      ...(screen !== 'hero' ? { heroSlot: null, heroPiece: null, dismissConfirm: false } : {}),
      ...(leaving === 'forge' && screen !== 'forge' ? { forge: null } : {}),
      ...patch,
      screen,
    });
    this.deps.onForge(screen === 'forge' ? (this.state.forge?.puzzle ?? null) : null);
    this.deps.onScreenChange(screen);
    this.page.scrollTop = 0;
    this.render();
  }

  openSettlement(settlementId: string): void {
    if (
      !this.sim.setActiveSettlement(settlementId) &&
      this.sim.world.activeSettlementId !== settlementId
    ) {
      return;
    }
    this.go('settlement', { selectedSlot: -1 });
  }

  openHero(uid: number): void {
    this.go('hero', { heroUid: uid, heroTab: 'info' });
  }

  ask(request: ConfirmRequest): void {
    this.set({ confirm: request });
  }

  startNewGame(): void {
    this.deps.onNewGame();
  }

  loadSlot(slot: number): void {
    if (slot > 0) this.deps.onLoad(slot);
  }

  /** Download this game as a file — the only copy that survives clearing the browser's data. */
  exportSave(): void {
    const world = { ...this.sim.world, savedAt: Date.now() };
    const blob = new Blob([JSON.stringify(world)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = el('a', {
      href: url,
      download: `dark-fantasy-settlement-${new Date().toISOString().slice(0, 10)}.json`,
    });
    document.body.append(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  importSave(file: File): void {
    void file.text().then((text) => {
      let world: World | null = null;
      try {
        world = normalizeWorld(JSON.parse(text));
      } catch {
        world = null;
      }
      if (!world) {
        this.showToast(t('save.import_failed'), []);
        return;
      }
      this.deps.onImport(world);
    });
  }

  saveTo(slot: number): void {
    const ok = this.deps.onSave(slot);
    this.showToast(ok ? t('save.saved', { slot }) : t('save.failed'), []);
    this.render();
  }

  recenterMap(): void {
    this.deps.onRecenter();
  }

  zoomMap(factor: number): void {
    this.deps.onZoom(factor);
  }

  wipeAll(): void {
    this.deps.onWipe();
  }

  // -- mounting ---------------------------------------------------------------

  mount(root: HTMLElement, stage: HTMLElement): void {
    this.stage = stage;
    this.panels.append(this.page);
    stage.append(this.panels, this.toasts);
    root.prepend(this.hud);
    root.append(this.nav, this.overlay);
    this.buildHud();

    bus.on((event) => {
      if (event.type === 'changed') this.render();
      else if (event.type === 'toast') this.showToast(event.title, event.lines);
      else if (event.type === 'zone:pressed') this.onZonePressed(event.key);
    });

    document.addEventListener('keydown', (event) => this.onKey(event));
    this.deps.onScreenChange(this.state.screen);
    this.render();
  }

  private buildHud(): void {
    const badges = RESOURCE_ORDER.map((id) => {
      const value = el('span', { class: 'hud-value' });
      const yieldNode = el('span', { class: 'hud-yield' });
      this.hudValues.set(id, { value, yieldNode });
      const badge = el('div', { class: 'hud-badge', title: resourceName(id) }, [
        el('span', { class: 'hud-icon', html: iconSvg(id, 20) }),
        el('span', { class: 'hud-text' }, [
          el('span', { class: 'hud-name', text: resourceName(id) }),
          value,
          yieldNode,
        ]),
      ]);
      badge.style.setProperty('--resource', resourceColors[id] ?? '#e6ddd3');
      return badge;
    });
    const sound = button(
      '',
      () => {
        setMuted(!isMuted());
        this.render();
      },
      {
        variant: 'ghost',
        small: true,
        icon: isMuted() ? 'mute' : 'sound',
        title: isMuted() ? t('hud.unmute') : t('hud.mute'),
      },
    );
    sound.classList.add('hud-sound');
    // The Settings page can flip sound too; keep the button's face in step.
    onSettingsChange(() => {
      sound.innerHTML = iconSvg(isMuted() ? 'mute' : 'sound', 18);
      sound.title = isMuted() ? t('hud.unmute') : t('hud.mute');
    });
    this.hud.append(
      el('div', { class: 'hud-row' }, [el('div', { class: 'hud-resources' }, badges), sound]),
    );
  }

  // -- the world map ------------------------------------------------------------

  private onZonePressed(key: string): void {
    if (this.state.screen !== 'world' || this.state.menu) return;
    const zone = this.sim.world.zones[key];
    if (!zone || zone.state === 'fog') return;
    if (zone.state === 'claimed' && !zone.noSettlement) {
      this.openSettlement(zone.settlementId);
      return;
    }
    this.set({ zone: { key, party: [] } });
  }

  /** The zone the map should outline, if any. */
  get selectedZone(): string | null {
    return this.state.screen === 'world' ? (this.state.zone?.key ?? null) : null;
  }

  // -- frame ------------------------------------------------------------------

  /** Runs every frame. */
  tick(dtSeconds: number): void {
    const forge = this.state.forge;
    if (this.state.screen === 'forge' && forge && !this.state.menu) {
      forge.puzzle.step(dtSeconds);
      if (forge.puzzle.completed && !forge.outcome) {
        const piece = this.sim.craft(
          forge.recipeId,
          forge.puzzle.success,
          forge.puzzle.failures,
          MAX_FAILURES,
        );
        const definition = piece?.definition;
        forge.outcome = { success: piece !== null, pieceName: definition?.name ?? null };
      }
      const shape = `${forge.puzzle.started}|${forge.puzzle.completed}|${forge.outcome !== null}`;
      if (shape !== this.forgeShape) {
        this.forgeShape = shape;
        this.render();
      }
    }

    this.toastNewEntries();

    if (this.sim.revision !== this.drawnRevision) this.render();
    this.updateHud();
    this.updateLive();
  }

  private updateHud(): void {
    const resources = this.sim.world.resources;
    for (const id of RESOURCE_ORDER) {
      const nodes = this.hudValues.get(id);
      if (!nodes) continue;
      const amount = id === 'heroes' ? this.sim.world.heroes.length : resources[id];
      const value = formatNumber(amount);
      const perTick = this.yields[id] ?? 0;
      const yieldText = perTick === 0 ? '' : t('hud.per_tick', { amount: formatYield(perTick) });
      const key = `${value}|${yieldText}`;
      if (this.hudShown.get(id) === key) continue;
      this.hudShown.set(id, key);
      nodes.value.textContent = value;
      nodes.yieldNode.textContent = yieldText;
      nodes.yieldNode.classList.toggle('negative', perTick < 0);
    }
  }

  private updateLive(): void {
    for (const node of this.liveClocks) {
      const key = node.dataset.clock;
      if (!key) continue;
      const seconds =
        key === RECRUIT_CLOCK ? this.sim.secondsToFreeRefresh() : this.sim.clearingSecondsLeft(key);
      const text = formatClock(seconds);
      if (node.textContent !== text) node.textContent = text;
    }
    const forge = this.state.forge;
    if (forge && this.state.screen === 'forge') {
      const feedback = t(forge.puzzle.feedback);
      const progress = forge.puzzle.progress();
      const progressText = t(progress.key, progress.params);
      if (this.liveForge.feedback && this.liveForge.feedback.textContent !== feedback) {
        this.liveForge.feedback.textContent = feedback;
      }
      if (this.liveForge.progress && this.liveForge.progress.textContent !== progressText) {
        this.liveForge.progress.textContent = progressText;
      }
    }
  }

  // -- rendering --------------------------------------------------------------

  /**
   * Replace a container's children, but only if the new markup differs from the old.
   *
   * The UI state is part of what is compared, not just the markup: the handlers
   * on a skipped rebuild are the old ones, so two states that happened to draw
   * identically must still count as different.
   */
  private patch(container: HTMLElement, nodes: Node[]): boolean {
    const fresh = el('div', {}, nodes);
    const { forge, confirm, ...rest } = this.state;
    const stateKey = JSON.stringify({
      ...rest,
      forge: forge ? [forge.recipeId, forge.puzzle.kind, forge.outcome] : null,
      confirm: confirm?.title ?? null,
      settlement: this.sim.world.activeSettlementId,
    });
    const html = `${stateKey}\n${fresh.innerHTML}`;
    if (this.lastHtml.get(container) === html) return false;
    this.lastHtml.set(container, html);
    container.replaceChildren(...Array.from(fresh.childNodes));
    return true;
  }

  private render(): void {
    this.drawnRevision = this.sim.revision;
    this.yields = yieldPreview(this.sim.world);
    this.hudShown.clear();
    this.fallBackIfLocked();

    const screen = this.state.screen;
    this.stage?.setAttribute('data-screen', screen);
    this.panels.classList.toggle('over-canvas', CANVAS_SCREENS.has(screen));

    this.patch(this.nav, this.renderNav());

    // A field being typed into is left alone: rebuilding it would drop the caret.
    const active = document.activeElement;
    const editing =
      active instanceof HTMLInputElement &&
      (active.type === 'text' || active.type === 'range') &&
      this.page.contains(active);
    if (!editing && this.patch(this.page, this.renderScreen())) this.collectLive();

    const overlay: Node[] = [];
    if (this.state.menu) overlay.push(renderMenu(this, this.activeSlot > 0));
    if (this.state.away && !this.state.menu) overlay.push(this.renderAway(this.state.away));
    if (this.state.confirm) overlay.push(this.renderConfirm(this.state.confirm));
    this.patch(this.overlay, overlay);
    document.body.classList.toggle('menu-open', this.state.menu !== null);

    this.updateHud();
    this.updateLive();
  }

  private collectLive(): void {
    this.liveClocks = [...this.page.querySelectorAll<HTMLElement>('[data-clock]')];
    this.liveForge = {
      feedback: this.page.querySelector<HTMLElement>('[data-live="forge-feedback"]'),
      progress: this.page.querySelector<HTMLElement>('[data-live="forge-progress"]'),
    };
  }

  /** A screen whose building was torn down falls back to the roster, as it did in Godot. */
  private fallBackIfLocked(): void {
    const world = this.sim.world;
    const screen = this.state.screen;
    if (screen === 'recruit' && !isRecruitmentUnlocked(world)) this.go('heroes');
    else if (screen === 'craft' && !isCraftingUnlocked(world)) this.go('heroes');
    else if (screen === 'debug' && !settings().showDebug) this.go('world');
  }

  private renderNav(): Node[] {
    const world = this.sim.world;
    return NAV.filter((item) => {
      if (item.screen === 'recruit') return isRecruitmentUnlocked(world);
      if (item.screen === 'craft') return isCraftingUnlocked(world);
      if (item.screen === 'debug') return settings().showDebug;
      return true;
    }).map((item) => {
      const current =
        item.screen === this.state.screen ||
        (item.screen === 'overview' && this.state.screen === 'settlement') ||
        (item.screen === 'heroes' && this.state.screen === 'hero') ||
        (item.screen === 'craft' && this.state.screen === 'forge');
      const node = button(
        t(item.label),
        () => {
          if (item.screen === 'menu') this.set({ menu: 'root' });
          else this.go(item.screen);
        },
        { variant: 'ghost', icon: item.icon, selected: current },
      );
      node.classList.add('nav-item');
      if (current) node.setAttribute('aria-current', 'page');
      return node;
    });
  }

  private renderScreen(): Node[] {
    switch (this.state.screen) {
      case 'world':
        return renderWorld(this);
      case 'settlement':
        return renderSettlement(this);
      case 'overview':
        return renderOverview(this);
      case 'recruit':
        return renderRecruit(this);
      case 'heroes':
        return renderHeroes(this);
      case 'hero':
        return renderHero(this);
      case 'inventory':
        return withTitle('page.inventory', renderInventory(this));
      case 'craft':
        return renderCraft(this);
      case 'forge':
        return renderForge(this);
      case 'saves':
        return withTitle('page.save_vault', renderSaves(this));
      case 'log':
        return withTitle('page.log', renderLog(this));
      case 'debug':
        return withTitle('page.debug', renderDebug(this));
      case 'settings':
        return withTitle('page.settings', renderSettings(this));
    }
  }

  private renderConfirm(request: ConfirmRequest): HTMLElement {
    const close = () => this.set({ confirm: null });
    return modal(
      request.title,
      [el('p', { text: request.body })],
      [
        button(t('common.back'), close, { variant: 'ghost' }),
        button(
          request.confirm,
          () => {
            this.state.confirm = null;
            request.onConfirm();
            this.render();
          },
          { variant: request.danger ? 'danger' : 'primary' },
        ),
      ],
      close,
    );
  }

  // -- toasts -----------------------------------------------------------------

  /** Log kinds worth interrupting the player for. */
  private static readonly TOASTED = new Set<LogEntry['kind']>([
    'victory',
    'defeat',
    'broken',
    'wounded',
    'restored',
    'healed',
    'level',
    'slate',
  ]);

  /** Toast whatever the log gained since the last frame. */
  private toastNewEntries(): void {
    const fresh = logSince(this.sim.world, this.lastLogSeen);
    if (fresh.length === 0) return;
    this.lastLogSeen = fresh[fresh.length - 1]!.id;
    for (const entry of fresh) {
      if (!Shell.TOASTED.has(entry.kind)) continue;
      const lines =
        entry.kind === 'victory' || entry.kind === 'defeat' ? entry.details.map(detailText) : [];
      if (settings().toasts) this.showToast(entryTitle(entry), lines, entry.kind);
      playFor(entry.kind);
    }
  }

  /** Show the welcome-back dialog, if the absence was long enough to be worth one. */
  showAway(summary: AwaySummary): void {
    if (summary.awayMs < 60_000 || !settings().awaySummary) return;
    this.set({ away: summary });
  }

  private renderAway(summary: AwaySummary): HTMLElement {
    const close = () => this.set({ away: null });
    const hours = Math.floor(summary.awayMs / 3_600_000);
    const minutes = Math.floor((summary.awayMs % 3_600_000) / 60_000);
    return modal(
      t('away.title'),
      [
        el('p', { text: t('away.duration', { hours, minutes }) }),
        summary.simulatedMs < summary.awayMs
          ? el('p', {
              class: 'muted small',
              text: t('away.capped', { hours: Math.round(summary.simulatedMs / 3_600_000) }),
            })
          : null,
        el('p', { class: 'label', text: t('away.gained') }),
        resourceList(summary.resources, 'yield'),
        el('p', { class: 'muted small', text: t('away.events', { count: summary.events }) }),
      ],
      [
        button(
          t('away.open_log'),
          () => {
            this.state.away = null;
            this.go('log');
          },
          { variant: 'ghost' },
        ),
        button(t('common.close'), close, { variant: 'primary' }),
      ],
      close,
    );
  }

  private showToast(title: string, lines: string[], kind = ''): void {
    const node = el(
      'div',
      { class: `toast ${kind ? `toast-${kind}` : ''}`.trim(), role: 'status' },
      [el('strong', { text: title }), ...lines.map((line) => el('span', { text: line }))],
    );
    this.toasts.append(node);
    while (this.toasts.children.length > 3) this.toasts.firstElementChild?.remove();
    window.setTimeout(() => {
      node.classList.add('leaving');
      window.setTimeout(() => node.remove(), 300);
    }, TOAST_MS);
  }

  // -- keyboard ---------------------------------------------------------------

  private onKey(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      if (this.state.confirm) this.set({ confirm: null });
      else if (this.state.menu && this.state.menu !== 'root') this.set({ menu: 'root' });
      else if (this.state.menu && this.activeSlot > 0) this.set({ menu: null });
      else if (this.state.zone) this.set({ zone: null });
      else if (this.state.assign) this.set({ assign: null });
      else if (this.state.heroPiece !== null) this.set({ heroPiece: null });
      else if (this.state.selectedSlot >= 0) this.set({ selectedSlot: -1 });
      return;
    }

    const forge = this.state.forge;
    if (
      this.state.screen !== 'forge' ||
      !forge ||
      forge.outcome ||
      this.state.menu ||
      this.state.confirm
    )
      return;
    if (event.target instanceof HTMLInputElement || event.repeat) return;
    const puzzle = forge.puzzle;
    const primary = event.key === ' ' || event.key === 'Enter';
    if (primary && !puzzle.started) {
      event.preventDefault();
      puzzle.start();
      this.render();
      return;
    }
    let handled = true;
    if (primary && puzzle instanceof TimingStrike) puzzle.strike();
    else if (primary && puzzle instanceof BellowsRhythm) puzzle.pump();
    else if (
      puzzle instanceof HeatBalance &&
      (event.key === 'ArrowUp' || event.key === 'ArrowRight')
    )
      puzzle.stoke();
    else if (
      puzzle instanceof HeatBalance &&
      (event.key === 'ArrowDown' || event.key === 'ArrowLeft')
    )
      puzzle.vent();
    else if (puzzle instanceof EdgeSharpening && event.key === 'ArrowLeft') puzzle.nudge(-1);
    else if (puzzle instanceof EdgeSharpening && event.key === 'ArrowRight') puzzle.nudge(1);
    else handled = false;
    if (handled) event.preventDefault();
  }
}

function withTitle(key: string, nodes: Node[]): Node[] {
  return [el('h2', { class: 'page-title', text: t(key) }), ...nodes];
}
