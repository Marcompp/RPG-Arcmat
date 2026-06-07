extends Node
# class_name CombatManager

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

var skills_db:   Dictionary = {}
var spells_db:   Dictionary = {}
var items_db:    Dictionary = {}
var status_db:   Dictionary = {}
var element_db:  Dictionary = {}

var status_effects: Dictionary = { "player": [] }
var cooldowns:      Dictionary = { "player": {} }

var rng: RandomNumberGenerator

var enemy_timers: Array = []
var enemy_first_actions: Array = []

var pending_action: Dictionary = {}
var _died_enemies: Array = []

var calc:       CombatCalculator
var status_sys: CombatStatusSystem
var menu:       CombatMenuBuilder

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
	status_sys.emit_status_update(who)
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
	player  = p
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

	skills_db  = CombatUtils.load_json("res://Database/skills.json")
	spells_db  = CombatUtils.load_json("res://Database/spells.json")
	items_db   = CombatUtils.load_json("res://Database/items.json")
	status_db  = CombatUtils.load_json("res://Database/status.json")
	element_db = CombatUtils.load_json("res://Database/element.json")

	status_effects      = { "player": [] }
	cooldowns           = { "player": {} }
	enemy_timers        = []
	enemy_first_actions = []
	pending_action      = {}
	_died_enemies       = []

	calc       = CombatCalculator.new(rng, element_db)
	status_sys = CombatStatusSystem.new(status_effects, cooldowns, status_db, player, enemies, _get_display_name)
	menu       = CombatMenuBuilder.new()

	p.set_stat_multipliers({})
	status_sys.emit_status_update("player")

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
		status_sys.emit_status_update(key)

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
	status_sys.tick_cooldowns("player")
	state = CombatState.CHOOSING_ACTION
	render_player_turn()

func restart_player_choices():
	state = CombatState.CHOOSING_ACTION
	show_choices(menu.main_choices(player))

func next_turn():
	start_player_turn()

func _find_auto_revive_item() -> String:
	var inv = player.get_inventory()
	for item_name in inv:
		if inv[item_name] > 0:
			var data = items_db.get(item_name, {})
			if data.get("effect", "") == "auto_revive":
				return item_name
	return ""

func check_combat_end(need_wait = true):
	if player.get_hp() <= 0:
		var revival_item = _find_auto_revive_item()
		if revival_item != "":
			player.consume_item(revival_item)
			var data       = items_db.get(revival_item, {})
			var revive_pct = data.get("magnitude", 50)
			var revive_hp  = max(1, int(player.get_mhp() * revive_pct / 100.0))
			player.heal(revive_hp)
			var item_nome = data.get("nome", revival_item)
			MyEventBus.emit("dialogue", { "text": "[color=yellow]The %s shattered! %s was revived with %d HP![/color]" % [item_nome, player.get_name(), revive_hp] })
			await wait_for_continue()
		else:
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
		var names   = ", ".join(enemy_display_names)
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
		var db         = skills_db if skills_db.has(skill_name) else spells_db
		var skill_data = db.get(skill_name, {})
		var target     = enemies[i] if skill_data.get("type", "attack") == "self" else player
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
		menu.main_choices(player)
	)

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
	show_choices(menu.build_list_menu(list, type, db, player, cooldowns))

