# Dark Fantasy Settlement — web

A browser recreation of the Godot game in this repository, built on the same stack as
Eternal Alchemy: **Vite + TypeScript + Phaser 4**, with DOM panels over the canvas, saves in
`localStorage`, a Vitest suite, Prettier, and a GitHub Pages deploy.

## Running it

```
cd web
npm install
npm run dev        # http://localhost:5173
```

| Script | Does |
| --- | --- |
| `npm run dev` | Dev server |
| `npm run build` | Type check, then production bundle into `web/dist/` |
| `npm run preview` | Serve the production bundle |
| `npm test` | Run the simulation test suite |
| `npm run typecheck` | Type check without building |
| `npm run format` | Format every file with Prettier |
| `npm run format:check` | Fail if any file is not formatted — the deploy runs this |

## Playing it on GitHub Pages

`.github/workflows/pages.yml` (at the repository root) checks formatting, runs the tests,
builds `web/`, and publishes `web/dist/` on every push to `master`. Switch Pages on once under
**Settings → Pages → Build and deployment → Source: GitHub Actions**; the site then lands at
`https://<owner>.github.io/dark-fantasy-management/`. `vite.config.ts` sets `base: './'` so every
asset path is relative and the same build works at that subpath or at a domain root.

The save lives in the browser, so it is per-browser and per-origin: the Pages copy and a local
`npm run dev` copy are different games.

## How it's put together

The one structural rule, as in Eternal Alchemy: **the simulation never imports the engine.**

```
web/src/
  sim/        Pure TypeScript. Every rule in the game. No Phaser, no DOM, no wall clock.
  i18n/       Strings, keyed. data/ui_text.json is the base; en.json adds the rest.
  ui/
    phaser/   The world map and the forge.
    dom/      The shell (resource bar, nav, dialogs, toasts, main menu) and one panel per screen.
  platform/   Save slots over localStorage.
```

The content is **not copied**: `sim/config.ts` imports the repository's top-level `data/*.json`
through the `@data` alias, so the Godot build and the web build read the same numbers. The
`web/` folder carries a `.gdignore`, so the Godot editor does not scan it (or `node_modules`).

**Phaser draws what it is good at** — the pannable, zoomable zone map and the forge bar — and
the DOM gets everything that is text and lists. The two halves talk only through the simulation
and `ui/bus.ts`.

**Time** runs in two-second ticks, as in Godot. The frame loop hands the simulation real elapsed
milliseconds and it runs every tick they pay for. A browser stops the frame loop in a background
tab, so a returning tab catches up on up to an hour of missed ticks — roughly what the desktop
build did by simply staying open.

**Randomness is seeded** and the generator's state is in the save. The map itself is hashed
from the world seed and each zone's coordinates, so biomes, names, claim costs and loot are
fixed per world however it is explored.

**The forge puzzles** are small state machines in `sim/puzzles.ts` with no renderer: the shell
steps them each frame and feeds them button presses (or Space and the arrow keys), and
`ForgeScene` only draws what it reads back. That keeps their timing rules under test.

## What carried over

Everything in the Godot game loop: the 8-plot home settlement; building, upgrading and
dismantling (80% refund); production per tick with level and work-stat multipliers; staffing
with work-stat requirements; the Triage and Barracks; the recruit market (tavern-gated, gem
heroes at tavern level 3, refresh cost, bonus recruits from cleared zones); the fog-of-war world
map with party requirements, clearing timers, rewards, claiming, biome-shaped settlements and
crystal caverns; equipment and effective stats; the Smithy's recipes and the four forge puzzles
(Timing Strike, Heat Balance, Bellows Rhythm, Edge Sharpening) with quality-scaled rolls; hero
detail with info, equipment, skills and lore tabs and dismissal; inventory; named save slots with
autosave every 12 seconds; the main menu; and the Debug page.

## What is different

- **Placeholder art.** The painted assets are not in the repository, so buildings, resources,
  gear slots and heroes use line icons and initials. Nothing else depends on them.
- **No mods or Exit button.** A web page has no `user://mods` folder to read and no process to
  quit. The Godot-only Rune Alignment and Material Sorting puzzles, which no recipe used, were not
  ported.
- **Triage charges once.** The Godot build took each patient's gold twice per tick — once as
  "production" and once when healing. It is taken once here, when healing.
- **A claimed crystal cavern opens its own dialog** (its reward and status). In Godot the press
  tried to open it as a settlement and did nothing.
- **Saves are not interchangeable** with the Godot build's.

Some reward tables and one recipe name items that are not in `data/items.json` (`rations`,
`grave_coin`, `veil_crystal`, `timber_bundle`) and equipment ids that are not in
`data/equipment.json`. As in Godot, those rewards are skipped and the Iron Brow recipe cannot be
paid for; the data, shared by both builds, is left as it is.
