extends RefCounted
class_name CombatCalculator

var rng: RandomNumberGenerator
var element_db: Dictionary

func _init(p_rng: RandomNumberGenerator, p_element_db: Dictionary) -> void:
	rng        = p_rng
	element_db = p_element_db

func get_element_multiplier(attack_element: String, target_element: String) -> float:
	if target_element == "" or not element_db.has(target_element):
		return 1.0
	var chart = element_db[target_element]
	if attack_element in chart.get("immune", []):
		return 0.25
	if attack_element in chart.get("weak", []):
		return 2.0
	if attack_element in chart.get("resist", []):
		return 0.5
	return 1.0

func check_hit(attacker, defender, base_acc: int) -> bool:
	if defender.stat_multipliers.get("evade", 0.0) > 0.0:
		return false
	var hit_rate = base_acc \
		+ attacker.get_total_stat("dex") \
		- defender.get_total_stat("agi") \
		- floori(defender.get_total_stat("lck") / 2.0)
	var acc_mult = attacker.stat_multipliers.get("acc_mult", 1.0)
	hit_rate = int(hit_rate * acc_mult)
	return rng.randi_range(1, 100) <= hit_rate

func resolve_action(user, target, data: Dictionary) -> Dictionary:
	var result      = { "damage": 0, "heal": 0, "mp_restore": 0, "status": "", "text": "", "critical": false, "element_reaction": "", "missed": false }
	var stats       = data.get("stats", {})
	var is_magic    = data.get("magic", false)
	var action_type = data.get("type", "attack")

	if action_type in ["self", "group"]:
		var mgt = stats.get("mgt", 0)
		if mgt < 0:
			result["heal"] = abs(mgt)
		var mp = stats.get("mp", 0)
		if mp < 0:
			result["mp_restore"] = abs(mp)
		var self_fx = data.get("effect", "none")
		if self_fx != "none" and self_fx != "":
			result["status"] = self_fx
		if result["text"] == "":
			result["text"] = "..."
		return result

	var acc = stats.get("acc", 90)
	if not check_hit(user, target, acc):
		result["missed"] = true
		return result

	var base_mgt     = stats.get("mgt", 0)
	var inherit_stat = data.get("inherit_stats", false)
	var inherit_wpn  = data.get("inherit_wpn",   false)
	var weapon       = user.get_weapon()

	if inherit_wpn:
		base_mgt += weapon.get("stats", {}).get("mys" if is_magic else "mgt", 0)

	if inherit_stat:
		base_mgt += user.get_total_stat("int" if is_magic else "str")

	var ignore_def = data.get("effect", "") == "ignore_def"
	var def_val    = 0
	if not ignore_def:
		def_val = target.get_mp() if is_magic else target.get_total_stat("def")

	var variance = rng.randf_range(0.9, 1.1)
	var dmg      = max(1, int((base_mgt - floori(def_val / 2)) * variance))

	var crit_chance = user.get_total_stat("crit") + stats.get("crit", 0) + user.get_total_stat("dex") - target.get_total_stat("lck")
	if inherit_wpn:
		crit_chance += weapon.get("stats", {}).get("crit", 0)
	if rng.randi_range(1, 100) <= crit_chance:
		dmg = int(dmg * 1.5)
		result["critical"] = true

	var attack_element = data.get("element", "")
	if attack_element == "" and weapon and not weapon.is_empty():
		attack_element = weapon.get("element", "")
	if attack_element == "":
		attack_element = "Neutral"
	var target_element = target.get_element()
	var elem_mult = get_element_multiplier(attack_element, target_element)
	if elem_mult == 0.0:
		result["element_reaction"] = "immune"
		return result
	dmg = max(1, int(dmg * elem_mult))
	if elem_mult >= 2.0:
		result["element_reaction"] = "weak"
	elif elem_mult <= 0.5:
		result["element_reaction"] = "resist"
	elif elem_mult == 0.25:
		result["element_reaction"] = "ineffective"

	var dmg_taken = target.stat_multipliers.get("dmg_taken", 1.0)
	if dmg_taken != 1.0:
		dmg = max(1, int(dmg * dmg_taken))

	if target.stat_multipliers.get("flying", 0.0) > 0.0 and not is_magic:
		var wpn_type = user.get_weapon().get("wpn_type", "")
		if wpn_type == "Ranged":
			dmg = max(1, int(dmg * 1.5))
		else:
			dmg = max(1, int(dmg * 0.5))

	result["damage"] = dmg
	result["text"]  += "[screenshake][instant][color=red]%d[/color] damage![/instant]" % dmg

	var effect = data.get("effect", "none")
	var chance = data.get("chance", 100)
	if effect != "none" and effect != "" and effect != "ignore_def" and rng.randi_range(1, 100) <= chance:
		result["status"] = effect

	return result

