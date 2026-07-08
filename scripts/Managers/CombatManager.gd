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
var enemy_channeling: Array = []

var pending_action: Dictionary = {}
var _died_enemies: Array = []
var _fled_indices: Array = []

var calc:        CombatCalculator
var status_sys:  CombatStatusSystem
var menu:        CombatMenuBuilder
var trinket_systems: Dictionary = {}

var trinkets_db: Dictionary = {}

var monster_db_ref: Array      = []
var armor_db:       Dictionary = {}
var weapon_db:      Dictionary = {}
var _accumulated_rewards:    Dictionary = {}
var _summon_name_counters:   Dictionary = {}

# ============================================================
# HELPERS
# ============================================================

func _tsys(who: String) -> TrinketSystem:
	return trinket_systems.get(who, null)

func _ekey(idx: int) -> String:
	return "enemy_%d" % idx

func _living_indices() -> Array:
	var r = []
	for i in range(enemies.size()):
		if enemies[i].get_hp() > 0 and not i in _fled_indices:
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

func _emit_timer_update() -> void:
	var timers: Array = []
	var locked: Array = []
	var hidden: Array = []
	for i in range(enemies.size()):
		var alive = enemies[i].get_hp() > 0
		timers.append(enemy_timers[i] if alive else -1)
		var is_stunned = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "stun")
		var is_frozen  = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "freeze")
		locked.append(alive and (is_stunned or is_frozen))
		var esys = _tsys(_ekey(i))
		hidden.append(alive and esys != null and esys.has_circadian_mask() and enemy_timers[i] > 0)

	MyEventBus.emit("enemy_timer_update", { "timers": timers, "locked": locked, "hidden": hidden })

func _check_channel_trigger(idx: int) -> Dictionary:
	var moves: Array = enemies[idx].data.get("ChannelMoves", [])
	if moves.is_empty():
		return {}
	var hp_pct = 100.0 * enemies[idx].get_hp() / max(1, enemies[idx].get_mhp())
	var eligible: Array = []
	for move in moves:
		var cond = move.get("condition", "always")
		var ok = cond == "always" or (cond == "hp_below" and hp_pct <= move.get("threshold", 100))
		if ok:
			eligible.append(move)
	if eligible.is_empty():
		return {}
	var pool: Array = []
	for move in eligible:
		for _w in range(move.get("weight", 1)):
			pool.append(move)
	return pool[rng.randi() % pool.size()]

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

	_summon_name_counters = name_count.duplicate()

	for i in range(enemies.size()):
		enemies[i].data["Name"] = enemy_display_names[i]
		enemies[i].stats_changed.emit()

	skills_db   = CombatUtils.load_json("res://Database/skills.json")
	spells_db   = CombatUtils.load_json("res://Database/spells.json")
	items_db    = CombatUtils.load_json("res://Database/items.json")
	status_db   = CombatUtils.load_json("res://Database/status.json")
	element_db  = CombatUtils.load_json("res://Database/element.json")
	trinkets_db = CombatUtils.load_json("res://Database/trinkets.json")

	status_effects      = { "player": [] }
	cooldowns           = { "player": {} }
	enemy_timers        = []
	enemy_first_actions = []
	enemy_channeling    = []
	pending_action      = {}
	_died_enemies       = []
	_fled_indices       = []
	_accumulated_rewards = { "xp": 0, "gold": 0, "drops": {} }

	calc        = CombatCalculator.new(rng, element_db)
	status_sys  = CombatStatusSystem.new(status_effects, cooldowns, status_db, player, enemies, _get_display_name)
	menu        = CombatMenuBuilder.new()
	trinket_systems["player"] = TrinketSystem.new(p, trinkets_db, status_effects, "player")
	status_sys.trinket_systems = trinket_systems

	p.set_stat_multipliers({})
	status_sys.emit_status_update("player")

	var psys_startup = trinket_systems.get("player", null)
	for skill in p.get_skills():
		var skill_data = skills_db.get(skill, {})
		if skill_data.has("startup"):
			cooldowns["player"][skill] = rng.randi_range(1, 5) if psys_startup and psys_startup.has_circadian_mask() else skill_data["startup"] + 1

	for i in range(enemies.size()):
		var e   = enemies[i]
		var key = _ekey(i)
		enemy_timers.append(e.data.get("Startup", 0))
		enemy_first_actions.append(true)
		enemy_channeling.append("")
		_register_enemy_slot(e, key)
		var esys_init = _tsys(key)
		if esys_init and esys_init.has_circadian_mask():
			enemy_timers[i] = rng.randi_range(1, 3)

	MyInputRouter.push(_handle_combat_input, "combat")

	await _show_intro()
	await wait_for_continue()
	await _execute_start_skills()
	await _execute_trinket_start_skills()
	await start_player_turn()

