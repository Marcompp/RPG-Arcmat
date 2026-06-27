# COMBAT.md

Technical reference and design guide for RPG-Arcmat's combat system. Covers the exact execution flow (`CombatManager.gd`, `CombatCalculator.gd`, `CombatStatusSystem.gd`) and best practices for designing monsters and encounters.

---

## Overall combat system

Combat is turn based. There's always just one player character and one (or in rare cases, two) enemy. The goal for each side is to deplete HP.

Enemies all have startup / cooldown timers for when they act, meaning the player will always get to act a handfull of times for each enemy action. This means enemies should have more HP than player characters for the most part.

Players have four types of actions they can do on their turn: Attack, Skill, Spell, or Item. 
Attacks are always available.
Player Skills have individual startup and cooldowns, meaning they will have to wait x turn to use the skill, then use it again. This prevents the player from spamming just one skill.
Spells cost MP, meaning they have to be used sparringly by the player. They also change the user's element to match the Spell's changing their defensive profile. MP is also the stat used for magical defense, meaning using spells makes you more vulnerable to the enemies, and saving your spells for when the enemy has already used theirs might be worth it.
Items are consumable, meaning the player must manage them across the whole playthrough.

The key to winning should be finding the right mix and order of actions to use between enemy actions.

Actions may inflict stats that have turn durations.

There are also passive effects from Trinkets, which can wildly vary the dynamic of battle.


## Combat State Machine

`CombatManager` tracks a single `state` enum throughout a fight:

| State | Description |
|---|---|
| `PLAYER_TURN` | Transition state — entering the player's decision phase |
| `CHOOSING_ACTION` | Player sees the main menu (Attack / Skill / Magic / Item) |
| `CHOOSING_SKILL` | Player browsing their skill list |
| `CHOOSING_MAGIC` | Player browsing their spell list |
| `CHOOSING_ITEM` | Player browsing their consumable inventory |
| `CHOOSING_TARGET` | Player picking which enemy to hit (multi-enemy fights only) |
| `RESOLUTION` | All actions execute in speed order; player cannot input |
| `END` | Combat is over; rewards or defeat screen |

---

## Turn Flow: Step by Step

### 1. Combat Start (`start_combat`)

Called by `GameManager` with the player `Character` and a single enemy or an array of enemies.

**Naming**: Enemies with duplicate names are renamed with letter suffixes (`Goblin A`, `Goblin B`). This also seeds `_summon_name_counters` so future summons of the same type continue the alphabetic sequence.

**Database loading**: `skills.json`, `spells.json`, `items.json`, `status.json`, `element.json`, and `trinkets.json` are loaded fresh for this combat instance.

**State initialization**:
- `status_effects` → `{ "player": [] }`, one empty array per enemy key (`"enemy_0"`, `"enemy_1"`)
- `cooldowns` → `{ "player": {} }`, one empty dict per enemy key
- `enemy_timers` → each enemy's `Startup` value (turns before first action)
- `enemy_first_actions` → all `true` (controls "Preparing" vs "Recharging" flavor text)
- `enemy_channeling` → all `""` (empty means not currently channeling)
- `_accumulated_rewards` → `{ "xp": 0, "gold": 0, "drops": {} }`
- `_died_enemies` and `_fled_indices` → empty

**Subsystem construction**: `CombatCalculator`, `CombatStatusSystem`, `CombatMenuBuilder`, and one `TrinketSystem` per entity (player; enemies only get one if they have trinkets equipped).

**Startup skill cooldowns**: Any player skill with a `"startup"` field is immediately put on cooldown for `startup + 1` turns — it cannot be used until that many turns have passed.

**Input context**: `MyInputRouter.push(...)` pushes the `"combat"` input context. All player input flows here for the duration of combat.

**Intro sequence**:
1. Show intro text (enemy names + "raring for a fight").
2. Wait for player to press Continue.
3. Execute each enemy's `"Start"` skill (if set) — fires immediately, before the player acts.
4. Execute player trinket battle-start skills.
5. Enter `start_player_turn()`.

---

### 2. Player Turn (`start_player_turn`)

Called at the beginning of every player turn.

