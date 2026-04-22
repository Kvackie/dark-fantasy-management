# Dark Fantasy Settlement

`Dark Fantasy Settlement` is a Godot 4 project for a dark-fantasy settlement builder with a light hero roster and world-expansion layer.

The current game loop focuses on building structures, assigning heroes, processing production ticks, recruiting new heroes, and clearing nearby world zones to found additional settlements.

## Overview

- Build and upgrade structures on an 8-slot settlement grid.
- Assign heroes to buildings to improve work output and unlock progression.
- Gain resources every 2 seconds through the production tick system.
- Expand across a fog-of-war world map by clearing and claiming zones.
- Unlock recruitment through the Tavern and grow the hero roster.
- Equip heroes and level them over time through passive progression systems.

This is currently a management-first prototype. Combat stats and equipment exist, but there is no full combat loop yet.

## Current Gameplay Loop

1. Start in `The Hollow March` with a small pool of resources.
2. Build resource and support buildings in the settlement grid.
3. Assign heroes to production or utility buildings.
4. Let ticks generate resources and apply building effects.
5. Build a Tavern to unlock the recruit market.
6. Clear nearby zones with idle heroes.
7. Claim cleared zones to expand your settlements.

## Main Systems

### Settlement Management

- The starting settlement has 8 building plots.
- Buildings can be constructed, upgraded, and staffed.
- Production and upkeep are driven by data in `data/buildings.json`.

### Heroes

- Heroes have classes, combat stats, work stats, XP, and equipment slots.
- Work stats matter for assignment and economic progression.
- Growth values can be fixed or randomized from ranges and are stored per hero.

### World Expansion

- The world uses a fog-of-war style zone map.
- Zones move through `discovered -> clearing -> cleared -> claimed` states.
- Claimed zones can become settlements or special reward areas.

### Recruitment

- Recruitment unlocks once at least one Tavern is built.
- The recruit market offers heroes based on data-driven definitions.
- Refresh costs and offer capacity are configured in `data/recruitment.json`.

### Inventory and Equipment

- Inventory data exists for items and equipment.
- Equipment affects hero stats and supports the hero-detail loop.
- Inventory items are present, but the main economy currently runs on `resources`.

### Saves and Mods

- Save slots are stored under `user://`.
- The project supports content mods for heroes, items, and equipment.
- Optional mod folders are loaded from:
  - `user://mods/heroes`
  - `user://mods/items`
  - `user://mods/equipment`

## Tech Stack

- Engine: Godot `4.6`
- Renderer: `GL Compatibility`
- Target resolution: `1280x720`
- Main scene: `res://scenes/main/main.tscn`

## Autoloads

The project depends on these autoloads defined in `project.godot`:

- `GameManager`
- `DataLoader`
- `GameSession`
- `ModBootstrap`

`GameManager` expects the session autoload to be named exactly `GameSession`.

## Project Structure

```text
assets/                UI, building, and resource art
data/                  JSON-driven game content and tuning
resources/themes/      Shared UI theme resources
scenes/                Main UI, world view, and reusable widget scenes
scripts/components/    Small gameplay components
scripts/data/          Data loading and mod bootstrap
scripts/game/          Runtime state and gameplay authority
scripts/ui/            Main screens and page controllers
scripts/widgets/       Reusable UI widgets
```

## Key Files

- `project.godot`: project config, autoloads, display setup
- `scripts/game/game_manager.gd`: main gameplay authority and signal hub
- `scripts/game/game_session.gd`: runtime state, save handling, autosave
- `scripts/data/data_loader.gd`: loads core data and optional mods
- `scripts/ui/main_screen.gd`: root UI shell and page navigation
- `scripts/ui/world_screen.gd`: world-map interaction and clearing flow
- `data/buildings.json`: building definitions, costs, production, worker slots
- `data/heroes.json`: hero roster definitions and stat baselines
- `data/world.json`: zone generation, reveal rules, claim costs, special biomes

## Running The Project

1. Open the project in Godot 4.6.
2. Load `project.godot`.
3. Run the main scene, or just press Play in the editor.

The game starts from `res://scenes/main/main.tscn`.

## Data-Driven Content

Most of the game is configured through JSON files in `data/`:

- `buildings.json`
- `settlements.json`
- `world.json`
- `recruitment.json`
- `heroes.json`
- `items.json`
- `equipment.json`
- `ui_text.json`

This makes it easy to tune progression and add content without changing core game flow.

## Current Limitations

- No full combat gameplay loop yet.
- Hero skills are placeholder UI.
- Some systems are scaffolded ahead of full gameplay use.
- Boot flow targets save slot `1` first.

## Notes

This repository is currently focused on clarity and iteration speed: small components, data-driven content, and a UI-first gameplay loop built around settlement growth and controlled expansion.
