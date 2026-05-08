extends RefCounted
class_name Character

signal stats_changed
signal mp_hit

var data = {}
var base_stats = {}
var equipment = {}
var final_stats = {}
var curr_stats = {}
var money = 0
var level = 1

var armor_db = {}
var weapon_db = {}

# ------------------------
# INIT
# ------------------------

func _init(char_data, arm_db, wpn_db):
	data = char_data
	armor_db = arm_db
	weapon_db = wpn_db
	
	money = char_data.get("Money", 0)
	level = int(char_data.get("Lvl", 1))
	base_stats = _build_base_stats(char_data)
	equipment = _build_equipment(char_data)

	recalculate()

# ------------------------
# BUILD
# ------------------------

func _build_base_stats(char):
	var stats = char.get("Stats", {})
	var base = {
		"hp":  _rank(stats.get("HP",  "E")) + 5,
		"mp":  _rank(stats.get("MP",  "E")),
		"str": _rank(stats.get("Str", "E")),
		"mag": _rank(stats.get("Mag", "E")),
		"agi": _rank(stats.get("Agi", "E")),
		"dex": _rank(stats.get("Dex", "E")),
		"lck": _rank(stats.get("Lck", "E")),
		"def": _rank(stats.get("Def", "E"))
	}
	return _apply_level_growth(char, base)

func _apply_level_growth(char, base: Dictionary) -> Dictionary:
	var lvl = int(char.get("Lvl", 1))
	if lvl <= 1:
		return base

	var stat_ranks = char.get("Stats", {})
	var rank_keys = {
		"hp":  "HP",
		"mp":  "MP",
		"str": "Str",
		"mag": "Mag",
		"agi": "Agi",
		"dex": "Dex",
		"lck": "Lck",
		"def": "Def"
	}

	var result = base.duplicate()
	for _level in range(1, lvl):
		for stat in result:
			var rank = stat_ranks.get(rank_keys.get(stat, ""), "E")
			var growth = _growth(rank) + (20 if stat == "hp" else 0)
			if randi() % 100 < growth:
				result[stat] += 1

	return result

func _build_equipment(char):
	var eq = {
		"weapon": {},
		"armor": {}
	}
	
	if char.has("Equip") and typeof(char["Equip"]) == TYPE_DICTIONARY:
		eq["weapon"] = weapon_db.get(char["Equip"].get("Weapon"))
		eq["armor"] = armor_db.get(char["Equip"].get("Armor"))
	
	return eq

func _rank(r):
	match r:
		"A": return 10
		"B": return 8
		"C": return 6
		"D": return 4
		"E": return 2
		"F": return 2
	return 5


func _growth(r):
	match r:
		"A": return 70
		"B": return 55
		"C": return 40
		"D": return 25
		"E": return 15
		"F": return 5
	return 5


# ------------------------
# CORE
# ------------------------

func recalculate():
	final_stats = base_stats.duplicate()
	
	for slot in equipment:
		var item = equipment[slot]
		if not item:
			continue
		
		for stat in item.get("stats", {}):
			if not final_stats.has(stat):
				final_stats[stat] = 0
			
			final_stats[stat] += item["stats"][stat]
	
	# init current stats se vazio
	if curr_stats.is_empty():
		curr_stats = {
			"hp": final_stats["hp"],
			"mp": final_stats["mp"],
			"mhp": final_stats["hp"],
			"mmp": final_stats["mp"]
		}
	stats_changed.emit()
	
	#emit_signal("stats_changed", self)

# ------------------------
# API LIMPA
# ------------------------

func take_damage(amount):
	curr_stats["hp"] = max(0, curr_stats["hp"] - amount)
	#emit_signal("stats_changed", self)
	stats_changed.emit()

func heal(amount):
	curr_stats["hp"] = min(curr_stats["mhp"], curr_stats["hp"] + amount)
	#emit_signal("stats_changed", self)
	stats_changed.emit()

func equip(slot, item_name):
	equipment[slot] = item_name
	recalculate()
	
# getters stats

func get_total_stat(stat):
	var base = base_stats.get(stat, 0)
	var bonus = get_equipment_bonus(stat)
	return base + bonus

func get_equipment_bonus(stat):
	var total = 0
	for slot in equipment:
		var item = equipment[slot]
		if item and item.has("stats"):
			total += item["stats"].get(stat, 0)
	return total

# getters úteis

func get_name():
	print(data)
	return data["Name"]

func get_char_class():
	return data.get("Class","")

func get_hp():
	return curr_stats["hp"]

func get_mhp():
	return get_max_hp()

func get_max_hp():
	return curr_stats["mhp"]
	
func get_mmp():
	return get_max_mp()
	
func get_mp():
	return curr_stats["mp"]

func get_max_mp():
	return curr_stats["mmp"]

func get_stat(stat):
	return final_stats.get(stat, 0)
	
func get_weapon():
	return equipment.get("weapon", {})

func get_equipment() -> Dictionary:
	var result = {}
	for slot in equipment:
		var item = equipment[slot]
		if item and typeof(item) == TYPE_DICTIONARY and item.size() > 0:
			result[slot] = item
	return result

func use_mp(amount: int):
	curr_stats["mp"] = max(0, curr_stats["mp"] - amount)
	stats_changed.emit()

func take_mp_damage(amount: int):
	curr_stats["mp"] = max(0, curr_stats["mp"] - amount)
	mp_hit.emit()
	stats_changed.emit()

func restore_mp(amount: int):
	curr_stats["mp"] = min(curr_stats["mmp"], curr_stats["mp"] + amount)
	stats_changed.emit()

func get_skills() -> Array:
	return data.get("Skills", [])

func get_spells() -> Array:
	return data.get("Spells", [])

func get_level() -> int:
	return level

func get_money() -> int:
	return money

func get_inventory() -> Dictionary:
	return data.get("Inventory", {})

func consume_item(item_name: String):
	var inv: Dictionary = data.get("Inventory", {})
	if inv.has(item_name):
		inv[item_name] = max(0, inv[item_name] - 1)
		if inv[item_name] == 0:
			inv.erase(item_name)
