extends RefCounted
class_name CombatMenuBuilder

func main_choices(player) -> Array:
	return [
		{ "text": "Attack", "type": "attack", "tooltip": format_weapon_tooltip(player) },
		{ "text": "Skill",  "type": "skill",  "tooltip": "Use a Skill" },
		{ "text": "Magic",  "type": "magic",  "tooltip": "Use a Spell" },
		{ "text": "Item",   "type": "item",   "tooltip": "Use an Item" }
	]

func build_list_menu(list, type: String, db: Dictionary, player, cooldowns: Dictionary) -> Array:
	var choices = []
	for item_name in list:
		var choice = build_action_choice(str(item_name), type, db.get(str(item_name), null), player, cooldowns)
		if choice != null:
			choices.append(choice)
	choices.append({ "text": "Back", "type": "back" })
	return choices

func build_action_choice(item_name: String, type: String, data, player, cooldowns: Dictionary) -> Variant:
	if data == null:
		return { "text": item_name, "type": type, "data": item_name }

	var label    = data.get("nome", item_name)
	var disabled = false
	var tooltip  = ""

	if data.get("effect", "") == "auto_revive":
		disabled = true
		tooltip  = "Activates automatically when HP reaches 0"

	if data.has("cost"):
		var cost = data["cost"]
		label += " (Cost: %d MP)" % cost
		if player.get_mp() < cost:
			disabled = true
			tooltip  = "Insufficient MP"

	if data.get("consumable", false):
		var count = player.get_inventory().get(item_name, 0)
		if count <= 0:
			return null
		label += " (On Hand: %d)" % count

	if data.has("cooldown"):
		var remaining = cooldowns["player"].get(item_name, 0)
		if remaining > 0:
			label    += " (%d Turns)" % remaining
			disabled  = true
			tooltip   = "On cooldown - %d turns left" % remaining
		else:
			label += " (Cooldown: %d)" % data["cooldown"]

	var choice = { "text": label, "type": type, "data": item_name }
	if disabled:
		choice["disabled"]         = true
		choice["disabled_text"]    = label
		if tooltip != "":
			choice["disabled_tooltip"] = tooltip
	else:
		choice["tooltip"] = format_action_tooltip(item_name, data)
	return choice

func format_weapon_tooltip(player) -> String:
	var weapon = player.get_weapon()
	if not weapon or weapon.is_empty():
		return "Current Weapon: Bare Hands"
	var stats = weapon.get("stats", {})
	return "Current Weapon: %s\nMgt: %d  |  Crit: %d%%  |  Wgt: %d" % [
		weapon.get("name", "Unknown"),
		stats.get("mgt",  0),
		stats.get("crit", 0),
		stats.get("wgt",  0)
	]

func format_action_tooltip(action_key: String, data: Dictionary) -> String:
	var lines       = [data.get("nome", action_key)]
	var stats       = data.get("stats", {})
	var action_type = data.get("type", "attack")
	var is_magic    = data.get("magic", false)

	if action_type in ["aoe"]:
		lines.append("Target: All Enemies")
	elif action_type in ["all"]:
		lines.append("Target: [color=red]EVERYONE[/color]")

	var stat_parts = []
	if action_type == "self":
		var mgt = stats.get("mgt", 0)
		if mgt < 0: stat_parts.append("Heal: %d HP"    % abs(mgt))
		var mp = stats.get("mp", 0)
		if mp  < 0: stat_parts.append("Restore: %d MP" % abs(mp))
	else:
		var mgt  = stats.get("mgt",  0)
		var acc  = stats.get("acc",  0)
		var crit = stats.get("crit", 0)
		if mgt  > 0: stat_parts.append("Mgt: +%d"   % mgt)
		if acc  > 0: stat_parts.append("Acc: %d%%"  % acc)
		if crit > 0: stat_parts.append("Crit: %d%%" % crit)
	if stat_parts.size() > 0:
		lines.append("  ".join(stat_parts))

	var hits     = data.get("hits", 1)
	var max_hits = data.get("max_hits", 1)
	if hits > 1:
		lines.append("Hits: %d×" % hits)
	elif max_hits > 1:
		lines.append("Hits: %d-%d×" % [data.get("min_hits", 1), max_hits])

	var effect = data.get("effect", "none")
	if effect == "ignore_def":
		lines.append("Ignores DEF")
	elif effect == "recharge":
		lines.append("Reduces all cooldowns by %d" % data.get("magnitude", 1))
	elif effect == "delay":
		lines.append("Delays enemy action by %d turn(s)" % data.get("magnitude", 1))
	elif effect != "none" and effect != "":
		var chance = data.get("chance", 100)
		lines.append("Effect: %s%s" % [
			effect.capitalize(),
			" (%d%%)" % chance if chance < 100 else ""
		])

	var cost = data.get("cost", 0)
	if cost > 0:
		lines.append("Cost: %d MP" % cost)

	var wgt = stats.get("wgt", 0)
	if wgt > 0:
		lines.append("Wgt: %d" % wgt)

	var inherit_parts = []
	if data.get("inherit_stats", false): inherit_parts.append("STR" if not is_magic else "MAG")
	if data.get("inherit_wpn",   false): inherit_parts.append("Weapon")
	if inherit_parts.size() > 0:
		lines.append("Scales: %s" % " + ".join(inherit_parts))

	return "\n".join(lines)
