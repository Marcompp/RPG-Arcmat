# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RPG-Arcmat is a Godot 4.4 turn-based RPG. All scripts are in GDScript (`.gd`). The database is entirely JSON-driven, loaded at runtime.

## Lore Reference

Full world-building reference (characters, regions, factions, artifacts, themes, tone) lives in [`LORE.md`](LORE.md). Consult it before writing any in-world text: event dialogue, item descriptions, location flavor text, or NPC lines.

Full game design philosophy (tone, combat design, content guidelines, regional structure) lives in [`DESIGN.md`](DESIGN.md). Consult it before adding new gameplay systems, enemies, or areas.

Event writing conventions, anti-patterns, branching rules, and NPC voice guidelines live in [`EVENTS.md`](EVENTS.md). Consult it before writing or editing any event.

## Running the Project

Open in the Godot 4.4 editor and press **F5** to run. There is no build step — Godot compiles GDScript at runtime.

- **F5** in-game: Quick save to current slot
- **F9** in-game: Quick load current slot

There is no test suite or linter — validate changes by running the game in Godot.

## Architecture

### Autoloads (Singletons)

Defined in `project.godot`, these are globally accessible from any script:

- **EventBus** (`scripts/Globals/EventBus.gd`) — Pub-sub system; use `EventBus.emit(...)`, `EventBus.subscribe(...)`, `EventBus.await_event(...)` for cross-system communication.
- **InputRouter** (`scripts/Globals/InputRouter.gd`) — Stack-based input context routing; all player input flows through here.
- **SaveManager** (`scripts/Managers/SaveManager.gd`) — Serializes/deserializes game state to `user://saves/`.
- **SettingsManager** (`scripts/Managers/SettingsManager.gd`) — Persists player preferences.

### Central Controller

**`GameManager.gd`** is the master orchestrator (~1185 lines). It:
- Loads all JSON databases into dictionaries at startup (`weapon_db`, `monster_db`, `spell_db`, etc.)
- Owns the `game_state` Dictionary (single source of truth)
- Manages the top-level game mode state machine: `MAIN_MENU → CHARACTER_SELECT → TRAVEL → COMBAT → REST`
- Instantiates and coordinates all child managers

### Game State

`game_state` is a Dictionary on GameManager containing:
```gdscript
{
  "player": Character,      # Current Character instance
  "gold": int,
  "region": String,
  "vars": {},               # Dynamic scripting variables
  "flags": {},              # One-shot event triggers
  "visited_nodes": {},      # Exploration tracking
  "area_progress": {},      # Per-region progress
  "used_events": {}         # Prevents event replay
}
```

### Gameplay Systems

| Manager | Responsibility |
|---|---|
| `CombatManager.gd` | Turn-based combat state machine (PLAYER_TURN → CHOOSING_ACTION → ENEMY_TURN → RESOLUTION → END) |
| `CombatCalculator.gd` | Damage, accuracy, element multipliers |
| `CombatStatusSystem.gd` | Status effect tracking (stun, freeze, DoT, stat mods) |
| `CombatMenuBuilder.gd` | Builds combat UI action choices |
| `TravelManager.gd` | World map navigation, node transitions, backdrop changes |
| `EventReader.gd` | Parses and executes event trees from `events.json` |
| `DialogueSystem.gd` | Presents event dialogue and player choices |
| `InventoryManager.gd` | Item/equipment/trinket UI and logic |
| `TownManager.gd` | Town interactions |
| `ShopManager.gd` | Buy/sell commerce |
| `TrinketSystem.gd` | Applies trinket special effects |
| `AudioManager.gd` | BGM and SFX |

### Character Model

`Character.gd` is the player/enemy data entity:
- Base and final stats: HP, MP, Str, Int, Agi, Dex, Lck, Def
- Equipment slots (weapons, armor, trinkets)
- Inventory
- Level/stat growth via randomized rolls
- Status effect multipliers applied at calculation time

### Database Layer

All game data lives in `Database/` as JSON files loaded at startup. The two largest files drive most content:

- **`events.json`** (~102KB) — Event and dialogue trees with conditions, branching, and actions
- **`area_nodes.json`** (~69KB) — World map node definitions with text, choices, and scripted actions

Other databases: `monsters.json`, `weapons.json`, `skills.json`, `spells.json`, `armors.json`, `trinkets.json`, `items.json`, `status.json`, `element.json`, `regions.json`, `towns.json`, `protags.json`, `audio.json`.

### Data Flow

```
Input → InputRouter → GameManager / TravelManager / CombatManager
                           ↓
                      EventBus (pub-sub) → UI / Character updates
                           ↓
                      game_state Dictionary  ←→  SaveManager
                           ↓
                   JSON database lookups (weapon_db, monster_db, etc.)
```

### Key Patterns

- **Event-driven**: Systems communicate through EventBus signals, not direct references where possible.
- **State machine**: Both GameManager (game modes) and CombatManager (combat phases) use explicit enum-based state machines.
- **Data-driven content**: Adding new monsters, skills, weapons, events, or areas means editing JSON — not GDScript.
- **SaveManager** serializes the full `game_state` plus RNG state (for replayability) and metadata (character name/level for slot display).
