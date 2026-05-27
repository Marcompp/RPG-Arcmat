extends Node
class_name CombatManager

enum CombatState {
	PLAYER_TURN,
	CHOOSING_ACTION,
	CHOOSING_SKILL,
	CHOOSING_MAGIC,
	CHOOSING_ITEM,
	CHOOSING_TARGET,
	ENEMY_TURN,
	RESOLUTION,
	END
}

var state = CombatState.PLAYER_TURN

var player = null
var enemies: Array = []
var enemy_display_names: Array = []

var skills_db: Dictionary = {}
var spells_db: Dictionary = {}
var items_db:  Dictionary = {}
var status_db: Dictionary = {}

var status_effects: Dictionary = { "player": [] }
var cooldowns:      Dictionary = { "player": {} }

var enemy_timers: Array = []
var enemy_first_actions: Array = []

var pending_action: Dictionary = {}
var _died_enemies: Array = []

# ============================================================
# HELPERS
# ============================================================

func _ekey(idx: int) -> String:
	return "enemy_%d" % idx

func _living_indices() -> Array:
	var r = []
	for i in range(enemies.size()):
		if enemies[i].get_hp() > 0:
			r.append(i)
	return r

func _get_display_name(entity) -> String:
	if entity == player:
		return player.get_name()
	for i in range(enemies.size()):
		if enemies[i] == entity:
			return enemy_display_names[i]
	return entity.get_name()

func _who_for(target) -> String:
	if target == player:
		return "player"
	for i in range(enemies.size()):
		if enemies[i] == target:
			return _ekey(i)
	return "player"

func _notify_if_died(target) -> String:
	if target == player or target.get_hp() > 0:
		return ""
	var who = _who_for(target)
	if who in _died_enemies:
		return ""
	_died_enemies.append(who)
	status_effects[who] = []
	target.set_stat_multipliers({})
	_emit_status_update(who)
	MyEventBus.emit("enemy_died", { "who": who })
	return "\n[b]%s[/b] went down!" % _get_display_name(target)

func _target_for(action: Dictionary):
	if action["who"] == "player":
		var living = _living_indices()
		var tidx = action.get("target_idx", living[0] if not living.is_empty() else 0)
		return enemies[tidx]
	return player

# ============================================================
# ENTRY
# ============================================================

func start_combat(p, e_or_array):
	player = p
	enemies = e_or_array if e_or_array is Array else [e_or_array]

	# Rename enemies with duplicate names: "Goblin" → "Goblin A", "Goblin B"
	var name_count: Dictionary = {}
	for e in enemies:
		var n = e.get_name()
		name_count[n] = name_count.get(n, 0) + 1

	enemy_display_names = []
	var name_idx: Dictionary = {}
	for e in enemies:
		var n = e.get_name()
		if name_count[n] > 1:
			if not name_idx.has(n):
				name_idx[n] = 0
			enemy_display_names.append("%s %s" % [n, char(65 + name_idx[n])])
			name_idx[n] += 1
		else:
			enemy_display_names.append(n)

	for i in range(enemies.size()):
		enemies[i].data["Name"] = enemy_display_names[i]
		enemies[i].stats_changed.emit()

	skills_db = _load_json("res://Database/skills.json")
	spells_db = _load_json("res://Database/spells.json")
	items_db  = _load_json("res://Database/items.json")
	status_db = _load_json("res://Database/status.json")

	status_effects = { "player": [] }
	cooldowns      = { "player": {} }
	enemy_timers   = []
	enemy_first_actions = []
	pending_action = {}
	_died_enemies  = []

	p.set_stat_multipliers({})
	_emit_status_update("player")

	for skill in p.get_skills():
		var skill_data = skills_db.get(skill, {})
		if skill_data.has("startup"):
			cooldowns["player"][skill] = skill_data["startup"] + 1

	for i in range(enemies.size()):
		var e   = enemies[i]
		var key = _ekey(i)
		status_effects[key] = []
		cooldowns[key]      = {}
		enemy_timers.append(e.data.get("Startup", 0))
		enemy_first_actions.append(true)

		e.set_stat_multipliers({})
		_emit_status_update(key)

		for skill in e.get_skills():
			var skill_data = skills_db.get(skill, {})
			if skill_data.has("startup"):
				cooldowns[key][skill] = skill_data["startup"]

	MyInputRouter.push(_handle_combat_input, "combat")

	await _show_intro()
	await wait_for_continue()
	await _execute_start_skills()
	start_player_turn()