# ============================================================
# TURN FLOW
# ============================================================

func start_player_turn():
	var turn_msg = _tsys("player").process_turn_start()
	if turn_msg != "":
		MyEventBus.emit("continue_text", { "text": turn_msg })
		await wait_for_continue()
	var is_stunned = status_effects.get("player", []).any(func(s): return s["type"] == "stun")
	var is_frozen  = status_effects.get("player", []).any(func(s): return s["type"] == "freeze")
	if not is_stunned and not is_frozen:
		status_sys.tick_cooldowns("player")
	if is_stunned:
		show_text("[b]%s[/b] is stunned and can't act!" % player.get_name())
		await wait_for_continue()
		await _resolve_turn_pair({ "actor": player, "who": "player", "type": "stunned" })
		return
	if is_frozen:
		show_text("[b]%s[/b] is frozen solid and can't act!" % player.get_name())
		await wait_for_continue()
		await _resolve_turn_pair({ "actor": player, "who": "player", "type": "frozen" })
		return
	state = CombatState.CHOOSING_ACTION
	render_player_turn()

func restart_player_choices():
	state = CombatState.CHOOSING_ACTION
	show_choices(menu.main_choices(player))

func next_turn():
	await start_player_turn()

func check_combat_end():
	if player.get_hp() <= 0:
		var revive_msg = _tsys("player").try_auto_revive()
		if revive_msg != "":
			MyEventBus.emit("dialogue", { "text": revive_msg })
			await wait_for_continue()
		else:
			await end_combat(false)
			return
	if _living_indices().is_empty():
		await end_combat(true)
		return
	await next_turn()

func end_combat(victory: bool):
	state = CombatState.END
	player.reset_element()
	for e in enemies:
		e.reset_element()
	for s in trinket_systems.values():
		s.reset_combat_state()
	_emit_trinket_states()
	MyEventBus.emit("enemy_timer_update", { "timers": [] })
	MyEventBus.emit("character_defeated", { "victory": victory, "enemy_count": enemies.size() })

	if victory and player.get_hp() > 0:
		var rewards = _calculate_rewards()
		var defeated_names: Array = []
		for i in range(enemies.size()):
			if not i in _fled_indices:
				defeated_names.append(enemy_display_names[i])
		if not defeated_names.is_empty():
			MyEventBus.emit("continue_text", { "text": "[color=yellow]%s[/color] was defeated!" % ", ".join(defeated_names) })
			await wait_for_continue()
		elif not _fled_indices.is_empty():
			MyEventBus.emit("continue_text", { "text": "All enemies are gone..." })
			await wait_for_continue()
		var trinket_msg = _tsys("player").process_post_battle()
		if trinket_msg != "":
			MyEventBus.emit("continue_text", { "text": trinket_msg })
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
	var any_skill = false
	for i in range(enemies.size()):
		var skill_name: String = enemies[i].data.get("Start", "")
		if skill_name == "":
			continue
		var db         = skills_db if skills_db.has(skill_name) else spells_db
		var skill_data = db.get(skill_name, {})
		var target     = enemies[i] if skill_data.get("type", "attack") == "self" else player
		await _execute_action(enemies[i], _ekey(i), skill_name, db, target)
		any_skill = true
	if any_skill:
		await wait_for_continue()

