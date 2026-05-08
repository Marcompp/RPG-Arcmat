extends Node
class_name CombatManager

enum CombatState {
	PLAYER_TURN,
	CHOOSING_ACTION,
	CHOOSING_SKILL,
	CHOOSING_MAGIC,
	CHOOSING_ITEM,
	ENEMY_TURN,
	RESOLUTION,
	END
}

var state = CombatState.PLAYER_TURN

var player = null
var enemy = null

var skills_db: Dictionary = {}
var spells_db: Dictionary = {}
var items_db: Dictionary = {}
var status_effects: Dictionary = { "player": [], "enemy": [] }
var cooldowns: Dictionary = { "player": {}, "enemy": {} }

# ========================
# ENTRY
# ========================

func start_combat(p, e):
	player = p
	enemy = e
	skills_db = _load_json("res://Database/skills.json")
	spells_db = _load_json("res://Database/spells.json")
	items_db  = _load_json("res://Database/items.json")
	status_effects = { "player": [], "enemy": [] }
	cooldowns = { "player": {}, "enemy": {} }

	MyInputRouter.push(_handle_combat_input, "combat")

	await _show_intro()
	await wait_for_continue()

	start_player_turn()

# ========================
# FLOW
# ========================

func start_player_turn():
	_tick_cooldowns("player")
	await _process_statuses("player")
	if player.get_hp() <= 0:
		check_combat_end()
		return
	state = CombatState.CHOOSING_ACTION
	render_player_turn()
	
func restart_player_choices():
	state = CombatState.CHOOSING_ACTION
	show_choices(_main_choices())

# ========================
# RENDER
# ========================

func show_text(text, choices = []):
	MyEventBus.emit("dialogue", {
		"text": text,
		"choices": choices
	})

func show_choices(choices = []):
	MyEventBus.emit("show_choices", {
		"choices": choices
	})

func render_player_turn():
	var text = "%s: %d hp.\n%s: %d hp.\n\nWhat would you like to do?" % [
		enemy.get_name(),
		enemy.get_hp(),
		player.get_name(),
		player.get_hp()
	]
	show_text(text, _main_choices())

func _show_intro():
	var text = "You encounter %s\n\n%s is raring for a fight!" % [
		enemy.get_name(),
		enemy.get_name()
	]
	show_text(text)

# ========================
# CHOICES BUILDERS
# ========================

func _main_choices():
	return [
		{ "text": "Attack", "type": "attack", "tooltip": _format_weapon_tooltip() },
		{ "text": "Skill",  "type": "skill",  "tooltip": "Use a Skill"  },
		{ "text": "Magic",  "type": "magic",  "tooltip": "Use a Spell"  },
		{ "text": "Item",   "type": "item",   "tooltip": "Use an Item"  }
	]

func _build_list_menu(list, type: String, db: Dictionary = {}) -> Array:
	var choices = []
	for item_name in list:
		var choice = _build_action_choice(str(item_name), type, db.get(str(item_name), null))
		if choice != null:
			choices.append(choice)
	choices.append({ "text": "Back", "type": "back" })
	return choices

func _build_action_choice(name: String, type: String, data) -> Variant:
	if data == null:
		return { "text": name, "type": type, "data": name }

	var label = data.get("nome", name)
	var disabled = false
	var tooltip = ""

	if data.has("cost"):
		var cost = data["cost"]
		label += " (Cost: %d MP)" % cost
		if player.get_mp() < cost:
			disabled = true
			tooltip = "Insufficient MP"

	if data.get("consumable", false):
		var count = player.get_inventory().get(name, 0)
		if count <= 0:
			return null
		label += " (On Hand: %d)" % count

	if data.has("cooldown"):
		var remaining = cooldowns["player"].get(name, 0)
		if remaining > 0:
			label += " (%d Turns)" % remaining
			disabled = true
			tooltip = "On cooldown - %d turns left" % remaining
		else:
			label += " (Cooldown: %d)" % data["cooldown"]

	var choice = { "text": label, "type": type, "data": name }
	if disabled:
		choice["disabled"] = true
		choice["disabled_text"] = label
		if tooltip != "":
			choice["disabled_tooltip"] = tooltip
	else:
		choice["tooltip"] = _format_action_tooltip(name, data)
	return choice

# ========================
# INPUT ROUTER
# ========================

func _handle_combat_input(choice):
	match state:
		CombatState.CHOOSING_ACTION:
			handle_main_action(choice)
		CombatState.CHOOSING_SKILL:
			handle_list_choice(choice, "skill")
		CombatState.CHOOSING_MAGIC:
			handle_list_choice(choice, "magic")
		CombatState.CHOOSING_ITEM:
			handle_list_choice(choice, "item")