1. **Trinket turn-start**: `TrinketSystem.process_turn_start()` runs first, potentially emitting a text message.
2. **Stun/Freeze check**:
   - If the player has an active `stun` or `freeze` status: display the skip message, then go directly to `_resolve_turn_pair` with `{ type: "stunned" }` or `{ type: "frozen" }`. Cooldowns do **not** tick while stunned or frozen.
3. **Cooldown tick**: If not stunned/frozen, all player skill cooldowns decrement by 1.
4. Set state to `CHOOSING_ACTION` and call `render_player_turn()`.

---

### 3. Render Player Turn (`render_player_turn`)

This function both updates enemy timers and displays the combat HUD text before showing the action menu.

**Timer refresh logic** (runs before rendering):
For each living enemy with `enemy_timers[i] < 0` (timer ran out last turn and the enemy already acted):
- Call `_check_channel_trigger(i)` — rolls a weighted ChannelMove from eligible moves.
  - Eligible = `condition == "always"` OR (`condition == "hp_below"` AND current HP% ≤ `threshold`).
  - A random eligible move is selected by weight.
- If a ChannelMove was selected: `enemy_channeling[i] = move.skill`, `enemy_timers[i] = move.duration`.
- If no ChannelMove: clear `enemy_channeling[i]`, reset `enemy_timers[i] = enemy.Cooldown`.

**Timer display**:
| Timer value | Color | Message |
|---|---|---|
| ≤ 0 | Red | `{Enemy} will act this turn!` |
| 1 | Yellow | `{Enemy} will act next turn.` |
| ≥ 2 | Green | `{Enemy} will act in N turns.` |
| ≤ 0 (channeling) | Red | `{Enemy} is about to unleash something!` |
| ≥ 1 (channeling) | Orange | `{Enemy} is channeling... (N)` |

The main menu offers four choices: Attack, Skill, Magic, Item (built by `CombatMenuBuilder`).

---

### 4. Action Selection (Player Input)

**Attack**: Goes to `_maybe_select_target`. If only one enemy is alive, resolves immediately. If multiple enemies are alive, state shifts to `CHOOSING_TARGET` and the player picks from a list ordered newest-first.

**Skill / Magic / Item**: Opens the corresponding list. The list is filtered and annotated by `CombatMenuBuilder` (cooldown status, MP cost, greyed-out if unusable).

**Choosing from a list**:
- If the action's `type` field is `"self"`, `"group"`, `"aoe"`, `"all"`, or `"random"`: no target selection needed; go straight to `_resolve_turn_pair`.
- Otherwise: go to `_maybe_select_target`.

**Back button**: From any sub-menu, returns to `CHOOSING_ACTION` and re-renders the main choices.

---

### 5. Resolution (`_resolve_turn_pair`)

The heart of the turn. Called once the player has committed to an action.

**Building the action list**:

The player's action is the first entry. Then for each living enemy (in index order):

1. If the enemy is **stunned**: add `{ type: "stunned" }` — enemy skips its turn.
2. If the enemy is **frozen**: add `{ type: "frozen" }`.
3. If `enemy_timers[i] <= 0` (the enemy is ready to act):
   - If currently channeling: fire the stored ChannelMove skill, clear `enemy_channeling[i]`.
   - Otherwise: call `calc.enemy_choose_action(...)` to select an action.
   - Set `enemy_first_actions[i] = false`.
   - Decrement `enemy_timers[i]` by 1.
4. If the enemy is **not** acting this turn and is **not** stunned/frozen: add `{ type: "timer_tick" }` — countdown display only.

Cooldowns for non-stunned/non-frozen enemies are ticked at this point.

**Speed sort**: The full action list is sorted by `get_action_speed`:
```
speed = AGI - max(action_weight - DEX, 0)
```
Higher speed = acts first. Weapons and skills carry a `wgt` stat that penalizes speed; DEX cancels up to `wgt` points of that penalty.

**Execution**: Actions run in speed order. After each action, if the player has died, `check_combat_end()` is called immediately. If all enemies died or fled mid-resolution, the loop breaks early.

**End-of-round status processing**: After all actions resolve:
1. `status_sys.process_statuses("player")` — DoT/HoT ticks, duration decrements, expired effect cleanup.
2. Same for each enemy slot.
3. `_notify_if_died` is called for any enemy whose HP is now ≤ 0 (clears their status effects, emits `enemy_died`).

Wait for the dialogue to finish writing, then wait for the player to press Continue, then call `next_turn()` → `start_player_turn()`.