func _execute_trinket_start_skills():
	_tsys("player").process_battle_start()
	var skills = _tsys("player").get_battle_start_skills()
	if skills.is_empty():
		return
	for skill_name in skills:
		var db         = skills_db if skills_db.has(skill_name) else spells_db
		var skill_data = db.get(skill_name, {})
		var action_type = skill_data.get("type", "attack")
		var target
		if action_type in ["self", "group"]:
			target = player
		else:
			var living = _living_indices()
			if living.is_empty():
				continue
			target = enemies[living[rng.randi_range(0, living.size() - 1)]]
		await _execute_action(player, "player", skill_name, db, target)
	await wait_for_continue()

func render_player_turn():
	var living = _living_indices()
	var now_chaneling = []

	for i in living:
		if enemy_timers[i] < 0:
			var cm = _check_channel_trigger(i)
			if not cm.is_empty():
				enemy_channeling[i] = cm.get("skill", "")
				var esys_ch = _tsys(_ekey(i))
				enemy_timers[i]     = rng.randi_range(1, 3) if esys_ch and esys_ch.has_circadian_mask() else cm.get("duration", enemies[i].data.get("Cooldown", 0))
				now_chaneling.append(true)
			else:
				enemy_channeling[i] = ""
				var esys_cd = _tsys(_ekey(i))
				enemy_timers[i]     = rng.randi_range(1, 3) if esys_cd and esys_cd.has_circadian_mask() else enemies[i].data.get("Cooldown", 0)
				now_chaneling.append(false)
		else:
			now_chaneling.append(false)

	_emit_timer_update()

	var enemy_lines = []
	for i in living:
		enemy_lines.append("%s: %d hp" % [enemy_display_names[i], enemies[i].get_hp()])

	var timer_lines = []
	for i in living:
		var t = enemy_timers[i]
		var n = enemy_display_names[i]
		var esys_t = _tsys(_ekey(i))
		var hide_timer = esys_t and esys_t.has_circadian_mask()
		var is_stunned = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "stun")
		var is_frozen  = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "freeze")
		if is_stunned or is_frozen:
			timer_lines.append("[color=cyan]%s ꩜[/color]" % n)
		elif enemy_channeling[i] != "":
			if t <= 0:
				timer_lines.append("[color=red]%s is about to unleash something![/color]" % n)
			elif now_chaneling[i]:
				timer_lines.append(
					CombatUtils.parse_action_text("[color=orange][SELF] has begun channeling something!![/color]",
						{"SELF": n, "SKILL": enemy_channeling[i]}
					)
				)
			else:
				timer_lines.append("[color=orange]%s is channeling... (%s)[/color]" % [n, "?" if hide_timer else str(t)])
		else:
			if t <= 0:
				timer_lines.append("[color=red]%s will act this turn![/color]" % n)
			elif t == 1:
				timer_lines.append("[color=yellow]%s will act next turn.[/color]" % n if not hide_timer else "[color=green]%s will act in ? turns.[/color]" % n)
			else:
				timer_lines.append("[color=green]%s will act in %s turns.[/color]" % [n, "?" if hide_timer else str(t)])

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
	var hide_cd = _tsys("player") != null and _tsys("player").has_circadian_mask()
	show_choices(menu.build_list_menu(list, type, db, player, cooldowns, hide_cd))

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

	var all_actions: Array = [player_action]
	var living = _living_indices()

	for i in living:
		var is_stunned = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "stun")
		var is_frozen  = status_effects.get(_ekey(i), []).any(func(s): return s["type"] == "freeze")

		if not is_stunned and not is_frozen:
			status_sys.tick_cooldowns(_ekey(i))

		if enemy_timers[i] <= 0:
			if is_stunned:
				all_actions.append({ "actor": enemies[i], "who": _ekey(i), "type": "stunned" })
			elif is_frozen:
				all_actions.append({ "actor": enemies[i], "who": _ekey(i), "type": "frozen" })
			else:
				if enemy_channeling[i] != "":
					var skill_name      = enemy_channeling[i]
					enemy_channeling[i] = ""
					var db = skills_db if skills_db.has(skill_name) else spells_db
					all_actions.append({ "actor": enemies[i], "who": _ekey(i), "type": "skill", "name": skill_name, "db": db, "enemy_index": i })
				else:
					all_actions.append(calc.enemy_choose_action(enemies[i], _ekey(i), cooldowns, skills_db, spells_db, status_effects, status_db, living.size()))
			enemy_first_actions[i] = false
			# enemy_timers[i] -= 1
			#enemy_timers[i]        = enemies[i].data.get("Cooldown", 0)
		elif not is_stunned and not is_frozen:
			all_actions.append({ "actor": enemies[i], "who": _ekey(i), "type": "timer_tick", "enemy_index": i, "is_first": enemy_first_actions[i] })

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

	status_sys.process_statuses("player")
	for i in range(enemies.size()):
		status_sys.process_statuses(_ekey(i))
		_notify_if_died(enemies[i])
	await wait_for_writing()

	state = CombatState.PLAYER_TURN

	if player.get_hp() <= 0 or _living_indices().is_empty():
		await check_combat_end()
		return

	await wait_for_continue()
	await next_turn()