# ========================
# ACTION HANDLERS
# ========================

func handle_main_action(choice):
	match choice["type"]:
		"attack":
			await _resolve_turn_pair({ "actor": player, "who": "player", "type": "attack" })
		"skill":
			open_menu("skill", player.get_skills(), skills_db)
		"magic":
			open_menu("magic", player.get_spells(), spells_db)
		"item":
			open_menu("item", player.get_inventory().keys(), items_db)

func open_menu(type: String, list, db: Dictionary = {}):
	match type:
		"skill": state = CombatState.CHOOSING_SKILL
		"magic": state = CombatState.CHOOSING_MAGIC
		"item":  state = CombatState.CHOOSING_ITEM
	show_choices(_build_list_menu(list, type, db))

func handle_list_choice(choice, type):
	if choice["type"] == "back":
		restart_player_choices()
		return
	var db: Dictionary = skills_db if type == "skill" else (spells_db if type == "magic" else items_db)
	await _resolve_turn_pair({ "actor": player, "who": "player", "type": type, "name": choice["data"], "db": db })

# ========================
# EXECUTE ACTION
# ========================

func _execute_action(user, who: String, name: String, db: Dictionary):
	var data = db.get(name, null)
	if not data:
		MyEventBus.emit("continue_text", { "text": "...%s?\n" % name })
		await wait_for_continue()
		return

	var action_type = data.get("type", "attack")
	var target
	if action_type == "self":
		target = user
	elif user == player:
		target = enemy
	else:
		target = player

	if data.has("cost"):
		user.use_mp(data["cost"])

	if data.has("cooldown") and who != "":
		cooldowns[who][name] = data["cooldown"]

	var lines = ["[b]%s[/b] used [color=cyan]%s[/color]!" % [user.get_name(), data.get("nome", name)]]
	var did_damage = false

	var hit_count = data.get("hits", 1)
	for _i in range(hit_count):
		var result = _resolve_action(user, target, data)
		lines.append(result["text"])
		if result["damage"] > 0:
			target.take_damage(result["damage"])
			did_damage = true
		if result["heal"] > 0:
			target.heal(result["heal"])
		if result["mp_restore"] > 0:
			target.restore_mp(result["mp_restore"])
		if result["status"] != "":
			if result["status"] == "stat_clear":
				var target_side = "player" if target == player else "enemy"
				status_effects[target_side] = []
				lines.append("[color=green]%s's status effects cleared![/color]" % target.get_name())
			else:
				_add_status(target, result["status"], 3)
				lines.append("[color=yellow]%s is %s![/color]" % [target.get_name(), result["status"]])

	if data.get("consumable", false):
		user.consume_item(name)

	MyEventBus.emit("continue_text", { "text": "\n".join(lines) + "\n" })
	if did_damage:
		MyEventBus.emit("screenshake")
	await wait_for_continue()

func _resolve_action(user, target, data) -> Dictionary:
	var result = { "damage": 0, "heal": 0, "mp_restore": 0, "status": "", "text": "" }
	var stats = data.get("stats", {})
	var is_magic = data.get("magic", false)
	var action_type = data.get("type", "attack")

	if action_type == "self":
		var mgt = stats.get("mgt", 0)
		if mgt < 0:
			result["heal"] = abs(mgt)
			result["text"] = "[color=green]+%d HP[/color]" % result["heal"]
		var mp = stats.get("mp", 0)
		if mp < 0:
			result["mp_restore"] = abs(mp)
			result["text"] += " [color=cyan]+%d MP[/color]" % result["mp_restore"]
		var effect = data.get("effect", "none")
		if effect != "none" and effect != "":
			result["status"] = effect
		if result["text"] == "":
			result["text"] = "..."
		return result

	var base_mgt = stats.get("mgt", 0)
	var inherit_stats = data.get("inherit_stats", false)
	var inherit_wpn = data.get("inherit_wpn", false)
	var weapon = user.get_weapon()

	if inherit_wpn:
		if is_magic:
			base_mgt += weapon.get("stats", {}).get("mys", 0)
		else:
			base_mgt += weapon.get("stats", {}).get("mgt", 0)

	var atk_stat = user.get_total_stat("mag") if is_magic else user.get_total_stat("str")
	if inherit_stats:
		base_mgt += atk_stat

	var ignore_def = data.get("effect", "") == "ignore_def"
	var def_val = 0 if ignore_def else target.get_total_stat("def")
	var dmg = max(1, base_mgt - def_val + randi_range(0, 2))

	var crit_chance = stats.get("crit", 0)
	if inherit_wpn:
		crit_chance += weapon.get("stats", {}).get("crit", 0)
	if randi_range(1, 100) <= crit_chance:
		dmg = int(dmg * 1.5)
		result["text"] = "[color=orange]Critical! [/color]"

	result["damage"] = dmg
	result["text"] += "[color=red]%d[/color] damage!" % dmg

	var effect = data.get("effect", "none")
	var chance = data.get("chance", 100)
	if effect != "none" and effect != "" and randi_range(1, 100) <= chance:
		result["status"] = effect

	return result

