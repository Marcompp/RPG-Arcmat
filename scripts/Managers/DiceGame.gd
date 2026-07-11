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
Royal Climb        —  three in a row + a separate pair  (ex: 1-2-3-5-5)
Three Arcs         —  three of a kind
Lover's Climb      —  three in a row with two pairs inside  (ex: 1-1-2-2-3)
Double Trouble     —  two different pairs  (ex: 1-1-2-2)
Drunkard's Climb   —  three in a row with a pair inside  (ex: 1-1-2-3)
The Climb          —  three in a row  (ex: 1-2-3)
Wanderer's Hand    —  pair of 4, 5, 6, 7 or Bridge
The Common         —  pair of 0, 1, 2 or 3
Dead Hand          —  no match
──
Special faces:
  Rogue  (0)    —  low numeric; pairs low, runs normally
  Knight (7)    —  high numeric; pairs high, runs normally
  Joker  (J)    —  wild; counts as any numeric value 0–7
  Bridge (B)    —  connects 6 or 7 to 0 or 1 in a run; usable once per sequence"

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
var npc_crossreact: bool = true


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

	var hierarchy_btn := {"text": "Hand Rankings", "key": "hierarchy", "type": "back"}

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
		if init_rank >= 3000:
			await _banter(npc, "hand_good_start", 0.35)
		elif init_rank == 0:
			await _banter(npc, "hand_bad_start", 0.35)

	# ── Round 1 ───────────────────────────────────────────────────
	# 5. Show table
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	# 6. Round banter
	if not npcs.is_empty():
		await _banter(npcs[rng.randi() % npcs.size()], "round_1", 0.55)

	# 7/8/9. Player reroll
	var reroll_choices: Array = [
		{"text": "Re-roll the %s" % _face_name(player_hand[0]), "key": "0"},
		{"text": "Re-roll the %s" % _face_name(player_hand[1]), "key": "1"},
		{"text": "Re-roll the %s" % _face_name(player_hand[2]), "key": "2"},
		{"text": "Stand pat", "key": "stand"},
		hierarchy_btn,
	]
	var rk1: String = "stand"
	while true:
		MyEventBus.emit("show_choices", {"choices": reroll_choices, "header": "Re-roll one die?"})
		var rr1: Dictionary = await capture_input_fn.call()
		rk1 = rr1.get("key", "stand")
		if rk1 != "hierarchy":
			break
		MyEventBus.emit("dialogue", {"text": HIERARCHY})
		await wait_for_continue_fn.call()
		MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	if rk1 != "stand":
		await _say("You re-roll a die.")
		await _dice_roll_sfx()
		var lck: int = stat_callback.call("lck") if stat_callback.is_valid() else 0
		player_hand[int(rk1)] = _roll_typed_with_lck(player_types[int(rk1)], lck)
		await _say("You rolled %s!" % _fmt_roll_result(player_hand[int(rk1)]))
		await _react_to_player_reroll(npcs, int(rk1), player_hand, community)
		await _say("Your hand: " + _fmt_typed(player_hand, player_types))
	else:
		await _say("You hold pat.")
		await _react_stand_pat(npcs)

	# 10. NPC turns
	await _run_npc_phase(npcs, community, 1, player_hand, player_types, comm_ids)
	await wait_for_continue_fn.call()

	# ── Community Die 1 ───────────────────────────────────────────
	community.append(community_pool[0])
	await _say("The first Dealer's Die is rolled.")
	await _dice_roll_sfx()
	await _say("Rolled %s!" % _fmt_roll_result(community[0]))
	await _react_to_community_die(npcs, community)

	# ── Round 2 ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	if not npcs.is_empty():
		var sp2: Dictionary = npcs[rng.randi() % npcs.size()]
		var sp2_rank: int = _rank_n(sp2["dice"] + community)
		var round2_keys: Array = ["round_2"]
		if sp2_rank >= 3000:
			round2_keys.append("round_good_hand")
		elif sp2_rank == 0:
			round2_keys.append("round_bad_hand")
		await _banter_pool(sp2, round2_keys, 0.55)

	var reroll2_choices: Array = [
		{"text": "Re-roll the %s" % _face_name(player_hand[0]), "key": "0"},
		{"text": "Re-roll the %s" % _face_name(player_hand[1]), "key": "1"},
		{"text": "Re-roll the %s" % _face_name(player_hand[2]), "key": "2"},
		{"text": "Stand pat", "key": "stand"},
		hierarchy_btn,
	]
	var rk2: String = "stand"
	while true:
		MyEventBus.emit("show_choices", {"choices": reroll2_choices, "header": "Re-roll one private die?"})
		var rr2: Dictionary = await capture_input_fn.call()
		rk2 = rr2.get("key", "stand")
		if rk2 != "hierarchy":
			break
		MyEventBus.emit("dialogue", {"text": HIERARCHY})
		await wait_for_continue_fn.call()
		MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	if rk2 != "stand":
		await _say("You re-roll a die.")
		await _dice_roll_sfx()
		var lck2: int = stat_callback.call("lck") if stat_callback.is_valid() else 0
		player_hand[int(rk2)] = _roll_typed_with_lck(player_types[int(rk2)], lck2)
		await _say("You rolled %s!" % _fmt_roll_result(player_hand[int(rk2)]))
		await _react_to_player_reroll(npcs, int(rk2), player_hand, community)
		await _say("Your hand: " + _fmt_typed(player_hand, player_types))
	else:
		await _say("You hold pat.")
		await _react_stand_pat(npcs)

	await _run_npc_phase(npcs, community, 2, player_hand, player_types, comm_ids)
	await wait_for_continue_fn.call()

	# ── Community Die 2 ───────────────────────────────────────────
	community.append(community_pool[1])
	MyEventBus.emit("dialogue", {"text": "The second Dealer's Die is rolled."})
	await _dice_roll_sfx()
	await _say("Rolled %s!" % _fmt_roll_result(community[1]))
	await _react_to_community_die(npcs, community)
	await wait_for_continue_fn.call()

	# ── Round 3 ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	if not npcs.is_empty():
		var sp3: Dictionary = npcs[rng.randi() % npcs.size()]
		var sp3_rank: int = _rank_n(sp3["dice"] + community)
		var round3_keys: Array = ["round_3"]
		if sp3_rank >= 4000:
			round3_keys.append("round_good_hand")
		elif sp3_rank <= 1999:
			round3_keys.append("round_bad_hand")
		await _banter_pool(sp3, round3_keys, 0.55)

	var reroll3_choices: Array = [
		{"text": "Re-roll the %s" % _face_name(player_hand[0]), "key": "0"},
		{"text": "Re-roll the %s" % _face_name(player_hand[1]), "key": "1"},
		{"text": "Re-roll the %s" % _face_name(player_hand[2]), "key": "2"},
		{"text": "Stand pat", "key": "stand"},
		hierarchy_btn,
	]
	var rk3: String = "stand"
	while true:
		MyEventBus.emit("show_choices", {"choices": reroll3_choices, "header": "Re-roll one private die?"})
		var rr3: Dictionary = await capture_input_fn.call()
		rk3 = rr3.get("key", "stand")
		if rk3 != "hierarchy":
			break
		MyEventBus.emit("dialogue", {"text": HIERARCHY})
		await wait_for_continue_fn.call()
		MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids)})
	if rk3 != "stand":
		await _say("You re-roll a die.")
		await _dice_roll_sfx()
		var lck3: int = stat_callback.call("lck") if stat_callback.is_valid() else 0
		player_hand[int(rk3)] = _roll_typed_with_lck(player_types[int(rk3)], lck3)
		await _say("You rolled %s!" % _fmt_roll_result(player_hand[int(rk3)]))
		await _react_to_player_reroll(npcs, int(rk3), player_hand, community)
		await _say("Your hand: " + _fmt_typed(player_hand, player_types))
	else:
		await _say("You hold pat.")
		await _react_stand_pat(npcs)

	await _run_npc_phase(npcs, community, 3, player_hand, player_types, comm_ids)

	# ── Showdown ──────────────────────────────────────────────────
	var p_final: Array = player_hand + community
	var player_rank: int = _rank_n(p_final)
	var best_npc_rank: int = 0
	for npc in npcs:
		best_npc_rank = max(best_npc_rank, _rank_n(npc["dice"] + community))

	MyEventBus.emit("dialogue", {"text": "Showdown!"})
	if not npcs.is_empty():
		await _banter(npcs[rng.randi() % npcs.size()], "showdown_start", 0.6)

	# NPCs reveal in reverse order
	var best_rank_so_far: int = player_rank
	for i in range(npcs.size() - 1, -1, -1):
		var npc: Dictionary = npcs[i]
		var npc_name: String = (npc["name"] as String).capitalize()
		var npc_rank: int = _rank_n(npc["dice"] + community)
		var is_last: bool = (i == 0)

		await _say("%s reveals their hand." % npc_name)

		var fired := false
		if not fired and npc_rank >= 9000:
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
		await _say("%s's hand: " % npc_name + _row(npc_name, npc["dice"], npc["dice_types"], community, comm_ids))

		if npcs.size() > 1:
			var other_idx: int = (i + 1) % npcs.size()
			await _banter_showdown_react(npcs[other_idx], npc_rank, best_rank_so_far, 0.5)

		best_rank_so_far = max(best_rank_so_far, npc_rank)

	# Player reveals last
	await _say("You reveal your hand:")
	await _say("Your hand: " + _row("You", player_hand, player_types, community, comm_ids))
	for npc in npcs:
		await _banter_showdown_react(npc, player_rank, best_rank_so_far, 0.4)
	await wait_for_continue_fn.call()

	# ── Results ───────────────────────────────────────────────────
	MyEventBus.emit("dialogue", {"text": _table(player_hand, player_types, npcs, community, comm_ids, true)})

	if player_rank > best_npc_rank:
		await _say("You win the pot.")
		MyEventBus.emit("give_gold", {"amount": pot})
	elif player_rank == best_npc_rank:
		await _say("A tie. The wager is returned.")
		MyEventBus.emit("give_gold", {"amount": player_committed})
	else:
		await _say("You lose.")

	var best_overall: int = max(player_rank, best_npc_rank)
	var top_count: int = (1 if player_rank == best_overall else 0)
	for npc in npcs:
		if _rank_n(npc["dice"] + community) == best_overall:
			top_count += 1
	var player_result_key: String
	if player_rank == best_overall and top_count == 1:
		player_result_key = "showdown_npc_lose"
	elif player_rank == best_overall:
		player_result_key = "showdown_npc_tie"
	else:
		player_result_key = "showdown_npc_win"
	for npc in npcs:
		var npc_rank: int = _rank_n(npc["dice"] + community)
		var result_keys: Array = [player_result_key]
		if npc_rank == best_overall and top_count == 1:
			result_keys.append("showdown_win")
		elif npc_rank == best_overall:
			result_keys.append("showdown_tie")
		else:
			result_keys.append("showdown_lose")
		await _banter_pool(npc, result_keys, 1.0)

	await wait_for_continue_fn.call()

	if player_rank > best_npc_rank:
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
		if v == 0: return "Rogue"
		if v == 7: return "Knight"
		return str(int(v))
	if v is String:
		if v == "J": return "Joker"
		if v == "B": return "Bridge"
	return str(int(v))


