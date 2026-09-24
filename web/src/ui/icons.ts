/**
 * Placeholder art: small line icons drawn in the colour of the text around them.
 *
 * The Godot build's painted assets are not in the repository, so everything
 * that had a picture gets a silhouette instead — buildings, resources, gear
 * slots, heroes. Each icon is a fragment on a 24×24 grid, stroked in
 * `currentColor`, so it takes the colour of whatever it sits in.
 */

const ICONS: Record<string, string> = {
  // resources
  wood: '<path d="M4 8h13a3.5 4 0 0 1 0 8H4a3.5 4 0 0 1 0-8Z"/><ellipse cx="17" cy="12" rx="1.6" ry="2"/><path d="M7 10.5h6M6 13.5h5"/>',
  food: '<path d="M4 15c0-4.5 3.6-7.5 8-7.5s8 3 8 7.5v3H4Z"/><path d="M9 11l-1 3M12.5 10.5v3.5M16 11l1 3"/>',
  stone: '<path d="M6 5h11l4 7-4 8H6l-3-8Z"/><path d="M9 9l3 3 4-2M12 12v6"/>',
  gold: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4.5"/>',
  heroes: '<path d="M5 20v-7a7 7 0 0 1 14 0v7h-4v-5H9v5Z"/><path d="M12 6v4"/>',
  gems: '<path d="M7 4h10l4 6-9 11L3 10Z"/><path d="M3 10h18M9 4l-2 6 5 11 5-11-2-6"/>',
  crystals: '<path d="M12 2l4 7-4 13-4-13Z"/><path d="M8 9h8"/>',

  // buildings
  gathering_lodge: '<path d="M3 12L12 4l9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-5h4v5"/>',
  farm: '<path d="M3 20h18"/><path d="M6 20V11M12 20V8M18 20V11"/><path d="M6 11l-2-2M6 11l2-2M12 8l-2-2M12 8l2-2M18 11l-2-2M18 11l2-2"/>',
  quarry: '<path d="M4 7c4-3 12-3 16 0"/><path d="M12 5.5V21"/><path d="M3 21l5-6h8l5 6"/>',
  lumber_camp: '<path d="M12 3l6 8h-3l4 5H5l4-5H6Z"/><path d="M12 16v5"/>',
  smithy: '<path d="M4 8h14l-2 4h-3v3l3 4H8l3-4v-3H8C6 12 4 10.5 4 8Z"/><path d="M19 8h2"/>',
  triage: '<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6Z"/>',
  barracks: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6Z"/><path d="M12 7v10M8 11h8"/>',
  tavern:
    '<path d="M5 6h10v14H5Z"/><path d="M15 9h2.5a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H15"/><path d="M8 9v8M12 9v8"/>',
  empty_plot: '<path d="M4 16l8 4 8-4-8-4Z"/><path d="M12 4v8M9 7l3-3 3 3"/>',

  // equipment slots
  head: '<path d="M5 17v-5a7 7 0 0 1 14 0v5"/><path d="M4 17h16"/><path d="M9 12h6"/>',
  chest: '<path d="M8 4l4 2 4-2 4 3-2 4v9H6v-9L4 7Z"/><path d="M12 6v14"/>',
  gloves: '<path d="M7 21v-8l-2-3 1-1 3 2V5h2v6-7h2v7-6h2v7-5h2v10l-2 4Z"/>',
  boots: '<path d="M8 3h6v10l6 3v4H6v-7l2-2Z"/><path d="M6 17h14"/>',
  amulet: '<path d="M5 3c0 6 3 9 7 9s7-3 7-9"/><path d="M12 12l4 4-4 5-4-5Z"/>',
  ring: '<circle cx="12" cy="14" r="6"/><path d="M9 5h6l-1.5 3h-3Z"/>',

  // navigation
  world:
    '<circle cx="12" cy="12" r="9"/><path d="M12 3v18M3 12h18"/><path d="M15 9l-2 4-4 2 2-4Z"/>',
  settlements: '<path d="M4 21V9l3-2 3 2v12M14 21V6l3-3 3 3v15M4 21h16"/><path d="M10 13h4"/>',
  recruit:
    '<path d="M5 6h10v14H5Z"/><path d="M15 9h2.5a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H15"/><path d="M8 9v8M12 9v8"/>',
  inventory: '<path d="M3 9h18v11H3Z"/><path d="M3 9l2-4h14l2 4"/><path d="M10 13h4"/>',
  craft: '<path d="M4 8h14l-2 4h-3v3l3 4H8l3-4v-3H8C6 12 4 10.5 4 8Z"/><path d="M19 8h2"/>',
  debug:
    '<circle cx="12" cy="12" r="3.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
  saves: '<path d="M6 3h9l4 4v14H6Z"/><path d="M15 3v4h4M9 12h7M9 16h7"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  target: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/>',
  item: '<path d="M6 8l6-4 6 4v8l-6 4-6-4Z"/><path d="M6 8l6 4 6-4M12 12v8"/>',
};

export function hasIcon(name: string): boolean {
  return name in ICONS;
}

/** An inline SVG icon, `size` pixels square, in the surrounding text colour. */
export function iconSvg(name: string, size = 18): string {
  const body = ICONS[name] ?? ICONS.item!;
  return `<svg class="icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
}

/** Initials for a hero with no portrait: "Mara the Grave Forager" → "MG". */
export function initials(name: string): string {
  const words = name.split(/[\s-]+/).filter((word) => /^[A-Z]/.test(word) && word !== 'The');
  const letters = (words.length > 1 ? [words[0], words[words.length - 1]] : words).map((w) =>
    (w ?? '').charAt(0),
  );
  return letters.join('') || name.charAt(0).toUpperCase();
}
