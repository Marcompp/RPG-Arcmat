class_name DiceGame
extends RefCounted

# Wanderer's Dice — a dice poker minigame.
# Instantiate, wire the four Callables, then: var outcome = await game.run(step)
# Returns "win", "tie", or "lose".  Outcome sequences are run by the caller.

const HIERARCHY := \
"Five Arcs         —  five of a kind
The Pilgrimage     —  five in a row  (ex: 2-3-4-5-6)
Four Arcs          —  four of a kind
The Stairwell      —  four in a row with a pair inside  (ex: 1-1-2-3-4)
The Long Road      —  four in a row  (ex: 1-2-3-4)
The Hearth         —  triple + pair  (ex: 1-1-1-2-2)
The Summit         —  three in a row with a trio inside (ex: 1-2-3-3-3)
The Peregrine      —  three in a row + a separate pair  (ex: 1-2-3-5-5)
Three Arcs         —  three of a kind
Lover's Climb      —  three in a row with two pairs inside  (ex: 1-1-2-2-3)
Double Duet        —  two different pairs  (ex: 1-1-2-2)
Drunkard's Climb   —  three in a row with a pair inside  (ex: 1-1-2-3)
The Climb          —  three in a row  (ex: 1-2-3)
Wanderer's Hand    —  pair of 4, 5, 6, 7
The Common         —  pair of 1, 2 or 3
Dead Hand          —  no match
──
Special faces:
  Rogue  (0)    —  low numeric; in a pair becomes Snake Eyes, the most powerful pair in the game (above The Climb) but loses uniques when paired with other combinations or in higher numbers, runs normally
  Knight (7)    —  high numeric; pairs high, runs normally
  Crown  (C)    —  the most powerful face; can upgrade any hand to a state even stronger than if the Crown was a Joker; Five Crowns (The Imperium) is the second best hand in the game
					Hierarchy goes 1 Crown (Crowned <Hand>) < 2 Crown (King's <Hand>) < 3 Crowns (Triumvirate / Dynastic <Hand>) < 4 Crowns (Four Day Reign) < 5 Crowns
  Joker  (J)    —  wild; counts as any numeric value 0–7; Five Jokers (Full Circus) is the most powerful hand in the game
  Bridge (B)    —  connects 6 or 7 to 0 or 1 in a run; usable once per sequence
  Skull  (S)	—  does nothing alone or as a pair; in greater numbers or in conjuction with Crowns, forms hands beyond the norm
					Hands formed: Three Skull (Graveyard) (above Peregrine) < Four Skull (Premonition) (under Five Arcs) < Five Skull (The Necronomicon) (above Five Arcs)
  Blank  (X)    —  does nothing; five Blanks form The Void, which ends the game in a draw"


const AI_PROFILES := {
	"easy": [
		{"w_ev": 0.2, "w_pr": 0.1, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 0.5, "stand_bias": 0.2},
		{"w_ev": 0.2, "w_pr": 0.1, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 0.4, "stand_bias": 0.2},
		{"w_ev": 0.3, "w_pr": 0.2, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 0.3, "stand_bias": 0.1},
	],
	"medium": [
		{"w_ev": 0.4, "w_pr": 0.3, "w_reveal": 0.05, "w_conserve": 0.3,  "noise": 0.2,  "stand_bias": 0.05},
		{"w_ev": 0.3, "w_pr": 0.4, "w_reveal": 0.05, "w_conserve": 0.4,  "noise": 0.15, "stand_bias": 0.05},
		{"w_ev": 0.2, "w_pr": 0.5, "w_reveal": 0.1,  "w_conserve": 0.55, "noise": 0.1,  "stand_bias": 0.0},
	],
	"hard": [
		{"w_ev": 0.5, "w_pr": 0.2, "w_reveal": 0.1,  "w_conserve": 0.3, "noise": 0.05, "stand_bias": 0.0},
		{"w_ev": 0.3, "w_pr": 0.4, "w_reveal": 0.1,  "w_conserve": 0.5, "noise": 0.03, "stand_bias": 0.0},
		{"w_ev": 0.1, "w_pr": 0.6, "w_reveal": 0.15, "w_conserve": 0.7, "noise": 0.01, "stand_bias": 0.0},
	],
	# Pure EV maximiser — zero noise, ignores Pr, escalating conservatism each phase
	"pro": [
		{"w_ev": 0.9, "w_pr": 0.0, "w_reveal": 0.1, "w_conserve": 0.3, "noise": 0.0, "stand_bias": 0.0},
		{"w_ev": 0.9, "w_pr": 0.0, "w_reveal": 0.1, "w_conserve": 0.5, "noise": 0.0, "stand_bias": 0.0},
		{"w_ev": 0.9, "w_pr": 0.0, "w_reveal": 0.1, "w_conserve": 0.8, "noise": 0.0, "stand_bias": 0.0},
	],
	# Gambler — very low conservatism, will re-roll even decent hands
	"risky": [
		{"w_ev": 0.5, "w_pr": 0.4, "w_reveal": 0.0, "w_conserve": 0.05, "noise": 0.1,  "stand_bias": 0.0},
		{"w_ev": 0.5, "w_pr": 0.4, "w_reveal": 0.0, "w_conserve": 0.05, "noise": 0.1,  "stand_bias": 0.0},
		{"w_ev": 0.4, "w_pr": 0.5, "w_reveal": 0.0, "w_conserve": 0.1,  "noise": 0.15, "stand_bias": 0.0},
	],
	# Cautious — high stand bias, only re-rolls when improvement is very likely
	"conservative": [
		{"w_ev": 0.1, "w_pr": 0.6, "w_reveal": 0.0, "w_conserve": 0.5, "noise": 0.05, "stand_bias": 0.3},
		{"w_ev": 0.1, "w_pr": 0.5, "w_reveal": 0.0, "w_conserve": 0.6, "noise": 0.05, "stand_bias": 0.3},
		{"w_ev": 0.0, "w_pr": 0.4, "w_reveal": 0.0, "w_conserve": 0.7, "noise": 0.05, "stand_bias": 0.4},
	],
	# Chaos — noise dominates all rational weights, picks randomly
	"wildcard": [
		{"w_ev": 0.1, "w_pr": 0.1, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 1.5, "stand_bias": 0.0},
		{"w_ev": 0.1, "w_pr": 0.1, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 1.5, "stand_bias": 0.0},
		{"w_ev": 0.1, "w_pr": 0.1, "w_reveal": 0.0, "w_conserve": 0.1, "noise": 1.5, "stand_bias": 0.0},
	],
}

# ── Special face identifiers ──────────────────────────────────────────────────
const FACE_JOKER    := "J"
const FACE_BRIDGE   := "B"
const FACE_CROWN    := "C"
const FACE_SKULL    := "S"
const FACE_BLANK    := "X"
const FACE_PRIEST   := "P"
const FACE_MAGICIAN := "M"
const FACE_DRAGON   := "D"
const FACE_ROGUE  := 0
const FACE_KNIGHT := 7
const NUMERIC_COUNT := 8  # legal numeric values: 0–7 (used in Joker brute-force loop)

# ── Hand rank thresholds ──────────────────────────────────────────────────────
const RANK_FULL_CIRCUS             := 11000
const RANK_DOMINIUM                := 10300
const RANK_FIRST_BLIGHT            := 10220
const RANK_KINGS_GRAVE             := 10190
const RANK_CROWNED_PREMONITION     := 10180
const RANK_FOUR_DAY_REIGN          := 10170
const RANK_KINGS_THREE_ARCS        := 10160
const RANK_CROWNED_FOUR_ARCS       := 10150
const RANK_NECRONOMICON            := 10100
const RANK_DYNASTIC_MARRIAGE       := 10050
const RANK_DEAD_DYNASTY            := 10020
const RANK_FIVE_ARCS               := 10000
const RANK_PREMONITION             := 9200
const RANK_KINGS_CLIMB             := 9100
const RANK_CROWNED_LONG_ROAD       := 9050
const RANK_PILGRIMAGE              := 9000
const RANK_KINGS_SKULL             := 8200
const RANK_KINGS_EYES              := 8170
const RANK_KINGS_WANDERER          := 8150
const RANK_KINGS_COMMON            := 8100
const RANK_TRIUMVIRATE             := 8050
const RANK_CROWNED_GRAVEYARD       := 8035
const RANK_CROWNED_THREE_ARCS      := 8020
const RANK_FOUR_ARCS               := 8000
const RANK_WIDOWER                 := 7520
const RANK_STAIRWELL               := 7500
const RANK_CROWNED_DRUNKARDS_CLIMB := 7100
const RANK_CROWNED_CLIMB           := 7050
const RANK_LONG_ROAD               := 7000
const RANK_SUMMIT                  := 6500
const RANK_CROWNED_DUET            := 6080
const RANK_HEARTH                  := 6000
const RANK_GRAVEYARD               := 5900
const RANK_PEREGRINE               := 5500
const RANK_KINGS_HAND              := 5200
const RANK_CROWNED_SNAKE_EYES      := 5120
const RANK_CROWNED_WANDERERS_HAND  := 5100
const RANK_CROWNED_COMMON          := 5080
const RANK_THREE_ARCS              := 5000
const RANK_LOVERS_CLIMB            := 4500
const RANK_DOUBLE_DUET             := 4000
const RANK_DRUNKARDS_CLIMB         := 3500
const RANK_CROWNED_SKULL           := 3450
const RANK_SNAKE_EYES              := 3400
const RANK_CLIMB                   := 3000
const RANK_CROWNED_HAND            := 2900
const RANK_WANDERERS_HAND          := 2000
const RANK_COMMON                  := 1000
const RANK_THE_VOID                := -1  # sentinel: five Blanks; forces a draw

# ── Misc numeric constants ────────────────────────────────────────────────────
const MAX_RANK                := 11100.0  # slightly above RANK_FULL_CIRCUS; used for EV normalisation
const LCK_ADVANTAGE_THRESHOLD := 10
const ADVANTAGE_ROLLS         := 2
const SORT_JOKER              := 100.0
const SORT_CROWN              := 9.0
const SORT_TRIGGER            := 8.0  # Priest / Magician / Dragon — kept by AI (effect faces)
const SORT_BRIDGE             := 8.5
const SORT_SKULL              := 6.0

## Callable() -> Dictionary  — resolves with the chosen choice dict
var capture_input_fn: Callable
## Callable() -> void  — shows Continue button and waits for player
var wait_for_continue_fn: Callable
## Callable(stat_name: String) -> int
var stat_callback: Callable
## Callable() -> int  — returns player's current gold
var gold_callback: Callable
## Callable() -> Array  — returns player's 3 equipped die IDs, e.g. ["standard","weighted","standard"]
var player_dice_callback: Callable
var rng: RandomNumberGenerator
var dice_db: Dictionary
var gamblers_db: Dictionary
## Callable() -> void — brief pause after dice SFX; caller wires it
var delay_fn: Callable
## Set false to disable NPC-to-NPC banter (NPC reacting to other NPC rerolls / stand pats)
var npc_crossreact: bool = false #true


func run(step: Dictionary) -> String:
	var wager: int = step.get("wager", 0)

	if wager > 0:
		MyEventBus.emit("give_gold", {"amount": -wager})

	var npcs: Array = []
	for gid in step.get("gamblers", []):
		var gdata: Dictionary = gamblers_db.get(gid, {})
		var gdice_types: Array = gdata.get("dice", ["standard", "standard", "standard"])
		var gdice: Array = []
		for dt in gdice_types:
			gdice.append(_roll_die(dt))
		npcs.append({
			"name": gdata.get("name", gid),
			"dice": gdice,
			"dice_types": gdice_types,
			"revealed": [false, false, false],
			"folded": false,
			"difficulty": gdata.get("difficulty", "easy"),
			"banter": gdata.get("banter", {}),
		})

	var pot: int = wager * (1 + npcs.size())
	var player_committed: int = wager
	var player_types: Array = player_dice_callback.call() if player_dice_callback.is_valid() \
		else ["standard", "standard", "standard"]

	var comm_ids: Array = step.get("community_dice", ["standard", "standard"])
	var community_pool: Array = [_roll_die(comm_ids[0]), _roll_die(comm_ids[1])]
	var community: Array = []
	# live_comm_ids mirrors community, tracking die types for display/color; modified by Dragon/Priest
	var live_comm_ids: Array = []

	# ── Setup Phase ───────────────────────────────────────────────
	# 1. NPC game_start banter
	if not npcs.is_empty():
		await _banter(npcs[rng.randi() % npcs.size()], "game_start", 0.7)

	# 2. Dice rolled out of sight
	var player_hand: Array = [
		_roll_die(player_types[0]),
		_roll_die(player_types[1]),
		_roll_die(player_types[2])
	]
	await _say("The starting dice are rolled out of sight.")
	await _dice_roll_sfx()

	# 3. Player sees their hand
	await _say("You roll: " + _fmt_typed(player_hand, player_types))

	# 4. NPCs react to their own initial hands
	for npc in npcs:
		var init_rank: int = _rank_n(npc["dice"] + community)
		if init_rank >= RANK_CLIMB:
			await _banter(npc, "hand_good_start", 0.35)
		elif init_rank == 0:
			await _banter(npc, "hand_bad_start", 0.35)

	# ── Round 1 ───────────────────────────────────────────────────
	# 5. Show table
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, live_comm_ids)})
	# 6. Round banter
	if not npcs.is_empty():
		await _banter(npcs[rng.randi() % npcs.size()], "round_1", 0.55)

	# 7/8/9. Player reroll
	var rk1 := await _pick_reroll(player_hand, "Re-roll one die?", player_types, npcs, community, live_comm_ids)
	await _do_player_reroll(rk1, player_hand, player_types, npcs, community, live_comm_ids)

	# 10. NPC turns
	await _run_npc_phase(npcs, community, 1, player_hand, player_types, live_comm_ids)
	await wait_for_continue_fn.call()

	# ── Community Die 1 ───────────────────────────────────────────
	community.append(community_pool[0])
	live_comm_ids.append(comm_ids[0])
	await _say("The first Dealer's Die is rolled.")
	await _dice_roll_sfx()
	await _say("Rolled %s!" % _fmt_roll_result(community[-1]))
	if _is_trigger_face(community[-1]):
		await _resolve_community_effect(community[-1], community, live_comm_ids, player_hand, player_types, npcs)
	await _react_to_community_die(npcs, community)

	# ── Round 2 ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, live_comm_ids)})
	await _npc_round_banter(npcs, community, "round_2", RANK_CLIMB, 1)

	var rk2 := await _pick_reroll(player_hand, "Re-roll one private die?", player_types, npcs, community, live_comm_ids)
	await _do_player_reroll(rk2, player_hand, player_types, npcs, community, live_comm_ids)

	await _run_npc_phase(npcs, community, 2, player_hand, player_types, live_comm_ids)
	await wait_for_continue_fn.call()

	# ── Community Die 2 ───────────────────────────────────────────
	community.append(community_pool[1])
	live_comm_ids.append(comm_ids[1])
	await _say("The second Dealer's Die is rolled.")
	await _dice_roll_sfx()
	await _say("Rolled %s!" % _fmt_roll_result(community[-1]))
	if _is_trigger_face(community[-1]):
		await _resolve_community_effect(community[-1], community, live_comm_ids, player_hand, player_types, npcs)
	await _react_to_community_die(npcs, community)
	await wait_for_continue_fn.call()

	# ── Round 3 ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, live_comm_ids)})
	await _npc_round_banter(npcs, community, "round_3", RANK_DOUBLE_DUET, RANK_WANDERERS_HAND)

	var rk3 := await _pick_reroll(player_hand, "Re-roll one private die?", player_types, npcs, community, live_comm_ids)
	await _do_player_reroll(rk3, player_hand, player_types, npcs, community, live_comm_ids)

	await _run_npc_phase(npcs, community, 3, player_hand, player_types, live_comm_ids)

	# ── Showdown ──────────────────────────────────────────────────
	var p_final: Array = player_hand + community
	var player_rank: int = _rank_n(p_final)
	var npc_ranks: Array = []
	for npc in npcs:
		npc_ranks.append(_rank_n(npc["dice"] + community))
	var best_npc_rank: int = 0
	for r in npc_ranks:
		best_npc_rank = max(best_npc_rank, r)

	MyEventBus.emit("dialogue", {"text": "Showdown!"})
	if not npcs.is_empty():
		await _banter(npcs[rng.randi() % npcs.size()], "showdown_start", 0.6)

	# NPCs reveal in reverse order
	var best_rank_so_far: int = player_rank
	for i in range(npcs.size() - 1, -1, -1):
		var npc: Dictionary = npcs[i]
		var npc_name: String = (npc["name"] as String).capitalize()
		var npc_rank: int = npc_ranks[i]
		var is_last: bool = (i == 0)

		await _say("%s reveals their hand." % npc_name)

		var fired := false
		if not fired and npc_rank >= RANK_PILGRIMAGE:
			fired = await _banter(npc, "showdown_best", 0.7)
		if not fired and is_last and npc_rank > best_rank_so_far:
			fired = await _banter(npc, "showdown_winning_last", 0.7)
		if not fired and is_last and npc_rank < best_rank_so_far:
			fired = await _banter(npc, "showdown_weak_last", 0.5)
		if not fired and npc_rank > best_rank_so_far:
			fired = await _banter(npc, "showdown_leading", 0.5)
		if not fired and npc_rank < best_rank_so_far:
			fired = await _banter(npc, "showdown_losing", 0.45)
		if not fired:
			fired = await _banter(npc, "showdown_reveal", 0.4)

		npc["revealed"] = [true, true, true]
		await _say("%s's hand: " % npc_name + _row(npc_name, npc["dice"], npc["dice_types"], community, live_comm_ids))

		if npcs.size() > 1 and npc_crossreact:
			var other_idx: int = (i + 1) % npcs.size()
			await _banter_showdown_react(npcs[other_idx], npc_rank, best_rank_so_far, 0.5)

		best_rank_so_far = max(best_rank_so_far, npc_rank)

	# Player reveals last
	await _say("You reveal your hand:")
	await _say("Your hand: " + _row("You", player_hand, player_types, community, live_comm_ids))
	for npc in npcs:
		await _banter_showdown_react(npc, player_rank, best_rank_so_far, 0.4)
	await wait_for_continue_fn.call()

	# ── Results ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, live_comm_ids, true)})

	var void_draw: bool = player_rank == RANK_THE_VOID or best_npc_rank == RANK_THE_VOID
	if void_draw:
		await _say("The Void. The game ends in a draw.")
		MyEventBus.emit("give_gold", {"amount": player_committed})
	elif player_rank > best_npc_rank:
		await _say("You win the pot.")
		MyEventBus.emit("give_gold", {"amount": pot})
	elif player_rank == best_npc_rank:
		await _say("A tie. The wager is returned.")
		MyEventBus.emit("give_gold", {"amount": player_committed})
	else:
		await _say("You lose.")

	if not void_draw:
		var best_overall: int = max(player_rank, best_npc_rank)
		var top_count: int = (1 if player_rank == best_overall else 0)
		for r in npc_ranks:
			if r == best_overall:
				top_count += 1
		var player_result_key: String
		if player_rank == best_overall and top_count == 1:
			player_result_key = "showdown_npc_lose"
		elif player_rank == best_overall:
			player_result_key = "showdown_npc_tie"
		else:
			player_result_key = "showdown_npc_win"
		for i in range(npcs.size()):
			var npc: Dictionary = npcs[i]
			var npc_rank: int = npc_ranks[i]
			var result_keys: Array = [player_result_key]
			if npc_rank == best_overall and top_count == 1:
				result_keys.append("showdown_win")
			elif npc_rank == best_overall:
				result_keys.append("showdown_tie")
			else:
				result_keys.append("showdown_lose")
			await _banter_pool(npc, result_keys, 1.0)

	await wait_for_continue_fn.call()

	if void_draw:
		return "tie"
	elif player_rank > best_npc_rank:
		return "win"
	elif player_rank == best_npc_rank:
		return "tie"
	return "lose"