func _face_char(v) -> String:
	if v is String: return v
	if v is int:
		if v == 0: return "Rogue"
		if v == 7: return "Knight"
		return str(v)
	return str(v)


func _fmt_roll_result(v) -> String:
	if v is String:
		if v == "J": return "Joker (J)"
		if v == "B": return "Bridge (B)"
	if v is int:
		if v == 0: return "Rogue"
		if v == 7: return "Knight"
		return str(v)
	return str(v)


# ── Hand ranking ──────────────────────────────────────────────────────────────

# Entry point — accepts any mix of ints (0–7), "J", "B"
func _rank_n(dice: Array) -> int:
	var jokers: int = 0
	var bridges: int = 0
	var numerics: Array = []
	for v in dice:
		if v is String:
			if v == "J": jokers += 1
			elif v == "B": bridges += 1
		else:
			numerics.append(int(v))
	if jokers == 0:
		return _rank_pure(numerics, bridges)
	return _best_with_jokers(numerics, bridges, jokers)


func _name_n(dice: Array) -> String:
	var rank: int = _rank_n(dice)
	if rank >= 10000: return "Five Arcs"
	if rank >= 9000: return "The Pilgrimage"
	if rank >= 8000: return "Four Arcs"
	if rank >= 7500: return "The Stairwell"
	if rank >= 7000: return "The Long Road"
	if rank >= 6000: return "The Hearth"
	if rank >= 5500: return "Royal Climb"
	if rank >= 5000: return "Three Arcs"
	if rank >= 4500: return "Lover's Climb"
	if rank >= 4000: return "Double Trouble"
	if rank >= 3500: return "Drunkard's Climb"
	if rank >= 3000: return "The Climb"
	if rank >= 2000: return "Wanderer's Hand"
	if rank >= 1000: return "The Common"
	return "Dead Hand"


