# DiceGame.md — Wanderer's Dice Design Reference

Wanderer's Dice is a roadside dice-poker minigame played across Arcmat. It is text-driven,
embedded in event flow via `DiceGame.gd`, and triggered by `dice_game` steps in event JSON.
This document covers game structure, hand rankings, special faces, dice types, NPC AI, and
content guidelines for adding new encounters.

---

## Concept

Wanderer's Dice is a community-card dice game: each player holds **3 private dice** and
**2 Dealer's Dice** are revealed during play for everyone to combine. Players get one reroll
opportunity per round; the final hand is the best 5-die combination of private + community.

The game is flavored as a fixture of common life across Arcmat — played in roadside camps,
village pubs, and traveling circuses. NPCs have distinct personalities expressed through banter.
Higher-difficulty opponents carry better dice loadouts and make smarter reroll decisions.

---

## Game Flow

A session has **three reroll rounds** separated by **two Dealer's Die reveals**:

```
Setup         — dice rolled out of sight; player sees their private hand
Round 1       — player picks one die to reroll (or stands pat); NPCs act
Dealer's Die 1 — first community die revealed; all react
Round 2       — player and NPCs reroll again
Dealer's Die 2 — second community die revealed
Round 3       — final reroll
Showdown      — NPCs reveal in reverse order; player reveals last; winner takes pot
```

### Design Principles:

1) Players have five cards to build their hands 

2) There should be no situation where two hands don't combine if they can be held simultaneously. 

3) Hands combining with a face fulfilling several roles are weaker than hands combining by forming independently 

4) The Arcs are the fundamental strength scale 

5) Longer runs beat shorter runs 

6) Mixed hands sit between the pure hands 

7) Runs are valued over pairs 

8) Crown is deliberately meant to be the most powerful face 

9) Crown always combine with hands in such a way that they are always better than if the Crown was a Joker. 

10) For hands upgraded by Crowns, having more Crowns is better (ex: having a hand made from two faces plus two crowns is better than a hand made by three faces and one crown from the same family) 
Upgrade tiers go Crowned > King's > Dynastic > Reign 

11) Joker only substitutes numeric values (with the exception of the Full Circus, which is a deliberate formula break) 

12) Bridge doesn't create hands, only makes runs possible 

13) Rogue is a deliberate oddball, with Snake Eyes being uniquely powerful as a pair, but losing uniqueness as a trio or when overshadowed in a hand. 

14) Skulls are meant to be useless by themselves, which is why skulls don't form pairs or runs. 

15) Skulls are meant to be high-risk, high-reward. When in high numbers, they are meant to be powerful beyond the norm. When alone, they can combine with Crowns, being about on par with combining them with a pair. 

16) Higher hands aren't going to happen in 90% of games. Even a Pilgrimage should be a near-guaranteed win. Special hands in particular are almost never going to happen. Remember that the player only controls 3 of the five dice. The other two might simply not have the Special face needed and cannot be re-rolled. Plus, the player probably won't have a full set of specialized dice. 

17) Special faces have different rarities, and different dices don't have to evenly turn up every face they have. Crown is by far the rarest, being at best a one in six in some of the rarest dice.
Skull is a common roll, but mostly only in specialised dice. Bridge is exclusive to specialized dice, but about a 1 in 3, Rogue and Knight appear in some dice, but not all. 
Joker is exclusive to a particular set of dice, which the player will probably not have many of.

### Wager & Pot

- Wager is set in the event step (`"wager": N`).
- The wager is deducted from the player's gold at the start.
- Pot = wager × (1 + number of NPCs).
- On win: player receives the full pot. On tie: wager is returned. On loss: nothing.
- **The Void** (five Blanks anywhere) forces a draw and returns everyone's wager.

---

## Hand Hierarchy

Hands are ranked from highest to lowest. Tiebreaks within a tier use the numeric value
of the key die (higher is better).

### Core Hands (numeric dice only)

