/**
 * The shared visual language: soot, ember and old gold.
 *
 * One palette for both halves of the UI. The DOM reads the CSS custom
 * properties in `main.css`; the Phaser scenes read these numbers. The colours
 * are the Godot build's own, lifted from its theme and widget styles.
 */

export const palette = {
  bgPage: 0x0d0b0c,
  bgPanel: 0x151214,
  bgRaised: 0x1c1618,
  bgInset: 0x100d0e,
  border: 0x47362f,
  borderStrong: 0x8b6d57,
  text: 0xe6ddd3,
  textDim: 0xcbbba9,
  textFaint: 0x8d8478,
  accent: 0xd0a170,
  accentWarm: 0xf0d0a8,
  good: 0x74c476,
  danger: 0xcf4f4f,
  marker: 0xf7efe3,
} as const;

export function cssHex(color: number): string {
  return `#${color.toString(16).padStart(6, '0')}`;
}

export const resourceColors: Record<string, string> = {
  wood: '#b98b60',
  food: '#d4a25c',
  stone: '#b7bcc7',
  gold: '#f0cc66',
  heroes: '#d8778f',
  gems: '#73b5ff',
  crystals: '#7dd7ff',
};

export const workStatColors: Record<string, string> = {
  farming: '#93be73',
  mining: '#8db0d8',
  lumbering: '#b38b5e',
};

export const statColors: Record<string, string> = {
  health: '#d8847b',
  sanity: '#c8b8d9',
  attack: '#d0a170',
  defense: '#88a8c8',
  critical_chance: '#f0c96c',
  critical_damage: '#e5b86f',
};

/** Map tile fills, per the Godot world view: state first, then biome for settled ground. */
export const biomeColors: Record<string, number> = {
  starting_zone: 0x4f3426,
  forest: 0x4f8a4f,
  mountain: 0x4b4f57,
  plains: 0xc8b64f,
  mixed: 0x7fb7d9,
  crystal_cavern: 0x8d7be0,
  neutral: 0xb28a6a,
};

export const zoneStateColors = {
  fog: 0xefefec,
  discovered: 0xa84a46,
  clearing: 0xc98142,
} as const;

/** Forge bar gradients, as colour stops across the bar. */
export const forgeColors = {
  cold: 0x8f4d2d,
  warm: 0xd08b4f,
  hot: 0xff8a2f,
  core: 0xff1f1f,
  ember: 0xe06b35,
  red: 0xd23a2f,
  safe: 0x74c476,
  danger: 0xc44d3c,
} as const;