func _execute_turn_action(action: Dictionary):
	var idx = -1
	if action["who"] != "player":
		idx = action.get("enemy_index",0)
		var esys = _tsys(action["who"])
		if esys:
			var msg = esys.process_turn_start()
			if msg != "":
				MyEventBus.emit("continue_text", { "text": msg })
				await wait_for_continue()
	match action["type"]:
		"stunned":
			MyEventBus.emit("continue_text", { "text": "[b]%s[/b] is stunned and can't act![wait=0.1]" % _get_display_name(action["actor"]) })
			await wait_for_writing()
		"frozen":
			MyEventBus.emit("continue_text", { "text": "[b]%s[/b] is frozen solid and can't act![wait=0.1]" % _get_display_name(action["actor"]) })
			await wait_for_writing()
		"timer_tick":
			var phase: String
			var phase_map = {"SELF":enemy_display_names[idx]}
			if enemy_channeling[idx] != "":
				var cm_list = enemies[idx].data.get("ChannelMoves", [])
				var cm = cm_list.filter(func(m): return m.get("skill", "") == enemy_channeling[idx])
				var chan_raw = cm[0].get("channel_texts", "[SELF] is channeling...") if not cm.is_empty() else "is channeling..."
				phase_map["SKILL"] = enemy_channeling[idx]
			else:
				var phase_key = "Preparing" if action["is_first"] else "Recharging"
				var phase_def = "[SELF] is preparing to attack!" if action["is_first"] else "[SELF] is catching its breath."
				var phase_raw = enemies[idx].data.get(phase_key, phase_def)
				phase = phase_raw[rng.randi() % phase_raw.size()] if phase_raw is Array else phase_raw
			MyEventBus.emit("continue_text", { "text":
				CombatUtils.parse_action_text(phase, phase_map) + "[wait=0.1]" })
			# MyEventBus.emit("continue_text", { "text": "[b]%s[/b] %s" % [enemy_display_names[idx], phase] })
			enemy_timers[idx] -= 1
			_emit_timer_update()
			await wait_for_writing()
		"attack":
			await _do_attack(action["actor"], action["who"], _target_for(action), idx)
		_:
			var data        = action.get("db", {}).get(action.get("name", ""), {})
			var action_type = data.get("type", "attack")
			if action["who"] == "player" and action_type in ["aoe", "all", "random"]:
				await _execute_action(action["actor"], action["who"], action["name"], action["db"], "_", idx)
			else:
				var target = action["actor"] if action_type == "self" else _target_for(action)
				await _execute_action(action["actor"], action["who"], action["name"], action["db"], target, idx)
			if action.get("type", "") in ["magic", "spell"]:
				var spell_element = data.get("element", "")
				if spell_element != "" and spell_element != action["actor"].get_element():
					action["actor"].set_element(spell_element)
					var elem_color = element_db.get(spell_element, {}).get("color", "#ffffff")
					MyEventBus.emit("continue_text", { "text": "[b]%s[/b] is now [color=%s]%s[/color] element!" % [_get_display_name(action["actor"]), elem_color, spell_element] })
					await wait_for_writing()