# ============================================================
# TURN FLOW
# ============================================================

func start_player_turn():
	_tick_cooldowns("player")
	state = CombatState.CHOOSING_ACTION
	render_player_turn()

func restart_player_choices():
	state = CombatState.CHOOSING_ACTION
	show_choices(_main_choices())

func next_turn():
	start_player_turn()

func check_combat_end(need_wait = true):
	if player.get_hp() <= 0:
		await end_combat(false)
		return
	if _living_indices().is_empty():
		await end_combat(true)
		return
	if need_wait:
		await wait_for_continue()
	next_turn()

func end_combat(victory: bool):
	state = CombatState.END
	MyEventBus.emit("enemy_timer_update", { "timers": [] })
	MyEventBus.emit("character_defeated", { "victory": victory, "enemy_count": enemies.size() })

	if victory and player.get_hp() > 0:
		var rewards = _calculate_rewards()
		var names = ", ".join(enemy_display_names)
		MyEventBus.emit("continue_text", { "text": "[color=yellow]%s[/color] was defeated!" % names })
		await wait_for_continue()
		MyEventBus.emit("combat_rewards", { "rewards": rewards })
		MyEventBus.emit("dialogue", { "text": _format_reward_text(rewards) })
		await wait_for_continue()
		MyInputRouter.pop()
		MyEventBus.emit("combat_ended", { "victory": true })
	else:
		MyEventBus.emit("continue_text", { "text": "You were defeated..." })
		await wait_for_continue()
		MyInputRouter.pop()
		MyEventBus.emit("combat_ended", { "victory": false })

# ============================================================
# RENDERING
# ============================================================

func show_text(text, choices = []):
	MyEventBus.emit("dialogue", { "text": text, "choices": choices })

func show_choices(choices = []):
	MyEventBus.emit("show_choices", { "choices": choices, "fixed_sizes": len(choices) > 3 })

func _show_intro():
	var names = " and ".join(enemy_display_names)
	if enemies.size() == 1:
		show_text("You encounter %s\n\n%s is raring for a fight!" % [names, names])
	else:
		show_text("You encounter %s\n\nThey're ready to fight!" % names)

func _execute_start_skills():
	for i in range(enemies.size()):
		var skill_name: String = enemies[i].data.get("Start", "")
		if skill_name == "":
			continue
		var db = skills_db if skills_db.has(skill_name) else spells_db
		var skill_data = db.get(skill_name, {})
		var target = enemies[i] if skill_data.get("type", "attack") == "self" else player
		await _execute_action(enemies[i], _ekey(i), skill_name, db, target)

func render_player_turn():
	var living = _living_indices()

	var timers: Array = []
	for i in range(enemies.size()):
		timers.append(enemy_timers[i] if enemies[i].get_hp() > 0 else -1)
	MyEventBus.emit("enemy_timer_update", { "timers": timers })

	var enemy_lines = []
	for i in living:
		enemy_lines.append("%s: %d hp" % [enemy_display_names[i], enemies[i].get_hp()])

	var timer_lines = []
	for i in living:
		var t = enemy_timers[i]
		var n = enemy_display_names[i]
		if t <= 0:
			timer_lines.append("[color=red]%s will act this turn![/color]" % n)
		elif t == 1:
			timer_lines.append("[color=yellow]%s will act next turn.[/color]" % n)
		else:
			timer_lines.append("[color=green]%s will act in %d turns.[/color]" % [n, t])

	show_text(
		"%s\n%s: %d hp.\n%s\n\nWhat would you like to do?" % [
			"\n".join(enemy_lines),
			player.get_name(), player.get_hp(),
			"\n".join(timer_lines)
		],
		_main_choices()
	)