func handle_list_choice(choice, type: String):
	if choice["type"] == "back":
		restart_player_choices()
		return
	var db: Dictionary  = skills_db if type == "skill" else (spells_db if type == "magic" else items_db)
	var data            = db.get(choice["data"], null)
	var action          = { "actor": player, "who": "player", "type": type, "name": choice["data"], "db": db }
	var action_type     = data.get("type", "attack") if data != null else "attack"
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
		state          = CombatState.CHOOSING_TARGET
		var choices    = []
		for i in living:
			choices = [{
				"text":    "%s (%d HP)" % [enemy_display_names[i], enemies[i].get_hp()],
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
		status_sys.tick_cooldowns(_ekey(i))

	var all_actions: Array     = [player_action]
	var preparing_indices: Array = []

	for i in _living_indices():
		if enemy_timers[i] <= 0:
			all_actions.append(calc.enemy_choose_action(enemies[i], _ekey(i), cooldowns, skills_db, spells_db))
			enemy_first_actions[i] = false
			enemy_timers[i]        = enemies[i].data.get("Cooldown", 0)
		else:
			preparing_indices.append(i)
			enemy_timers[i] -= 1

	all_actions.sort_custom(func(a, b):
		return calc.get_action_speed(a["actor"], a) > calc.get_action_speed(b["actor"], b)
	)

	for action in all_actions:
		if action["who"] != "player" and action["actor"].get_hp() <= 0:
			continue
		await _execute_turn_action(action)
		if player.get_hp() <= 0:
			await check_combat_end()
			return
		if _living_indices().is_empty():
			break

	var prep_msgs: Array = []
	for i in preparing_indices:
		if enemies[i].get_hp() > 0:
			var phase = "is preparing to attack!" if enemy_first_actions[i] else "is catching its breath."
			prep_msgs.append("[b]%s[/b] %s" % [enemy_display_names[i], phase])
	if prep_msgs.size() > 0:
		MyEventBus.emit("continue_text", { "text": "\n".join(prep_msgs) })
		await wait_for_continue()

	var need_wait = false
	need_wait = status_sys.process_statuses("player")
	for i in range(enemies.size()):
		need_wait = need_wait or status_sys.process_statuses(_ekey(i))

	state = CombatState.PLAYER_TURN
	await check_combat_end(need_wait)

func _execute_turn_action(action: Dictionary):
	match action["type"]:
		"attack":
			await _do_attack(action["actor"], action["who"], _target_for(action))
		_:
			var data        = action.get("db", {}).get(action.get("name", ""), {})
			var action_type = data.get("type", "attack")
			if action["who"] == "player" and action_type in ["aoe", "all", "random"]:
				await _execute_action(action["actor"], action["who"], action["name"], action["db"], "_")
			else:
				var target = action["actor"] if action_type == "self" else _target_for(action)
				await _execute_action(action["actor"], action["who"], action["name"], action["db"], target)

# ============================================================
# DAMAGE & ACTION EXECUTION
# ============================================================

func _do_attack(actor, who: String, target):
	var weapon  = actor.get_weapon()
	var acc     = weapon.get("stats", {}).get("acc", 90) if weapon and not weapon.is_empty() else 90
	if not calc.check_hit(actor, target, acc):
		MyEventBus.emit("continue_text", { "text": "...but missed![wait=0.1]", "linebreak": false })
		await wait_for_writing()
		return
	var dmg      = calc.calculate_damage(actor, target)
	var wpn_type = weapon.get("wpn_type", "").to_lower() if weapon and not weapon.is_empty() else ""

	var attack_element = weapon.get("element", "Neutral") if weapon and not weapon.is_empty() else "Neutral"
	var target_element = target.data.get("Element", "Neutral")
	var elem_mult      = calc.get_element_multiplier(attack_element, target_element)
	var elem_reaction  = ""
	if elem_mult == 0.0:
		elem_reaction = "immune"
	elif elem_mult != 1.0:
		dmg = max(1, int(dmg * elem_mult))
		elem_reaction = "weak" if elem_mult >= 2.0 else "resist"

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

	MyEventBus.emit("play_sfx", { "sound": wpn_type if wpn_type != "" else "attack" })
	if elem_reaction == "immune":
		MyEventBus.emit("continue_text", { "text": "[color=cyan]No effect![/color][wait=0.1]", "linebreak": false })
	else:
		target.take_damage(dmg)
		var down_msg = _notify_if_died(target)
		var prefix   = "[color=yellow]Weak![/color] " if elem_reaction == "weak" \
				else ("[color=cyan]Resisted![/color] " if elem_reaction == "resist" else "")
		MyEventBus.emit("continue_text", {
			"text": prefix + "[screenshake][instant][color=red]%d[/color] damage![/instant]%s" % [dmg, down_msg],
			"linebreak": false
		})
	await wait_for_writing()

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
	if data.get("type", "attack") == "all":
		target_name = "the whole area"
	elif not ((who == "player" and data.get("type", "attack") in ["aoe", "all"]) or (who != "player" and data.get("type", "attack") in ["group", "all"])):
		target_name = _get_display_name(target)

	var use_text = data.get("use_text", "[b]%s[/b] used [color=cyan]%s[/color]!" % [user.get_name(), data.get("nome", action_name)])
	MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(use_text, { "USER": user.get_name(), "TARGET": target_name }) + "[wait=0.1]" })
	await wait_for_writing()

	if (who == "player" and data.get("type", "attack") in ["aoe", "all"]) or (who != "player" and data.get("type", "attack") in ["group", "all"]):
		if who != "player" and data.get("type", "attack") == "all":
			await _execute_hit(data, user, who, player)
			await wait_for_writing()
		for i in _living_indices():
			await _execute_hit(data, user, who, enemies[i])
			await wait_for_writing()
		if who == "player" and data.get("type", "attack") == "all":
			await _execute_hit(data, user, who, player)
			await wait_for_writing()
	elif who == "player" and data.get("type", "attack") in ["random"]:
		var hits = int(data.get("hits", 1))
		if data.has("max_hits"):
			hits = rng.randi_range(data.get("min_hits", 1), data["max_hits"])
		for i in range(hits):
			if len(_living_indices()) > 0:
				var living     = _living_indices()
				var new_target = enemies[living[rng.randi() % living.size()]]
				var temp_data  = data.duplicate()
				temp_data["hits"]     = 1
				temp_data["max_hits"] = 1
				await _execute_hit(temp_data, user, who, new_target)
				await wait_for_writing()
	else:
		await _execute_hit(data, user, who, target)
		await wait_for_writing()

	if data.get("consumable", false):
		user.consume_item(action_name)

	await wait_for_continue()

