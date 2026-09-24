# Dark Fantasy Settlement

A grim settlement builder for the browser. Raise a frontier town, staff it with heroes, and push
back the fog. Built with **Vite + TypeScript + Phaser 4**, with DOM panels over the canvas, saves
in `localStorage`, a Vitest suite, Prettier, and a GitHub Pages deploy — the same stack as Eternal
Alchemy.

Play it at **https://kvackie.github.io/dark-fantasy-management/**.

It began as a Godot 4 prototype. The web version replaced it; the Godot project is in this
repository's history up to commit `ca3b808`.

## Running it

```
npm install
npm run dev        # http://localhost:5173
```

| Script | Does |
| --- | --- |
| `npm run dev` | Dev server |
| `npm run build` | Type check, then production bundle into `dist/` |
| `npm run preview` | Serve the production bundle |
| `npm test` | Run the simulation and balance suites |
| `npm run typecheck` | Type check without building |
| `npm run format` | Format every file with Prettier |
| `npm run format:check` | Fail if any file is not formatted — the deploy runs this |

## Deploying

`.github/workflows/pages.yml` checks formatting, runs the tests, builds, and publishes `dist/` to
GitHub Pages on every push to `master`. `vite.config.ts` sets `base: './'`, so every asset path is
relative and the same build works at the project subpath or at a domain root.

The save lives in the browser, so it is per-browser and per-origin: the Pages copy and a local
`npm run dev` copy are different games.

## How it's put together

The one structural rule: **the simulation never imports the engine.**

```
src/
  sim/        Pure TypeScript. Every rule in the game. No Phaser, no DOM, no wall clock.
  data/       JSON. Every tunable number, so balance is diffable in git.
  i18n/       Every user-facing string, keyed, in en.json.
  ui/
    phaser/   The world map and the forge.
    dom/      The shell (resource bar, nav, dialogs, toasts, main menu) and one panel per screen.
  platform/   Save slots over localStorage.
```

**Phaser draws what it is good at** — the pannable, zoomable zone map and the forge bar — and the
DOM gets everything that is text and lists. The two halves talk only through the simulation and
`ui/bus.ts`.

**Time** runs in two-second ticks. The frame loop hands the simulation real elapsed milliseconds
and it runs every tick they pay for.

**Randomness is seeded** and the generator's state is in the save. The map itself is hashed from
the world seed and each zone's coordinates, so biomes, names and claim costs are fixed per world
however it is explored.

**The forge puzzles** are small state machines in `sim/puzzles.ts` with no renderer: the shell
steps them each frame and feeds them button presses (or Space and the arrow keys), and
`ForgeScene` only draws what it reads back. That keeps their timing rules under test.