# ============================================================
# MENU BUILDING
# ============================================================

func _main_choices() -> Array:
	return [
		{ "text": "Attack", "type": "attack", "tooltip": _format_weapon_tooltip() },
		{ "text": "Skill",  "type": "skill",  "tooltip": "Use a Skill" },
		{ "text": "Magic",  "type": "magic",  "tooltip": "Use a Spell" },
		{ "text": "Item",   "type": "item",   "tooltip": "Use an Item" }
	]

func _build_list_menu(list, type: String, db: Dictionary = {}) -> Array:
	var choices = []
	for item_name in list:
		var choice = _build_action_choice(str(item_name), type, db.get(str(item_name), null))
		if choice != null:
			choices.append(choice)
	choices.append({ "text": "Back", "type": "back" })
	return choices

func _build_action_choice(item_name: String, type: String, data) -> Variant:
	if data == null:
		return { "text": item_name, "type": type, "data": item_name }

	var label    = data.get("nome", item_name)
	var disabled = false
	var tooltip  = ""

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
		choice["tooltip"] = _format_action_tooltip(item_name, data)
	return choice

# ============================================================
# INPUT ROUTING
# ============================================================

func _handle_combat_input(choice):
	match state:
		CombatState.CHOOSING_ACTION: handle_main_action(choice)
		CombatState.CHOOSING_SKILL:  handle_list_choice(choice, "skill")
		CombatState.CHOOSING_MAGIC:  handle_list_choice(choice, "magic")
		CombatState.CHOOSING_ITEM:   handle_list_choice(choice, "item")
		CombatState.CHOOSING_TARGET: handle_target_choice(choice)

# ============================================================
# ACTION HANDLERS
# ============================================================

func handle_main_action(choice):
	match choice["type"]:
		"attack":
			var action = { "actor": player, "who": "player", "type": "attack" }
			await _maybe_select_target(action)
		"skill": open_menu("skill", player.get_skills(),           skills_db)
		"magic": open_menu("magic", player.get_spells(),           spells_db)
		"item":  open_menu("item",  player.get_inventory().keys(), items_db)

func open_menu(type: String, list, db: Dictionary = {}):
	match type:
		"skill": state = CombatState.CHOOSING_SKILL
		"magic": state = CombatState.CHOOSING_MAGIC
		"item":  state = CombatState.CHOOSING_ITEM
	show_choices(_build_list_menu(list, type, db))

func handle_list_choice(choice, type: String):
	if choice["type"] == "back":
		restart_player_choices()
		return
	var db: Dictionary = skills_db if type == "skill" else (spells_db if type == "magic" else items_db)
	var data = db.get(choice["data"], null)
	var action = { "actor": player, "who": "player", "type": type, "name": choice["data"], "db": db }
	var action_type = data.get("type", "attack") if data != null else "attack"
	if action_type in ["self", "group"] or action_type in ["aoe", "all", "random"]:
		await _resolve_turn_pair(action)
	else:
		await _maybe_select_target(action)

func handle_target_choice(choice):
	if choice["type"] == "back":
		restart_player_choices()
		return
	pending_action["target_idx"] = choice["data"]
	var action = pending_action.duplicate()
	pending_action = {}
	await _resolve_turn_pair(action)

func _maybe_select_target(action: Dictionary):
	var living = _living_indices()
	if living.size() == 1:
		action["target_idx"] = living[0]
		await _resolve_turn_pair(action)
	else:
		pending_action = action
		state = CombatState.CHOOSING_TARGET
		var choices = []
		for i in living:
			choices = [{
				"text":    '%s (%d HP)' % [enemy_display_names[i], enemies[i].get_hp()],
				"type":    "target",
				"data":    i,
				"tooltip": "%s: %d HP" % [enemy_display_names[i], enemies[i].get_hp()]
			}] + choices
		choices.append({ "text": "Back", "type": "back" })
		show_choices(choices)

