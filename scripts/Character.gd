extends RefCounted
class_name Character

signal stats_changed

var data = {}
var base_stats = {}
var equipment = {}
var final_stats = {}
var curr_stats = {}

var equipment_db = {}

# ------------------------
# INIT
# ------------------------

func _init(char_data, equip_db):
	data = char_data
	equipment_db = equip_db
	
	base_stats = _build_base_stats(char_data)
	equipment = _build_equipment(char_data)
	
	recalculate()

# ------------------------
# BUILD
# ------------------------

func _build_base_stats(char):
	return {
		"hp": _rank(char["Stats"].get("HP","E")) + 5,
		"mp": _rank(char["Stats"].get("MP","E")),
		"str": _rank(char["Stats"].get("Str","E")),
		"mag": _rank(char["Stats"].get("Mag","E")),
		"agi": _rank(char["Stats"].get("Agi","E")),
		"dex": _rank(char["Stats"].get("Dex","E")),
		"lck": _rank(char["Stats"].get("Lck","E")),
		"def": _rank(char["Stats"].get("Def","E"))
	}

func _build_equipment(char):
	var eq = {
		"weapon": null,
		"armor": null
	}
	
	if char.has("Equip") and typeof(char["Equip"]) == TYPE_DICTIONARY:
		eq["weapon"] = char["Equip"].get("Weapon")
		eq["armor"] = char["Equip"].get("Armor")
	
	return eq

func _rank(r):
	match r:
		"A": return 10
		"B": return 8
		"C": return 6
		"D": return 4
		"E": return 2
	return 5

# ------------------------
# CORE
# ------------------------

func recalculate():
	final_stats = base_stats.duplicate()
	
	for slot in equipment:
		var item_name = equipment[slot]
		if item_name == null:
			continue
		
		if not equipment_db.has(item_name):
			continue
		
		var item = equipment_db[item_name]
		
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
		var item_id = equipment[slot]
		var item = equipment_db.get(item_id, {})
		
		if item.has("stats"):
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
	var equip = equipment.get("weapon")
	return {"name":equip}
	#return weapon_db.get(equip, {"Name":equip})