# ── Display helpers ───────────────────────────────────────────────────────────

func _table(player_hand: Array, player_types: Array, npcs: Array, community: Array, comm_ids: Array, reveal_all: bool = false) -> String:
	var lines: Array = []
	if not community.is_empty():
		lines.append("Community:  [b]%s[/b]\n" % _fmt_typed(community, comm_ids))
	lines.append(_row("You", player_hand, player_types, community, comm_ids))
	for npc in npcs:
		if not npc["folded"]:
			if reveal_all:
				lines.append(_row((npc["name"] as String).capitalize(), npc["dice"], npc["dice_types"], community, comm_ids))
			else:
				lines.append(_row_npc(
					(npc["name"] as String).capitalize(), npc["dice"], npc["dice_types"], npc["revealed"], community, comm_ids
				))
	return "\n".join(lines)


func _row(label: String, private_dice: Array, private_types: Array, community: Array, comm_ids: Array) -> String:
	var all_dice: Array = private_dice + community
	var priv_str: String = _fmt_typed(private_dice, private_types)
	if community.is_empty():
		return "%s:  [b]%s[/b]  —  %s" % [label, priv_str, _name_n(all_dice)]
	return "%s:  [b]%s  /  %s[/b]  —  %s" % [label, priv_str, _fmt_typed(community, comm_ids), _name_n(all_dice)]


