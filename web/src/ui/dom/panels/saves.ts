/**
 * The Save Vault inside a game, the Debug page, and the main menu overlay.
 */

import { formatDate, t } from '@/i18n';
import { button, card, el, heading, muted } from '../components';
import type { Ui } from '../context';

function slotName(ui: Ui, slot: number): string {
  return ui.saves.summary(slot).name || t('save.slot_default_name', { slot });
}

export function renderSaves(ui: Ui): Node[] {
  const slots = ui.saves.slots();
  const out: Node[] = [
    muted(t('save.description')),
    el('div', { class: 'button-row' }, [
      button(t('save.new_slot'), () => ui.saveTo(ui.saves.nextNewSlot()), {
        variant: 'ghost',
        small: true,
      }),
    ]),
  ];
  for (const slot of slots) {
    const summary = ui.saves.summary(slot);
    const input = el('input', {
      type: 'text',
      class: 'text-input',
      placeholder: t('save.slot_heading', { slot }),
      value: summary.name,
      'aria-label': t('save.name_placeholder'),
      maxlength: '40',
    });
    const commit = () => {
      if (input.value.trim() !== summary.name) {
        ui.saves.rename(slot, input.value);
        ui.set({});
      }
    };
    input.addEventListener('change', commit);
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') input.blur();
    });
    out.push(
      card(
        [
          el('div', { class: 'card-title' }, [
            el('strong', { text: t('save.slot_heading', { slot }) }),
            slot === ui.activeSlot ? el('span', { class: 'badge', text: t('save.active') }) : null,
          ]),
          input,
          summary.savedAt
            ? muted(t('save.last_autosave', { date: formatDate(summary.savedAt) }), 'small')
            : null,
          muted(
            t('save.summary_line', {
              ticks: summary.tickCount,
              heroes: summary.heroCount,
              settlements: summary.settlementCount,
            }),
            'small',
          ),
          el('div', { class: 'button-row' }, [
            button(
              t('save.button_save'),
              () =>
                ui.ask({
                  title: t('save.confirm_save_title', { slot }),
                  body:
                    slot === ui.activeSlot
                      ? t('save.confirm_save_body_active')
                      : t('save.confirm_save_body'),
                  confirm: t('save.button_save'),
                  onConfirm: () => ui.saveTo(slot),
                }),
              { variant: 'primary', small: true },
            ),
            slot === ui.activeSlot
              ? null
              : button(
                  t('save.button_load'),
                  () =>
                    ui.ask({
                      title: t('menu.load_confirm', { name: slotName(ui, slot) }),
                      body: t('menu.load_warning'),
                      confirm: t('save.button_load'),
                      onConfirm: () => ui.loadSlot(slot),
                    }),
                  { variant: 'ghost', small: true },
                ),
          ]),
        ],
        slot === ui.activeSlot ? 'active' : '',
      ),
    );
  }
  return out;
}

export function renderDebug(ui: Ui): Node[] {
  const section = (title: string, rows: Array<[string, string, () => void]>) =>
    card([
      heading(title, 4),
      ...rows.flatMap(([text, label, action]) => [
        muted(text, 'small'),
        button(label, () => ui.act(action), { small: true }),
      ]),
    ]);
  return [
    muted(t('debug.intro')),
    el('div', { class: 'card-grid' }, [
      section(t('debug.resources_title'), [
        [
          t('debug.resources_text'),
          t('debug.resources_button'),
          () => ui.sim.debugGrantResources(),
        ],
      ]),
      section(t('debug.heroes_title'), [
        [t('debug.recruit_text'), t('debug.recruit_button'), () => ui.sim.debugRecruitRandomHero()],
        [t('debug.xp_text'), t('debug.xp_button'), () => ui.sim.debugGrantHeroExperience()],
      ]),
      section(t('debug.inventory_title'), [
        [t('debug.items_text'), t('debug.items_button'), () => ui.sim.debugGrantRandomItems()],
        [
          t('debug.equipment_text'),
          t('debug.equipment_button'),
          () => ui.sim.debugGrantRandomEquipment(),
        ],
      ]),
      section(t('debug.time_title'), [
        [t('debug.ticks_text'), t('debug.ticks_button'), () => ui.sim.debugProgressTicks()],
      ]),
    ]),
  ];
}

/** The main menu: over everything at boot, and from the nav at any time. */
export function renderMenu(ui: Ui, canResume: boolean): HTMLElement {
  const mode = ui.state.menu;
  const body: Node[] = [];
  if (mode === 'saves') {
    const slots = ui.saves.slots();
    if (slots.length === 0) body.push(muted(t('menu.no_saves')));
    for (const slot of slots) {
      const summary = ui.saves.summary(slot);
      const name = summary.name || t('save.slot_default_name', { slot });
      body.push(
        card([
          el('strong', { text: name }),
          summary.lastPlayed
            ? muted(t('menu.last_played', { date: formatDate(summary.lastPlayedAt) }), 'small')
            : null,
          muted(
            t('save.summary_line', {
              ticks: summary.tickCount,
              heroes: summary.heroCount,
              settlements: summary.settlementCount,
            }),
            'small',
          ),
          el('div', { class: 'button-row' }, [
            button(
              t('save.button_load'),
              () =>
                ui.ask({
                  title: t('menu.load_confirm', { name }),
                  body: t('menu.load_warning'),
                  confirm: t('save.button_load'),
                  onConfirm: () => ui.loadSlot(slot),
                }),
              { variant: 'primary', small: true },
            ),
            button(
              t('menu.delete'),
              () =>
                ui.ask({
                  title: t('menu.delete_confirm', { name }),
                  body: t('menu.delete_warning'),
                  confirm: t('menu.delete'),
                  danger: true,
                  onConfirm: () => {
                    ui.saves.delete(slot);
                    if (slot === ui.activeSlot) ui.startNewGame();
                    else ui.set({});
                  },
                }),
              { variant: 'danger', small: true },
            ),
          ]),
        ]),
      );
    }
    body.push(button(t('common.back'), () => ui.set({ menu: 'root' }), { variant: 'ghost' }));
  } else {
    const last = ui.saves.lastPlayedSlot();
    if (canResume)
      body.push(button(t('menu.resume'), () => ui.set({ menu: null }), { variant: 'primary' }));
    body.push(
      button(t('menu.new_game'), () => ui.startNewGame(), canResume ? {} : { variant: 'primary' }),
      button(t('menu.continue'), () => ui.loadSlot(last), { disabled: last <= 0 }),
      button(t('menu.load_save'), () => ui.set({ menu: 'saves' })),
    );
  }

  return el('div', { class: 'menu-overlay' }, [
    el('div', { class: 'menu-panel' }, [
      el('h1', { class: 'menu-title', text: t('game.title') }),
      el('p', {
        class: 'muted menu-subtitle',
        text: mode === 'saves' ? t('menu.load_save') : t('game.tagline'),
      }),
      el('div', { class: 'menu-body' }, body),
    ]),
  ]);
}