| Hand | Description | Example |
|---|---|---|
| Five Arcs | Five of a kind | 3-3-3-3-3 |
| The Pilgrimage | Five consecutive | 2-3-4-5-6 |
| Four Arcs | Four of a kind | 4-4-4-4 |
| The Stairwell | Four consecutive + pair inside the run | 1-1-2-3-4 |
| The Long Road | Four consecutive | 1-2-3-4 |
| The Summit | Triple overlapping a three-in-a-row | 3-3-3-2-4 |
| The Hearth | Triple + pair | 1-1-1-2-2 |
| Lucky Sevens | Three Knights | 7-7-7 |
| The Peregrine | Three-in-a-row + separate pair | 1-2-3-5-5 |
| Three Arcs | Three of a kind | 5-5-5 |
| Lover's Climb | Three consecutive + two pairs, all inside the run | 1-1-2-2-3 |
| Double Duet | Two different pairs | 1-1-2-2 |
| Drunkard's Climb | Three consecutive + pair inside the run | 1-1-2-3 |
| Snake Eyes | Pair of Rogues (0-0) | 0-0 |
| The Climb | Three consecutive | 1-2-3 |
| Wanderer's Hand | Pair of 4, 5, 6, or 7 | 5-5 |
| The Common | Pair of 1, 2, or 3 | 2-2 |
| Dead Hand | No match | — |

> **Snake Eyes** sits between Drunkard's Climb and The Climb — above a lone 3-in-a-row
> but below a run with a pair inside it.

### Special-Face Hands

| Hand | Condition |
|---|---|
| Full Circus | Five Jokers |
| The Dominium | Five Crowns |
| First Blight | Four Crowns + one Skull |
| Four Day Reign | Four Crowns |
| Dynastic Marriage | Three Crowns + any pair |
| Dead Dynasty | Three Crowns + one Skull |
| King's Lucky Sevens | Two Crowns + three Knights |
| King's Grave | Two Crowns + one Skull |
| The Necronomicon | Five Skulls |
| Jackpot | Five Knights |
| The Premonition | Four Skulls |
| King's Skull | Two Crowns + one Skull |
| The Triumvirate | Three Crowns |
| The Widower | Three Skulls + pair |
| Graveyard | Three Skulls |
| King's Hand | Two Crowns |

### Crown Upgrades

One Crown can upgrade any (physically possible) hand. The upgrade naming follows the pattern
**Crowned \<Hand\>** → **King's \<Hand\>** → **Triumvirate / Dynastic \<Hand\>** →
**Four Day Reign** → **The Dominium**.

| Crowns | Upgrade applied to |
|---|---|
| 1 Crown | Crowned Hand (lone Crown) / Crowned Common / Crowned Wanderer's Hand / Crowned Snake Eyes / Crowned Duet / Crowned Climb / Crowned Drunkard's Climb / Crowned Lucky Sevens / Crowned Three Arcs / Crowned Long Road / Crowned Four Arcs / Crowned Graveyard |
| 2 Crowns | King's Hand / King's Common / King's Wanderer / King's Eyes / King's Climb / King's Lucky Sevens / King's Three Arcs |
| 3 Crowns | The Triumvirate (overrides pair tier) / Dynastic Marriage (with a pair) |
| 4 Crowns | Four Day Reign |
| 5 Crowns | The Dominium |

Crown upgrades slot into the hierarchy between normal hands; a **Crowned Long Road**
beats The Long Road but sits below The Hearth. A lone Crown is a **Crowned Hand**,
which beats Wanderer's Hand.

### Skull Hands

Skulls form a parallel ladder that merges into the Crown/normal hierarchy:

```
Crowned Skull (C+S)
Graveyard (S-S-S)               — between The Peregrine and Three Arcs
Crowned Graveyard (C+S-S-S)
The Widower (S-S-S + pair)      — between Four Arcs and The Stairwell
King's Skull (C-C-S)
The Premonition (S-S-S-S)       — between The Pilgrimage and Five Arcs
King's Grave (C-C-S-S)
Dead Dynasty (C-C-C-S)
The Necronomicon (S-S-S-S-S)    — above Five Arcs, below The Premonition tier
Crowned Premonition (C+S-S-S-S)
First Blight (C-C-C-C-S)        — between Four Day Reign and The Dominium
```