func _row_npc(label: String, private_dice: Array, private_types: Array, revealed: Array, community: Array, comm_ids: Array) -> String:
	var parts: Array = []
	var known: Array = []
	for i in range(private_dice.size()):
		var color: String = _die_color(private_types[i]) if i < private_types.size() else ""
		if revealed[i]:
			var face: String = _face_char(private_dice[i])
			parts.append("[color=%s]%s[/color]" % [color, face] if color else face)
			known.append(private_dice[i])
		else:
			parts.append("[color=%s]?[/color]" % color if color else "?")
	var known_all: Array = known + community
	var hand_info: String = "Unknown" if known_all.is_empty() else _name_n(known_all)
	if community.is_empty():
		return "%s:  [b]%s[/b]  —  %s" % [label, "  –  ".join(parts), hand_info]
	return "%s:  [b]%s  /  %s[/b]  —  %s" % [label, "  –  ".join(parts), _fmt_typed(community, comm_ids), hand_info]


func _fmt_typed(dice: Array, die_types: Array) -> String:
	var parts: Array = []
	for i in range(dice.size()):
		var color: String = _die_color(die_types[i]) if i < die_types.size() else ""
		var face: String = _face_char(dice[i])
		if color:
			parts.append("[color=%s]%s[/color]" % [color, face])
		else:
			parts.append(face)
	return "  –  ".join(parts)


func _face_name(v) -> String:
	if v is int:
		if v == FACE_ROGUE: return "Rogue"
		if v == FACE_KNIGHT: return "Knight"
		return str(int(v))
	if v is String:
		if v == FACE_JOKER:    return "Joker"
		if v == FACE_BRIDGE:   return "Bridge"
		if v == FACE_CROWN:    return "Crown"
		if v == FACE_SKULL:    return "Skull"
		if v == FACE_PRIEST:   return "Priest"
		if v == FACE_MAGICIAN: return "Magician"
		if v == FACE_DRAGON:   return "Dragon"
	return str(int(v))


func _face_char(v) -> String:
	if v is String: return v
	var i := int(v)
	if i == FACE_ROGUE: return "Rogue"
	if i == FACE_KNIGHT: return "Knight"
	return str(i)


func _fmt_roll_result(v) -> String:
	if v is String:
		if v == FACE_JOKER:    return "Joker (J)"
		if v == FACE_BRIDGE:   return "Bridge (B)"
		if v == FACE_CROWN:    return "Crown (C)"
		if v == FACE_SKULL:    return "Skull (S)"
		if v == FACE_PRIEST:   return "Priest (P)"
		if v == FACE_MAGICIAN: return "Magician (M)"
		if v == FACE_DRAGON:   return "Dragon (D)"
		return v
	var i := int(v)
	if i == FACE_ROGUE: return "Rogue (0)"
	if i == FACE_KNIGHT: return "Knight (7)"
	return str(i)


# ── Hand ranking ──────────────────────────────────────────────────────────────

# Entry point — accepts any mix of ints (0–7), "J", "B"
func _rank_n(dice: Array) -> int:
	var jokers: int = 0
	var bridges: int = 0
	var crowns: int = 0
	var skulls: int = 0
	var blanks: int = 0
	var numerics: Array = []
	for v in dice:
		if v is String:
			if v == FACE_JOKER: jokers += 1
			elif v == FACE_BRIDGE: bridges += 1
			elif v == FACE_CROWN: crowns += 1
			elif v == FACE_SKULL: skulls += 1
			elif v == FACE_BLANK: blanks += 1
		else:
			numerics.append(int(v))
	if blanks == 5:
		return RANK_THE_VOID
	if jokers >= 5:
		return RANK_FULL_CIRCUS
	if jokers == 0:
		return _rank_pure(numerics, bridges, crowns, skulls)
	return _best_with_jokers(numerics, bridges, jokers, crowns, skulls)


