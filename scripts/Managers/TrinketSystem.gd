extends RefCounted
class_name TrinketSystem

const NEGATIVE_STATUSES = ["poison", "burn", "freeze", "stun", "blind", "break"]

var owner
var owner_key: String = ""
var trinkets_db: Dictionary
var status_effects: Dictionary

var _states: Dictionary = {}
var _bandana_proced: bool = false

func _init(p_owner, p_trinkets_db: Dictionary, p_status_effects: Dictionary, p_owner_key: String = "") -> void:
	owner          = p_owner
	owner_key      = p_owner_key
	trinkets_db    = p_trinkets_db
	status_effects = p_status_effects
	var combined_stats: Dictionary = {}
	for t in owner.get_trinkets():
		var tdata  = trinkets_db.get(t, {})
		var effect = tdata.get("effect", "")
		match effect:
			"duelist_combo": _states[t] = { "combo": 0 }
			"last_stand":    _states[t] = { "used": false }
			"stat_bonus":
				for stat in tdata.get("stats", {}):
					combined_stats[stat] = combined_stats.get(stat, 0) + int(tdata["stats"][stat])
	owner.set_trinket_flat_bonus(combined_stats)

func _trinkets_with_effect(effect: String) -> Array:
	var result = []
	for t in owner.get_trinkets():
		if trinkets_db.get(t, {}).get("effect", "") == effect:
			result.append(t)
	return result

func get_battle_start_skills() -> Array:
	var result = []
	for t in owner.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "battle_start_skill":
			var skill_name = tdata.get("skill", "")
			if skill_name != "":
				result.append(skill_name)
	return result

func is_immune_to_status(status: String) -> bool:
	for t in owner.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "immunity" and tdata.get("status", "") == status:
			return true
	return false

# Returns the combined damage multiplier from all owner trinkets (>= 1.0).
func get_attack_multiplier(target_who: String, attack_element: String) -> float:
	var mult = 1.0
	for t in owner.get_trinkets():
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
				var char_element = owner.get_element()
				if char_element != "Neutral" and char_element == attack_element:
					mult *= 1.0 + bonus
	return mult

# Call after every hit the owner lands.
func on_hit(attack_element: String) -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] += 1
	if not _trinkets_with_effect("resonance").is_empty():
		owner.set_element(attack_element)

# Call after the owner misses.
func on_miss() -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0

# Call after any hit lands on the owner.
func on_owner_hit() -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0

func try_counter_stun() -> bool:
	for t in _trinkets_with_effect("unnerving_rattle"):
		var chance: int = trinkets_db.get(t, {}).get("magnitude", 20)
		if randi() % 100 < chance:
			return true
	return false

func get_lifesteal_amount(damage_dealt: int) -> int:
	var total := 0
	for t in _trinkets_with_effect("soul_drain"):
		var magnitude: int = trinkets_db.get(t, {}).get("magnitude", 10)
		total += int(damage_dealt * magnitude / 100.0)
	return total

# Caps damage so a last_stand trinket leaves the owner at 1 HP (once per battle).
func check_death_prevention(damage: int) -> int:
	_bandana_proced = false
	for t in _trinkets_with_effect("last_stand"):
		if not _states[t]["used"] and damage >= owner.get_hp():
			_states[t]["used"] = true
			_bandana_proced    = true
			return owner.get_hp() - 1
	return damage

# Returns a non-empty BBCode message if the bandana just triggered; clears the flag.
func get_bandana_message() -> String:
	if not _bandana_proced:
		return ""
	_bandana_proced = false
	var t = _trinkets_with_effect("last_stand")[0]
	return "\n[color=yellow]The %s holds! %s survives with 1 HP![/color]" % [t, owner.get_name()]

func process_battle_start() -> void:
	for t in owner.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "battle_start_element":
			owner.set_element(tdata.get("element", "Fire"))

# Resets all per-battle state (combo, element). Called at end_combat().
func reset_combat_state() -> void:
	for t in _trinkets_with_effect("duelist_combo"):
		_states[t]["combo"] = 0
	if not _trinkets_with_effect("resonance").is_empty():
		owner.set_element("Neutral")
	if not _trinkets_with_effect("battle_start_element").is_empty():
		owner.reset_element()

func get_states() -> Dictionary:
	return _states

# Checks for an auto_revive trinket when the owner hits 0 HP. Permanently
# removes one crystal from the Trinkets array and revives the owner.
func try_auto_revive() -> String:
	for t in _trinkets_with_effect("auto_revive"):
		var mag       = trinkets_db.get(t, {}).get("magnitude", 50)
		var revive_hp = max(1, int(owner.get_mhp() * mag / 100.0))
		owner.heal(revive_hp)
		owner.data["Trinkets"].erase(t)
		owner.stats_changed.emit()
		return "[color=yellow]The %s shatters! %s is revived with %d HP![/color]" % [t, owner.get_name(), revive_hp]
	return ""

# Call at the start of every owner turn. Returns a message if MP or HP was restored.
func process_turn_start() -> String:
	var lines: Array = []
	var total_mp = 0
	for t in owner.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "mp_regen_turn":
			total_mp += tdata.get("magnitude", 0)
	if total_mp > 0 and owner.get_mp() < owner.get_mmp():
		owner.restore_mp(total_mp)
		lines.append("[color=cyan]%s recovered %d MP.[/color]" % [owner.get_name(), total_mp])
	for t in _trinkets_with_effect("hp_regen_turn"):
		var mag = trinkets_db.get(t, {}).get("magnitude", 5)
		var heal_amount = max(1, int(owner.get_mhp() * mag / 100.0))
		if owner.get_hp() < owner.get_mhp():
			owner.heal(heal_amount)
			lines.append("[color=green]%s regenerated %d HP.[/color]" % [owner.get_name(), heal_amount])
	if not _trinkets_with_effect("status_decay").is_empty():
		if owner_key != "" and status_effects.has(owner_key):
			for s in status_effects[owner_key]:
				s["duration"] = max(0, s["duration"] - 1)
	return "\n".join(lines)

# Heals the owner from post-battle trinkets and returns a display message (or "").
func process_post_battle() -> String:
	var lines: Array = []
	var total_heal = 0
	for t in owner.get_trinkets():
		var tdata = trinkets_db.get(t, {})
		if tdata.get("effect", "") == "post_battle_heal":
			total_heal += tdata.get("magnitude", 0)
	if total_heal > 0:
		owner.heal(total_heal)
		lines.append("[color=green]%s recovered %d HP from trinkets.[/color]" % [owner.get_name(), total_heal])
	if owner.data.has("Inventory"):
		for t in _trinkets_with_effect("scavenge"):
			var loot_table = trinkets_db.get(t, {}).get("loot_table", [])
			if loot_table.is_empty():
				continue
			var item = loot_table[randi() % loot_table.size()]
			owner.data["Inventory"][item] = owner.data["Inventory"].get(item, 0) + 1
			lines.append("[color=cyan]%s scavenged a %s![/color]" % [owner.get_name(), item])
	return "\n".join(lines)