# ============================================================
# DAMAGE & ACTION EXECUTION
# ============================================================

func _do_attack(actor, who: String, target, idx: int = -1):
	var weapon   = actor.get_weapon()
	var wpn_name = weapon.get("name", "") if weapon and not weapon.is_empty() else ""
	var target_part = ""
	if who == "player" and enemies.size() > 1:
		target_part = " [b]%s[/b]" % _get_display_name(target)

	var attacktxt: String
	if who != "player" and wpn_name == "":
		attacktxt = "[b]%s[/b] struck%s![wait=0.1]" % [actor.get_name(), target_part]
	else:
		attacktxt = "[b]%s[/b] struck%s with %s![wait=0.1]" % [actor.get_name(), target_part, wpn_name if wpn_name != "" else "bare hands"]
	MyEventBus.emit("continue_text", { "text": attacktxt })
	if idx >=0:
		enemy_timers[idx] -= 10
		_emit_timer_update()
	await wait_for_writing()

	var weapon_data = {
		"type":          "attack",
		"magic":         false,
		"stats": {
			"mgt":  weapon.get("stats", {}).get("mgt",  0) if weapon and not weapon.is_empty() else 0,
			"acc":  weapon.get("stats", {}).get("acc", 90) if weapon and not weapon.is_empty() else 90,
			"crit": weapon.get("stats", {}).get("crit", 0) if weapon and not weapon.is_empty() else 0,
		},
		"element":       weapon.get("element", "Neutral") if weapon and not weapon.is_empty() else "Neutral",
		"inherit_stats": true,
	}
	await _execute_hit(weapon_data, actor, who, target)
	await wait_for_writing()

func _execute_action(user, who: String, action_name: String, db: Dictionary, target, idx: int = -1):
	var data = db.get(action_name, null)
	if not data:
		MyEventBus.emit("continue_text", { "text": "...%s?\n" % action_name })
		if idx >=0:
			enemy_timers[idx] -= 10
			_emit_timer_update()
		await wait_for_continue()
		return

	if data.get("drain_all_mp", false):
		var mp_consumed = user.get_mp()
		user.use_mp(mp_consumed)
		data = data.duplicate()
		data["stats"] = data["stats"].duplicate()
		data["stats"]["mgt"] = int(mp_consumed * data.get("magnitude", 1.0))
	elif data.has("cost"):
		user.use_mp(data["cost"])
	if data.has("cooldown") and who == "player":
		var psys_cd = _tsys("player")
		cooldowns[who][action_name] = rng.randi_range(1, 5) if psys_cd and psys_cd.has_circadian_mask() else data["cooldown"] + 1

	var target_name = "all enemies"
	if data.get("type", "attack") == "all":
		target_name = "the whole area"
	elif not ((who == "player" and data.get("type", "attack") in ["aoe", "all", "random"]) or (who != "player" and data.get("type", "attack") in ["group", "all"])):
		target_name = _get_display_name(target)

	var use_text = data.get("use_text", "[b]%s[/b] used [color=cyan]%s[/color]!" % [user.get_name(), data.get("nome", action_name)])
	MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(use_text, { "USER": user.get_name(), "TARGET": target_name }) + "[wait=0.1]" })
	if idx >=0:
		enemy_timers[idx] -= 10
		_emit_timer_update()
	await wait_for_writing()

	if data.get("type", "attack") == "flee":
		var parts = who.split("_")
		if parts.size() > 1 and parts[0] == "enemy":
			_fled_indices.append(int(parts[1]))
			MyEventBus.emit("enemy_fled", { "who": who })
		return

	if data.get("type", "attack") == "summon":
		await _perform_summon(user, who, data)
		return

	if data.get("type", "attack") == "random_skill":
		var exclude_list: Array = data.get("exclude", [])
		var pool: Array = []
		for sname in skills_db:
			if not exclude_list.has(sname):
				var sd = skills_db.get(sname, {})
				if sd.get("type", "") != "flee":
					pool.append({"name": sname, "db": skills_db})
		for spname in spells_db:
			if not exclude_list.has(spname):
				var sp = spells_db.get(spname, {})
				if sp.get("cost", 0) <= user.get_mp():
					pool.append({"name": spname, "db": spells_db})
		if not pool.is_empty():
			var chosen    = pool[rng.randi() % pool.size()]
			var cd        = chosen["db"].get(chosen["name"], {})
			var ct        = cd.get("type", "attack")
			var ctarget
			if ct == "self":
				ctarget = user
			elif who == "player":
				var living = _living_indices()
				if living.is_empty():
					return
				ctarget = enemies[living[rng.randi() % living.size()]]
			else:
				ctarget = player
			await _execute_action(user, who, chosen["name"], chosen["db"], ctarget, -1)
		return

	if data.get("hits_from_idle", false):
		var actor_sys_idle = _tsys(who)
		var idle = actor_sys_idle.get_idle_turns() if actor_sys_idle else 0
		data = data.duplicate()
		data["hits"] = data.get("base_hits", 1) + idle

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

	await wait_for_writing()

