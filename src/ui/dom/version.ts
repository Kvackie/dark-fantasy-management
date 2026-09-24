/**
 * Which build is running: the version from package.json, the commit it was
 * built from, and the day. Shown on the main menu and in Settings, so a report
 * of a problem can say exactly which deploy it came from.
 */

import { t } from '@/i18n';
import { el } from './components';

export function versionLine(extraClass = ''): HTMLElement {
  const date = new Date(`${__BUILD_DATE__}T00:00:00Z`).toLocaleDateString('en', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
  const parts = [t('version.label', { version: __APP_VERSION__ }), __APP_COMMIT__, date];
  return el('p', {
    class: `muted small version-line ${extraClass}`.trim(),
    text: parts.filter(Boolean).join(' · '),
  });
}
