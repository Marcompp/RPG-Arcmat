# RPG-Arcmat

## Monster AI Fields (`Database/monsters.json`)

Every monster entry supports the following optional fields to control enemy behaviour in combat. All fields are opt-in — omitting them falls back to the default behaviour.

### `Skill_Chance` (int, default `35`)
Percentage chance each turn that the enemy considers using a skill or spell at all. If the roll fails, the enemy always does a basic attack regardless of what skills are available.

```json
"Skill_Chance": 50
```

### `Skill_HP_Thresholds` (object, default `{}`)
Gates specific skills behind an HP threshold. A skill listed here is only eligible when the enemy's current HP is **at or below** that percentage. Skills not listed are always eligible (no threshold).

Useful for making enemies use recovery or defensive abilities only when actually threatened.

```json
"Skill_HP_Thresholds": {
    "Regen": 50,
    "First Aid": 30
}
```

### `Skill_Weights` (object, default all `1`)
Controls how likely each skill is to be chosen when the enemy decides to use a skill. The value is a relative weight — a skill with weight `3` is three times as likely to be picked as one with weight `1`. Skills not listed default to weight `1`.

```json
"Skill_Weights": {
    "Bite": 3,
    "Claws": 1
}
```

### `Startup` (int, default `0`)
Number of turns the enemy waits before acting for the first time at the start of combat.

### `Cooldown` (int, default `0`)
Number of turns the enemy waits between actions after acting.

---

## Status Effect Fields (`Database/status.json`)

Each status entry supports these fields:

| Field | Type | Description |
|---|---|---|
| `duration` | int | How many turns the status lasts |
| `damage` | float | Fraction of max HP dealt as damage each turn (e.g. `0.1` = 10%) |
| `heal` | float | Fraction of max HP restored each turn |
| `stats` | object | Stat multipliers applied while active (e.g. `"def": 2.0` doubles DEF) |
| `inflict_text` | string | Message shown when the status is applied (`[TARGET]` is replaced) |
| `upkeep_text` | string | Message shown when the per-turn effect triggers |
| `end_text` | string | Message shown when the status expires |

#### Special stat key: `acc_mult`
Multiplies the attacker's final hit rate. Applied after all other accuracy modifiers (base acc, DEX, target AGI/LCK). Values below `1.0` reduce accuracy (e.g. Blind: `0.5`).

```json
"blind": {
    "duration": 3,
    "stats": { "acc_mult": 0.5 },
    "inflict_text": "[TARGET] is blinded!"
}
```

#### Special stat key: `dmg_taken`
Setting `"dmg_taken"` in `stats` scales all incoming damage to the affected unit — both physical and magical, after element multipliers. Values below `1.0` reduce damage (e.g. Brace: `0.75`); values above `1.0` increase it (e.g. Break: `1.25`).

```json
"brace": {
    "duration": 3,
    "stats": { "dmg_taken": 0.75 },
    "inflict_text": "[TARGET] takes a defensive stance!"
}
```