# ============================================================
# TURN RESOLUTION
# ============================================================

func _resolve_turn_pair(player_action: Dictionary):
	state = CombatState.RESOLUTION

	for i in _living_indices():
		_tick_cooldowns(_ekey(i))

	var all_actions: Array = [player_action]
	var preparing_indices: Array = []

	for i in _living_indices():
		if enemy_timers[i] <= 0:
			all_actions.append(_enemy_choose_action(i))
			enemy_first_actions[i] = false
			enemy_timers[i] = enemies[i].data.get("Cooldown", 0)
		else:
			preparing_indices.append(i)
			enemy_timers[i] -= 1

	all_actions.sort_custom(func(a, b):
		return _get_action_speed(a["actor"], a) > _get_action_speed(b["actor"], b)
	)

	for action in all_actions:
		if action["who"] != "player" and action["actor"].get_hp() <= 0:
			continue
		await _execute_turn_action(action)
		if player.get_hp() <= 0:
			check_combat_end()
			return

	var prep_msgs: Array = []
	for i in preparing_indices:
		if enemies[i].get_hp() > 0:
			var phase = "is preparing to attack!" if enemy_first_actions[i] else "is catching its breath."
			prep_msgs.append("[b]%s[/b] %s" % [enemy_display_names[i], phase])
	if prep_msgs.size() > 0:
		MyEventBus.emit("continue_text", { "text": "\n".join(prep_msgs) })
		await wait_for_continue()
	var need_wait = false
	need_wait = _process_statuses("player")
	for i in range(enemies.size()):
		need_wait = need_wait or _process_statuses(_ekey(i))

	state = CombatState.PLAYER_TURN
	check_combat_end(need_wait)

func _execute_turn_action(action: Dictionary):
	match action["type"]:
		"attack":
			await _do_attack(action["actor"], action["who"], _target_for(action))
		_:
			var data        = action.get("db", {}).get(action.get("name", ""), {})
			var action_type = data.get("type", "attack")
			if action["who"] == "player" and action_type in ["aoe", "all", "random"]:
				await _execute_action(action["actor"], action["who"], action["name"], action["db"],"_")
			else:
				var target = action["actor"] if action_type == "self" else _target_for(action)
				await _execute_action(action["actor"], action["who"], action["name"], action["db"], target)

func _do_attack(actor, who: String, target):
	var weapon   = actor.get_weapon()
	var dmg      = calculate_damage(actor, target)
	var wpn_type = weapon.get("wpn_type", "").to_lower() if weapon and not weapon.is_empty() else ""

	var target_part = ""
	if who == "player" and enemies.size() > 1:
		target_part = " [b]%s[/b]" % _get_display_name(target)

	var attacktxt: String
	if who != "player" and not weapon.has("name"):
		attacktxt = "[b]%s[/b] struck%s![wait=0.1]" % [actor.get_name(), target_part]
	else:
		attacktxt = "[b]%s[/b] struck%s with %s![wait=0.1]" % [actor.get_name(), target_part, weapon.get("name", "bare hands")]

	MyEventBus.emit("continue_text", { "text": attacktxt })
	await wait_for_writing()

	target.take_damage(dmg)
	var down_msg = _notify_if_died(target)
	MyEventBus.emit("play_sfx", { "sound": wpn_type if wpn_type != "" else "attack" })
	MyEventBus.emit("continue_text", {
		"text": "[screenshake][instant][color=red]%d[/color] damage![/instant]%s" % [dmg, down_msg],
		"linebreak": false
	})
	await wait_for_writing()

