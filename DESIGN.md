# DESIGN.md

Game design philosophy and content guidelines for RPG-Arcmat. Consult this before adding new gameplay systems, enemies, events, or areas. For world-building specifics (character names, faction lore, region details), see [`LORE.md`](LORE.md).

---

## Tone & Voice

The world is **grounded and sensory** — descriptions prioritize smell, sound, and physical sensation over spectacle. Absurdist moments happen and are accepted without breaking immersion; the world doesn't wink at the player.

NPC voices are tied to role and faction:
- Merchants have verbal tics that signal their personality (repetition, warmth, professional detachment).
- Bosses speak with cold certainty and theatric.
- Ambient NPCs react to the transaction, not the protagonist.

Environmental storytelling is preferred over exposition: found journals, carved inscriptions, headstones, architectural details. The world existed before the player arrived and will exist after.

---

## Core Gameplay Loops

**Travel loop:** 
Seven regions, broken down in nodes:
Upon arrival in a node the player can encounter an enemy or a random event (one-time interactions, random encounters, optional secrets)
At a node the player has four options:
*TRAVEL* - each node has one to four possible exits
Each exit has a progress value, upon reaching a progress threshold, the player will arrive in a TERMINAL node, which will contain a boss fight, followed by travel to the next region or town
*ACTION* - action unique to each node
*INVENTORY* 
*REST* - way to quit the game

**Town loop:**
Each town has a multiple of four locations (shops, pubs, misc) and an exit.
Choosing to leave the town will often lead to an event (usually a boss fight), before going to the next region

**Combat loop:** `PLAYER_TURN → CHOOSING_ACTION → (CHOOSING SKILL/SPELL/ITEM) → (CHOOSING_TARGET) → RESOLUTION`. Status effects and trinket procs layer onto the base attack/skill/magic/item structure.
During turn, the player has four options:
*Attack* -- basic attack using weapon (may be changed via trinket)
*Skill* -- learned skills - each skill has an individual cooldown
*Spell* -- learned spells - each spell has a mana cost
*Item* -- consumable items

**Progression loop:** Level up → stat growth (randomized rolls, not fixed) → new equipment/spells/skills from shops/drops/events.

**UI:**
Current region is displayed at the top-center of the screen
Player information is persistent at all times on the top left: (Name, Class, Lvl, HP, MP, Status, Gear, Element, Exp) and should always remain up to date
Living enemy information is persistent during battle on the top right: (Name, Lvl, HP, MP, Status, Gear, Element, Time to act) and should always remain up to date. Currently, there's only room for two enemies at a time
Current gold is displayed on the top left, next to player panel (for now)
The entire center of the screen is reserved for text
The button of the screen is reserved for choices (a header, four buttons in a grid, plus the back button and the two arrows to scroll through more choices when applicable)
Log button on the bottem left
Option button on the bottom right

---

## Combat Design Philosophy

The player controls only one character.
There can be up to two enemies in battle at a time. (for now)


**Stats**:
- *HP*: health - pretty much all enemies should all have an HP TrueStat since it exists in a different scale to other stats and should scale much harder
- *MP*: used to cast spells. Current MP also determines resistence to enemy spells
- *STR*: determines damage from physical attacks
- *INT*: determines damage from magical attacks
- *AGI*: mitigates enemy accuracy, determines turn order
- *DEX*: determines accuracy and crit chance, mitigates action wgt when determining turn order
- *DEF*: resistence to enemy physical attacks
- *LCK*: mitigates enemy accuracy and crit chance, increases odds of good random outcomes in events

**Enemy telegraphing:** Enemies use Startup/Cooldown timers. A visible "preparing" state before any action is taken gives the player room to strategise and prepare. That said, each turn they do act should be impactful. New enemies should design around this — the preparation is the counterplay opportunity.

