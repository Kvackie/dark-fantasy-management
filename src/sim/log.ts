/**
 * The event log: what happened, newest last.
 *
 * Capped, so a long game does not grow its save without end. Entries carry
 * i18n keys rather than finished text; the Log screen and the toasts render them.
 */

import type { LogEntry, LogKind, World } from './types';

export const LOG_LIMIT = 300;

type Params = Record<string, string | number>;

export function addLog(
  world: World,
  kind: LogKind,
  key: string,
  params: Params = {},
  details: LogEntry['details'] = [],
): LogEntry {
  const entry: LogEntry = {
    id: world.nextLogId,
    tick: world.tickCount,
    kind,
    key,
    params,
    details,
  };
  world.nextLogId += 1;
  world.log.push(entry);
  if (world.log.length > LOG_LIMIT) world.log.splice(0, world.log.length - LOG_LIMIT);
  return entry;
}

/** Entries newer than `afterId`, oldest first. */
export function logSince(world: World, afterId: number): LogEntry[] {
  return world.log.filter((entry) => entry.id > afterId);
}