# ========================
# TURN RESOLUTION
# ========================

func _resolve_turn_pair(player_action: Dictionary):
	state = CombatState.RESOLUTION
	_tick_cooldowns("enemy")
	await _process_statuses("enemy")
	if enemy.get_hp() <= 0:
		check_combat_end()
		return

	var enemy_action = _enemy_choose_action()
	var p_speed = _get_action_speed(player, player_action)
	var e_speed = _get_action_speed(enemy, enemy_action)

	var first  = player_action if p_speed >= e_speed else enemy_action
	var second = enemy_action  if p_speed >= e_speed else player_action

	await _execute_turn_action(first)
	if player.get_hp() <= 0 or enemy.get_hp() <= 0:
		check_combat_end()
		return
	await _execute_turn_action(second)
	state = CombatState.PLAYER_TURN
	check_combat_end()

func _execute_turn_action(action: Dictionary):
	match action["type"]:
		"attack":
			await _do_attack(action["actor"])
		_:
			await _execute_action(action["actor"], action["who"], action["name"], action["db"])

func _do_attack(actor):
	var weapon     = actor.get_weapon()
	var target     = enemy if actor == player else player
	var dmg        = calculate_damage(actor, target)
	MyEventBus.emit("continue_text", {
		"text": "[b]%s[/b] struck with %s![wait=0.1]" % [
			actor.get_name(), weapon.get("name", "bare hands")
		]
	})
	await wait_for_writing()
	target.take_damage(dmg)
	MyEventBus.emit("continue_text", {
		"text": "[screenshake][instant][color=red]%d[/color] damage![/instant]" % [dmg],
		"linebreak": false
	})
	await wait_for_writing()

func _enemy_choose_action() -> Dictionary:
	var skills    = enemy.get_skills()
	var available = skills.filter(func(s): return cooldowns["enemy"].get(s, 0) == 0 and skills_db.has(s))
	if available.size() > 0 and randi_range(1, 100) <= 35:
		var chosen = available[randi_range(0, available.size() - 1)]
		return { "actor": enemy, "who": "enemy", "type": "skill", "name": chosen, "db": skills_db }
	return { "actor": enemy, "who": "enemy", "type": "attack" }

func _get_action_speed(actor, action: Dictionary) -> float:
	var agi = actor.get_total_stat("agi")
	var dex = actor.get_total_stat("dex")
	return float(agi - max(_get_action_wgt(actor, action) - dex, 0))

func _get_action_wgt(actor, action: Dictionary) -> int:
	if action["type"] == "attack":
		return actor.get_weapon().get("stats", {}).get("wgt", 0)
	return action.get("db", {}).get(action.get("name", ""), {}).get("stats", {}).get("wgt", 0)

# ========================
# END
# ========================

func check_combat_end():
	if player.get_hp() <= 0:
		await end_combat(false)
		return
	if enemy.get_hp() <= 0:
		await end_combat(true)
		return
	await wait_for_continue()
	next_turn()

func next_turn():
	start_player_turn()

func end_combat(victory):
	state = CombatState.END
	var text = "[color=yellow]%s[/color] was defeated!" % enemy.get_name() \
		if victory else "You were defeated..."
	MyEventBus.emit("character_defeated", { "victory": victory })
	MyEventBus.emit("continue_text", { "text": text })
	await wait_for_continue()
	MyInputRouter.pop()
	MyEventBus.emit("combat_ended", { "victory": victory })

# ========================
# STATUS & COOLDOWNS
# ========================

func _tick_cooldowns(who: String):
	for skill in cooldowns[who]:
		cooldowns[who][skill] = max(0, cooldowns[who][skill] - 1)

func _add_status(target, effect: String, duration: int):
	var who = "player" if target == player else "enemy"
	status_effects[who].append({ "type": effect, "duration": duration })