func _execute_hit(data, user, who: String, target):
	var hits = int(data.get("hits", 1))
	if data.has("max_hits") and data["max_hits"] > 1:
		hits = rng.randi_range(data.get("min_hits", 1), data["max_hits"])
	for _i in range(hits):
		if target.get_hp() <= 0:
			break
		var result = calc.resolve_action(user, target, data)
		if result.get("missed", false):
			var miss_txt = "Missed![wait=0.1]"
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				miss_txt = "%s evaded![wait=0.1]" % _get_display_name(target)
			MyEventBus.emit("continue_text", { "text": miss_txt, "linebreak": false })
			await wait_for_writing()
			continue
		if data.has("hit_text"):
			MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(data["hit_text"] + "[wait=0.1]", {
				"TARGET": _get_display_name(target), "USER": user.get_name()
			}), "linebreak": false })
			await wait_for_writing()

		if result["damage"] > 0:
			if result["critical"]:
				MyEventBus.emit("continue_text", { "text": "[color=orange]Critical![/color][wait=0.1]", "linebreak": false })
				await wait_for_writing()
			match result.get("element_reaction", ""):
				"weak":
					MyEventBus.emit("continue_text", { "text": "[color=yellow]Weak![/color] ", "linebreak": false })
					await wait_for_writing()
				"resist":
					MyEventBus.emit("continue_text", { "text": "[color=cyan]Resisted![/color] ", "linebreak": false })
					await wait_for_writing()
			_play_damage_sound(data, user, target)
			target.take_damage(result["damage"])
			var down_msg   = _notify_if_died(target)
			var damage_txt = "[screenshake][instant][color=red]%d[/color] damage![/instant][wait=0.1]" % result["damage"]
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				damage_txt = "[screenshake][instant]%s took [color=red]%d[/color] damage![/instant][wait=0.1]" % [_get_display_name(target), result["damage"]]
			if down_msg != "":
				damage_txt += down_msg
			MyEventBus.emit("continue_text", { "text": damage_txt, "linebreak": false })
			await wait_for_writing()
		elif result.get("element_reaction") == "immune":
			MyEventBus.emit("continue_text", { "text": "[color=cyan]No effect![/color][wait=0.1]", "linebreak": false })
			await wait_for_writing()

		if result["heal"] > 0 and target.get_hp() > 0:
			target.heal(result["heal"])
			var heal_txt = "[instant]Gained [color=green]%d[/color] HP![/instant][wait=0.1]" % result["heal"]
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				heal_txt = "[instant]%s gained [color=green]%d[/color] HP![/instant][wait=0.1]" % [_get_display_name(target), result["heal"]]
			MyEventBus.emit("continue_text", { "text": heal_txt, "linebreak": false })
			await wait_for_writing()

		if result["mp_restore"] > 0 and target.get_hp() > 0:
			target.restore_mp(result["mp_restore"])
			var mp_txt = "[instant]Gained [color=cyan]%d[/color] MP![/instant][wait=0.1]" % result["mp_restore"]
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				mp_txt = "[instant]%s gained [color=cyan]%d[/color] MP![/instant][wait=0.1]" % [_get_display_name(target), result["mp_restore"]]
			MyEventBus.emit("continue_text", { "text": mp_txt, "linebreak": false })
			await wait_for_writing()

		if result["status"] != "":
			if result["status"] == "stat_clear" and target.get_hp() > 0:
				var side = _who_for(target)
				status_effects[side] = []
				MyEventBus.emit("continue_text", { "text": "[color=green]%s's status effects cleared![/color]" % _get_display_name(target), "linebreak": false })
				await wait_for_writing()
			elif result["status"] == "recharge" and target.get_hp() > 0:
				var mag: int = data.get("magnitude", 1)
				if who != "":
					for skill in cooldowns[who]:
						cooldowns[who][skill] = max(0, cooldowns[who][skill] - mag)
				MyEventBus.emit("continue_text", { "text": "[color=cyan]All cooldowns reduced by %d![/color]" % mag, "linebreak": false })
				await wait_for_writing()
			elif result["status"] == "delay" and target.get_hp() > 0:
				var target_who = _who_for(target)
				if target_who != "player":
					var mag: int = data.get("magnitude", 1)
					var idx      = int(target_who.split("_")[1])
					enemy_timers[idx] += mag
					MyEventBus.emit("continue_text", { "text": "[color=yellow]%s's next action delayed by %d![/color]" % [_get_display_name(target), mag], "linebreak": false })
				await wait_for_writing()
			elif result["status"] == "lifedrain" and result["damage"] > 0:
				var drain_amount = max(1, int(result["damage"] * data.get("magnitude", 0.5)))
				user.heal(drain_amount)
				MyEventBus.emit("continue_text", { "text": "[instant]Drained [color=green]%d[/color] HP![/instant][wait=0.1]" % drain_amount, "linebreak": false })
				await wait_for_writing()
			elif target.get_hp() > 0:
				status_sys.add_status(target, result["status"], data.get("magnitude", -1))
				var sdata   = status_db.get(result["status"], {})
				var inflict = sdata.get("inflict_text", "[color=yellow][TARGET] gained a status effect![/color]")
				MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(inflict, { "TARGET": _get_display_name(target) }), "linebreak": false })
				await wait_for_writing()

func _play_damage_sound(data, user, _target):
	var dmg_sfx = "attack"
	if data.has("element"):
		var element = data.get("element", "").to_lower()
		if element != "":
			dmg_sfx = element
	if data.get("inherit_wpn", true):
		var weapon   = user.get_weapon()
		var wpn_type = weapon.get("wpn_type", "").to_lower() if weapon and not weapon.is_empty() else ""
		if wpn_type != "":
			dmg_sfx = wpn_type
	MyEventBus.emit("play_sfx", { "sound": dmg_sfx if dmg_sfx != "" else "attack" })

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
			if rng.randi_range(1, 100) <= e.data["Drops"][item]:
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