func _enemy_choose_action(idx: int) -> Dictionary:
	var e      = enemies[idx]
	var key    = _ekey(idx)
	var skills = e.get_skills()
	var spells = e.get_spells()
	var available = skills.filter(func(s): return cooldowns[key].get(s, 0) == 0 and skills_db.has(s))
	available += spells.filter(func(s): return cooldowns[key].get(s, 0) == 0 and spells_db.has(s) and spells_db[s].get("cost",0) <= e.get_mp())
	print(available)
	if available.size() > 0 and (randi_range(1, 100) <= e.data.get('Skill_Chance',35)):
		var chosen = available[randi_range(0, available.size() - 1)]
		if skills_db.has(chosen):
			return { "actor": e, "who": key, "type": "skill", "name": chosen, "db": skills_db }
		if spells_db.has(chosen):
			return { "actor": e, "who": key, "type": "spell", "name": chosen, "db": spells_db }
	return { "actor": e, "who": key, "type": "attack" }

func _get_action_speed(actor, action: Dictionary) -> float:
	var agi = actor.get_total_stat("agi")
	var dex = actor.get_total_stat("dex")
	return float(agi - max(_get_action_wgt(actor, action) - dex, 0))

func _get_action_wgt(actor, action: Dictionary) -> int:
	if action["type"] == "attack":
		return actor.get_weapon().get("stats", {}).get("wgt", 0)
	return action.get("db", {}).get(action.get("name", ""), {}).get("stats", {}).get("wgt", 0)

# ============================================================
# DAMAGE & ACTION EXECUTION
# ============================================================

func calculate_damage(attacker, defender) -> int:
	var weapon = attacker.get_weapon()
	var mgt    = weapon.get("stats", {}).get("mgt",  0)
	var crit   = weapon.get("stats", {}).get("crit", 0)
	var atk    = attacker.get_total_stat("str") + mgt
	var def    = defender.get_total_stat("def")
	var dmg    = max(1, atk - floori(def / 2) + randi_range(0, 2))
	if randi_range(1, 100) <= crit:
		dmg = int(dmg * 1.5)
	return dmg

func _execute_action(user, who: String, action_name: String, db: Dictionary, target):
	var data = db.get(action_name, null)
	if not data:
		MyEventBus.emit("continue_text", { "text": "...%s?\n" % action_name })
		await wait_for_continue()
		return

	if data.has("cost"):
		user.use_mp(data["cost"])
	if data.has("cooldown") and who != "":
		cooldowns[who][action_name] = data["cooldown"]

	var target_name = "all enemies"

	if data.get("type","attack") == 'all':
		target_name = "the whole area"
	elif not ((who == "player" and data.get("type","attack") in ["aoe","all"]) or (who != "player" and data.get("type","attack") in ["group","all"])):
		target_name = _get_display_name(target)
	
	var use_text = data.get("use_text", "[b]%s[/b] used [color=cyan]%s[/color]!" % [user.get_name(), data.get("nome", action_name)])
	
	MyEventBus.emit("continue_text", { "text": _parse_action_text(use_text, {
											"USER": user.get_name(), "TARGET": target_name})+ "[wait=0.1]"})
	await wait_for_writing()

	if (who == "player" and data.get("type","attack") in ["aoe","all"]) or (who != "player" and data.get("type","attack") in ["group","all"]):
		if who != "player" and data.get("type","attack") == "all":
			await _execute_hit(data, user, who, player)
			await wait_for_writing()
		for i in _living_indices():
			var new_target = enemies[i]
			await _execute_hit(data, user, who, new_target)
			await wait_for_writing()
		if who == "player" and data.get("type","attack") == "all":
			await _execute_hit(data, user, who, player)
			await wait_for_writing()
	elif who == "player" and data.get("type","attack") in ["random"]:
		for i in range(int(data.get("hits",1))):
			if len(_living_indices()) > 0:
				var new_target = enemies[_living_indices().pick_random()]
				var temp_data = data.duplicate()
				temp_data["hits"] = 1
				await _execute_hit(temp_data, user, who, new_target)
				await wait_for_writing()
	else:
		await _execute_hit(data, user, who, target)
		await wait_for_writing()

	if data.get("consumable", false):
		user.consume_item(action_name)

	await wait_for_continue()