func _name_n(dice: Array) -> String:
	var rank: int = _rank_n(dice)
	if rank == RANK_THE_VOID:            return "The Void"
	if rank >= RANK_FULL_CIRCUS:         return "Full Circus"
	if rank >= RANK_DOMINIUM:            return "The Dominium"
	if rank >= RANK_FIRST_BLIGHT:        return "First Blight"
	if rank >= RANK_KINGS_GRAVE:         return "King's Grave"
	if rank >= RANK_CROWNED_PREMONITION: return "Crowned Premonition"
	if rank >= RANK_FOUR_DAY_REIGN:      return "Four Day Reign"
	if rank >= RANK_DYNASTIC_MARRIAGE:   return "Dynastic Marriage"
	if rank >= RANK_DEAD_DYNASTY:        return "Dead Dynasty"
	if rank >= RANK_KINGS_THREE_ARCS:    return "King's Three Arcs"
	if rank >= RANK_CROWNED_FOUR_ARCS:   return "Crowned Four Arcs"
	if rank >= RANK_NECRONOMICON:        return "The Necronomicon"
	if rank >= RANK_FIVE_ARCS:           return "Five Arcs"
	if rank >= RANK_PREMONITION:         return "The Premonition"
	if rank >= RANK_KINGS_CLIMB:         return "The King's Climb"
	if rank >= RANK_CROWNED_LONG_ROAD:   return "Crowned Long Road"
	if rank >= RANK_PILGRIMAGE:          return "The Pilgrimage"
	if rank >= RANK_KINGS_SKULL:         return "King's Skull"
	if rank >= RANK_KINGS_EYES:          return "King's Eyes"
	if rank >= RANK_KINGS_WANDERER:      return "The King's Wanderer"
	if rank >= RANK_KINGS_COMMON:        return "The King's Common"
	if rank >= RANK_TRIUMVIRATE:         return "The Triumvirate"
	if rank >= RANK_CROWNED_GRAVEYARD:   return "Crowned Graveyard"
	if rank >= RANK_CROWNED_THREE_ARCS:  return "Crowned Three Arcs"
	if rank >= RANK_FOUR_ARCS:           return "Four Arcs"
	if rank >= RANK_WIDOWER:             return "The Widower"
	if rank >= RANK_STAIRWELL:           return "The Stairwell"
	if rank >= RANK_CROWNED_DRUNKARDS_CLIMB: return "Crowned Drunkard's Climb"
	if rank >= RANK_CROWNED_CLIMB:       return "The Crowned Climb"
	if rank >= RANK_LONG_ROAD:           return "The Long Road"
	if rank >= RANK_SUMMIT:              return "The Summit"
	if rank >= RANK_CROWNED_DUET:        return "Crowned Duet"
	if rank >= RANK_HEARTH:              return "The Hearth"
	if rank >= RANK_GRAVEYARD:           return "Graveyard"
	if rank >= RANK_PEREGRINE:           return "The Peregrine"
	if rank >= RANK_KINGS_HAND:          return "King's Hand"
	if rank >= RANK_CROWNED_SNAKE_EYES:  return "Crowned Snake Eyes"
	if rank >= RANK_CROWNED_WANDERERS_HAND: return "Crowned Wanderer's Hand"
	if rank >= RANK_CROWNED_COMMON:      return "The Crowned Common"
	if rank >= RANK_THREE_ARCS:          return "Three Arcs"
	if rank >= RANK_LOVERS_CLIMB:        return "Lover's Climb"
	if rank >= RANK_DOUBLE_DUET:         return "Double Duet"
	if rank >= RANK_DRUNKARDS_CLIMB:     return "Drunkard's Climb"
	if rank >= RANK_CROWNED_SKULL:       return "Crowned Skull"
	if rank >= RANK_SNAKE_EYES:          return "Snake Eyes"
	if rank >= RANK_CLIMB:               return "The Climb"
	if rank >= RANK_CROWNED_HAND:        return "Crowned Hand"
	if rank >= RANK_WANDERERS_HAND:      return "Wanderer's Hand"
	if rank >= RANK_COMMON:              return "The Common"
	return "Dead Hand"


# Brute-force Joker substitution: try each numeric value 0–7 for each Joker
func _best_with_jokers(numerics: Array, bridges: int, jokers: int, crowns: int = 0, skulls: int = 0) -> int:
	if jokers == 0:
		return _rank_pure(numerics, bridges, crowns, skulls)
	var best: int = 0
	for v in range(NUMERIC_COUNT):
		best = max(best, _best_with_jokers(numerics + [v], bridges, jokers - 1, crowns, skulls))
	return best


# Core ranking: numerics are ints (0–7), bridges is count of "B" dice
func _rank_numeric(numerics: Array, bridges: int) -> int:
	if numerics.is_empty() and bridges == 0:
		return 0

	# Sort unique numerics for run detection
	var sorted_n: Array = numerics.duplicate()
	sorted_n.sort()
	var unique: Array = []
	var seen: Dictionary = {}
	for v in sorted_n:
		if not seen.has(v):
			seen[v] = true
			unique.append(v)

	# Count occurrences — numerics get counted normally; B's tracked via bridges
	var counts: Dictionary = {}
	for v in numerics:
		counts[v] = counts.get(v, 0) + 1
	if bridges >= 1:
		counts[FACE_BRIDGE] = bridges

	var pair_vals: Array = []
	var triple_val = null
	var quad_val = null
	var penta_val = null
	for val in counts:
		if val == FACE_BRIDGE:
			continue  # Bridge is a run extender; it never pairs
		var cnt: int = counts[val]
		if cnt >= 5: penta_val = val
		elif cnt == 4: quad_val = val
		elif cnt == 3: triple_val = val
		elif cnt == 2: pair_vals.append(val)
	pair_vals.sort_custom(func(a, b): return _prv(a) < _prv(b))

	# Run detection with optional bridge
	var ri: Array = _best_run_info_with_bridge(unique, bridges >= 1)
	var run_len: int = ri[0]
	var run_high: int = ri[1]
	var run_values: Array = ri[2]

	# ── Hierarchy checks ──────────────────────────────────────────

	# Five Arcs
	if penta_val != null:
		return RANK_FIVE_ARCS + _prv(penta_val)

	# The Pilgrimage (5 consecutive including Bridge)
	if run_len >= 5:
		return RANK_PILGRIMAGE + run_high

	# Four Arcs
	if quad_val != null:
		return RANK_FOUR_ARCS + _prv(quad_val)

	# The Stairwell (4 in a row + pair inside run)
	if run_len >= 4 and pair_vals.size() >= 1:
		if run_values.has(pair_vals[-1]):
			return RANK_STAIRWELL + run_high

	# The Long Road (4 consecutive)
	if run_len >= 4:
		return RANK_LONG_ROAD + run_high

	# The Summit (triple overlapping 3 in a row)
	if triple_val != null and run_len >= 3 and run_values.has(triple_val):
		return RANK_SUMMIT + _prv(triple_val) * 10 + run_high

	# The Hearth (triple + pair)
	if triple_val != null and pair_vals.size() >= 1:
		return RANK_HEARTH + _prv(triple_val) * 10 + _prv(pair_vals[0])

	# The Peregrine (3 in a row + pair outside run)
	if run_len >= 3 and pair_vals.size() == 1:
		if not run_values.has(pair_vals[0]):
			return RANK_PEREGRINE + run_high * 10 + _prv(pair_vals[0])

	# Three Arcs
	if triple_val != null:
		var ho: int = 0
		for v in numerics:
			if not (triple_val is int and v == triple_val):
				ho = max(ho, v)
		return RANK_THREE_ARCS + _prv(triple_val) * 10 + ho

	# Lover's Climb (3 in a row + two pairs both inside run)
	if run_len >= 3 and pair_vals.size() >= 2:
		var all_in := true
		for pv in pair_vals:
			if not run_values.has(pv):
				all_in = false
				break
		if all_in:
			return RANK_LOVERS_CLIMB + run_high

	# Double Duet
	if pair_vals.size() >= 2:
		return RANK_DOUBLE_DUET + _prv(pair_vals[-1]) * 10 + _prv(pair_vals[-2])

	# Drunkard's Climb (3 in a row + pair inside run)
	if run_len >= 3 and pair_vals.size() == 1:
		if run_values.has(pair_vals[0]):
			return RANK_DRUNKARDS_CLIMB + run_high

	# Snake Eyes (pair of Rogues)
	if counts.get(FACE_ROGUE, 0) >= 2:
		return RANK_SNAKE_EYES

	# The Climb (3+ consecutive)
	if run_len >= 3:
		return RANK_CLIMB + run_len * 100 + run_high

	# Wanderer's Hand / The Common
	if pair_vals.size() == 1:
		var pv = pair_vals[0]
		var prv: int = _prv(pv)
		var hk: int = 0
		for v in numerics:
			if v != pv:
				hk = max(hk, v)
		return (RANK_WANDERERS_HAND if prv >= 4 else RANK_COMMON) + prv * 10 + hk

	# Dead Hand
	if not numerics.is_empty():
		return numerics.max()
	return 0


func _rank_pure(numerics: Array, bridges: int, crowns: int = 0, skulls: int = 0) -> int:
	var base := _rank_numeric(numerics, bridges)
	var best := base
	if crowns > 0:
		best = max(best, _crown_rank(crowns, base))
	if skulls > 0:
		best = max(best, _skull_rank(skulls, crowns, base))
	return best


func _rank_to_tier(rank: int) -> String:
	if rank >= RANK_FIVE_ARCS:     return "five_arcs"
	if rank >= RANK_PILGRIMAGE:    return "pilgrimage"
	if rank >= RANK_FOUR_ARCS:     return "four_arcs"
	if rank >= RANK_STAIRWELL:     return "stairwell"
	if rank >= RANK_LONG_ROAD:     return "long_road"
	if rank >= RANK_SUMMIT:        return "summit"
	if rank >= RANK_HEARTH:        return "hearth"
	if rank >= RANK_PEREGRINE:     return "royal_climb"
	if rank >= RANK_THREE_ARCS:    return "three_arcs"
	if rank >= RANK_LOVERS_CLIMB:  return "lovers_climb"
	if rank >= RANK_DOUBLE_DUET:   return "double_trouble"
	if rank >= RANK_DRUNKARDS_CLIMB: return "drunkard_climb"
	if rank >= RANK_SNAKE_EYES:    return "snake_eyes"
	if rank >= RANK_CLIMB:         return "climb"
	if rank >= RANK_WANDERERS_HAND: return "high_pair"
	if rank >= RANK_COMMON:        return "low_pair"
	return "none"


