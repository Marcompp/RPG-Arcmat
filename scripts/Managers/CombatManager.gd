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
var enemy  = null

var skills_db: Dictionary = {}
var spells_db: Dictionary = {}
var items_db:  Dictionary = {}
var status_db: Dictionary = {}

var status_effects: Dictionary = { "player": [], "enemy": [] }
var cooldowns:      Dictionary = { "player": {}, "enemy": {} }

# Counts down each player turn. When it reaches 0 the enemy acts.
var enemy_action_timer: int  = 0
# Switches the waiting-message from "preparing to attack" → "catching its breath" after the first action.
var enemy_first_action: bool = true

# ============================================================
# ENTRY
# ============================================================

func start_combat(p, e):
	player = p
	enemy  = e
	skills_db = _load_json("res://Database/skills.json")
	spells_db = _load_json("res://Database/spells.json")
	items_db  = _load_json("res://Database/items.json")
	status_db = _load_json("res://Database/status.json")

	status_effects = { "player": [], "enemy": [] }
	cooldowns      = { "player": {}, "enemy": {} }

	p.set_stat_multipliers({})
	e.set_stat_multipliers({})
	_emit_status_update("player")
	_emit_status_update("enemy")

	# "startup" lets a skill skip its first cooldown tick so it's usable immediately.
	for skill in p.get_skills():
		var skill_data = skills_db.get(skill, {})
		if skill_data.has("startup"):
			cooldowns["player"][skill] = skill_data["startup"]
	for skill in e.get_skills():
		var skill_data = skills_db.get(skill, {})
		if skill_data.has("startup"):
			cooldowns["enemy"][skill] = skill_data["startup"]

	enemy_action_timer = e.data.get("Startup", 0)
	enemy_first_action = true

	MyInputRouter.push(_handle_combat_input, "combat")

	await _show_intro()
	await wait_for_continue()
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

func check_combat_end():
	if player.get_hp() <= 0:
		await end_combat(false)
		return
	if enemy.get_hp() <= 0:
		await end_combat(true)
		return
	await wait_for_continue()
	next_turn()

func end_combat(victory: bool):
	state = CombatState.END
	MyEventBus.emit("enemy_timer_update", { "timer": -1 })
	MyEventBus.emit("character_defeated", { "victory": victory })

	if victory:
		var rewards = _calculate_rewards()
		MyEventBus.emit("continue_text", { "text": "[color=yellow]%s[/color] was defeated!" % [enemy.get_name()] })
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
	MyEventBus.emit("show_choices", { "choices": choices, "fixed_sizes": len(choices) > 2 })

func _show_intro():
	show_text("You encounter %s\n\n%s is raring for a fight!" % [enemy.get_name(), enemy.get_name()])

