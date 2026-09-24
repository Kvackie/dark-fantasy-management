/**
 * Small DOM builders shared by every panel.
 *
 * Deliberately plain: no framework, no virtual DOM. A panel is rebuilt from
 * scratch and swapped in only if its markup actually changed — see
 * `Shell.render` — which at this size is cheaper than diffing and much easier
 * to reason about.
 */

import { formatNumber, formatYield, t, titleCase } from '@/i18n';
import { iconSvg, initials } from '@/ui/icons';
import { resourceColors, statColors, workStatColors } from '@/ui/theme';
import { RESOURCE_ORDER, type ResourceMap } from '@/sim/types';

type Child = Node | string | null | undefined | false;

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  children: Child[] = [],
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === 'class') node.className = value;
    else if (key === 'html') node.innerHTML = value;
    else if (key === 'text') node.textContent = value;
    else node.setAttribute(key, value);
  }
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    node.append(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

export function icon(name: string, size = 18, extraClass = ''): HTMLElement {
  return el('span', { class: `icon-wrap ${extraClass}`.trim(), html: iconSvg(name, size) });
}

export interface ButtonOptions {
  variant?: 'primary' | 'danger' | 'ghost' | 'tab';
  disabled?: boolean;
  small?: boolean;
  selected?: boolean;
  title?: string;
  icon?: string;
  /** Fire on pointer-down rather than click — for the forge, where timing is the game. */
  onPress?: boolean;
}

export function button(
  label: string,
  onClick: () => void,
  options: ButtonOptions = {},
): HTMLButtonElement {
  const classes = ['btn'];
  if (options.variant) classes.push(options.variant);
  if (options.small) classes.push('small');
  if (options.selected) classes.push('selected');
  const node = el('button', { class: classes.join(' '), type: 'button' }, [
    options.icon ? icon(options.icon, options.small ? 14 : 16) : null,
    label ? el('span', { text: label }) : null,
  ]);
  if (options.disabled) node.disabled = true;
  if (options.title) node.title = options.title;
  if (options.selected) node.setAttribute('aria-pressed', 'true');
  if (options.onPress) {
    node.addEventListener('pointerdown', (event) => {
      event.preventDefault();
      onClick();
    });
    // Keyboard presses still arrive as clicks with no pointer behind them.
    node.addEventListener('click', (event) => {
      if (event.detail === 0) onClick();
    });
  } else {
    node.addEventListener('click', (event) => {
      event.stopPropagation();
      onClick();
    });
  }
  return node;
}

export function heading(text: string, level: 2 | 3 | 4 = 3, extraClass = ''): HTMLElement {
  return el(`h${level}`, { class: extraClass, text });
}

export function muted(text: string, extraClass = ''): HTMLElement {
  return el('p', { class: `muted ${extraClass}`.trim(), text });
}

export function card(children: Child[], extraClass = ''): HTMLElement {
  return el('div', { class: `card ${extraClass}`.trim() }, children);
}

/** A label-over-value box, as the Godot panels drew level and worker counts. */
export function infoChip(label: string, value: string): HTMLElement {
  return el('div', { class: 'info-chip' }, [
    el('span', { class: 'info-label', text: label }),
    el('span', { class: 'info-value', text: value }),
  ]);
}

export type AmountStyle = 'plain' | 'cost' | 'refund' | 'yield';

/**
 * A row of resource amounts in their own colours.
 *
 * Costs read as negatives and refunds as positives, as they did in Godot;
 * anything the settlement does not track still shows, in plain text colour.
 */
export function resourceList(
  values: ResourceMap,
  style: AmountStyle = 'plain',
  canPay?: (id: string, amount: number) => boolean,
): HTMLElement {
  const known = RESOURCE_ORDER.filter((id) => (values[id] ?? 0) !== 0);
  const extra = Object.keys(values).filter(
    (id) => !(RESOURCE_ORDER as readonly string[]).includes(id) && values[id] !== 0,
  );
  const ids: string[] = [...known, ...extra];
  if (ids.length === 0) return el('span', { class: 'muted', text: t('common.none') });
  return el(
    'span',
    { class: 'resource-list' },
    ids.map((id) => {
      const amount = values[id] ?? 0;
      let shown: string;
      if (style === 'cost') shown = `-${formatNumber(Math.abs(amount))}`;
      else if (style === 'refund') shown = `+${formatNumber(Math.abs(amount))}`;
      // A yield can be fractional: a gem every ten ticks is +0.1.
      else if (style === 'yield') shown = formatYield(amount);
      else shown = formatNumber(amount);
      const short = canPay ? !canPay(id, Math.abs(amount)) : false;
      const node = el('span', { class: `amount${short ? ' short' : ''}` }, [
        el('span', { class: 'amount-icon', html: iconSvg(id, 14) }),
        el('span', { text: `${resourceName(id)} ${shown}` }),
      ]);
      node.style.color = resourceColors[id] ?? '';
      return node;
    }),
  );
}

export function resourceName(id: string): string {
  const key = `resource.${id}`;
  const translated = t(key);
  return translated === key ? titleCase(id) : translated;
}

export function statName(id: string): string {
  const key = `stat.${id}`;
  const translated = t(key);
  return translated === key ? titleCase(id) : translated;
}

/** A labelled value, coloured for the stat it is. */
export function statRow(label: string, value: string, statId?: string): HTMLElement {
  const valueNode = el('span', { class: 'stat-value', text: value });
  const color = statId ? (statColors[statId] ?? workStatColors[statId]) : undefined;
  if (color) valueNode.style.color = color;
  return el('div', { class: 'stat-row' }, [
    el('span', { class: 'stat-label', text: label }),
    valueNode,
  ]);
}

export function workStatsLine(stats: Record<string, number>): HTMLElement {
  return el(
    'span',
    { class: 'work-line' },
    (['farming', 'mining', 'lumbering'] as const).map((key) => {
      const node = el('span', { text: `${t(`work.${key}`)} ${stats[key] ?? 0}` });
      node.style.color = workStatColors[key] ?? '';
      return node;
    }),
  );
}

/** A hero's face: initials on a disc tinted by class, since the portraits are not in the repo. */
export function heroAvatar(
  name: string,
  heroClass: string,
  size: 'small' | 'large' = 'small',
): HTMLElement {
  return el('span', {
    class: `avatar avatar-${size} class-${heroClass.toLowerCase()}`,
    text: initials(name),
    'aria-hidden': 'true',
  });
}

/** A modal dialog over the stage. `onClose` runs on the backdrop, the close button and Escape. */
export function modal(
  title: string,
  body: Child[],
  footer: Child[],
  onClose: () => void,
  options: { subtitle?: string; wide?: boolean } = {},
): HTMLElement {
  const dialog = el(
    'div',
    {
      class: `dialog${options.wide ? ' wide' : ''}`,
      role: 'dialog',
      'aria-modal': 'true',
      'aria-label': title,
    },
    [
      el('header', { class: 'dialog-header' }, [
        el('div', {}, [
          el('h3', { text: title }),
          options.subtitle ? el('p', { class: 'muted small', text: options.subtitle }) : null,
        ]),
        button('', onClose, {
          variant: 'ghost',
          icon: 'close',
          small: true,
          title: t('common.close'),
        }),
      ]),
      el('div', { class: 'dialog-body' }, body),
      footer.length ? el('footer', { class: 'dialog-footer' }, footer) : null,
    ],
  );
  const backdrop = el('div', { class: 'backdrop', 'data-modal': 'true' }, [dialog]);
  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) onClose();
  });
  return backdrop;
}

/** A tick box with a label, for choosing heroes. */
export function checkRow(
  checked: boolean,
  disabled: boolean,
  onToggle: (checked: boolean) => void,
  content: Child[],
): HTMLElement {
  const input = el('input', { type: 'checkbox' });
  input.checked = checked;
  if (checked) input.setAttribute('checked', '');
  input.disabled = disabled;
  input.addEventListener('change', () => onToggle(input.checked));
  return el(
    'label',
    { class: `check-row${checked ? ' checked' : ''}${disabled ? ' disabled' : ''}` },
    [input, ...content],
  );
}