---

### 6. Executing an Action (`_execute_turn_action` / `_execute_action`)

**For basic attacks** (`type: "attack"`):
- Show "X struck Y with [weapon]!" text.
- Assemble synthetic weapon data (mgt, acc 90, crit from weapon stats, element from weapon).
- Call `_execute_hit`.

**For skills, spells, and items** (`_execute_action`):
- If `drain_all_mp = true`: consume all current MP, set `stats.mgt = current_mp × magnitude` before resolving.
- Otherwise consume `cost` MP.
- Apply cooldown: `cooldowns[who][action_name] = cooldown + 1`.
- Determine target name for the use_text string.
- Show the `use_text` (or a default "X used Y!" message).
- **Flee**: Remove enemy from active combat, add to `_fled_indices`.
- **Summon**: Call `_perform_summon` (see Summon Mechanics below).
- **AoE** (player `type: "aoe"/"all"`, enemy `type: "group"/"all"`): Hit all living enemies / the player in sequence.
- **Random** (player only): Roll number of hits between `min_hits` and `max_hits`, pick a random living target per hit.
- **Single target**: Call `_execute_hit` once.
- After all hits: if `consumable = true`, remove one unit of the item from inventory.
- **Element shift**: If the action was a spell with an element, the caster takes on that element. The element persists until another spell changes it or combat ends.

---

### 7. Hit Resolution (`_execute_hit` + `CombatCalculator.resolve_action`)

For each hit (multi-hit skills run this loop):

**Miss check** (`check_hit`):
```
hit_rate = base_acc + attacker.DEX - defender.AGI - floor(defender.LCK / 2)
hit_rate = hit_rate × attacker.stat_multipliers["acc_mult"]
hits if rand(1-100) <= hit_rate
```
If evade multiplier is active on the defender: always miss.

**Damage formula**:
```
base_mgt = stats.mgt
         + weapon.mgt          (if inherit_wpn)
         + actor.STR or INT    (if inherit_stats; INT for magic = true)
defense  = target.DEF / 2      (physical) or target.MP (magic)
           0 if effect = "ignore_def"
raw_dmg  = max(1, (base_mgt - floor(defense)) × rand(0.9–1.1))
```

**Crit check**:
```
crit_chance = actor.crit_stat + stats.crit + actor.DEX - target.LCK
              + weapon.crit (if inherit_wpn)
crits if rand(1-100) <= crit_chance → damage × 1.5
```

**Element multiplier** (applied after crit):
| Multiplier | Display |
|---|---|
| 2.0 | `[yellow]Weak![/yellow]` |
| 0.5 | `[cyan]Resisted![/cyan]` |
| 0.25 | `[brown]Ineffective![/brown]` |
| 0.0 (immune) | `[cyan]No effect![/cyan]` — damage is 0, no further processing |

Attack element is resolved as: skill `element` field → weapon `element` → `"Neutral"`.

**Shatter** (checked before trinket multipliers): If the target has `freeze` status and this hit would deal damage, the freeze is removed, damage is multiplied by 1.5, and `"Shattered!"` is displayed.

**Trinket multipliers**:
- Attacker's `TrinketSystem.get_attack_multiplier(target_who, element)` (e.g. Resonant Badge).
- Target's `TrinketSystem.get_damage_taken_multiplier(living_count)` (e.g. Woodcutter's Bandana scaling).
- Target's `TrinketSystem.check_death_prevention(damage)` — can cap damage to leave 1 HP.
- Special rule: a player at full HP can never be one-shot by a single hit (damage is capped at `max_hp - 1`).

**Damage is applied** (`target.take_damage(result["damage"])`).

**Status effect** (if `effect != "none"` and `rand(1-100) <= chance`):
- `"stat_clear"`: wipes all status effects from target.
- `"recharge"`: reduces all cooldowns on the actor by `magnitude`.
- `"delay"`: increases the target enemy's timer by `magnitude`.
- `"lifedrain"`: heals the user for `damage × magnitude`.
- Any other string: added via `status_sys.add_status()`.

**Heal / MP restore**: If `result["heal"] > 0` or `result["mp_restore"] > 0`, applied after damage.

**On-hit trinket procs**: Actor's `on_hit(element)` and target's `on_owner_hit()` fire; these may modify multipliers or state for subsequent hits.