**Stat grading:** Monster stats use A–F grades in `monsters.json` that map to final numeric values. Use these grades to signal the enemy's threat profile at a glance (e.g., high Str / low Agi = slow hard hitter). Don't assign A across all stats.
This can be overwritten by TrueStats for stats that don't exist in a curve.

**Elemental system — 15 elements:**
- Neutral: Used by human non-mages and most weapons to bypass elemental interactions
- Primary (9): Fire, Water, Wind, Earth, Thunder, Ice, Plant, Dark, Light
- Secondary (5): Metal, Poison, Spirit, Mind, Ether (Don't use for characters)
- Upon using a spell, the user will temporarily take on the spell's element.
- For the purposes of this game, characters and spells can only have one element at a time
- Elements have vulnerabilties, resistences and immunities. Vulnerabilities mean more damage, resistences mean less damage and immunities means much less damage
- Elements are **morally neutral**. Light ≠ good (the Cult of Light is antagonistic; Carlon uses Light). Dark ≠ evil (spirits, ancient magic, death are Dark). Do not assign moral weight to elements when designing enemies or events.

**Difficulty curve:**
- Early (Apple Woods / Caves): Mostly basic enemies and mechanics. Lvls 1~6
- Mid (Sundown / Legory / Core Cavern): Named bosses with unique mechanics (Ringmaster, Necromancer, Icelady, Infrit)
- Late (Swamp / Arcmat): Enemies with unique mechanics, difficult bosses King of the Swamp, Carlon Lvl 20 (signature multi-element boss)

---

## Content Design Principles

### Node design principles

## What is a node
Each region has a few generic nodes that are less specific spots and more like a class of terrain in the region and thus a fairly generic available action IE: a woods node is supposed to represent 'someplace in the woods' not a specific point in the map.

They also have non-repeatable (`"condition": {"visit_count":{"max":0}}`) nodes, that do represent specific spots or landmarks. Those can be event nodes with guaranteed evens and enconter_rate = 0, where there's something that must immediatelly be addressed in the node (ie: it's an enemy camp, so there are enemies), or simply have unique actions where the player interacts with the landmark at their leasure.

Each region also has at least one Terminal node, which is a transitory node between the region and the next, where the boss is fought. The player moves on immediatelly after the boss, and so doesn't really linger in these nodes. 

## Node writing principles
Arrival text and description are always shown together, so should never be redundant, no matter which of which is picked. Arrival text is about giving a sense of place, while description is about adding texture. IE: Arrival tells you, you are at a bridge, while descriptions tells you the water ripples beneath the bridge as it creaks in the wind.


### Unique Mechanics Per Region

Each region should have something structurally distinct from "walk in, fight enemy, walk out":

| Region | Distinctive Element |
|---|---|
| Apple Woods | Apple picking in most nodes, travellers on road, fishing on river/lake |
| Caves of Light | Bask in the Light for MP in most nodes / Cultist events |
| Sundown Plateau | Undead encounters / Dig on surface / Circus trap optional town / Catacombs vs Surface / Graveyard optional boss |
| Mount Legory | Climb up and down the mountain (affects events) / Great Roc optional boss at summit |
| Core Cavern | Lizal civilization, Troll ruins in lava, Mine in mineshaft, hazardous travel sometimes|
| Lost Swamp | Cursed fog, liminal space tone, entry to Arcmat / Lost Woods type area / Arcward optional town |
| Arcmat Ruins | Final dungeon, shifting glyphs, the origin of all magic |

Every (non-terminal) node should have an unique action
Every region should have at least ten or so unique random events spread across its nodes

### Named Items Carry Lore Weight

Equipment names reference their origin. A weapon dropped by a named boss or found in a specific region should feel like it belongs there. The Sword of Maciera is Bertunia's founding artifact — it doesn't just deal damage, it carries history.

### Trinket Design

Most Trinkets should **scale with gameplay state** or enable unique builds and strategies, not just add flat numbers:
- Duelist Glove: scales with consecutive hits
- Hidden Blade: scales with status effects on target
- Woodcutter's Bandana: mercy-save on lethal hit
- Resonant Badge: elemental damage amplifier