func _process_statuses(who: String):
	var target = player if who == "player" else enemy
	var remaining = []
	for s in status_effects[who]:
		match s["type"]:
			"poison":
				var dmg = max(1, target.get_max_hp() / 10)
				target.take_damage(dmg)
				MyEventBus.emit("continue_text", {
					"text": "[color=purple]%s is poisoned! -%d HP[/color]\n" % [target.get_name(), dmg]
				})
			"regen":
				var hp = max(1, target.get_max_hp() / 8)
				target.heal(hp)
				MyEventBus.emit("continue_text", {
					"text": "[color=green]%s regenerates +%d HP[/color]\n" % [target.get_name(), hp]
				})
		s["duration"] -= 1
		if s["duration"] > 0:
			remaining.append(s)
	status_effects[who] = remaining

# ========================
# UTILS
# ========================

func wait_for_writing():
	var ds := get_parent().get_node("DialogueSystem") as DialogueSystem
	while ds.is_typing:
		await get_tree().process_frame

func wait_for_continue():
	var wait_state = { "done": false }
	MyInputRouter.push(func(choice):
		if choice.get("type") == "continue":
			wait_state["done"] = true
			MyInputRouter.pop(),
		"wait")
	MyEventBus.emit("show_choices", {
		"choices": [{ "text": "Continue", "type": "continue" }]
	})
	while not wait_state["done"]:
		await get_tree().process_frame

func calculate_damage(attacker, defender) -> int:
	var weapon = attacker.get_weapon()
	var mgt = weapon.get("stats", {}).get("mgt", 0)
	var crit = weapon.get("stats", {}).get("crit", 0)
	var atk = attacker.get_total_stat("str") + mgt
	var def = defender.get_total_stat("def")
	var dmg = max(1, atk - def + randi_range(0, 2))
	if randi_range(1, 100) <= crit:
		dmg = int(dmg * 1.5)
	return dmg

func _format_weapon_tooltip() -> String:
	var weapon = player.get_weapon()
	if not weapon or weapon.is_empty():
		return "Current Weapon: Bare Hands"
	var name = weapon.get("name", "Unknown")
	var stats = weapon.get("stats", {})
	var mgt  = stats.get("mgt",  0)
	var crit = stats.get("crit", 0)
	var wgt  = stats.get("wgt",  0)
	return "Current Weapon: %s\nMgt: %d  |  Crit: %d%%  |  Wgt: %d" % [name, mgt, crit, wgt]

func _format_action_tooltip(name: String, data: Dictionary) -> String:
	var lines = []
	var action_name = data.get("nome", name)
	lines.append(action_name)

	var stats = data.get("stats", {})
	var action_type = data.get("type", "attack")
	var is_magic = data.get("magic", false)

	var stat_parts = []
	if action_type == "self":
		var mgt = stats.get("mgt", 0)
		if mgt < 0:
			stat_parts.append("Heal: %d HP" % abs(mgt))
		var mp = stats.get("mp", 0)
		if mp < 0:
			stat_parts.append("Restore: %d MP" % abs(mp))
	else:
		var mgt = stats.get("mgt", 0)
		if mgt > 0:
			stat_parts.append("Mgt: +%d" % mgt)
		var acc = stats.get("acc", 0)
		if acc > 0:
			stat_parts.append("Acc: %d%%" % acc)
		var crit = stats.get("crit", 0)
		if crit > 0:
			stat_parts.append("Crit: %d%%" % crit)
	if stat_parts.size() > 0:
		lines.append("  ".join(stat_parts))

	var hits = data.get("hits", 1)
	if hits > 1:
		lines.append("Hits: %d×" % hits)

	var effect = data.get("effect", "none")
	if effect == "ignore_def":
		lines.append("Ignores DEF")
	elif effect != "none" and effect != "":
		var chance = data.get("chance", 100)
		if chance < 100:
			lines.append("Effect: %s (%d%%)" % [effect.capitalize(), chance])
		else:
			lines.append("Effect: %s" % effect.capitalize())

	var cost = data.get("cost", 0)
	if cost > 0:
		lines.append("Cost: %d MP" % cost)

	var wgt = stats.get("wgt", 0)
	if wgt > 0:
		lines.append("Wgt: %d" % wgt)

	var inherit_parts = []
	if data.get("inherit_stats", false):
		inherit_parts.append("STR" if not is_magic else "MAG")
	if data.get("inherit_wpn", false):
		inherit_parts.append("Weapon")
	if inherit_parts.size() > 0:
		lines.append("Scales: %s" % " + ".join(inherit_parts))

	return "\n".join(lines)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON parse error: " + path)
		return {}
	return json.data