func _execute_hit(data, user, who: String, target):
	var hits = int(data.get("hits", 1))
	if data.has("max_hits") and data["max_hits"] > 1:
		hits = rng.randi_range(data.get("min_hits", 1), data["max_hits"])
	var is_magic_hit: bool = data.get("magic", false)
	var act_data = data
	var pre_sys = _tsys(who)
	if pre_sys:
		var proc_mult = pre_sys.get_proc_chance_mult()
		if proc_mult != 1.0:
			var effect = data.get("effect", "none")
			var action_type = data.get("type", "attack")
			var has_effect = effect not in ["none", "", "ignore_def"]
			var src_stats = data.get("stats", {})
			var is_nondmg = src_stats.get("mgt", 0) == 0 \
				and not data.get("inherit_stats", false) \
				and not data.get("inherit_wpn", false) \
				and action_type not in ["self", "group"]
			if has_effect or is_nondmg:
				act_data = data.duplicate()
				if has_effect:
					act_data["chance"] = min(100, int(data.get("chance", 100) * proc_mult))
				if is_nondmg:
					act_data["stats"] = src_stats.duplicate()
					act_data["stats"]["acc"] = int(src_stats.get("acc", 90) * proc_mult)
	for _i in range(hits):
		if target.get_hp() <= 0:
			break
		var result = calc.resolve_action(user, target, act_data)
		if result.get("missed", false):
			var miss_txt = "...but missed![wait=0.1]"
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				miss_txt = "%s evaded![wait=0.1]" % _get_display_name(target)
			MyEventBus.emit("continue_text", { "text": miss_txt, "linebreak": false })
			await wait_for_writing()
			var ms = _tsys(who)
			if ms: ms.on_miss()
			_emit_trinket_states()
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
				"ineffective":
					MyEventBus.emit("continue_text", { "text": "[color=brown]Ineffective![/color] ", "linebreak": false })
					await wait_for_writing()
			if _try_shatter(target):
				result["damage"] = int(result["damage"] * 1.5)
				MyEventBus.emit("continue_text", { "text": "[color=cyan]Shattered![/color][wait=0.1]", "linebreak": false })
				await wait_for_writing()
			var attack_element = data.get("element", "")
			if attack_element == "":
				var wpn = user.get_weapon()
				attack_element = wpn.get("element", "") if wpn and not wpn.is_empty() else ""
			if attack_element == "":
				attack_element = "Neutral"
			var actor_sys     = _tsys(who)
			var target_who_str = _who_for(target)
			var target_sys    = _tsys(target_who_str)
			result["damage"] = max(1, int(result["damage"] * (actor_sys.get_attack_multiplier(target_who_str, attack_element, is_magic_hit) if actor_sys else 1.0)))
			var living_count  = _living_indices().size()
			var target_timer: int = -1
			if target_who_str.begins_with("enemy_"):
				var ei = int(target_who_str.substr(6))
				if ei < enemy_timers.size():
					target_timer = enemy_timers[ei]
			result["damage"] = max(1, int(result["damage"] * (target_sys.get_damage_taken_multiplier(living_count, target_timer) if target_sys else 1.0)))
			result["damage"] = target_sys.check_death_prevention(result["damage"]) if target_sys else result["damage"]
			if target_who_str == "player" and target.get_hp() >= target.get_max_hp():
				result["damage"] = min(result["damage"], target.get_max_hp() - 1)
			_play_damage_sound(data, user, target)
			target.take_damage(result["damage"])
			if actor_sys: actor_sys.on_hit(attack_element, is_magic_hit)
			if target_sys: target_sys.on_owner_hit()
			_emit_trinket_states()
			var bandana_msg = target_sys.get_bandana_message() if target_sys else ""
			var down_msg   = _notify_if_died(target)
			var damage_txt = "[screenshake][instant][color=red]%d[/color] damage![/instant][wait=0.1]" % result["damage"]
			if data.get("type", "attack") in ["group", "aoe", "all", "random"]:
				damage_txt = "[screenshake][instant]%s took [color=red]%d[/color] damage![/instant][wait=0.1]" % [_get_display_name(target), result["damage"]]
			if down_msg != "":
				damage_txt += down_msg
			if bandana_msg != "":
				damage_txt += bandana_msg
			MyEventBus.emit("continue_text", { "text": damage_txt, "linebreak": false })
			await wait_for_writing()
			if actor_sys:
				var lifesteal := actor_sys.get_lifesteal_amount(result["damage"])
				if lifesteal > 0 and user.get_hp() > 0:
					user.heal(lifesteal)
					MyEventBus.emit("continue_text", {"text": "[instant][color=green]+%d[/color] HP absorbed![/instant]" % lifesteal, "linebreak": false})
					await wait_for_writing()
			if target_sys and target_who_str == "player" and target.get_hp() > 0:
				if target_sys.try_counter_stun():
					status_sys.add_status(user, "stun", 1)
					MyEventBus.emit("continue_text", {"text": "\n[b]%s[/b] is startled by the rattle![wait=0.1]" % _get_display_name(user), "linebreak": false})
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
					_emit_timer_update()
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
				_emit_timer_update()
				MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(inflict, { "TARGET": _get_display_name(target) }), "linebreak": false })
				await wait_for_writing()