func render_player_turn():
	MyEventBus.emit("enemy_timer_update", { "timer": enemy_action_timer })

	var timer_text: String
	match enemy_action_timer:
		0: timer_text = "[color=red]%s will act this turn![/color]"       % enemy.get_name()
		1: timer_text = "[color=yellow]%s will act next turn.[/color]"    % enemy.get_name()
		_: timer_text = "[color=green]%s will act in %d turns.[/color]"   % [enemy.get_name(), enemy_action_timer]

	show_text(
		"%s: %d hp.\n%s: %d hp.\n%s\n\nWhat would you like to do?" % [
			enemy.get_name(), enemy.get_hp(),
			player.get_name(), player.get_hp(),
			timer_text
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

# ============================================================
# ACTION HANDLERS
# ============================================================

func handle_main_action(choice):
	match choice["type"]:
		"attack": await _resolve_turn_pair({ "actor": player, "who": "player", "type": "attack" })
		"skill":  open_menu("skill", player.get_skills(),         skills_db)
		"magic":  open_menu("magic", player.get_spells(),         spells_db)
		"item":   open_menu("item",  player.get_inventory().keys(), items_db)

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
	await _resolve_turn_pair({ "actor": player, "who": "player", "type": type, "name": choice["data"], "db": db })

# ============================================================
# TURN RESOLUTION
# ============================================================

func _resolve_turn_pair(player_action: Dictionary):
	state = CombatState.RESOLUTION
	_tick_cooldowns("enemy")

	if enemy_action_timer > 0:
		# Enemy is still winding up — execute the player's action only.
		enemy_action_timer -= 1
		var phase_msg = "is preparing to attack!" if enemy_first_action else "is catching its breath."
		await _execute_turn_action(player_action)
		if player.get_hp() <= 0 or enemy.get_hp() <= 0:
			check_combat_end()
			return
		MyEventBus.emit("continue_text", { "text": "[b]%s[/b] %s" % [enemy.get_name(), phase_msg] })
		await wait_for_continue()
	else:
		# Both sides act this turn; faster side goes first.
		var enemy_action   = _enemy_choose_action()
		enemy_first_action = false
		enemy_action_timer = enemy.data.get("Cooldown", 0)

		var p_speed = _get_action_speed(player, player_action)
		var e_speed = _get_action_speed(enemy,  enemy_action)

		# Higher speed value means acting first.
		var first  = player_action if p_speed >= e_speed else enemy_action
		var second = enemy_action  if p_speed >= e_speed else player_action

		await _execute_turn_action(first)
		if player.get_hp() <= 0 or enemy.get_hp() <= 0:
			check_combat_end()
			return
		await _execute_turn_action(second)

	_process_statuses("player")
	_process_statuses("enemy")
	state = CombatState.PLAYER_TURN
	check_combat_end()

func _execute_turn_action(action: Dictionary):
	match action["type"]:
		"attack": await _do_attack(action["actor"], action["who"])
		_:        await _execute_action(action["actor"], action["who"], action["name"], action["db"])

func _do_attack(actor, who):
	var weapon   = actor.get_weapon()
	var target   = enemy if actor == player else player
	var dmg      = calculate_damage(actor, target)
	var wpn_type = weapon.get("wpn_type", "").to_lower() if weapon and not weapon.is_empty() else ""
	var attacktxt = "[b]%s[/b] struck with %s![wait=0.1]" % [actor.get_name(), weapon.get("name", "bare hands")]
	if who != "enemy" and not weapon.has("name"):
		attacktxt = "[b]%s[/b] struck![wait=0.1]" % [actor.get_name()]

	MyEventBus.emit("continue_text", {
		"text": attacktxt
	})
	await wait_for_writing()

	target.take_damage(dmg)
	MyEventBus.emit("play_sfx", { "sound": wpn_type if wpn_type != "" else "attack" })
	MyEventBus.emit("continue_text", {
		"text": "[screenshake][instant][color=red]%d[/color] damage![/instant]" % [dmg],
		"linebreak": false
	})
	await wait_for_writing()

func _enemy_choose_action() -> Dictionary:
	var skills    = enemy.get_skills()
	# 35% chance to pick a skill; guarantees a basic attack is always possible.
	var available = skills.filter(func(s): return cooldowns["enemy"].get(s, 0) == 0 and skills_db.has(s))
	if available.size() > 0 and randi_range(1, 100) <= 35:
		var chosen = available[randi_range(0, available.size() - 1)]
		return { "actor": enemy, "who": "enemy", "type": "skill", "name": chosen, "db": skills_db }
	return { "actor": enemy, "who": "enemy", "type": "attack" }

func _get_action_speed(actor, action: Dictionary) -> float:
	var agi = actor.get_total_stat("agi")
	var dex = actor.get_total_stat("dex")
	# DEX absorbs weight penalty before it cuts into speed.
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
	# Halved DEF with small rng variance; minimum 1 so attacks never miss.
	var dmg    = max(1, atk - floori(def / 2) + randi_range(0, 2))
	if randi_range(1, 100) <= crit:
		dmg = int(dmg * 1.5)
	return dmg

func _execute_action(user, who: String, action_name: String, db: Dictionary):
	var data = db.get(action_name, null)
	if not data:
		MyEventBus.emit("continue_text", { "text": "...%s?\n" % action_name })
		await wait_for_continue()
		return

	var action_type = data.get("type", "attack")
	var target = user if action_type == "self" else (enemy if user == player else player)

	if data.has("cost"):
		user.use_mp(data["cost"])
	if data.has("cooldown") and who != "":
		cooldowns[who][action_name] = data["cooldown"]

	var lines      = ["[b]%s[/b] used [color=cyan]%s[/color]!" % [user.get_name(), data.get("nome", action_name)]]
	var did_damage = false

	for _i in range(data.get("hits", 1)):
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
				var side = "player" if target == player else "enemy"
				status_effects[side] = []
				lines.append("[color=green]%s's status effects cleared![/color]" % target.get_name())
			elif result["status"] == "recharge":
				var mag: int = data.get("magnitude", 1)
				if who != "":
					for skill in cooldowns[who]:
						cooldowns[who][skill] = max(0, cooldowns[who][skill] - mag)
				lines.append("[color=cyan]All cooldowns reduced by %d![/color]" % mag)
			else:
				_add_status(target, result["status"], data.get("magnitude", -1))
				var sdata   = status_db.get(result["status"], {})
				var inflict = sdata.get("inflict_text", "[color=yellow]%s gained a status effect![/color]")
				lines.append(inflict % [target.get_name()])

	if data.get("consumable", false):
		user.consume_item(action_name)

	MyEventBus.emit("continue_text", { "text": "\n".join(lines) + "\n" })
	if did_damage:
		MyEventBus.emit("screenshake")
	await wait_for_continue()

func _resolve_action(user, target, data) -> Dictionary:
	var result      = { "damage": 0, "heal": 0, "mp_restore": 0, "status": "", "text": "" }
	var stats       = data.get("stats", {})
	var is_magic    = data.get("magic", false)
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
		# Pull the relevant weapon stat based on whether the action is physical or magical.
		base_mgt += weapon.get("stats", {}).get("mys" if is_magic else "mgt", 0)

	var atk_stat = user.get_total_stat("mag" if is_magic else "str")
	if inherit_stat:
		base_mgt += atk_stat

	var ignore_def = data.get("effect", "") == "ignore_def"
	var def_val    = 0
	if not ignore_def:
		# Magic pierces physical DEF; it is resisted by MP (resource-as-shield design).
		def_val = target.get_mp() if is_magic else target.get_total_stat("def")

	var dmg = max(1, base_mgt - floori(def_val / 2) + randi_range(0, 2))

	var crit_chance = stats.get("crit", 0)
	if inherit_wpn:
		crit_chance += weapon.get("stats", {}).get("crit", 0)
	if randi_range(1, 100) <= crit_chance:
		dmg = int(dmg * 1.5)
		result["text"] = "[color=orange]Critical! [/color]"

	result["damage"] = dmg
	result["text"]  += "[color=red]%d[/color] damage!" % dmg

	var effect = data.get("effect", "none")
	var chance = data.get("chance", 100)
	if effect != "none" and effect != "" and effect != "ignore_def" and randi_range(1, 100) <= chance:
		result["status"] = effect

	return result

# ============================================================
# REWARDS
# ============================================================

func _calculate_rewards() -> Dictionary:
	var lvl  = enemy.get_level()
	var xp   = int(10.0 * pow(1.5, lvl - 1))
	var gold = enemy.data.get("Gold", 0)
	var drops = {}
	for item in enemy.data.get("Drops", {}):
		if randi_range(1, 100) <= enemy.data["Drops"][item]:
			drops[item] = 1
	return { "xp": xp, "gold": gold, "drops": drops }

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
	var who      = "player" if target == player else "enemy"
	var duration = magnitude if magnitude > 0 else status_db.get(effect, {}).get("duration", 3)
	for s in status_effects[who]:
		if s["type"] == effect:
			# Refresh only if the new duration is longer — don't punish re-application.
			s["duration"] = max(s["duration"], duration)
			_emit_status_update(who)
			return
	status_effects[who].append({ "type": effect, "duration": duration })
	_apply_stat_modifiers(who)
	_emit_status_update(who)

func _apply_stat_modifiers(who: String):
	var target   = player if who == "player" else enemy
	var combined: Dictionary = {}
	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		for stat in data.get("stats", {}):
			# Multiplicative stacking — each effect compounds on top of the last.
			combined[stat] = combined.get(stat, 1.0) * float(data["stats"][stat])
	target.set_stat_multipliers(combined)

func _process_statuses(who: String):
	var target    = player if who == "player" else enemy
	var remaining = []

	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		if not data.is_empty():
			var damage_frac: float = data.get("damage", 0.0)
			var heal_frac:   float = data.get("heal",   0.0)
			var upkeep:      String = data.get("upkeep_text", "")

			if damage_frac > 0.0:
				var dmg = max(1, int(target.get_max_hp() * damage_frac))
				target.take_damage(dmg)
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": upkeep % [target.get_name(), dmg] + "\n" })
			elif heal_frac > 0.0:
				var hp = max(1, int(target.get_max_hp() * heal_frac))
				target.heal(hp)
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": upkeep % [target.get_name(), hp] + "\n" })

		s["duration"] -= 1
		if s["duration"] > 0:
			remaining.append(s)
		else:
			var end_text: String = data.get("end_text", "")
			if end_text != "":
				MyEventBus.emit("continue_text", { "text": end_text % [target.get_name()] + "\n" })

	status_effects[who] = remaining
	_apply_stat_modifiers(who)
	_emit_status_update(who)

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

func _format_action_tooltip(action_key: String, data: Dictionary) -> String:
	var lines       = [data.get("nome", action_key)]
	var stats       = data.get("stats", {})
	var action_type = data.get("type", "attack")
	var is_magic    = data.get("magic", false)

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