func _execute_hit(data, user, who: String, target):
	for _i in range(data.get("hits", 1)):
		var result = _resolve_action(user, target, data)
		if data.has('hit_text'):
			MyEventBus.emit("continue_text", {"text": _parse_action_text(data["hit_text"]+"[wait=0.1]", {
				"TARGET":_get_display_name(target), "USER": user.get_name()
			}), "linebreak":false})
			await wait_for_writing()

		if result["damage"] > 0:
			if result["critical"]:
				MyEventBus.emit("continue_text", {"text": "[color=orange]Critical![/color][wait=0.1]", "linebreak":false})
				await wait_for_writing()
			_play_damage_sound(data, user, target)
			target.take_damage(result["damage"])
			var down_msg = _notify_if_died(target)
			var damage_txt = "[screenshake][instant][color=red]%d[/color] damage![/instant][wait=0.1]" % result["damage"]
			if data.get("type","attack") in ["group","aoe","all"]:
				damage_txt = "[screenshake][instant]%s took [color=red]%d[/color] damage![/instant][wait=0.1]" % [_get_display_name(target), result["damage"]]
			if down_msg != "":
				damage_txt += down_msg
			MyEventBus.emit("continue_text", {"text": damage_txt, "linebreak":false})
			await wait_for_writing()
		if result["heal"] > 0 and target.get_hp() > 0:
			target.heal(result["heal"])
			var heal_txt = "[instant]Gained [color=green]%d[/color] HP![/instant][wait=0.1]" % result["heal"]
			if data.get("type","attack") in ["group","aoe","all"]:
				heal_txt = "[instant]%s gained [color=green]%d[/color] HP![/instant][wait=0.1]" %  [_get_display_name(target), result["heal"]]
			MyEventBus.emit("continue_text", {"text": heal_txt, "linebreak":false})
			await wait_for_writing()
		if result["mp_restore"] > 0 and target.get_hp() > 0:
			target.restore_mp(result["mp_restore"])
			var mp_restore_txt = "[instant]Gained [color=cyan]%d[/color] MP![/instant][wait=0.1]" % result["mp_restore"]
			if data.get("type","attack") in ["group","aoe","all"]:
				mp_restore_txt = "[instant]%s gained [color=cyan]%d[/color] MP![/instant][wait=0.1]" %  [_get_display_name(target), result["mp_restore"]]
			MyEventBus.emit("continue_text", {"text": mp_restore_txt, "linebreak":false})
			await wait_for_writing()

		if result["status"] != "":
			if result["status"] == "stat_clear" and target.get_hp() > 0:
				var side = _who_for(target)
				status_effects[side] = []
				MyEventBus.emit("continue_text", {"text": "[color=green]%s's status effects cleared![/color]" % _get_display_name(target), 
					"linebreak":false})
				await wait_for_writing()
			elif result["status"] == "recharge" and target.get_hp() > 0:
				var mag: int = data.get("magnitude", 1)
				if who != "":
					for skill in cooldowns[who]:
						cooldowns[who][skill] = max(0, cooldowns[who][skill] - mag)
				MyEventBus.emit("continue_text", {"text": "[color=cyan]All cooldowns reduced by %d![/color]" % mag, 
					"linebreak":false})
				await wait_for_writing()
			elif result["status"] == "delay" and target.get_hp() > 0:
				var target_who = _who_for(target)
				if target_who != "player":
					var mag: int = data.get("magnitude", 1)
					var idx = int(target_who.split("_")[1])
					enemy_timers[idx] += mag
					MyEventBus.emit("continue_text", {"text": "[color=yellow]%s's next action delayed by %d![/color]" % [_get_display_name(target), mag], 
						"linebreak":false})
				await wait_for_writing()
			elif target.get_hp() > 0:
				_add_status(target, result["status"], data.get("magnitude", -1))
				var sdata   = status_db.get(result["status"], {})
				var inflict = sdata.get("inflict_text", "[color=yellow][TARGET] gained a status effect![/color]")
				MyEventBus.emit("continue_text", {"text": _parse_action_text(inflict, {"TARGET": _get_display_name(target)}), 
						"linebreak":false})
				await wait_for_writing()

