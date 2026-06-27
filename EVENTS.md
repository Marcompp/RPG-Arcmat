# EVENTS.md

Event writing reference for RPG-Arcmat. Consult this before writing or editing any event in `events.json` or `area_nodes.json`. For world-building specifics (character names, faction lore, region details), see [`LORE.md`](LORE.md). For broader design philosophy, see [`DESIGN.md`](DESIGN.md).

---

## Event design best practices

Try to limit the amount of times the player has to press continue overall. Usually just before a `text` that clears the screen is the most appropriate place to leave `no_continue`:`false` (which is the default), or when a deliberate pause is desired.
`text` commands followed by `choice` commands should have `no_wait`:`true` (which is like `no_continue`, except the next command doesn't even wait for the text to type)

Whenever an event does something that affects the UI (ie: damage or giving gold, etc), the command should immediatelly preceed the text announcement, as to make them happen in synch.

In most cases, there's no need to explain what happens to an enemy after it's defeated, specially if it doesn't survive. Going straight from a battle to `show node` is preferable to placing a `text` with "The enemy fell down, dead" between them - especially for regular enemies

Every event tree should end with either a `show_node` event, `show_node_text` + `show_node_actions`, just `show_node_actions`, or some sort of command that moves the player (`exit` or `to_town`)
`show_node` is used when the event text should clear after execution (most cases)
`show_node_text` (with `clear`:false) + `show_node_actions` should be used when the event ends with only a small amount of text on-screen that doesn't need to be cleared, adding to the node text
just `show_node_actions` should be used when the event never clear text once, usually when it's just a single atmospheric paragraph 

Try to make events as reusable and readable as possible, by using the `event` command instead of repeating commands or making very complex inline trees

**What sorts of things are events:**
- Random Events: random occurrences that happen while travelling: meeting someone, finding something, being found by enemies, getting lost, etc
They are alternatives for encountering enemies outright. Some types of random encounters include: avoidable fights with the region's enemies, quick atmospheric flourishes with no gameplay implications, optional oportunities to engage with something on the way, NPC encounters, etc
There are also events that are guaranteed to happen in a node, IE: running into treasure in a treasure room. In this case, the event node is meant to be a setpiece/atraction by itself, turning the node into an event node -> an optional boss fight, some valuable loot, an optional town, an enemy encampment, etc.

- Node Actions: optional interactions with the node itself's features, IE: drinking the water at a spring, etc
By chosing the action, the player has already chosen to engage with the event, so no need for confirmation
They are less special than random events, and will be seen by more players, so they should either be brief and simple conveniences (ie: a basic heal), or have many outcomes.
They should generally have worse benefits than random events on average, and only be repeatable (as defined in area_nodes) if not abusable.
They greatly contribute to the identity of the node.

- Node Exit Events: those are complications on the way out of the current location -- before reaching the next node. They happen in response to the chosen exit, IE: if the player chose to cross a bridge, the bridge might be dangerous. They either give a risk to travel, or change the player's destination

- Town Exit Events: for main towns, those are story events where the main characters interact. For optional towns, they involve being ambushed on the way out somehow.

**One-time events & state tracking**

`repeatable: false` on the event entry prevents the encounter system from selecting that event again. `mark_used` + a condition check is for when *other* parts of the tree need to know the event already happened. These serve different purposes and are often both needed.

Always place `mark_used` **before** the event body — if the player saves and quits mid-event, the state is already committed:
```json
{"type": "if", "condition": {"my_event_done": 0}, "then": [
  {"type": "mark_used", "event": "my_event_done"},
  ...body...
], "else": [...repeat or skip...]}
```

**Variable & naming conventions**

Use `vars` for all dynamic state. `flags` is legacy — do not use in new events.

Naming: `noun_verb` or `noun_done` — lowercase, underscore-separated, long enough to be unambiguous across regions.
- Good: `cabin_drawer_done`, `bridge_toll_paid`, `cultist_sermon_heard`
- Avoid: `x`, `done`, `flag1`, or anything generic enough to collide with another region's events

For explicit assignments use object syntax: `{"set": N}`. Reserve bare numbers for increments: `{"add": 1}`.

Use `0` (not `false`) for "not yet happened" — `set_var` stores integers; mixing the two for the same var across events is confusing even though the engine treats both as falsy.

**Conditions**

Check all gating conditions at the **top** of the tree, before any actions fire.

Use `lacks_item` / `lacks_skill` / `lacks_spell` to gate item and skill rewards — this is the primary enforcement mechanism for the loot philosophy (players should never receive duplicates).

Compound logic: a plain object `{"a": 1, "b": 2}` is AND. Use `{"any": [{...}, {...}]}` for OR.

**Branching & choices**

Choice `key` values should be semantic: `"fight"`, `"flee"`, `"yes"`, `"no"`, `"open"`, `"leave"`.

Every key listed in `choices` must have a matching entry in `branches`. Missing keys fall through silently — the player gets no output and no error is raised.
`choices` with `type`: `back` are special, being able to act as fifth choices thanks to their special spot in the choice layout. They are meant to represent refusal or cancelling or going back 

If an `if`/`else` tree goes 3+ levels deep, extract inner branches into separate named events called via `{"type": "event"}`. Flat trees are readable; deeply nested JSON is not.

**Combat**

If you want winning to be optional specify `on_defeat`. Omitting it triggers game over.

Multi-stage combats: chain sequential `combat` steps inside `on_victory`. Each stage is its own step, not nested inside the previous victory branch.

**Random outcomes**

Use `stat_weights` to tie probability to player stats: `{"lck": 1}` adds the player's LCK to that outcome's weight at runtime. Use `lck` for lucky finds, `dex` for evasion-flavored outcomes.

For reference, the average stat for the player should be considered about 6 in Apple Woods, and go up 2 per region travelled.

Put a `condition` on individual outcomes to exclude impossible results (e.g., `{"lacks_item": "Rainbow Apple"}` on an apple-reward outcome prevents the player from receiving a duplicate).

Weights are relative — they don't need to sum to 100. A `2 / 6 / 4` split is fine.

**Anti-patterns to avoid**

- **Circular `event` references** without a `mark_used` guard will loop until the game crashes.
- **Type inconsistency:** don't check `{"my_var": false}` in one event and `{"my_var": 0}` in another for the same variable. Use `0` throughout.
- **Effect after announcement:** `give_gold`, `effect`, and `give_item` must immediately *precede* their text announcement, not follow it.

**Writing & tone**

Every event should contribute at least one of: atmosphere, lore, loot, mechanical consequence, or meaningful player agency. An event that does none of these is filler.

Use sensory language for scene-setting: smell, sound, texture, temperature. "The cave smells of wet stone and old fire" is a place. "The cave is dark and ominous" is a description of nothing. Don't try to get to poetic or metaphorical. Placed should only smell of things that have a smell, etc.

Avoid generic lines. Even throwaway NPCs should sound like someone with a role and a mood — not "Safe travels" or "Move along." One specific detail (a verbal tic, a grievance, an occupation) makes a line land.

No fourth-wall breaks, no jokes that directly acknowledge this is a game. Absurd things happen and are treated as real by the world. The narration can be funny, and somewhat self-aware, but not in a way that takes away from the world.

Tonal consistency within an event: a grim body-horror encounter shouldn't end with a punchline. A comedic NPC shouldn't die off-screen and pivot to tragedy without setup. Shifts in tone need to be earned.

When something lucky/unlucky happens, a brief exclamation such as "How lucky!" can add to the tone. Projected interiority is fine if not taken too seriously. IE: as something to add a bit of irony to failure states, or very lightly lampshade an absurd event. Ex: Adding something like "...That certainly happened," after an improbable sequence of events.

AVOID cheap gravitas ie: something like "The cold that thinks is worse than the cold that simply is" means absolutely nothing.
Most events are just normal occurences, that happen to actual people sometimes in over their head, not dramatic metaphors happening to purple-prose prone pretentious idiots.
Avoid nonsense metaphors and too much personification of innanimate concepts.

**Choices & player agency**

Each branch of a choice should lead somewhere meaningfully distinct — different outcomes, different flavor, different rewards, or a different part of the world. That said, a choice with the same outcomes, but different ways of determining it (such as using different stats) is fine too, so long as it's telegraphed.

Avoid false choices: if all branches converge immediately to the same result, collapse them into a single path and remove the choice, unless that's the joke.

Include a non-violent option where the fiction supports it. Peaceful resolutions are valid and can be mechanically rewarded.

"Do you want to do X? Yes / No" with No leading straight back to `show_node` is fine if context requires for it. (Exception: Action Events, where the player already chose to engage.)

**Failure states**

Most failures should be soft: HP damage, lost gold, a narrative setback, a door that doesn't open, a battle against a regular enemy.

Permanent consequences — joining a faction, consuming a unique item, an irreversible story flag — should be telegraphed before they lock in. Give the player one clear moment to understand the cost before it's committed. Same for fighting a boss in a battle that could result in a Game Over.

**NPC & character voice**

Named NPCs have consistent voices across all their events. If Bo is enthusiastic and verbose, he should sound that way every time. If a boss is cold and assured, they don't suddenly crack jokes.

The player characters have distinct personalities. Events that branch on `player_name` should reflect those personalities in the writing — not just swap a name into a generic line. Agnes is sharp and competitive; Borin is stubborn, protective and grounded; Chala is emotional and naive; Danil is lighthearted and morally ambiguous.

Antagonists can be hammy, but still menacing. They can be exuberant or eccentric, but not in ways that diminish them as credible threats.

**Environmental storytelling**

Found objects — journals, inscriptions, tools, furnishings — should tell a story through specifics. A journal that ends mid-sentence implies death more powerfully than stating the author died. A dented shield implies a fight; a pristine one implies it was never used.

The world has layered history. Events in old places should suggest what came before: deliberate geometry, tools for an unfamiliar trade, inscriptions in a dead language. The current inhabitants don't need to explain it.

Don't describe what the player already knows. Don't recap the region they're in or explain game mechanics through event text.

The narration shouldn't be too omniscient, or tell things that require too much context to conclude. IE: ruins might depict carvings of Trolls, but they shouldn't be explicitly called ruins of Troll-make, unless that's already been established by something preceeding it.

**Scope & length**

Events should be as long as they need to be. A random forest stumble doesn't need five steps of atmospheric setup. A first visit to a significant location does.

If a single branch exceeds ~8 steps, ask whether the event is doing too much — consider splitting the inner sequence into a named sub-event called via `{"type": "event"}`.

Short events can still have voice. Two lines that are specific and grounded beat five lines of generic atmosphere.

---

## Random Events
Usually start with a single text sentence with `clear=false`, announcing the subject of the event IE: "You see something up ahead."
If no imediate choice is required, then `no_continue` is false, and the event will continue with a more detail text with `clear`:`true` (which is the default)

## Action Events
Start with a clearing text.
There's no need for 'Do you want to do X' type choices at the start, because the player chose to do the event

## Exit Events
Always end with some sort of movement command
