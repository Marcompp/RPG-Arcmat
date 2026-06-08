extends RefCounted
class_name TrinketSystem

const NEGATIVE_STATUSES = ["poison", "burn", "freeze", "stun", "blind", "break"]

var player
var trinkets_db: Dictionary
var status_effects: Dictionary

var _states: Dictionary = {}
var _bandana_proced: bool = false

func _init(p_player, p_trinkets_db: Dictionary, p_status_effects: Dictionary) -> void:
	player         = p_player
	trinkets_db    = p_trinkets_db
	status_effects = p_status_effects
	for t in player.get_trinkets():
		var effect = trinkets_db.get(t, {}).get("effect", "")
		match effect:
			"duelist_combo": _states[t] = { "combo": 0 }
			"last_stand":    _states[t] = { "used": false }

func _trinkets_with_effect(effect: String) -> Array:
	var result = []
	for t in player.get_trinkets():
		if trinkets_db.get(t, {}).get("effect", "") == effect:
			result.append(t)
	return result

# Returns the combined damage multiplier from all attacker trinkets (>= 1.0).
func get_attack_multiplier(actor, target_who: String, attack_element: String) -> float:
	if actor != player:
		return 1.0
	var mult = 1.0
	for t in player.get_trinkets():
		var effect = trinkets_db.get(t, {}).get("effect", "")
		match effect:
			"duelist_combo":
				var step = trinkets_db.get(t, {}).get("magnitude", 5) / 100.0
				mult *= 1.0 + step * _states[t]["combo"]
			"hidden_blade":
				var neg_count = 0
				for s in status_effects.get(target_who, []):
					if s["type"] in NEGATIVE_STATUSES:
						neg_count += 1
				var step = trinkets_db.get(t, {}).get("magnitude", 10) / 100.0
				mult *= 1.0 + step * neg_count
			"resonance":
				var bonus = trinkets_db.get(t, {}).get("magnitude", 25) / 100.0
				var char_element = actor.get_element()
				if char_element != "Neutral" and char_element == attack_element:
					mult *= 1.0 + bonus
	return mult

# Call after every hit the player lands.
func on_hit(actor, attack_element: String) -> void:
	if actor != player:
		return
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] += 1
	if not _trinkets_with_effect("resonance").is_empty():
		player.set_element(attack_element)

# Call after the player misses.
func on_miss(actor) -> void:
	if actor != player:
		return
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0

# Call after any enemy hit lands on the player.
func on_player_hit() -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0

# Caps damage so a last_stand trinket leaves the player at 1 HP (once per battle).
func check_death_prevention(target, damage: int) -> int:
	_bandana_proced = false
	if target != player:
		return damage
	for t in _trinkets_with_effect("last_stand"):
		if not _states[t]["used"] and damage >= target.get_hp():
			_states[t]["used"] = true
			_bandana_proced    = true
			return target.get_hp() - 1
	return damage

# Returns a non-empty BBCode message if the bandana just triggered; clears the flag.
func get_bandana_message() -> String:
	if not _bandana_proced:
		return ""
	_bandana_proced = false
	var t = _trinkets_with_effect("last_stand")[0]
	return "\n[color=yellow]The %s holds! %s survives with 1 HP![/color]" % [t, player.get_name()]

# Resets all per-battle state (combo, element). Called at end_combat().
func reset_combat_state() -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0
	if not _trinkets_with_effect("resonance").is_empty():
		player.set_element("Neutral")

func get_states() -> Dictionary:
	return _states

# Checks for an auto_revive trinket when the player hits 0 HP. Permanently
# removes one crystal from the Trinkets array and revives the player.
func try_auto_revive() -> String:
	for t in _trinkets_with_effect("auto_revive"):
		var mag       = trinkets_db.get(t, {}).get("magnitude", 50)
		var revive_hp = max(1, int(player.get_mhp() * mag / 100.0))
		player.heal(revive_hp)
		player.data["Trinkets"].erase(t)
		player.stats_changed.emit()
		return "[color=yellow]The %s shatters! %s is revived with %d HP![/color]" % [t, player.get_name(), revive_hp]
	return ""

# Call at the start of every player turn. Returns a message if MP was restored.
func process_turn_start() -> String:
	var total_mp = 0
	for t in player.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "mp_regen_turn":
			total_mp += tdata.get("magnitude", 0)
	if total_mp > 0 and player.get_mp() < player.get_mmp():
		player.restore_mp(total_mp)
		return "[color=cyan]%s recovered %d MP.[/color]" % [player.get_name(), total_mp]
	return ""

# Heals the player from post-battle trinkets and returns a display message (or "").
func process_post_battle() -> String:
	var total_heal = 0
	for t in player.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "post_battle_heal":
			total_heal += tdata.get("magnitude", 0)
	if total_heal > 0:
		player.heal(total_heal)
		return "[color=green]%s recovered %d HP from trinkets.[/color]" % [player.get_name(), total_heal]
	return ""