func _try_shatter(target) -> bool:
	var who = _who_for(target)
	if not status_effects.get(who, []).any(func(s): return s["type"] == "freeze"):
		return false
	status_effects[who] = status_effects[who].filter(func(s): return s["type"] != "freeze")
	status_sys.apply_stat_modifiers(who)
	status_sys.emit_status_update(who)
	return true

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

func _bank_enemy_rewards(idx: int) -> void:
	if idx in _fled_indices:
		return
	var e = enemies[idx]
	_accumulated_rewards["xp"]   += int(10.0 * pow(1.5, e.get_level() - 1))
	_accumulated_rewards["gold"] += e.data.get("Gold", 0)
	for item in e.data.get("Drops", {}):
		if rng.randi_range(1, 100) <= e.data["Drops"][item]:
			_accumulated_rewards["drops"][item] = _accumulated_rewards["drops"].get(item, 0) + 1

func _calculate_rewards() -> Dictionary:
	var total_xp   = _accumulated_rewards.get("xp",   0)
	var total_gold = _accumulated_rewards.get("gold",  0)
	var all_drops: Dictionary = _accumulated_rewards.get("drops", {}).duplicate()
	for i in range(enemies.size()):
		if i in _fled_indices:
			continue
		var e   = enemies[i]
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
# SUMMONS
# ============================================================