func get_action_speed(actor, action: Dictionary) -> float:
	var agi = actor.get_total_stat("agi")
	var dex = actor.get_total_stat("dex")
	return float(agi - max(get_action_wgt(actor, action) - dex, 0))

func get_action_wgt(actor, action: Dictionary) -> int:
	if action["type"] == "attack":
		return actor.get_weapon().get("stats", {}).get("wgt", 0)
	return action.get("db", {}).get(action.get("name", ""), {}).get("stats", {}).get("wgt", 0)

func enemy_choose_action(e, key: String, cooldowns: Dictionary, skills_db: Dictionary, spells_db: Dictionary, status_effects: Dictionary, status_db: Dictionary, living_count: int = 1, enemy_index: int = 0) -> Dictionary:
	var skills    = e.get_skills()
	var spells    = e.get_spells()

	# 1. Cooldown + MP filter
	var available = skills.filter(func(s): return cooldowns[key].get(s, 0) == 0 and skills_db.has(s))
	available    += spells.filter(func(s): return cooldowns[key].get(s, 0) == 0 and spells_db.has(s) and spells_db[s].get("cost", 0) <= e.get_mp())

	# 1b. Summon filter — only usable when this enemy is the sole survivor
	available = available.filter(func(s):
		var t = skills_db.get(s, spells_db.get(s, {})).get("type", "attack")
		return t != "summon" or living_count == 1
	)

	# 1b. Mana Explosion filter — only usable when this enemy has mp
	available = available.filter(func(s):
		var t = skills_db.get(s, spells_db.get(s, {})).get("effect", "")
		return t != "use_all_mp" or e.get_mp() > 0
	)

	# 2. HP threshold filter — skills tagged with "use_when_hp_below" in e.data only appear when hurt enough
	var hp_pct     = 100.0 * e.get_hp() / max(1, e.get_mhp())
	var thresholds = e.data.get("Skill_HP_Thresholds", {})
	available = available.filter(func(s): return not thresholds.has(s) or hp_pct <= thresholds[s])

	# 3. Status deduplication — skip skills whose effect is already active on the target
	var player_fx = status_effects.get("player", []).map(func(s): return s["type"])
	var self_fx   = status_effects.get(key, []).map(func(s): return s["type"])
	available = available.filter(func(s):
		var data   = skills_db.get(s, spells_db.get(s, {}))
		var effect = data.get("effect", "none")
		if not status_db.has(effect):
			return true
		var is_self = data.get("type", "attack") in ["self", "group"]
		return effect not in (self_fx if is_self else player_fx)
	)

	if available.size() > 0 and (rng.randi_range(1, 100) <= e.data.get("Skill_Chance", 35)):
		# 4. Weighted selection — "Skill_Weights": { "Bite": 3, "Claws": 1 }, default weight 1
		var weights = e.data.get("Skill_Weights", {})
		var pool    = []
		for s in available:
			for _i in range(weights.get(s, 1)):
				pool.append(s)
		var chosen = pool[rng.randi_range(0, pool.size() - 1)]
		if skills_db.has(chosen):
			return { "actor": e, "who": key, "type": "skill", "name": chosen, "db": skills_db }
		if spells_db.has(chosen):
			return { "actor": e, "who": key, "type": "spell", "name": chosen, "db": spells_db }
	return { "actor": e, "who": key, "type": "attack", "enemy_index": enemy_index }
