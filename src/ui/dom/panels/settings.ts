/**
 * The Settings page: sound, notices, the map, saving, and clearing it all.
 *
 * Shown as a screen from the nav, and inside the main menu before a game is
 * running. Preferences live in `ui/settings.ts`, not in the save, so they are
 * the same in every game on this browser.
 */

import { t } from '@/i18n';
import { play } from '@/ui/sound';
import { AUTOSAVE_CHOICES, resetSettings, settings, updateSettings } from '@/ui/settings';
import { button, checkRow, el, heading, muted } from '../components';
import type { Ui } from '../context';
import { versionLine } from '../version';

function section(title: string, rows: Node[]): HTMLElement {
  return el('section', { class: 'settings-section' }, [heading(title, 3), ...rows]);
}

function toggle(label: string, hint: string, value: boolean, onChange: (v: boolean) => void) {
  return checkRow(value, false, onChange, [
    el('span', { class: 'check-main' }, [
      el('strong', { text: label }),
      muted(hint, 'small setting-hint'),
    ]),
  ]);
}

/**
 * A 0–100 slider. It saves on every move so the sound follows the thumb, and
 * the shell leaves a focused slider alone when it redraws.
 */
function level(id: string, label: string, value: number, onChange: (v: number) => void) {
  const output = el('output', { class: 'setting-value', for: id, text: `${value}%` });
  const input = el('input', {
    id,
    type: 'range',
    min: '0',
    max: '100',
    step: '5',
    value: String(value),
  });
  input.addEventListener('input', () => {
    output.textContent = `${input.value}%`;
    onChange(Number(input.value));
  });
  return el('div', { class: 'setting-level' }, [
    el('label', { for: id, text: label }),
    input,
    output,
  ]);
}

export function renderSettings(ui: Ui): Node[] {
  const s = settings();
  const set = (patch: Parameters<typeof updateSettings>[0]) => {
    updateSettings(patch);
    ui.set({});
  };

  const sound = section(t('settings.sound'), [
    toggle(t('settings.sound_on'), t('settings.sound_on_hint'), s.sound, (v) => set({ sound: v })),
    level('setting-music', t('settings.music'), s.music, (v) => updateSettings({ music: v })),
    level('setting-effects', t('settings.effects'), s.effects, (v) => {
      updateSettings({ effects: v });
      play('click');
    }),
  ]);

  const notices = section(t('settings.notices'), [
    toggle(t('settings.toasts'), t('settings.toasts_hint'), s.toasts, (v) => set({ toasts: v })),
    toggle(t('settings.away'), t('settings.away_hint'), s.awaySummary, (v) =>
      set({ awaySummary: v }),
    ),
  ]);

  const map = section(t('settings.map'), [
    toggle(t('settings.mist'), t('settings.mist_hint'), s.mist, (v) => set({ mist: v })),
  ]);

  const saving = section(t('settings.saving'), [
    el('div', { class: 'setting-choice' }, [
      el('strong', { text: t('settings.autosave') }),
      muted(t('settings.autosave_hint'), 'small setting-hint'),
      el(
        'div',
        { class: 'button-row', role: 'group', 'aria-label': t('settings.autosave') },
        AUTOSAVE_CHOICES.map((seconds) =>
          button(
            t('settings.every_seconds', { seconds }),
            () => set({ autosaveSeconds: seconds }),
            { variant: 'tab', small: true, selected: s.autosaveSeconds === seconds },
          ),
        ),
      ),
    ]),
    toggle(t('settings.debug'), t('settings.debug_hint'), s.showDebug, (v) =>
      set({ showDebug: v }),
    ),
  ]);

  const data = section(t('settings.data'), [
    muted(t('settings.data_hint'), 'small'),
    el('div', { class: 'button-row' }, [
      button(
        t('settings.reset'),
        () =>
          ui.ask({
            title: t('settings.reset_confirm'),
            body: t('settings.reset_warning'),
            confirm: t('settings.reset'),
            onConfirm: () => {
              resetSettings();
              ui.set({});
            },
          }),
        { variant: 'ghost', small: true },
      ),
      button(
        t('settings.wipe'),
        () =>
          ui.ask({
            title: t('settings.wipe_confirm'),
            body: t('settings.wipe_warning'),
            confirm: t('settings.wipe'),
            danger: true,
            onConfirm: () => ui.wipeAll(),
          }),
        { variant: 'danger', small: true },
      ),
    ]),
  ]);

  return [el('div', { class: 'settings' }, [sound, notices, map, saving, data, versionLine()])];
}