func _crown_rank(crowns: int, base_rank: int) -> int:
	var tier: String = _rank_to_tier(base_rank)
	if crowns >= 5:
		return RANK_DOMINIUM
	if crowns == 4:
		return RANK_FOUR_DAY_REIGN
	if crowns == 3:
		if tier == "low_pair" or tier == "high_pair" or tier == "snake_eyes":
			return RANK_DYNASTIC_MARRIAGE
		return max(base_rank, RANK_TRIUMVIRATE)
	if crowns == 2:
		match tier:
			"none":        return RANK_KINGS_HAND
			"low_pair":    return RANK_KINGS_COMMON
			"high_pair":   return RANK_KINGS_WANDERER
			"snake_eyes":  return RANK_KINGS_EYES
			"climb":       return RANK_KINGS_CLIMB
			"three_arcs":  return RANK_KINGS_THREE_ARCS
			_:             return max(base_rank, RANK_KINGS_HAND)
	# crowns == 1
	match tier:
		"none":            return RANK_CROWNED_HAND
		"low_pair":        return RANK_CROWNED_COMMON
		"high_pair":       return RANK_CROWNED_WANDERERS_HAND
		"snake_eyes":      return RANK_CROWNED_SNAKE_EYES
		"double_trouble":  return RANK_CROWNED_DUET
		"climb":           return RANK_CROWNED_CLIMB
		"drunkard_climb":  return RANK_CROWNED_DRUNKARDS_CLIMB
		"three_arcs":      return RANK_CROWNED_THREE_ARCS
		"long_road":       return RANK_CROWNED_LONG_ROAD
		"four_arcs":       return RANK_CROWNED_FOUR_ARCS
		_:                 return max(base_rank, RANK_CROWNED_HAND)


func _skull_rank(skulls: int, crowns: int, base_rank: int) -> int:
	if skulls >= 5:
		return RANK_NECRONOMICON
	if skulls == 4:
		return RANK_CROWNED_PREMONITION if crowns >= 1 else RANK_PREMONITION
	if skulls == 3:
		if crowns >= 2: return RANK_KINGS_GRAVE
		if crowns >= 1: return RANK_CROWNED_GRAVEYARD
		return RANK_WIDOWER if base_rank >= RANK_COMMON else RANK_GRAVEYARD
	if skulls == 1 and crowns > 0:
		if crowns >= 4: return RANK_FIRST_BLIGHT
		if crowns >= 3: return RANK_DEAD_DYNASTY
		if crowns >= 2: return RANK_KINGS_SKULL
		return RANK_CROWNED_SKULL
	return 0  # 2 skulls or 1 skull alone: no skull-specific hand


# Pair rank value — converts any pair key (int or "B") to an int for scoring
func _prv(v) -> int:
	if v is String and v == FACE_BRIDGE: return FACE_KNIGHT
	return int(v)


# ── Run detection ─────────────────────────────────────────────────────────────

# Returns [run_len, run_high, run_values: Array]
# run_values lists the actual values (ints and/or "B") in the best run found.
func _best_run_info_with_bridge(unique: Array, use_bridge: bool) -> Array:
	# 1. Normal best run (no bridge)
	var best_len: int = 0
	var best_high: int = 0
	var best_vals: Array = []

	if not unique.is_empty():
		var cs: int = 0  # current run start index
		var cl: int = 1  # current run length
		for i in range(1, unique.size()):
			if unique[i] == unique[i - 1] + 1:
				cl += 1
			else:
				if cl > best_len or (cl == best_len and unique[i - 1] > best_high):
					best_len = cl
					best_high = unique[i - 1]
					best_vals = unique.slice(cs, i)
				cs = i
				cl = 1
		if cl > best_len or (cl == best_len and unique[-1] > best_high):
			best_len = cl
			best_high = unique[-1]
			best_vals = unique.slice(cs, unique.size())

	if best_len == 0 and not unique.is_empty():
		best_len = 1
		best_high = unique[-1]
		best_vals = [unique[-1]]

	if not use_bridge:
		return [best_len, best_high, best_vals]

	# 2a. Top extension: run ending at 7 or 6, extend with B above
	for top in [FACE_KNIGHT, 6]:
		if top in unique:
			var ri: Array = _run_ending_at(unique, top)
			var ext_len: int = ri[0] + 1
			if ext_len > best_len or (ext_len == best_len and top > best_high):
				best_len = ext_len
				best_high = top
				best_vals = (ri[1] as Array) + [FACE_BRIDGE]

	# 2b. Bottom extension: run starting at 0 or 1, extend with B below
	for bot in [FACE_ROGUE, 1]:
		if bot in unique:
			var ri: Array = _run_starting_at(unique, bot)
			var ext_len: int = ri[0] + 1
			var ext_high: int = bot + ri[0] - 1
			if ext_len > best_len or (ext_len == best_len and ext_high > best_high):
				best_len = ext_len
				best_high = ext_high
				best_vals = [FACE_BRIDGE] + (ri[1] as Array)

	# 2c. Wrap bridge: high group + B + low group
	for top in [FACE_KNIGHT, 6]:
		if top in unique:
			var hi: Array = _run_ending_at(unique, top)
			for bot in [FACE_ROGUE, 1]:
				if bot in unique:
					var lo: Array = _run_starting_at(unique, bot)
					var total: int = (hi[0] as int) + 1 + (lo[0] as int)
					if total > best_len or (total == best_len and top > best_high):
						best_len = total
						best_high = top
						best_vals = (hi[1] as Array) + [FACE_BRIDGE] + (lo[1] as Array)

	return [best_len, best_high, best_vals]


# Returns [length, [values]] for the longest consecutive run ending at `top`
func _run_ending_at(unique: Array, top: int) -> Array:
	var values: Array = [top]
	var cur: int = top - 1
	while cur in unique:
		values.insert(0, cur)
		cur -= 1
	return [values.size(), values]


# Returns [length, [values]] for the longest consecutive run starting at `bot`
func _run_starting_at(unique: Array, bot: int) -> Array:
	var values: Array = [bot]
	var cur: int = bot + 1
	while cur in unique:
		values.append(cur)
		cur += 1
	return [values.size(), values]


# ── NPC decision ─────────────────────────────────────────────────────────────

# Returns -1 (stand pat) or 0/1/2 (index of private die to re-roll).
# Scores all four options using EV gain, Pr(improvement), info-leak cost,
# and hand conservatism, weighted by the gambler's difficulty and phase.
func _npc_decide(npc: Dictionary, community: Array, phase: int, difficulty: String) -> int:
	var private_dice: Array = npc["dice"]
	var private_types: Array = npc["dice_types"]
	var revealed: Array = npc["revealed"]

	var phases: Array = AI_PROFILES.get(difficulty, AI_PROFILES["easy"])
	var profile: Dictionary = phases[clampi(phase - 1, 0, phases.size() - 1)]

	var current_rank: int = _rank_n(private_dice + community)
	var current_norm: float = current_rank / MAX_RANK

	var best_score: float = profile["w_conserve"] * current_norm \
		+ profile["stand_bias"] + rng.randf() * profile["noise"]
	var best_action: int = -1

	for i in range(private_dice.size()):
		var faces: Array = dice_db.get(private_types[i], {}).get("values", [])
		if faces.is_empty():
			continue
		var rank_sum: float = 0.0
		var improve: int = 0
		for v in faces:
			var trial: Array = private_dice.duplicate()
			trial[i] = v
			var r: int = _rank_n(trial + community)
			rank_sum += r
			if r > current_rank:
				improve += 1
		var ev_gain: float = (rank_sum / faces.size() - current_rank) / MAX_RANK
		var pr_improve: float = float(improve) / faces.size()
		var is_rev: float = 1.0 if revealed[i] else 0.0

		var score: float = profile["w_ev"] * ev_gain \
			+ profile["w_pr"] * pr_improve \
			+ profile["w_reveal"] * is_rev \
			- profile["w_conserve"] * current_norm \
			+ rng.randf() * profile["noise"]

		if score > best_score:
			best_score = score
			best_action = i

	return best_action


# ── Dice helpers ──────────────────────────────────────────────────────────────

func _roll_die(die_id: String):
	var values: Array = dice_db.get(die_id, {}).get("values", [1, 2, 3, 4, 5, 6])
	return values[rng.randi() % values.size()]


func _die_color(die_id: String) -> String:
	return dice_db.get(die_id, {}).get("color", "")