func _play_damage_sound(data, user, target):
	var dmg_sfx = "attack"
	if data.has("element"):
		var element = data.get("element", "").to_lower()
		if element != "":
			dmg_sfx = element
		
	if data.get("inherit_wpn",true):
		var weapon   = user.get_weapon()
		var wpn_type = weapon.get("wpn_type", "").to_lower() if weapon and not weapon.is_empty() else ""
		if wpn_type != "":
			dmg_sfx = wpn_type
	MyEventBus.emit("play_sfx", { "sound": dmg_sfx if dmg_sfx != "" else "attack" })

func _resolve_action(user, target, data) -> Dictionary:
	var result      = { "damage": 0, "heal": 0, "mp_restore": 0, "status": "", "text": "", "critical": false }
	var stats       = data.get("stats", {})
	var is_magic    = data.get("magic", false)
	var action_type = data.get("type", "attack")

	if action_type in ["self","group"]:
		var mgt = stats.get("mgt", 0)
		if mgt < 0:
			result["heal"] = abs(mgt)
		var mp = stats.get("mp", 0)
		if mp < 0:
			result["mp_restore"] = abs(mp)
			#result["text"] += " " % result["mp_restore"]
		var self_fx = data.get("effect", "none")
		if self_fx != "none" and self_fx != "":
			result["status"] = self_fx
		if result["text"] == "":
			result["text"] = "..."
		return result

	var base_mgt     = stats.get("mgt", 0)
	var inherit_stat = data.get("inherit_stats", false)
	var inherit_wpn  = data.get("inherit_wpn",   false)
	var weapon       = user.get_weapon()

	if inherit_wpn:
		base_mgt += weapon.get("stats", {}).get("mys" if is_magic else "mgt", 0)

	var atk_stat = user.get_total_stat("int" if is_magic else "str")
	if inherit_stat:
		base_mgt += atk_stat

	var ignore_def = data.get("effect", "") == "ignore_def"
	var def_val    = 0
	if not ignore_def:
		def_val = target.get_mp() if is_magic else target.get_total_stat("def")

	var dmg = max(1, base_mgt - floori(def_val / 2) + randi_range(0, 2))

	var crit_chance = stats.get("crit", 0) + user.get_total_stat("dex") - target.get_total_stat("lck")
	if inherit_wpn:
		crit_chance += weapon.get("stats", {}).get("crit", 0)
	if randi_range(1, 100) <= crit_chance:
		dmg = int(dmg * 1.5)
		#result["text"] = "[color=orange]Critical! [/color]"
		result["critical"] = true

	result["damage"] = dmg
	result["text"]  += "[screenshake][instant][color=red]%d[/color] damage![/instant]" % dmg

	var effect = data.get("effect", "none")
	var chance = data.get("chance", 100)
	if effect != "none" and effect != "" and effect != "ignore_def" and randi_range(1, 100) <= chance:
		result["status"] = effect

	return result

# ============================================================
# REWARDS
# ============================================================

func _calculate_rewards() -> Dictionary:
	var total_xp   = 0
	var total_gold = 0
	var all_drops: Dictionary = {}
	for e in enemies:
		var lvl = e.get_level()
		total_xp   += int(10.0 * pow(1.5, lvl - 1))
		total_gold += e.data.get("Gold", 0)
		for item in e.data.get("Drops", {}):
			if randi_range(1, 100) <= e.data["Drops"][item]:
				all_drops[item] = all_drops.get(item, 0) + 1
	return { "xp": total_xp, "gold": total_gold, "drops": all_drops }