func _register_enemy_slot(e: Character, key: String) -> void:
	status_effects[key] = []
	cooldowns[key]      = {}
	e.set_stat_multipliers({})
	status_sys.emit_status_update(key)
	var trinkets = e.data.get("Trinkets", [])
	for i in range(trinkets.size()):
		var variants = trinkets_db.get(trinkets[i], {}).get("variants", [])
		if not variants.is_empty():
			trinkets[i] = variants[rng.randi() % variants.size()]
	if not e.get_trinkets().is_empty():
		trinket_systems[key] = TrinketSystem.new(e, trinkets_db, status_effects, key)

func _perform_summon(summoner, summoner_who: String, skill_data: Dictionary):
	var monster_names = skill_data.get("summons", "")
	if typeof(monster_names) != TYPE_ARRAY:
		if monster_names == "":
			return
		monster_names = [monster_names]
	if monster_names == []:
		return
	var how_many = skill_data.get("magnitude",1)
	var to_summon = []
	for i in range(how_many):
		var monster_name_aux = monster_names[rng.randi() % monster_names.size()]
		var monster_data: Dictionary = {}
		for m in monster_db_ref:
			if m.get("Name", "") == monster_name_aux:
				monster_data = m.duplicate()
				to_summon.append(monster_data)
				break
		if monster_data.is_empty():
			push_error("Summon: monster not found in db: " + monster_name_aux)
			return
	var name_count = {}
	for e in to_summon:
		var n = e.get('Name','')
		name_count[n] = name_count.get(n, 0) + 1
	
	for monster_data in to_summon:
		var monster_name = monster_data.get("Name", "")
		var slot_idx: int = -1
		if enemies.size() == 1:
			slot_idx = 1
		else:
			for i in range(enemies.size()):
				if enemies[i].get_hp() <= 0 or i in _fled_indices:
					slot_idx = i
					break
		if slot_idx == -1:
			return

		if slot_idx < enemies.size():
			_bank_enemy_rewards(slot_idx)

		if monster_data.has('displayName'):
			monster_name = monster_data['displayName']
		var display_name = monster_name

		_summon_name_counters[monster_name] = _summon_name_counters.get(monster_name, 0) + 1
		if _summon_name_counters[monster_name] > 1 or name_count.get(monster_name,0) > 1:
			display_name = "%s %s" % [monster_name, char(64 + _summon_name_counters[monster_name])]
		monster_data["Name"] = display_name

		var new_char = Character.new(monster_data, armor_db, weapon_db, rng)
		var new_key  = _ekey(slot_idx)

		if slot_idx < enemies.size():
			enemies[slot_idx]             = new_char
			enemy_display_names[slot_idx] = display_name
			enemy_timers[slot_idx]        = -1 # monster_data.get("Startup", 0)
			enemy_first_actions[slot_idx] = true
			enemy_channeling[slot_idx]    = ""
			_died_enemies.erase(new_key)
		else:
			enemies.append(new_char)
			enemy_display_names.append(display_name)
			enemy_timers.append(monster_data.get("Startup", 0))
			enemy_first_actions.append(true)
			enemy_channeling.append("")

		_register_enemy_slot(new_char, new_key)

		new_char.data["Name"] = display_name
		new_char.stats_changed.emit()

		MyEventBus.emit("enemy_summoned", { "who": new_key, "character": new_char })
		_emit_timer_update()

		MyEventBus.emit("continue_text", { "text": "[b]%s[/b] appeared!" % display_name })
		await wait_for_writing()

		var start_skill: String = new_char.data.get("Start", "")
		if start_skill != "":
			var start_db = skills_db if skills_db.has(start_skill) else spells_db
			var start_data = start_db.get(start_skill, {})
			var start_target = new_char if start_data.get("type", "attack") == "self" else player
			await _execute_action(new_char, new_key, start_skill, start_db, start_target)
			await wait_for_writing()

# ============================================================
# UTILITIES
# ============================================================

func _emit_trinket_states() -> void:
	MyEventBus.emit("trinket_states_changed", {
		"trinkets": player.get_trinkets(),
		"states":   _tsys("player").get_states()
	})

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