func _roll_raw(count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append(rng.randi_range(1, 6))
	return result


func _roll_with_lck(lck: int) -> int:
	var rolls: int = ADVANTAGE_ROLLS if lck >= LCK_ADVANTAGE_THRESHOLD else 1
	var best: int = 0
	for i in range(rolls):
		best = max(best, rng.randi_range(1, 6))
	return best


func _roll_typed_with_lck(die_id: String, lck: int):
	var count := ADVANTAGE_ROLLS if lck >= LCK_ADVANTAGE_THRESHOLD else 1
	var best = null
	for _i in range(count):
		var v = _roll_die(die_id)
		if best == null or _sort_value(v) > _sort_value(best):
			best = v
	return best


# Returns index of the worst die to re-roll; J and B are kept (treated as high value)
func _worst_idx(dice: Array) -> int:
	var min_idx: int = 0
	for i in range(1, dice.size()):
		if _sort_value(dice[i]) < _sort_value(dice[min_idx]):
			min_idx = i
	return min_idx


func _sort_value(v) -> float:
	if v is String:
		if v == FACE_JOKER:    return SORT_JOKER
		if v == FACE_CROWN:    return SORT_CROWN
		if v == FACE_BRIDGE:   return SORT_BRIDGE
		if v == FACE_PRIEST or v == FACE_MAGICIAN or v == FACE_DRAGON: return SORT_TRIGGER
		if v == FACE_SKULL:    return SORT_SKULL
		return 50.0
	return float(v)


# ── Banter helpers ────────────────────────────────────────────────────────────

func _npc_visible_dice(npc: Dictionary) -> Array:
	var visible: Array = []
	for i in range(npc["dice"].size()):
		if npc["revealed"][i]:
			visible.append(npc["dice"][i])
	return visible


func _creates_pair(face, pool: Array) -> bool:
	if face is String and face == FACE_BRIDGE:
		return false
	return pool.has(face)



func _face_has_synergy(face, pool: Array) -> bool:
	if face is String:
		return true
	if pool.has(face):
		return true
	for v in pool:
		if v is int and (v == face - 1 or v == face + 1):
			return true
	return false


func _is_good_visible(dice: Array) -> bool:
	return _rank_n(dice) >= RANK_CLIMB


func _say(line: String) -> void:
	MyEventBus.emit("continue_text", {"text": line, "linebreak": false})
	await MyEventBus.await_event("typing_finished")


func _banter(npc: Dictionary, trigger: String, chance: float = 0.45) -> bool:
	var b: Dictionary = npc.get("banter", {})
	if not b.has(trigger):
		return false
	var lines: Array = b[trigger]
	if lines.is_empty():
		return false
	if rng.randf() > chance:
		return false
	await _say(lines[rng.randi() % lines.size()])
	return true


func _banter_pool(npc: Dictionary, keys: Array, chance: float = 1.0) -> bool:
	var pool: Array = []
	for key in keys:
		pool += npc.get("banter", {}).get(key, [])
	if pool.is_empty() or rng.randf() > chance:
		return false
	await _say(pool[rng.randi() % pool.size()])
	return true


func _banter_showdown_react(npc: Dictionary, revealed_rank: int, best_so_far: int, chance: float) -> bool:
	var key: String
	if revealed_rank > best_so_far:
		key = "showdown_react_best"
	elif revealed_rank >= RANK_WANDERERS_HAND:
		key = "showdown_react_good"
	else:
		key = "showdown_react_bad"
	return await _banter(npc, key, chance)


func _is_special_face_ext(face) -> bool:
	if face is String: return true
	if face is int: return face == FACE_ROGUE or face == FACE_KNIGHT
	return false


func _special_die_key(face) -> String:
	if face is String:
		if face == FACE_JOKER:    return "joker"
		if face == FACE_BRIDGE:   return "bridge"
		if face == FACE_CROWN:    return "crown"
		if face == FACE_SKULL:    return "skull"
		if face == FACE_PRIEST:   return "priest"
		if face == FACE_MAGICIAN: return "magician"
		if face == FACE_DRAGON:   return "dragon"
	if face is int:
		if face == FACE_ROGUE: return "rogue"
		if face == FACE_KNIGHT: return "knight"
	return ""


func _is_trigger_face(face) -> bool:
	return face is String and (face == FACE_PRIEST or face == FACE_MAGICIAN or face == FACE_DRAGON)


func _is_standard_face(face) -> bool:
	return face is int and face >= 1 and face <= 6


func _dice_roll_sfx() -> void:
	MyEventBus.emit("play_sfx", {"sound": "dice"})
	if delay_fn.is_valid():
		await delay_fn.call()


func _react_stand_pat(reactors: Array) -> void:
	if reactors.is_empty():
		return
	var reactor: Dictionary = reactors[rng.randi() % reactors.size()]
	await _banter(reactor, "react_stand_pat", 0.35)


func _react_to_npc_reroll(all_npcs: Array, acting_npc: Dictionary, rerolled_idx: int, community: Array) -> void:
	var others: Array = all_npcs.filter(func(n): return n != acting_npc)
	if others.is_empty():
		return
	var new_face = acting_npc["dice"][rerolled_idx]
	var other_pool: Array = []
	for i in range(acting_npc["dice"].size()):
		if i != rerolled_idx:
			other_pool.append(acting_npc["dice"][i])
	other_pool += community
	var reactor: Dictionary = others[rng.randi() % others.size()]
	if _is_good_visible(acting_npc["dice"] + community):
		await _banter(reactor, "react_good_roll", 0.35)
	elif _creates_pair(new_face, other_pool):
		await _banter(reactor, "react_pair", 0.35)
	elif not _face_has_synergy(new_face, other_pool):
		await _banter(reactor, "react_no_combo", 0.35)


func _run_npc_phase(npcs: Array, community: Array, phase: int, player_hand: Array, player_types: Array, comm_ids: Array) -> void:
	for npc in npcs:
		var npc_name: String = (npc["name"] as String).capitalize()
		var action: int = _npc_decide(npc, community, phase, npc.get("difficulty", "easy"))
		if action >= 0:
			# 10a: NPC rerolls
			await _say("%s re-rolls a die." % npc_name)
			await _banter(npc, "reroll")
			await _dice_roll_sfx()
			npc["dice"][action] = _roll_die(npc["dice_types"][action])
			npc["revealed"][action] = true
			var new_face = npc["dice"][action]

			await _say("%s rolled %s!" % [npc_name, _fmt_roll_result(new_face)])

			var other_pool: Array = []
			for i in range(npc["dice"].size()):
				if i != action and npc["revealed"][i]:
					other_pool.append(npc["dice"][i])
			other_pool += community

			var fired := false
			if _is_special_face_ext(new_face):
				var suffix: String = _special_die_key(new_face)
				if not suffix.is_empty():
					fired = await _banter(npc, "special_die_self_" + suffix, 0.4)
				if not fired:
					fired = await _banter(npc, "special_die_self", 0.4)
			if not fired and _is_good_visible(other_pool + [new_face]):
				fired = await _banter(npc, "good_roll", 0.4)
			if not fired and _creates_pair(new_face, other_pool):
				fired = await _banter(npc, "pair_hit", 0.4)
			if not fired and not _face_has_synergy(new_face, other_pool):
				await _banter(npc, "no_combo", 0.4)

			if _is_trigger_face(new_face):
				await _resolve_npc_reroll_effect(new_face, npc, action, player_hand, player_types, npcs, community, comm_ids)

			if npc_crossreact:
				await _react_to_npc_reroll(npcs, npc, action, community)
			await _say("%s's hand: " % npc_name + _row_npc(npc_name, npc["dice"], npc["dice_types"], npc["revealed"], community, comm_ids))
		else:
			# 10b: NPC holds pat
			await _say("%s held pat." % npc_name)
			await _banter(npc, "keep_hand")
			if npc_crossreact:
				var others: Array = npcs.filter(func(n): return n != npc)
				await _react_stand_pat(others)


func _react_to_player_reroll(npcs: Array, rerolled_idx: int, player_hand: Array, community: Array) -> void:
	if npcs.is_empty():
		return
	var new_face = player_hand[rerolled_idx]
	var reactor: Dictionary = npcs[rng.randi() % npcs.size()]
	if _is_good_visible([new_face] + community):
		await _banter(reactor, "react_good_roll", 0.45)
	elif _creates_pair(new_face, community):
		await _banter(reactor, "react_pair", 0.45)
	elif not _face_has_synergy(new_face, community):
		await _banter(reactor, "react_no_combo", 0.45)


func _react_to_community_die(npcs: Array, community: Array) -> void:
	if npcs.is_empty() or community.is_empty():
		return
	var new_comm = community[-1]
	var comm_before: Array = community.slice(0, community.size() - 1)
	for npc in npcs:
		var fired := false
		if _is_special_face_ext(new_comm):
			var suffix: String = _special_die_key(new_comm)
			if not suffix.is_empty():
				fired = await _banter(npc, "special_die_community_" + suffix, 1.0)
			if not fired:
				fired = await _banter(npc, "special_die_community", 1.0)
		if not fired:
			var npc_pool: Array = _npc_visible_dice(npc) + comm_before
			if _face_has_synergy(new_comm, npc_pool):
				await _banter(npc, "community_favor_self", 1.0)
			else:
				await _banter(npc, "community_favor_other", 1.0)


# ── Run helpers ───────────────────────────────────────────────────────────────

func _build_reroll_choices(player_hand: Array) -> Array:
	return [
		{"text": "Re-roll the %s" % _face_name(player_hand[0]), "key": "0"},
		{"text": "Re-roll the %s" % _face_name(player_hand[1]), "key": "1"},
		{"text": "Re-roll the %s" % _face_name(player_hand[2]), "key": "2"},
		{"text": "Stand pat", "key": "stand"},
		{"text": "Hand Rankings", "key": "hierarchy", "type": "back"},
	]


func _pick_reroll(player_hand: Array, header: String, player_types: Array, npcs: Array, community: Array, comm_ids: Array) -> String:
	while true:
		MyEventBus.emit("show_choices", {"choices": _build_reroll_choices(player_hand), "header": header})
		var rr: Dictionary = await capture_input_fn.call()
		var rk: String = rr.get("key", "stand")
		if rk != "hierarchy":
			return rk
		MyEventBus.emit("dialogue", {"text": _build_hierarchy(player_types, npcs, comm_ids)})
		await wait_for_continue_fn.call()
		MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	return "stand"


func _do_player_reroll(rk: String, player_hand: Array, player_types: Array, npcs: Array, community: Array, comm_ids: Array) -> void:
	if rk != "stand":
		await _say("You re-roll a die.")
		await _dice_roll_sfx()
		var lck: int = stat_callback.call("lck") if stat_callback.is_valid() else 0
		player_hand[int(rk)] = _roll_typed_with_lck(player_types[int(rk)], lck)
		await _say("You rolled %s!" % _fmt_roll_result(player_hand[int(rk)]))
		await _react_to_player_reroll(npcs, int(rk), player_hand, community)
		if _is_trigger_face(player_hand[int(rk)]):
			await _resolve_player_reroll_effect(player_hand[int(rk)], int(rk), player_hand, player_types, npcs, community, comm_ids)
		await _say("Your hand: " + _fmt_typed(player_hand, player_types))
	else:
		await _say("You hold pat.")
		await _react_stand_pat(npcs)


func _npc_round_banter(npcs: Array, community: Array, round_key: String, high_threshold: int, low_threshold: int) -> void:
	if npcs.is_empty():
		return
	var sp: Dictionary = npcs[rng.randi() % npcs.size()]
	var rank: int = _rank_n(sp["dice"] + community)
	var keys: Array = [round_key]
	if rank >= high_threshold:
		keys.append("round_good_hand")
	elif rank < low_threshold:
		keys.append("round_bad_hand")
	await _banter_pool(sp, keys, 0.55)


# ── Hierarchy builder ─────────────────────────────────────────────────────────

func _active_faces(player_types: Array, npcs: Array, comm_ids: Array) -> Dictionary:
	var ids: Array = player_types.duplicate()
	for id in comm_ids:
		ids.append(id)
	for npc in npcs:
		for dt in npc.get("dice_types", []):
			ids.append(dt)
	var f := {"crown": false, "joker": false, "bridge": false, "skull": false, "rogue": false, "knight": false, "blank": false, "priest": false, "magician": false, "dragon": false}
	for die_id in ids:
		for v in dice_db.get(die_id, {}).get("values", []):
			if v == FACE_CROWN:       f["crown"] = true
			elif v == FACE_JOKER:     f["joker"] = true
			elif v == FACE_BRIDGE:    f["bridge"] = true
			elif v == FACE_SKULL:     f["skull"] = true
			elif v == FACE_BLANK:     f["blank"] = true
			elif v == FACE_PRIEST:    f["priest"] = true
			elif v == FACE_MAGICIAN:  f["magician"] = true
			elif v == FACE_DRAGON:    f["dragon"] = true
			elif v is int and v == FACE_ROGUE:  f["rogue"] = true
			elif v is int and v == FACE_KNIGHT: f["knight"] = true
	return f


func _build_hierarchy(player_types: Array, npcs: Array, comm_ids: Array) -> String:
	var f := _active_faces(player_types, npcs, comm_ids)
	var crown: bool = f["crown"]
	var joker: bool = f["joker"]
	var bridge: bool = f["bridge"]
	var skull: bool = f["skull"]
	var blank: bool = f["blank"]
	var rogue: bool = f["rogue"]
	var knight: bool = f["knight"]
	var both: bool = crown and skull
	var max_num = "7" if knight else "6"
	var min_num = "0" if rogue else "1"

	var lines: Array = []

	if joker:
		lines.append("Full Circus             —  five Jokers (ex: J-J-J-J-J)")
	if crown:
		lines.append("The Dominium            —  five Crowns (ex: C-C-C-C-C)")
		if both:
			lines.append("First Blight           —  Skull + four Crowns  (ex: C-C-C-C-S)")
		lines.append("Four Day Reign          —  four Crowns (ex: C-C-C-C)")
	if skull:
		lines.append("The Necronomicon        —  five Skulls (ex: S-S-S-S-S)")
	if crown:
		lines.append("The Dynastic Marriage   —  three Crowns + any pair (ex: C-C-C-1-1)")
		if both:
			lines.append("Dead Dynasty            —  Skull + three Crowns  (ex: C-C-C-S)")
	lines.append("Five Arcs               —  five of a kind")
	if skull:
		lines.append("The Premonition         —  four Skulls (ex: S-S-S-S)")
	lines.append("The Pilgrimage          —  five in a row  (ex: 2-3-4-5-6)")
	if both:
		lines.append("King's Skull            —  two Crowns + Skull  (ex: C-C-S)")
	if crown:
		lines.append("The Triumvirate         —  three Crowns (ex: C-C-C)")
	lines.append("Four Arcs               —  four of a kind")
	if skull:
		lines.append("The Widower             —  three Skulls + pair  (ex: S-S-S-1-1)")
	lines.append("The Stairwell           —  four in a row with a pair inside  (ex: 1-1-2-3-4)")
	lines.append("The Long Road           —  four in a row  (ex: 1-2-3-4)")
	lines.append("The Summit              —  triple overlapping a climb  (ex: 3-3-3-2-4)")
	lines.append("The Hearth              —  triple + pair  (ex: 1-1-1-2-2)")
	if skull:
		lines.append("Graveyard               —  three Skulls  (ex: S-S-S)")
	lines.append("The Peregrine             —  three in a row + a separate pair  (ex: 1-2-3-5-5)")
	if crown:
		lines.append("King's Hand             —  two Crowns   (ex: C-C)")
	lines.append("Three Arcs              —  three of a kind")
	lines.append("Lover's Climb           —  three in a row with two pairs inside  (ex: 1-1-2-2-3)")
	lines.append("Double Duet          —  two different pairs  (ex: 1-1-2-2)")
	lines.append("Drunkard's Climb        —  three in a row with a pair inside  (ex: 1-1-2-3)")
	if both:
		lines.append("Crowned Skull           —  Crown + Skull  (ex: C-S)")
	if rogue:
		lines.append("Snake Eyes              —  pair of Rogues  (0-0)")
	lines.append("The Climb               —  three in a row  (ex: 1-2-3)")
	if crown:
		lines.append("Crowned Hand            —  Crown alone")
	if bridge:
		lines.append("Wanderer's Hand         —  pair of 4-%s or Bridge" % max_num)
	else:
		lines.append("Wanderer's Hand         —  pair of 4-%s" % max_num)
	lines.append("The Common              —  pair of 1-3")
	lines.append("Dead Hand               —  no match")

	var special: Array = []
	if crown:
		special.append("  Crown  (C)    —  upgrades any hand to its crowned form; a lone Crown is a Crowned Hand")
	if joker:
		special.append("  Joker  (J)    —  wild; counts as any numeric value %s–%s" % [min_num,max_num])
	if bridge:
		var top_seq = "6 or 7" if knight else "6"
		var bot_seq = "0 or 1" if rogue else "1"
		special.append("  Bridge (B)    —  connects %s to %s in a run; usable once per sequence" % [top_seq, bot_seq])
	if skull:
		special.append("  Skull  (S)    —  forms dedicated Graveyard hands; three or more Skulls beat most ordinary hands")
	if blank:
		special.append("  Blank  (X)    —  does nothing; five Blanks form The Void, which ends the game in a draw")

	var out: String = "\n".join(lines)
	if not special.is_empty():
		out += "\n──\nSpecial faces:\n" + "\n".join(special)
	return out


# ── Trigger-face resolvers ────────────────────────────────────────────────────

func _resolve_player_reroll_effect(face, die_idx: int, player_hand: Array, player_types: Array, npcs: Array, community: Array, comm_ids: Array) -> void:
	match face:
		FACE_PRIEST:   await _effect_priest_reroll(true,  -1, player_hand, player_types, npcs, community, comm_ids)
		FACE_MAGICIAN: await _effect_magician_player(die_idx, player_hand, player_types, npcs)
		FACE_DRAGON:   await _effect_dragon_player(community, comm_ids)


func _resolve_npc_reroll_effect(face, acting_npc: Dictionary, die_idx: int, player_hand: Array, player_types: Array, npcs: Array, community: Array, comm_ids: Array) -> void:
	var npc_idx: int = npcs.find(acting_npc)
	match face:
		FACE_PRIEST:   await _effect_priest_reroll(false, npc_idx, player_hand, player_types, npcs, community, comm_ids)
		FACE_MAGICIAN: await _effect_magician_npc(acting_npc, die_idx, player_hand, player_types)
		FACE_DRAGON:   await _effect_dragon_npc(acting_npc, community, comm_ids)


func _resolve_community_effect(face, community: Array, comm_ids: Array, player_hand: Array, player_types: Array, npcs: Array) -> void:
	match face:
		FACE_PRIEST:   await _effect_priest_community(player_hand, player_types, npcs)
		FACE_MAGICIAN: await _effect_magician_community(player_hand, player_types, npcs)
		FACE_DRAGON:   await _effect_dragon_community(community, comm_ids)


# ── Priest ────────────────────────────────────────────────────────────────────

func _priest_standardize(die_arr: Array, type_arr: Array, idx: int) -> void:
	type_arr[idx] = "standard"
	if not _is_standard_face(die_arr[idx]):
		die_arr[idx] = _roll_die("standard")


func _effect_priest_reroll(is_player: bool, npc_idx: int, player_hand: Array, player_types: Array, npcs: Array, community: Array, comm_ids: Array) -> void:
	await _say("Priest! Every die outside the hand is converted to a standard die.")
	if is_player:
		for npc in npcs:
			for i in range(npc["dice"].size()):
				_priest_standardize(npc["dice"], npc["dice_types"], i)
		for i in range(community.size()):
			_priest_standardize(community, comm_ids, i)
	else:
		for i in range(player_hand.size()):
			_priest_standardize(player_hand, player_types, i)
		for i in range(npcs.size()):
			if i == npc_idx:
				continue
			for j in range(npcs[i]["dice"].size()):
				_priest_standardize(npcs[i]["dice"], npcs[i]["dice_types"], j)
		for i in range(community.size()):
			_priest_standardize(community, comm_ids, i)


func _effect_priest_community(player_hand: Array, player_types: Array, npcs: Array) -> void:
	await _say("Priest! All players' private dice are converted to standard dice.")
	for i in range(player_hand.size()):
		_priest_standardize(player_hand, player_types, i)
	for npc in npcs:
		for i in range(npc["dice"].size()):
			_priest_standardize(npc["dice"], npc["dice_types"], i)


# ── Magician ──────────────────────────────────────────────────────────────────

func _effect_magician_player(m_idx: int, player_hand: Array, player_types: Array, npcs: Array) -> void:
	if npcs.is_empty():
		await _say("Magician! But there is no one to swap with.")
		return
	await _say("Magician! Choose a participant to swap a die with.")
	var npc_choices: Array = []
	for i in range(npcs.size()):
		npc_choices.append({"text": (npcs[i]["name"] as String).capitalize(), "key": str(i)})
	MyEventBus.emit("show_choices", {"choices": npc_choices, "header": "Magician — swap with:"})
	var r1: Dictionary = await capture_input_fn.call()
	var n: int = int(r1.get("key", "0"))
	var die_choices: Array = []
	for i in range(npcs[n]["dice"].size()):
		var label: String
		if npcs[n]["revealed"][i]:
			label = "Take their %s" % _face_name(npcs[n]["dice"][i])
		else:
			label = "Take their unknown die (Die %d)" % (i + 1)
		die_choices.append({"text": label, "key": str(i)})
	MyEventBus.emit("show_choices", {"choices": die_choices, "header": "Which die?"})
	var r2: Dictionary = await capture_input_fn.call()
	var n_idx: int = int(r2.get("key", "0"))
	var tmp_face = player_hand[m_idx]
	var tmp_type: String = player_types[m_idx]
	player_hand[m_idx] = npcs[n]["dice"][n_idx]
	player_types[m_idx] = npcs[n]["dice_types"][n_idx]
	npcs[n]["dice"][n_idx] = tmp_face
	npcs[n]["dice_types"][n_idx] = tmp_type
	npcs[n]["revealed"][n_idx] = true
	await _say("You receive %s's die; the Magician's die passes to them." \
		% (npcs[n]["name"] as String).capitalize())


func _effect_magician_npc(acting_npc: Dictionary, m_idx: int, player_hand: Array, player_types: Array) -> void:
	var npc_name: String = (acting_npc["name"] as String).capitalize()
	await _say("Magician! %s demands you give them one of your dice." % npc_name)
	var choices: Array = []
	for i in range(player_hand.size()):
		choices.append({"text": "Give the %s" % _face_name(player_hand[i]), "key": str(i)})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Which die do you give up?"})
	var rr: Dictionary = await capture_input_fn.call()
	var p_idx: int = int(rr.get("key", "0"))
	var tmp_face = player_hand[p_idx]
	var tmp_type: String = player_types[p_idx]
	player_hand[p_idx] = acting_npc["dice"][m_idx]
	player_types[p_idx] = acting_npc["dice_types"][m_idx]
	acting_npc["dice"][m_idx] = tmp_face
	acting_npc["dice_types"][m_idx] = tmp_type
	await _say("You hand over your %s and receive the Magician's die." % _face_name(tmp_face))


func _effect_magician_community(player_hand: Array, player_types: Array, npcs: Array) -> void:
	await _say("Community Magician! Each participant passes a die to the next.")
	if npcs.is_empty():
		await _say("No other participants — the Magician's trick falls flat.")
		return
	var choices: Array = []
	for i in range(player_hand.size()):
		choices.append({"text": "Pass the %s" % _face_name(player_hand[i]), "key": str(i)})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Which die do you pass?"})
	var rr: Dictionary = await capture_input_fn.call()
	var p_give: int = int(rr.get("key", "0"))
	var npc_give: Array = []
	for npc in npcs:
		npc_give.append(_worst_idx(npc["dice"]))
	# Snapshot outgoing: index 0 = player, 1..n = npcs
	var out_faces: Array = [player_hand[p_give]]
	var out_types: Array = [player_types[p_give]]
	for i in range(npcs.size()):
		out_faces.append(npcs[i]["dice"][npc_give[i]])
		out_types.append(npcs[i]["dice_types"][npc_give[i]])
	# Rotation: player → NPC[0] → … → NPC[n-1] → player
	npcs[0]["dice"][npc_give[0]] = out_faces[0]
	npcs[0]["dice_types"][npc_give[0]] = out_types[0]
	npcs[0]["revealed"][npc_give[0]] = true
	for i in range(1, npcs.size()):
		npcs[i]["dice"][npc_give[i]] = out_faces[i]
		npcs[i]["dice_types"][npc_give[i]] = out_types[i]
		npcs[i]["revealed"][npc_give[i]] = true
	player_hand[p_give] = out_faces[npcs.size()]
	player_types[p_give] = out_types[npcs.size()]
	await _say("The dice have changed hands around the table.")


# ── Dragon ────────────────────────────────────────────────────────────────────

func _effect_dragon_player(community: Array, comm_ids: Array) -> void:
	if community.is_empty():
		await _say("The Dragon roars — but no Dealer's Die has been revealed yet.")
		return
	var choices: Array = []
	for i in range(community.size()):
		choices.append({"text": "Destroy the %s" % _fmt_roll_result(community[i]), "key": str(i)})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Dragon — choose a Dealer's Die to destroy:"})
	var rr: Dictionary = await capture_input_fn.call()
	var idx: int = int(rr.get("key", "0"))
	await _say("The Dragon devours the %s." % _fmt_roll_result(community[idx]))
	community.remove_at(idx)
	comm_ids.remove_at(idx)


func _effect_dragon_npc(acting_npc: Dictionary, community: Array, comm_ids: Array) -> void:
	if community.is_empty():
		await _say("The Dragon roars into the void — no Dealer's Die to devour.")
		return
	var npc_name: String = (acting_npc["name"] as String).capitalize()
	var best_idx: int = 0
	var best_rank: int = -999999
	for i in range(community.size()):
		var trial: Array = community.duplicate()
		trial.remove_at(i)
		var r: int = _rank_n(acting_npc["dice"] + trial)
		if r > best_rank:
			best_rank = r
			best_idx = i
	await _say("%s's Dragon devours the %s." % [npc_name, _fmt_roll_result(community[best_idx])])
	community.remove_at(best_idx)
	comm_ids.remove_at(best_idx)


func _effect_dragon_community(community: Array, comm_ids: Array) -> void:
	await _say("The Dragon has awoken! It devours the first Dealer's Die.")
	community.remove_at(0)
	comm_ids.remove_at(0)