New trinkets should follow this pattern — a condition or state that the player can build toward, not a passive +5 to a stat.

### Loot philosophy 
As a rule, the player should be never able to obtain an useless item - weapons or equipment or non-stackable trinkets they already have, spell books and skill scrolls they already have or know, spell books when they already have the cap of spells

---

## Adding New Content

### New Monster (`monsters.json`)

Required fields: `Name`, `Element`, `Level`, `Stats` (A–F grades per stat), `TrueStats` (numeric), `Drops`, `Skills` / `Spells`, `Startup` (turns before first attack), `Cooldown` (turns between attacks), `Location`, `Rarity`.

Design checklist:
- Assign stat grades that tell a story (e.g., fast Agi + low Def = glass cannon)
- At least one telegraphed attack via Startup > 1
- Drops that make sense for where the enemy lives
- Fits the elemental palette of its region

### New Event (`events.json`)

Events use conditional branching on `player_name`, `flags`, `vars`, and `game_state` fields. Structure: top-level event object with `text`, `choices` array, and per-choice `actions` (set flags, give items, trigger combat, start sub-event).

Keep in mind:
- Atmospheric text should use sensory language (sight, sound, smell)
- One-time events use `flags` to prevent replay
- Random encounter events use weighted probability on type

### New Area Node (`area_nodes.json`)

Each node needs: entrances, arrival text (one for each entrance, describing the arrival + standard, the text used for when the player already is in the node), one or more `description` texts for atmosphere (picked at random, should not be redundant with the arrival text), `exits` list with direction and destination ID (`exits` are ways to travel from the node, not ways to interact with it), and one `action` (specific interaction with the node, may be shared by many nodes).
`events` list for events that can be encountered in node (1 means the event is guaranteed), `encounter_rate` to dictate how often enemies appear (if the node is meant to house a guaranteed event, encounter_rate should be 0, since enemies take precedence over events)
Also, optional `backdrop` image and `ambience` sounds, and `enemies` list that overrides the region encounters.

Arrival text convention: plain first sentence describing the arrival ("Walking down the road, you reach the stone bridge."). For standard, something setting the stage ("The bridge groans under your weight. Below, the river smells of iron.").



### New Skill (`skills.json`), Spell (`spells.json`), Item (`items.json`)

Fields: `type` (attack / self), `mgt` (power multiplier), `acc` (accuracy), `crit` (crit chance), `wgt` (weight/priority), `effect` (status to apply), `magnitude` (magnitude of the effect), `chance` (chance of the effect happening), `inherit_stats` (whether the skill takes the character's stats into account), `inherit_wpn` (whether the skill takes the equipped weapon's stats into account).

Skills have `cooldown`, and `startup` (turns before the skill can be used)
Spells have `cost` (MP cost)

---

## Narrative Arc

The journey moves **west to east** across the Rozar Continent, passing through layers of civilization age:

1. **Apple Woods** — sunny fantasy forest; bandits and wildlife
2. **Caves of Light** — a living cult built around natural, not understood power
3. **Sundown Plateau** — burial culture, death as theme, naturally ocurring undeath, necromancers trying to take advantage
4. **Mount Legory** — nature's ancient indifference
5. **Core Cavern** — a hidden civilization (Lizals) living in ruins of an even older one (Trolls)
6. **Lost Swamp** — liminal, cursed, where the known world ends and laws of spatial reality blur
7. **Arcmat Ruins** — the source. Impossibly precise geometry, violet energy, the origin of all magic. Impossibly ancient arcane civilization

Every region contains evidence of a prior civilization. Players walk through historical layers. The Arcmat Ruins resolve the mystery: why does magic exist, and who built what made it possible?

**Post-game (The Arena):** Intentionally unserious, "dubiously canon." A lighthearted space to revisit all enemies with a fully-realized character. Tone here can be playful in a way the main game avoids.