Two Skulls alone or one Skull alone form no special hand (unless paired with Crowns).

---

## Special Faces

| Face | ID | Behavior |
|---|---|---|
| **Rogue** | `0` (int) | Lowest numeric; pairs to form Snake Eyes; runs normally in sequences |
| **Knight** | `7` (int) | Highest numeric; pairs high; runs normally |
| **Crown** | `"C"` | Upgrades any hand to its Crowned form; scales with Crown count; stacks with Skulls |
| **Joker** | `"J"` | Wild — counts as any numeric value 0–7 during hand evaluation (brute-forced) |
| **Bridge** | `"B"` | Connects a run of 6 or 7 down to 0 or 1; usable once per hand evaluation |
| **Skull** | `"S"` | Alone or in pairs: no effect; in groups of 3+, or with Crowns, forms Skull hands |
| **Blank** | `"X"` | Does nothing; five Blanks form **The Void** and end the game in a draw |

### The Void

If any hand (player or NPC) resolves as five Blanks, the game ends immediately in a draw.
Both sides keep their wager. This is a sentinel rank (`RANK_THE_VOID = -1`).

---

## Dice Types

All dice are defined in `Database/dice.json`. Each die has a `values` array; the roll
picks uniformly from that array (duplicated entries increase that face's probability).

| Die | Color | Notable Faces | Notes |
|---|---|---|---|
| Standard | — | 1–6 | Default die for most encounters |
| Weighted | gray | 1–6, with 5 and 6 doubled | More likely to roll high |
| Trick | purple | 1,1,2,3,3,4,5,5,J | Has one Joker face; low-bias otherwise |
| Circus | purple | 1,1,6,J,J,J | Three Joker faces; high Joker probability |
| Bertunia | blue | 0,0,1,2,5,6,7,7 | Uses Rogue (0) and Knight (7); Bertunia regional variant |
| Lantern | orange | B,1,2,5,6,B | Two Bridge faces; built for run-building |
| Bone | red | S,S,S,S,1,2,3 | Four Skull faces |
| Skull-Carved | red | S,S,S,S,S,S | All Skulls |
| Crown | yellow | 2,3,4,5,6,C | One Crown face |
| Decadent | gold | S,S,S,S,C,C | Four Skulls + two Crowns |
| Crude | gray | 1,2,3,X,X,X | Three Blank faces |
| Blank | gray | X,X,X,X,X,X | All Blanks |
| Runecarved | indigo | 0,1,2,3,5,7,M,M | Has unimplemented `M` (rune?) faces |

Community (Dealer's) dice are also drawn from this pool and are set per event step
via `"community_dice": ["id1", "id2"]`.

### Luck Advantage

If the player's **Lck stat ≥ 10**, each reroll draws **2 dice** from that die's value
pool and keeps the better one (`ADVANTAGE_ROLLS = 2`). This applies only to the player,
not to NPCs.

---

## NPC AI

Each NPC gambler has a **difficulty** string that maps to a profile in `AI_PROFILES`.
The AI evaluates three actions per phase (reroll die 0, 1, or 2) plus "stand pat":

```
score = w_ev × EV_gain
      + w_pr × Pr(improvement)
      + w_reveal × is_revealed_die
      - w_conserve × current_rank_normalized
      + rand() × noise
```

Stand pat score = `w_conserve × current_rank + stand_bias + noise`.

The AI chooses the action with the highest score.

| Profile | Behavior |
|---|---|
| `easy` | Low weights, high noise — plays roughly randomly |
| `medium` | Balanced weights, moderate noise |
| `hard` | High EV weight, low noise — plays near-optimally |
| `pro` | Pure EV maximizer; zero noise; ignores Pr |
| `risky` | Very low conservatism; rerolls aggressively even with good hands |
| `conservative` | High stand bias; only rerolls when improvement is near-certain |
| `wildcard` | Noise dominates all rational weights — random behavior |

Profiles have three phases (rounds 1–3); later phases tend to be more conservative
(higher `w_conserve`) as hands are closer to final.

---

## Gamblers (NPC Roster)

Gamblers are defined in `Database/gamblers.json`.

| ID | Name | Dice | Difficulty | Lck | Personality |
|---|---|---|---|---|---|
| `travelling_gambler` | Travelling Gambler | Standard×2 + Weighted | easy | 3 | Superstitious; invokes "Lady Luck" constantly |
| `veteran_gambler` | Veteran Gambler | Standard + Weighted×2 | medium | 5 | Taciturn and experienced; speaks in brief observations |
| `shark` | The Shark | Weighted×3 | hard | 8 | Cold and silent; lets results speak for themselves |
| `smiley_clown` | Smiley Clown | Trick×2 + Standard | risky | 4 | Theatrical; treats every roll as a performance |
| `gamer_clown` | Gamer Clown | Trick×2 + Standard | wildcard | 4 | Gaming-brain; narrates strategy in meta terms |
| `frowny_clown` | Frowny Clown | Standard×2 + Trick | conservative | 2 | Melancholic; expects to lose; oddly dignified about it |
| `serious_clown` | Serious Clown | Trick + Standard + Trick | pro | 6 | Says almost nothing; pure physical presence |
| `surprised_clown` | Surprised Clown | Trick + Circus + Trick | wildcard | 3 | Genuinely startled by everything; chaotic energy |

### Banter Triggers

Each gambler has a `banter` dictionary. Each key maps to a pool of lines; the system
picks randomly at a given chance per trigger.

| Key | Fires when |
|---|---|
| `game_start` | Before any rolling |
| `round_1/2/3` | Start of each reroll round |
| `round_good_hand` | NPC has a strong hand at round start |
| `round_bad_hand` | NPC has a weak hand at round start |
| `hand_good_start` | NPC's initial roll is above The Climb |
| `hand_bad_start` | NPC's initial roll is Dead Hand |
| `reroll` | NPC decides to reroll |
| `keep_hand` | NPC stands pat |
| `good_roll` | NPC rolled something with good synergy |
| `pair_hit` | NPC rolled a face that forms a pair |
| `no_combo` | NPC rolled something with no synergy |
| `special_die_self_<face>` | NPC rolled a specific special face (joker/bridge/crown/skull/rogue/knight) |
| `react_pair` | NPC reacts to player forming a pair |
| `react_good_roll` | NPC reacts to player's good reroll |
| `react_no_combo` | NPC reacts to player's weak reroll |
| `react_stand_pat` | NPC reacts to player holding |
| `community_favor_self` | Community die synergizes with this NPC |
| `community_favor_other` | Community die doesn't help this NPC |
| `special_die_community_<face>` | Community die shows a special face |
| `showdown_start` | Showdown begins |
| `showdown_reveal` | NPC reveals their hand |
| `showdown_leading` | NPC's hand is ahead at reveal time |
| `showdown_best` | NPC has a Pilgrimage or better |
| `showdown_winning_last` | Last NPC to reveal and currently winning |
| `showdown_weak_last` | Last NPC to reveal and currently losing |
| `showdown_losing` | NPC's hand is behind another revealed hand |
| `showdown_react_best/good/bad` | NPC reacts to a hand revealed by another player |
| `showdown_win/tie/lose` | NPC's final result |
| `showdown_npc_win/lose/tie` | NPC comments on the overall match result |

### Banter Text Placeholders

Banter lines (and other data-driven text routed through `_parse_game_text`, like `start_text`)
may use `[KEY]`-style placeholders, replaced at display time. Unset keys are left as literal
`[KEY]` text, so only use a placeholder where it's documented to apply below.

| Key | Value | Applies to |
|---|---|---|
| `[PLAYER]` | The player's name | Every trigger |
| `[SELF]` | The name of the NPC currently speaking | Every trigger |
| `[SUBJECT]` | The name of the participant being reacted to | `react_*`, `react_stand_pat`, `showdown_react_*` |
| `[NPC1]` / `[NPC2]` / `[NPC3]` | Name of the first / second / third NPC participant (omitted if that seat is empty) | Every trigger |
| `[NPCs]` | All NPC names joined as "A, B and C" | Every trigger |
| `[FACE]` | The die face being rerolled (`reroll`) or just rolled/revealed (`react_*`, `good_roll`, `pair_hit`, `no_combo`, `special_die_*`, `community_favor_*`) | Reroll/roll-reaction triggers |
| `[HAND]` | The name of the hand in question | `hand_good_start`, `hand_bad_start`, `round_*`, `showdown_*` |
| `[SELF_HAND]` | The name of the speaking NPC's own current hand | Every trigger |
| `[RANDOM_HAND]` / `[RANDOM_HIGH_HAND]` / `[RANDOM_LOW_HAND]` | A random hand name (any / top half / bottom half of the hierarchy) reachable with the dice actually in this game — for bluffing | Every trigger |
| `[WINNER]` / `[WINNER_HAND]` | The name/hand of whoever is currently or finally ahead | `showdown_losing`, `showdown_weak_last`, `showdown_lose`, `showdown_npc_*` |
| `[DRAW_WITH]` | The other participant(s) this NPC tied with, joined as "A, B and C" | `showdown_tie`, `showdown_npc_tie` |
| `[WAGER]` | The amount wagered by each participant | Every trigger |
| `[TOTAL_WAGER]` / `[POT]` | The full pot (sum of all wagers) to be given to the winner | Every trigger |

---

## Hierarchy Display

The in-game "Hand Rankings" reference (accessible during any reroll choice) is built
dynamically from the dice in play. Faces not present in any die in the current session
are omitted from the displayed list.

---

## Event Step Format

```json
{
  "type": "dice_game",
  "wager": 50,
  "gamblers": ["travelling_gambler"],
  "community_dice": ["standard", "standard"]
}
```

`gamblers` is an array of gambler IDs — multiple NPCs can play simultaneously.
`community_dice` is always an array of exactly two die IDs.
`wager: 0` means no money is at stake (practice game).

The step returns `"win"`, `"tie"`, or `"lose"` for branching in the event tree.

---

## Design Guidelines

**Adding a new gambler:**
- Pick a difficulty profile that fits their characterization.
- Give them a dice loadout appropriate to their skill level; introduce special dice
  only when the location or lore justifies them.
- Write banter lines for all common triggers. The personality should come through in
  *how* they react to the same events — not in what events they react to.
- Keep lines brief and in-world. No modern idioms except for the Clown characters,
  whose anachronism is intentional.

**Adding a new dice type:**
- Define it in `dice.json` with an `id`, `name`, `values` array, optional `color`,
  and `description`.
- Duplicate face entries to bias probability (e.g., Weighted Die doubles 5 and 6).
- Introduce new dice as rewards or purchases tied to specific locations or events.

**Designing a game encounter:**
- Wager should feel meaningful but not ruinous; scale to the region's expected gold.
- Community dice drive the session's "feel": standard games are neutral; Lantern dice
  encourage run-building; Skull/Bone community dice create tension around Graveyard hands.
- A lone NPC makes the game feel like a duel; two or three NPCs add table chatter and
  raise the pot significantly.
- Use the event step's win/tie/lose outcomes to give rewards, advance storylines,
  or trigger follow-up events.

---

## Outstanding Work (from to_do.txt)

- Fix missing Wait-for-continue after certain lines
- Fix missing dice roll SFX at some points
- Fix line spacing (consecutive lines in the same action shouldn't insert a linebreak)
- Fix repeated `X's hand: X's: HAND` display bug
- Reward: Weighted Die from Travelling Gambler on first high-stakes win
- Reward: Bone Die as possible reward from digging in Sundown Plateau
- New encounter: Skeleton Gambler in Sundown Plateau (rewards Skull-Carved Die)
- Game House in Arena Town — player chooses ruleset (community dice variant):
  Standard, Bertunian, Undead, Enchanted, Dungeon, Circus, Royal, Sundown, Decadent