# Brute-force Joker substitution: try each numeric value 0–7 for each Joker
func _best_with_jokers(numerics: Array, bridges: int, jokers: int) -> int:
	if jokers == 0:
		return _rank_pure(numerics, bridges)
	var best: int = 0
	for v in range(8):
		best = max(best, _best_with_jokers(numerics + [v], bridges, jokers - 1))
	return best


# Core ranking: numerics are ints (0–7), bridges is count of "B" dice
func _rank_pure(numerics: Array, bridges: int) -> int:
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
		counts["B"] = bridges

	var pair_vals: Array = []
	var triple_val = null
	var quad_val = null
	var penta_val = null
	for val in counts:
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

	# 10000 — Five Arcs
	if penta_val != null:
		return 10000 + _prv(penta_val)

	# 9000 — The Pilgrimage (5 consecutive including Bridge)
	if run_len >= 5:
		return 9000 + run_high

	# 8000 — Four Arcs
	if quad_val != null:
		return 8000 + _prv(quad_val)

	# 7500 — The Stairwell (4 in a row + pair inside run)
	if run_len >= 4 and pair_vals.size() >= 1:
		if run_values.has(pair_vals[-1]):
			return 7500 + run_high

	# 7000 — The Long Road (4 consecutive)
	if run_len >= 4:
		return 7000 + run_high

	# 6000 — The Hearth (triple + pair)
	if triple_val != null and pair_vals.size() >= 1:
		return 6000 + _prv(triple_val) * 10 + _prv(pair_vals[0])

	# 5500 — Royal Climb (3 in a row + pair outside run)
	if run_len >= 3 and pair_vals.size() == 1:
		if not run_values.has(pair_vals[0]):
			return 5500 + run_high * 10 + _prv(pair_vals[0])

	# 5000 — Three Arcs
	if triple_val != null:
		var ho: int = 0
		for v in numerics:
			if not (triple_val is int and v == triple_val):
				ho = max(ho, v)
		return 5000 + _prv(triple_val) * 10 + ho

	# 4500 — Lover's Climb (3 in a row + two pairs both inside run)
	if run_len >= 3 and pair_vals.size() >= 2:
		var all_in := true
		for pv in pair_vals:
			if not run_values.has(pv):
				all_in = false
				break
		if all_in:
			return 4500 + run_high

	# 4000 — Double Trouble
	if pair_vals.size() >= 2:
		return 4000 + _prv(pair_vals[-1]) * 10 + _prv(pair_vals[-2])

	# 3500 — Drunkard's Climb (3 in a row + pair inside run)
	if run_len >= 3 and pair_vals.size() == 1:
		if run_values.has(pair_vals[0]):
			return 3500 + run_high

	# 3000 — The Climb (3+ consecutive)
	if run_len >= 3:
		return 3000 + run_len * 100 + run_high

	# 2000 / 1000 — Wanderer's Hand / The Common
	if pair_vals.size() == 1:
		var pv = pair_vals[0]
		var prv: int = _prv(pv)
		var hk: int = 0
		for v in numerics:
			if v != pv:
				hk = max(hk, v)
		return (2000 if prv >= 4 else 1000) + prv * 10 + hk

	# Dead Hand
	if not numerics.is_empty():
		return numerics.max()
	return 0