func _format_reward_text(r: Dictionary) -> String:
	var lines = ["[b]Rewards[/b]", "[color=cyan]+%d XP[/color]" % r["xp"]]
	if r["gold"] > 0:
		lines.append("[color=yellow]+%dG[/color]" % r["gold"])
	for item in r["drops"]:
		lines.append("  • %s" % item)
	return "\n".join(lines)

# ============================================================
# STATUS EFFECTS & COOLDOWNS
# ============================================================

func _tick_cooldowns(who: String):
	for skill in cooldowns[who]:
		cooldowns[who][skill] = max(0, cooldowns[who][skill] - 1)

func _add_status(target, effect: String, magnitude: int = -1):
	var who      = _who_for(target)
	var duration = magnitude if magnitude > 0 else status_db.get(effect, {}).get("duration", 3)
	for s in status_effects[who]:
		if s["type"] == effect:
			s["duration"] = max(s["duration"], duration)
			_emit_status_update(who)
			return
	status_effects[who].append({ "type": effect, "duration": duration })
	_apply_stat_modifiers(who)
	_emit_status_update(who)

func _apply_stat_modifiers(who: String):
	var target = player if who == "player" else enemies[int(who.split("_")[1])]
	var combined: Dictionary = {}
	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		for stat in data.get("stats", {}):
			combined[stat] = combined.get(stat, 1.0) * float(data["stats"][stat])
	target.set_stat_multipliers(combined)

func _process_statuses(who: String):
	var target = player if who == "player" else enemies[int(who.split("_")[1])]
	var remaining = []
	var need_wait = false

	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		if not data.is_empty():
			var damage_frac: float = data.get("damage", 0.0)
			var heal_frac:   float = data.get("heal",   0.0)
			var upkeep:      String = data.get("upkeep_text", "")

			if damage_frac > 0.0:
				var dmg = max(1, int(target.get_max_hp() * damage_frac))
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": _parse_action_text(upkeep, {"TARGET":_get_display_name(target)}) + "[wait=0.1]" })
				target.take_damage(dmg)
				MyEventBus.emit("continue_text", { "text": "[screenshake][instant][color=red]%d[/color] damage![/instant]" % dmg, 
								"linebreak":false})
				need_wait = true
			elif heal_frac > 0.0:
				var hp = max(1, int(target.get_max_hp() * heal_frac))
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": _parse_action_text(upkeep, {"TARGET":_get_display_name(target)}) + "[wait=0.1]" })
				target.heal(hp)
				MyEventBus.emit("continue_text", { "text": "[instant]Gained [color=green]%d[/color] HP![/instant]" % hp, 
								"linebreak":false})
				need_wait = true

		s["duration"] -= 1
		if s["duration"] > 0:
			remaining.append(s)
		else:
			var end_text: String = data.get("end_text", "")
			if end_text != "":
				MyEventBus.emit("continue_text", { "text": _parse_action_text(end_text, {"TARGET":_get_display_name(target)}) + "\n" })
				need_wait = true

	status_effects[who] = remaining
	_apply_stat_modifiers(who)
	_emit_status_update(who)
	return need_wait

func _emit_status_update(who: String):
	MyEventBus.emit("status_changed", { "who": who, "effects": status_effects[who] })

# ============================================================
# UTILITIES
# ============================================================

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
	MyEventBus.emit("show_choices", { "choices": [{ "text": "Continue", "type": "continue" }] })
	while not wait_state["done"]:
		await get_tree().process_frame

func _format_weapon_tooltip() -> String:
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

func _parse_action_text(text: String, values: Dictionary) -> String:
	for key in values:
		text = text.replace("[" + key + "]", str(values[key]))
	return text

func _format_action_tooltip(action_key: String, data: Dictionary) -> String:
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

	var hits = data.get("hits", 1)
	if hits > 1:
		lines.append("Hits: %d×" % hits)

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

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json  = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON parse error: " + path)
		return {}
	return json.data
