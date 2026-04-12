# Game Overview

- Settlement builder with a light roster/world layer, not a combat game yet.
- Core loop is: build structures on a 3x3 settlement grid, assign heroes, wait for ticks, spend output to expand.
- Production runs every 2 seconds and is the main source of progress.
- Heroes matter mostly as workers and world-clearing units; their combat stats are mostly data/UI for now.
- World map expansion is fog-of-war based: clear a zone, pay claim cost, get a new settlement, reveal nearby zones.
- Recruitment is the mid-loop unlock: build a Tavern, then buy heroes from the recruit market.
- Equipment mainly boosts hero stats/work stats and feeds the hero detail/inventory loop.

# How It Works

- `DataLoader` loads all static content from `data/*.json` plus optional `user://mods/...` catalogs.
- `GameSession` owns runtime/save data: resources, settlement slot grids, heroes, inventory, recruit offers, world zones, active settlement, save slots.
- `GameManager` is the gameplay authority on top of `GameSession`: building, upgrading, assignment, recruitment, world clearing/claiming, ticking, save/load, autosave, signal emission.
- `MainScreen` is the root UI shell. It auto-loads save slot 1, listens to `GameManager` signals, and swaps between settlement mode and page modes.
- Settlement view is local to `active_settlement_id`; top-bar resources and yield preview are empire-wide.
- `WorldScreen` + `WorldView` handle map interaction. `WorldView` only renders/selects; `WorldScreen` runs the popup flow and calls `GameManager`.
- `HeroDetailScreen` is the hero inspector/editor for equipment and dismissal.
- `SettlementSlot` and `HeroCard` are dumb widgets; they render data and emit selection signals.

# Key Flows

- Startup/save flow: `MainScreen` tries `GameManager.load_game(1)` on boot -> if no save, `GameManager` emits fresh default state -> game starts with `The Hollow March`, starting resources, starter items, and starter equipment.
- Settlement loop: click a slot -> build a structure if empty or manage it if built -> assign/move/unassign heroes -> next ticks add production to global resources.
- Recruitment loop: build at least one Tavern anywhere -> Recruit page appears -> offers seed/replenish automatically -> pay recruit cost -> hero instance is added to the roster.
- World expansion loop: pick a discovered zone -> choose up to 3 idle/unassigned heroes -> zone enters `clearing` for several ticks -> when done, pay claim cost -> zone becomes a new owned settlement and reveals nearby zones.
- Equipment loop: open a hero -> pick a fixed equipment slot -> choose matching inventory equipment -> equip/unequip updates both hero stats and reverse ownership on the inventory item.

# Gotchas

- Boot always targets save slot 1 first. "New game" only happens if slot 1 is missing or reset.
- `GameManager` expects a node/autoload literally named `GameSession`; renaming that breaks state access.
- `get_available_heroes_for_slot()` does not really filter; the UI shows already-assigned heroes too and treats them as movable.
- Claimed settlements are a mix of one authored start settlement and generated settlements from world zones.
- Inventory items exist, but the real economy uses `resources`; items are mostly inventory/UI content right now.

# TODO

- Combat is mostly scaffolded through hero/equipment stats; there is no real combat loop yet.
- Hero skills tab is placeholder UI for now.
- Add the ability to setup special zones that can be randomly generated into the loop.
- Make a use for inventory items.
- Give equipment bonuses that affect other parts of gameplay loop.