# Pair rank value — converts any pair key (int or "B") to an int for scoring
func _prv(v) -> int:
	if v is String and v == "B": return 7
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
	for top in [7, 6]:
		if top in unique:
			var ri: Array = _run_ending_at(unique, top)
			var ext_len: int = ri[0] + 1
			if ext_len > best_len or (ext_len == best_len and top > best_high):
				best_len = ext_len
				best_high = top
				best_vals = (ri[1] as Array) + ["B"]

	# 2b. Bottom extension: run starting at 0 or 1, extend with B below
	for bot in [0, 1]:
		if bot in unique:
			var ri: Array = _run_starting_at(unique, bot)
			var ext_len: int = ri[0] + 1
			var ext_high: int = bot + ri[0] - 1
			if ext_len > best_len or (ext_len == best_len and ext_high > best_high):
				best_len = ext_len
				best_high = ext_high
				best_vals = ["B"] + (ri[1] as Array)

	# 2c. Wrap bridge: high group + B + low group
	for top in [7, 6]:
		if top in unique:
			var hi: Array = _run_ending_at(unique, top)
			for bot in [0, 1]:
				if bot in unique:
					var lo: Array = _run_starting_at(unique, bot)
					var total: int = (hi[0] as int) + 1 + (lo[0] as int)
					if total > best_len or (total == best_len and top > best_high):
						best_len = total
						best_high = top
						best_vals = (hi[1] as Array) + ["B"] + (lo[1] as Array)

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
	const MAX_RANK := 10100.0
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
	var rolls: int = 2 if lck >= 10 else 1
	var best: int = 0
	for i in range(rolls):
		best = max(best, rng.randi_range(1, 6))
	return best


func _roll_typed_with_lck(die_id: String, lck: int):
	var count := 2 if lck >= 10 else 1
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
		if v == "J": return 100.0
		if v == "B": return 8.5
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
	return pool.has(face)


func _is_special_face(face) -> bool:
	return face is String


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
	return _rank_n(dice) >= 3000


func _say(line: String) -> void:
	MyEventBus.emit("continue_text", {"text": "\n" + line + "\n", "linebreak": false})
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
	elif revealed_rank >= 2000:
		key = "showdown_react_good"
	else:
		key = "showdown_react_bad"
	return await _banter(npc, key, chance)


func _is_special_face_ext(face) -> bool:
	if face is String: return true
	if face is int: return face == 0 or face == 7
	return false


func _special_die_key(face) -> String:
	if face is String:
		if face == "J": return "joker"
		if face == "B": return "bridge"
		if face == "C": return "crown"
	if face is int:
		if face == 0: return "rogue"
		if face == 7: return "knight"
	return ""


func _dice_roll_sfx() -> void:
	MyEventBus.emit("play_sfx", {"id": "dice"})
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
			if not fired and _is_special_face_ext(new_face):
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
				fired = await _banter(npc, "no_combo", 0.4)

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
	if npcs.is_empty():
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