**Lifesteal**: If the attacker's trinket has a lifesteal amount, the user heals after dealing damage.

**Counter-stun**: If the player's trinket fires `try_counter_stun()` after being hit, the attacker gains a `stun` status.

---

### 8. End of Combat (`end_combat`)

**Victory**:
1. Reset element on all combatants.
2. Reset all TrinketSystem states.
3. Show defeated enemy names.
4. Run `TrinketSystem.process_post_battle()` for trinket end-of-battle effects.
5. Calculate rewards.
6. Show reward text (XP, gold, items).
7. Pop the input context.
8. Emit `combat_ended { victory: true }`.

**Defeat**:
1. Check `TrinketSystem.try_auto_revive()` — if a trinket (e.g. Woodcutter's Bandana in certain states) can revive, do so and continue combat.
2. If no revive: show "You were defeated...", pop input, emit `combat_ended { victory: false }`.

**Rewards formula**:
- XP per enemy = `10 × 1.5^(level - 1)` (exponential; Level 1 → 10 XP, Level 5 → ~75 XP, Level 10 → ~576 XP).
- Gold = enemy's `Gold` field.
- Drops = each entry in `Drops` dict is rolled independently at its percentage chance.
- Fled enemies yield no rewards.

---

## Enemy AI

### Timer System

The timer is not a cooldown in the traditional sense — it controls **when** the enemy acts in the round resolution, not whether they can use a skill.

- `Startup`: Turns before the **first** action. `0` means the enemy acts on the very first turn (before the player if speed allows). `1` means the player gets one free turn. `3` means three turns of preparation.
- `Cooldown`: Turns between subsequent actions after the first.
- The timer counts down during `timer_tick` entries in the action list. When it hits 0, the enemy acts on that same round.
- `enemy_first_actions[i]` tracks whether the enemy has ever acted — controls whether the flavor text says "Preparing" or "Recharging".

### Action Selection (`CombatCalculator.enemy_choose_action`)

Runs in this order:

1. **Build available pool**: Union of `skills` and `spells` that have `cooldown == 0` and (for spells) `cost <= current MP`.
2. **Summon filter**: Remove any `type: "summon"` skills unless this enemy is the only living one (`living_count == 1`). Summons are only usable as a last resort.
3. **HP threshold filter**: Remove skills listed in `Skill_HP_Thresholds` whose threshold% is above the enemy's current HP%. (`{ "Rage": 50 }` means Rage is only usable below 50% HP.)
4. **Status deduplication**: Remove skills whose `effect` is already active on the target (no point applying poison when the player is already poisoned).
5. **Skill roll**: If available pool is non-empty AND `rand(1-100) <= Skill_Chance`: select from the weighted pool using `Skill_Weights` (default weight 1 per skill). If `Skill_Chance` is not set, defaults to 35%.
6. **Basic attack fallback**: If the roll fails or the pool is empty, use a basic attack.

### ChannelMoves

A ChannelMove is a powerful skill that requires a wind-up before it fires. It replaces the normal Cooldown reset with a countdown.

Each entry in the `ChannelMoves` array:
```json
{
  "skill": "Mana Explosion",
  "condition": "always" | "hp_below",
  "threshold": 50,
  "duration": 2,
  "channel_start": ["[SELF] starts channeling [SKILL]!"]
  "channel_texts": ["[SELF] draws MP from the dead...", "trembles as dark energy builds."],
  "weight": 1
}
```

**Trigger**: At the start of `render_player_turn`, if an enemy's timer just expired (timer < 0), the system checks eligible ChannelMoves (`always` or HP below threshold). If any are eligible, one is selected by weight and sets up the channel. If none are eligible, the normal Cooldown resets instead.

**During the channel**: Each turn the enemy shows one of its `channel_texts` (orange) and the timer counts down. The player sees exactly how many turns they have left.

**For the texts** use [SELF] to substitute the enemy name and [SKILL] to substitute the skill name

**On trigger** (timer hits 0): The skill fires immediately with `type: "skill"` in the action list. The `enemy_channeling` field is cleared, so the next reset will roll normally again.

### Summons (`_perform_summon`)

Triggered by a skill with `type: "summon"` and a `summons` field (string or array of monster names).

1. The skill is only available via AI when the summoner is the **sole surviving** enemy (enforced by the summon filter in `enemy_choose_action`).
2. `magnitude` determines how many monsters to summon (default 1). If `summons` is an array, each summon picks randomly from it.
3. If a dead or fled enemy slot exists, it is recycled (its rewards are banked first). If all slots are occupied by living enemies, the summon is capped at max party size (currently 2).
4. The new character's timer is set to `-1` (acts immediately next turn), `enemy_first_actions` = `true`.
5. The summoned monster's `Start` skill fires immediately.
6. Duplicate summon names get letter suffixes using the shared `_summon_name_counters` dict.

---

## Special Mechanics

### Shatter

Targets with `freeze` status are **shattered** when they take damage from any source. On shatter:
- The `freeze` status is removed.
- Damage for the triggering hit is multiplied by **1.5**.
- `"Shattered!"` is displayed.

This creates a two-step setup: apply Freeze, then shatter it with a physical hit for burst damage.

### Element Shifting

When a character casts a spell, they temporarily become that spell's element until they cast a different spell or combat ends. This matters because:
- The character is now **vulnerable to the counters of that element**.
- Elemental weapons that hit the now-shifted character use the updated element chart.
- This applies to both the player and enemies — an enemy that casts Fire becomes Fire element and is then weak to Water.

Enemy elements listed in `monsters.json` are their **default** element. If they only cast one spell type, that default and their spell element are usually the same. If they cast multiple elements, the shifts happen in real time.

### MP as Magic Defense

Physical defense uses the `DEF` stat. Magic defense uses the target's current **MP**. Depleting an enemy's MP (via the Drain spell or similar) reduces their magical resilience. Conversely, a player with high MP is more resistant to spells.

---

## Status Effects

Status effects are defined in `status.json`. `CombatStatusSystem` manages them.

**Core mechanics**:
- Effects stack in **duration** — applying the same effect to a target that already has it adds to the remaining duration rather than replacing it.
- Stat modifier effects (`dmg_taken`, `acc_mult`, `evade`, etc.) are recalculated by multiplying all active `stats` fields from the status DB and applying them via `set_stat_multipliers`.
- DoT damage = `damage_frac × target.max_hp`, applied at end of round. HoT heals similarly.
- Stun and freeze prevent the affected entity from acting **and** prevent their cooldowns from ticking.
- Freeze enables the Shatter interaction.
- `stat_clear` (as a skill effect) wipes all status effects from the target — it is not a status itself.

**Trinket immunity**: A `TrinketSystem` may declare immunity to specific status types. `add_status` checks this before adding.

---

## Monster Design Reference

### Required Fields

| Field | Type | Notes |
|---|---|---|
| `Name` | string | Unique. Used as display name and lookup key |
| `Element` | string | Default element from the 15-element chart |
| `Lvl` | int | Used for XP formula and stat grade scaling |
| `Stats` | `{stat: grade}` | A–F (or S for exceptional) grades for all 8 stats |
| `TrueStats` | `{stat: number}` | Numeric overrides for stats where the grade curve doesn't apply |
| `Drops` | `{item: chance%}` | Each item rolled independently |
| `Gold` | int | Gold reward |
| `Startup` | int | Turns before first action |
| `Cooldown` | int | Turns between actions after first |
| `Skills` | `[string]` | Skill names from `skills.json` |
| `Spells` | `[string]` | Spell names from `spells.json` |
| `Location` | string | Region name for encounter system |
| `Rarity` | int / `"Hidden"` / `null` | int = weight for random encounter table; `"Hidden"` = never random; `null` = boss (only placed explicitly) |

### Optional Fields

| Field | Type | Notes |
|---|---|---|
| `FName` | string | First name for gendered display |
| `Gender` | string | `"Male"`, `"Female"`, `"Random"`, `"None"` |
| `Equip` | `{Weapon, Armor}` | Equipment the monster uses in battle |
| `Trinkets` | `[string]` | Trinkets; grants TrinketSystem for this enemy |
| `Skill_Chance` | int | % chance to use a skill vs basic attack. Default 35 |
| `Skill_Weights` | `{skill: weight}` | Relative weight per skill in selection. Default 1 |
| `Skill_HP_Thresholds` | `{skill: hp%}` | Skill only available at or below this HP% |
| `Preparing` | string / `[string]` | Text shown while counting down to first action |
| `Recharging` | string / `[string]` | Text shown while counting down between actions |
| `Start` | string | Skill or spell used at combat start, before player acts |
| `ChannelMoves` | `[ChannelMove]` | See ChannelMoves section above |

### Stat Grade Guide

Grades map to numeric values via a curve defined in `Character.gd`. Think of them as archetypes:

| Grade | Meaning | Typical use |
|---|---|---|
| S | Exceptional | Boss HP, signature trait of a major threat |
| A | Strong | Primary threat stat, boss secondary stats |
| B | Good | Competent in this stat, notable |
| C | Average | Baseline competence |
| D | Below average | Minor weakness |
| E | Weak | Functionally negligible |
| F | Negligible | Effectively zero |

`TrueStats` overrides the grade for specific stats. Use it to give enemies HP outside the player curve or when a stat should stand out for some reason (e.g. an exorbitant Def value for an enemy that should be countered with magical attacks).

### Encounter Group Entries

Multi-enemy encounters are defined as separate entries with an `Enemies` array:
```json
{
  "Name": "Bandit Brothers",
  "Enemies": ["Bandit", "Bandit"],
  "Location": "Apple Woods",
  "Rarity": null
}
```
The encounter system instantiates each named monster independently. The group entry can override `Gender` with an array to assign genders to each slot.

---

## Combat Design Best Practices

### The Timer Is the Core Design Space

Every monster's identity lives in its Startup / Cooldown rhythm. This is the primary tool for teaching the player what threat they're facing:

- **Startup 0–1**: Aggressive, immediate pressure. Best for low-HP glass cannons or swarm enemies. Leaves little reaction time, so pair with modest damage.
- **Startup 2–3**: Standard. The player gets at least one free turn to set up — good for most enemies. The preparation window is where skill cooldowns are managed.
- **Startup 4+**: Deliberate, looming threat. Use for high-HP slow bruisers, environmental hazards (the River King), or enemies where the wait itself is the tension.

- **Startup 1**: Relentless pressure.
- **Startup 2**: Standard. The player gets at least one free turn to set up — good for most enemies. The preparation window is where skill cooldowns are managed.
- **Startup 3+**: Deliberate, looming threat. Use for high-HP slow bruisers, or enemies where the wait itself is the tension.

**Never give a boss a Cooldown of 0 without compensating elsewhere.** It removes all rhythm and degrades into a war of attrition.

### Stat Profiles Tell the Player What to Do

Players learn monster threat from the visible stat grades in the UI. Design each enemy so its grade spread communicates a clear playstyle signal:

| Archetype | Profile | Counterplay |
|---|---|---|
| Glass cannon | High Str or Int, low HP/Def | Burst it down fast; don't let it act |
| Stalwart | High HP and Def, low Str and Agi | Outlast; DoT and sustained damage; it hits slow and soft |
| Speed threat | High Agi, low Def | It acts first almost every round; prioritize debuffs or freeze |
| Magic wall | High MP (magic resist), low physical Def | Hit physically; drain MP to reduce magic defense |
| Lucky tank | High LCK, average everything | Its crit chance and evasion are dangerous; use high-accuracy skills |
| Summoner | Low personal threat stats | Kill it before it chains summons; it only summons when alone |

Don't assign A across all stats. A monster that excels at everything is not interesting — it just does more of everything the player already handles.

### Elemental Identity Should Match Region

Every region has a dominant elemental palette. Monsters from that region should primarily use and be affiliated with those elements:

| Region | Elements |
|---|---|
| Apple Woods | Neutral, Water, Earth |
| Caves of Light | Light, Dark, Water |
| Sundown Plateau | Dark, (Neutral for non-undead fighters) |
| Mount Legory | Wind, Ice |
| Core Cavern | Fire, Earth |
| Lost Swamp | Plant, Water, Dark |
| Arcmat Ruins | All elements |

Mixing elements within a region is fine for variety, but the elemental tone should feel cohesive. A Fire enemy in the Apple Woods needs a lore reason to be there.

### Skill Design for Enemies

Since enemies attack less often, each skill or spell they use should feel impactful. Either as a big hit or as something that shifts the face of battle.
Only one-three skills they use at all times.
Having lots of situational skills is fine.

Design guidelines:
- Use `Skill_Chance` to control frequency. A boss with `Skill_Chance: 100` always uses skills — no basic attacks. A common enemy at `35` (default) uses skills occasionally. Most enemies should probably have more.
- Use `Skill_Weights` to make some skills feel like a signature move (`{ "Raise Skeleton": 3, "Raise Ghost": 1 }` makes the Necromancer summon skeletons more often).
- Use `Skill_HP_Thresholds` to gate desperation moves (phase 2 behavior without a true phase change).

### ChannelMoves: The Signature Threat

ChannelMoves are the most powerful tool for communicating danger and creating decision pressure. Use them for:
- A boss's most powerful attack that the player has 2–3 turns to prepare for (heal up, apply buffs, use a Delay skill).
- A high-HP enemy that becomes dangerous at low health (`condition: "hp_below"`, `threshold: 50`).

**Design checklist for a ChannelMove**:
1. The skill itself should deal significantly more damage than the enemy's normal attacks, or have a severe debilitating effect. If it isn't notably dangerous, the multi-turn wind-up creates false tension.
2. The `channel_texts` should sell the threat in sensory language ("draws the heat from the air around it.", "the ground fractures beneath its feet.").
3. Give the player a meaningful response window: `duration: 2` for most, `duration: 3` for very high-damage attacks.
4. The player should have at least one viable counter: using a Delay skill, healing to survive it, or applying freeze to interrupt it. If the only correct play is "take the hit", the wind-up is cosmetic.

### Start Skills

`Start` is used for monsters that change the combat state before the player's first turn:
- Summoners that arrive with minions (Necromancer uses `Raise Ghost` on entry).
- Enemies that self-buff or apply an aura from the start.
- A boss opening move that establishes the fight's tone.

Use sparingly. Most regular enemies don't need a Start skill. If every enemy had one, player turn 1 would always be reactive rather than proactive.

### Boss Design Checklist

- [ ] Unique stat profile that isn't just "high in everything"
- [ ] At least one ChannelMove that the player can respond to
- [ ] Startup of at least 2 (give the player a setup turn)
- [ ] Drops that feel earned and lore-appropriate (100% on unique items is fine for bosses)
- [ ] Element that fits the region or is justified by lore
- [ ] Rarity set to `null` (never random, only placed explicitly)
- [ ] `Start` skill only if it meaningfully establishes the fight
- [ ] `Skill_Chance` of 80–100 (bosses should not be fighting with basic attacks)
- [ ] `Skill_HP_Thresholds` to create phase-2-like behavior at low HP
- [ ] `Preparing` / `Recharging` flavor text that sets the tone for the battle (use [SELF] to substitute the enemy name): "**[SELF] glares at you.**"

### Regular Enemy Checklist

- [ ] Stat grade spread that communicates one or two clear strengths/weaknesses
- [ ] Startup and Cooldown that match their threat level
- [ ] Drops thematically tied to the enemy (bandits drop weapons; animals drop natural materials)
- [ ] Rarity as a positive integer; higher = more common
- [ ] `Preparing` / `Recharging` flavor text that fits the creature's nature (use [SELF] to substitute the enemy name): "**[SELF] hobbles in place.**"
- [ ] Element consistent with the region's palette

### Things to Avoid

**Avoid Cooldown 0 with Skill_Chance 100.** The enemy fires a skill every single turn with no rhythm. This removes the telegraphing that makes the timer system work.

**Don't use Light and Dark to signal morality.** The Cult of Light is antagonistic. Dark enemies include spirits and ancient magic. Element choice should be driven by creature type, region, and gameplay role — not moral alignment.

**Avoid multi-element enemies at low levels.** Learning the elemental chart is a skill the player develops progressively. Early enemies should reinforce one element clearly. Cross-element enemies work best at mid-to-late game when the player has enough spell variety to respond.

**Don't over-load Drops.** Four or more possible drops means the player rarely gets any specific one, and loot feels random noise. Two to three drops — one high-chance consumable, one low-chance equipment — is more satisfying.

**Don't make summon skills available to enemies in group encounters.** The AI already filters summons to "only when alone," but populating a group enemy's skill list with a summon creates dead weight. Put summon skills only on enemies that make narrative sense as commanders or necromancers, and give them low personal HP so the player has incentive to kill them first.
