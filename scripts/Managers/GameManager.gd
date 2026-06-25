extends Node

@onready var dialogue = $DialogueSystem
@onready var travel = $TravelManager
@onready var combat = $CombatManager
@onready var game_ui = $GameUI
@onready var audio = $AudioManager
@onready var main_menu = $MainMenu
@onready var gameover = $GameOverMenu
@onready var options_menu = $OptionsMenu

# ========================
# CORE
# ========================

enum GameMode {
	MAIN_MENU,
	CHARACTER_SELECT,
	CHARACTER_CONFIRM,
	TRAVEL,
	INVENTORY,
	REST,
	MONSTERS
}

var current_mode = GameMode.MAIN_MENU

var characters = []
var monster_db = {}
var armor_db = {}
var weapon_db = {}
var spell_db = {}
var skill_db = {}
var trinkets_db = {}

var in_combat = false
var _suppress_defeat_game_over: bool = false
var _pending_level_ups: Array = []
var _pending_rewards: Dictionary = {}

var pending_character = null
var current_slot = 1

var game_state = GameState.new()
var rng := RandomNumberGenerator.new()

signal character_updated(char)

func get_var(key, default := 0):
	return game_state["vars"].get(key, default)

# ------------------------
# INIT
# ------------------------

func _ready():
	MyEventBus.subscribe("combat_ended", _on_combat_ended)
	MyEventBus.subscribe("combat_rewards", func(data):
		var player = game_state["player"]
		if player:
			var old_xp = player.get_xp()
			var old_level = player.get_level()
			_pending_rewards = data.get("rewards", {})
			_pending_level_ups = player.gain_exp(_pending_rewards.get("xp", 0))
			game_ui.animate_xp_gain(old_xp, old_level, _pending_level_ups)
	)
	MyEventBus.subscribe("register_visit", func(data):
		register_visit(data.get('key',0))
	)
	MyEventBus.subscribe("add_progress", func(data):
		add_progress(data.get('progress',0),data.get('reset',false),data.get("region",""))
	)
	MyEventBus.subscribe("take_damage", func(data):
		apply_damage(data['damage'])
	)
	MyEventBus.subscribe("apply_effect", func(data):
		apply_effect(data)
	)
	MyEventBus.subscribe("change_vars", func(data):
		apply_vars_changes(data)
	)
	MyEventBus.subscribe("start_combat", func(data):
		start_combat(data)
	)
	MyEventBus.subscribe("game_over", func(_data):
		show_game_over()
	)
	MyEventBus.subscribe("modify_stat", func(data):
		var player = game_state.get("player")
		if player:
			player.apply_level_up(data.get("stats", {}))
	)
	MyEventBus.subscribe("give_gold", func(data):
		game_state["gold"] = game_state["gold"] + data.get("amount", 0)
	)
	MyEventBus.subscribe("give_item", func(data):
		var item_name: String = data.get("item", "")
		var player = game_state["player"]
		if player == null or item_name == "":
			MyEventBus.emit("give_item_done", {})
			return
		var price: int = data.get("price", 0)
		var from_shop: bool = data.get("from_shop", false)
		await _process_item_acquisition(item_name, player, price, from_shop)
		MyEventBus.emit("give_item_done", {})
	)
	MyEventBus.subscribe("learn_skill", func(data):
		var skill_name: String = data.get("skill", "")
		var player = game_state["player"]
		if player == null or skill_name == "":
			MyEventBus.emit("learn_skill_done", {})
			return
		var skills: Array = player.get_skills()
		if not skills.has(skill_name):
			skills.append(skill_name)
			player.data["Skills"] = skills
		MyEventBus.emit("learn_skill_done", {})
	)
	#game_state["player"] = null
	game_state["gold"] = 0
	game_state["region"] = ""
	game_state["vars"] = {}
	game_state["flags"] = {}
	game_state["visited_nodes"] = {}
	game_state["visited_count"] = {}
	game_state["area_progress"] = {"Apple Woods":0}
	game_state["used_events"] = {}
	travel.game_state = game_state
	travel.game_manager = self
	travel.rng = rng
	combat.rng = rng
	game_state["region"] = travel.current_region
	game_ui.bind(game_state)
	
	MyInputRouter.push(_handle_game_input, "exploration")
	#MyEventBus.subscribe("choice_selected", _on_choice)
	#dialogue.choice_selected.connect(_on_choice)
	
	dialogue.condition_callback = func(cond):
		return check_condition(cond, travel.current_node)
	travel.condition_callback = func(cond, current_node):
		return check_condition(cond, current_node)
	
	characters = load_json("res://Database/protags.json")
	monster_db = load_json("res://Database/monsters.json")
	armor_db = load_json("res://Database/armors.json")
	weapon_db = load_json("res://Database/weapons.json")
	spell_db    = load_json("res://Database/spells.json")
	skill_db    = load_json("res://Database/skills.json")
	trinkets_db = load_json("res://Database/trinkets.json")

	dialogue.visible = false
	main_menu.new_game_requested.connect(_on_main_menu_new_game)
	main_menu.continue_requested.connect(_on_main_menu_continue)
	gameover.retry_requested.connect(_on_gameover_retry)
	gameover.title_screen_requested.connect(_on_gameover_title)

	main_menu.options_requested.connect(func(): options_menu.show_options())
	game_ui.options_requested.connect(func(): options_menu.show_options())
	options_menu.closed.connect(func(): main_menu.setup(SaveManager.list_saves().size() > 0))

	show_main_menu()

# ------------------------
# JSON
# ------------------------

func load_json(path):
	if not FileAccess.file_exists(path):
		push_error("Arquivo não encontrado: " + path)
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	
	var json = JSON.new()
	var result = json.parse(content)
	
	if result != OK:
		push_error("Erro ao fazer parse do JSON")
		return {}
	
	return json.data

# ------------------------
# WRAPPER
# ------------------------
func show_text(text):
	MyEventBus.emit("dialogue", {
		"text": text
	})

func show_choices(choices):
	MyEventBus.emit("show_choices", {
		"text": choices
	})
# ------------------------
# GAME FLOW
# ------------------------

func start_game():
	current_mode = GameMode.TRAVEL
	travel.enter_node(0, "ROAD")

# ------------------------
# MAIN MENU
# ------------------------

func show_main_menu():
	current_mode = GameMode.MAIN_MENU
	MyEventBus.emit("play_bgm",{"song":"title"})
	MyEventBus.emit("set_backdrop",{"backdrop":"title_backdrop4.png"})
	dialogue.visible = false
	game_ui._clear_ui()
	main_menu.visible = true
	main_menu.setup(SaveManager.list_saves().size() > 0)

func _on_main_menu_new_game():
	current_slot = SaveManager.next_slot()
	main_menu.visible = false
	dialogue.visible = true
	start_character_selection()

func _on_main_menu_continue(slot: int):
	current_slot = slot
	main_menu.visible = false
	dialogue.visible = true
	load_game(slot)

#-------------------------
# CHAR SELECT
#-------------------------

func start_character_selection():
	current_mode = GameMode.CHARACTER_SELECT
	
	show_text(
		"Welcome, traveler. A great journey awaits you.\n\nChoose who you will be."
	)
	
	show_character_choices()

func pad_right(text, size):
	while text.length() < size:
		text += " "
	return text
	
func build_character_tooltip(chara):
	var t = chara["Name"] + "  Lv." + str(chara.get("Lvl", 1))
	#Name
	t += "\nClass: " + chara["Class"]
	
	# ------------------------
	# STATS (2 por linha)
	# ------------------------
	t += "\n\nStats:\n"
	
	var stat_keys = chara["Stats"].keys()
	
	t += "[table=5]"

	for i in range(0, stat_keys.size(), 2):
		var k1 = stat_keys[i]
		var r1 = str(chara["Stats"][k1])
		var c1 = get_rank_color(r1)
		
		t += "[cell]" + k1 + ": [/cell]"
		t += "[cell][b][color=" + c1 + "]" + r1 + "[/color][/b][/cell]"
		t += "[cell]   [/cell]"
		
		if i + 1 < stat_keys.size():
			var k2 = stat_keys[i + 1]
			var r2 = str(chara["Stats"][k2])
			var c2 = get_rank_color(r2)
			
			t += "[cell]" + k2 + ": [/cell]"
			t += "[cell][b][color=" + c2 + "]" + r2 + "[/color][/b][/cell]"
		else:
			t += "[cell][/cell][cell][/cell]"

	t += "[/table]\n"
	
	# Equip
	if chara.has("Equip") and typeof(chara["Equip"]) == TYPE_DICTIONARY:
		t += "\nStarting Equipment:\n"
		for e in chara["Equip"]:
			t += e + ": " + chara["Equip"][e] + "\n"
		if chara.has("Trinkets"):
			t += "Trinket: " + ", ".join(chara["Trinkets"]) + "\n"
	
	# Skills
	if chara["Skills"].size() > 0:
		t += "\nStarting Skill:\n"
		for s in chara["Skills"]:
			t += "- " + s + "\n"
	
	# Spells
	if chara["Spells"].size() > 0:
		t += "\nStarting Spells:\n"
		for s in chara["Spells"]:
			t += "- " + s + "\n"

	# Money
	t += "\nGold: " + str(chara.get("Money", 0)) + "G\n"

	# Inventory
	var inv = chara.get("Inventory", {})
	if typeof(inv) == TYPE_DICTIONARY and inv.size() > 0:
		t += "\nStarting Items:\n"
		for item in inv:
			t += "- " + item + " x" + str(inv[item]) + "\n"
	t += "\n"

	return t.strip_edges()

func show_character_choices():
	var choices = []
	
	for chara in characters:
		choices.append({
			"text": chara["Name"] + ", the " + chara["Class"],
			"type": "character",
			"data": chara,
			"tooltip": build_character_tooltip(chara)
		})
	
	dialogue.set_choices(choices, "Select your character")
	
func handle_character_select(choice):
	var chara = choice.get("data", {})
	pending_character = chara
	
	show_character_confirm(chara)
	
func make_bar(value, max_value):
	var bars = int((value / float(max_value)) * 10.0)
	var bar = ""
	
	for i in range(10):
		if i < bars:
			bar += "█"
		else:
			bar += "░"
	
	return bar
	
func show_character_confirm(char):
	current_mode = GameMode.CHARACTER_CONFIRM
	
	var text = ""
	
	# ------------------------
	# HEADER
	# ------------------------
	text += "Are you sure you want to play as this character:\n\n" 
	
	text += "[b]" + char["Name"] + "[/b], the " + char["Class"] + "\n"
	text += "[i]" + char.get("Description", "A wandering adventurer.") + "[/i]\n\n"
	
	# ------------------------
	# HP / MP PREVIEW
	# ------------------------
	#var hp = convert_rank_to_value(char["Stats"]["HP"]) + 5
	#var mp = convert_rank_to_value(char["Stats"]["MP"])
	#
	#text += "HP: " + make_bar(hp, 20) + " " + str(hp) + "\n"
	#text += "MP: " + make_bar(mp, 20) + " " + str(mp) + "\n\n"
	
	# ------------------------
	# STATS GRID
	# ------------------------
	text += "[b]Stats[/b]\n"
	text += "[table=18]"
	
	for k in char["Stats"].keys():
		var v = char["Stats"][k]
		var c = get_rank_color(v)
		
		text += "[cell]" + k + ": [/cell]"
		text += "[cell][color=" + c + "][b]" + v + "[/b][/color]   [/cell]"
	
	text += "[/table]\n\n"
	
	# ------------------------
	# SKILLS
	# ------------------------
	if char["Skills"].size() > 0:
		text += "[b]Skills[/b]\n"
		text += "[table=5]"
		for s in char["Skills"]:
			text += "[cell]- " + s + "[/cell][cell]  [/cell]"
		text += "[/table]\n\n"
	
	# ------------------------
	# SPELLS
	# ------------------------
	if char["Spells"].size() > 0:
		text += "[b]Spells[/b]\n"
		text += "[table=5]"
		for s in char["Spells"]:
			text += "[cell]- " + s + "[/cell][cell]  [/cell]"
		text += "[/table]\n\n"

	# ------------------------
	# EQUIP & Inventory
	# ------------------------
	text += "[b]Inventory[/b]\n"
	text += "[table=9]"
	if char.has("Equip"):
		for s in char["Equip"]:
			text += "[cell]" + s + ": " + char["Equip"][s] + "[/cell][cell]  [/cell]"
	if char.has("Trinkets"):
		text += "[cell]Trinket: " + ", ".join(char["Trinkets"]) + "[cell]  [/cell]"
	
	var inv = char.get("Inventory", {})
	if typeof(inv) == TYPE_DICTIONARY and inv.size() > 0:
		
		for item in inv:
			text += "[cell]- " + item + " x" + str(int(inv[item])) + "[/cell][cell]  [/cell]"
		text += "\n"
	text += "[/table]\n"
	
	# ------------------------
	# MONEY & INVENTORY
	# ------------------------
	text += "[b]Starting Gold:[/b] [color=yellow]"
	text += str(int(char.get("Money", 0))) + "G[/color]"

	# ------------------------
	# WARNING
	# ------------------------
	text += ""
	
	show_text(text)
	
	dialogue.set_choices([
		{ "text": "▶ Start Journey", "type": "confirm_character" },
		{ "text": "◀ Choose Another", "type": "back" }
	], "[color=yellow]This choice cannot be undone.[/color]")
	
func confirm_character():
	var chara = pending_character
	rng.randomize()
	var character = Character.new(chara, armor_db, weapon_db, rng)
	character.recalculate_trinket_bonus(trinkets_db)
	game_state["player"] = character
	game_state["gold"] = character.get_money()
	
	#character.stats_changed.connect(_on_character_stats_changed)
	
	MyEventBus.emit("character_selected", {
		"character": chara
	})
	travel.current_region = "Apple Woods"
	
	pending_character = null
	
	start_game()
	
func cancel_character():
	pending_character = null
	current_mode = GameMode.CHARACTER_SELECT
	
	show_text(
		"Very well.\n\nThen, who will you be?"
	)
	
	show_character_choices()
			
func convert_rank_to_value(rank):
	match rank:
		"A": return 10
		"B": return 8
		"C": return 6
		"D": return 4
	return 5
	
func convert_rank_to_growth(rank):
	match rank:
		"A": return 70
		"B": return 55
		"C": return 40
		"D": return 25
	return 35
	
func get_rank_color(rank):
	match rank:
		"A": return "#00E676" # verde
		"B": return "#3989FF" # azul
		"C": return "#CCCC66" # amarelo
		"D": return "#F44336" # vermelho
	return "#FFFFFF"
	
# ------------------------
# INPUT
# ------------------------

func _handle_game_input(choice):
	if in_combat:
		return  # ignora tudo

	match current_mode:
		GameMode.CHARACTER_SELECT:
			handle_character_select(choice)
			
		
		GameMode.CHARACTER_CONFIRM:
			match choice.get("type", ""):
				"confirm_character":
					confirm_character()
				"back":
					cancel_character()
		
		GameMode.TRAVEL:
			travel.handle_input(choice)
			
# ------------------------
# ACTIONS
# ------------------------

func _build_start_combat_data(monster) -> Array:
	if monster is String:
		for m in monster_db:
			if m.get("Name", "") == monster:
				monster = m
				break
		if monster is String:
			push_error("Monster not found: " + monster)
			return []
	if not monster.has("Enemies"):
		return [monster]
	var enemy_list: Array = []
	for i in range(len(monster["Enemies"])):
		var name = monster["Enemies"][i]
		for m in monster_db:
			if m.get("Name", "") == name:
				var m_data = m.duplicate()
				if monster.has("Genders"):
					m_data["Gender"] = monster["Genders"][i]
				if monster.has("Lvls"):
					m_data["Lvl"] = monster["Lvls"][i]
				enemy_list.append(m_data)
				break
	return enemy_list

func start_combat(data):
	in_combat = true
	_suppress_defeat_game_over = data.get("suppress_defeat_game_over", false)

	var enemy_data_list: Array
	if data.has("enemies"):
		enemy_data_list = data["enemies"]
	else:
		enemy_data_list = _build_start_combat_data(
			data.get("enemy", { "Name": "Slime", "Stats": { "Hp": 10, "Def": 1 } })
		)	

	var level_override = data.get("level", -1)
	var overrides: Dictionary = data.get("overrides", {})
	var enemy_chars: Array = []
	for i in range(enemy_data_list.size()):
		var enemy_data = enemy_data_list[i]
		if level_override > 0 or not overrides.is_empty():
			enemy_data = enemy_data.duplicate()
			if level_override > 0:
				enemy_data["Lvl"] = level_override
			for key in overrides:
				enemy_data[key] = overrides[key]
		var enmy = Character.new(enemy_data, armor_db, weapon_db, rng)
		game_state.set_value("enemy_%d" % i, enmy)
		enemy_chars.append(enmy)

	game_state.set_value("enemy", enemy_chars[0])

	combat.monster_db_ref = monster_db
	combat.armor_db       = armor_db
	combat.weapon_db      = weapon_db
	combat.start_combat(game_state["player"], enemy_chars)


# ------------------------
# VAR SYSTEM
# ------------------------

func apply_vars_changes(vars_data):
	for key in vars_data.keys():
		var instruction = vars_data[key]
		
		if not game_state["vars"].has(key):
			game_state["vars"][key] = 0
		
		if typeof(instruction) in [TYPE_INT, TYPE_FLOAT]:
			game_state["vars"][key] += instruction
		
		elif typeof(instruction) == TYPE_DICTIONARY:
			if instruction.has("add"):
				game_state["vars"][key] += instruction["add"]
			
			if instruction.has("set"):
				game_state["vars"][key] = instruction["set"]
			
			if instruction.has("mul"):
				game_state["vars"][key] *= instruction["mul"]
			
			if instruction.has("min"):
				game_state["vars"][key] = max(game_state["vars"][key], instruction["min"])
			
			if instruction.has("max"):
				game_state["vars"][key] = min(game_state["vars"][key], instruction["max"])

func check_condition(cond, node_index):
	if cond == null or cond.is_empty():
		return true
	
	return evaluate_condition(cond, node_index)

func evaluate_condition(cond, node_index):
	if typeof(cond) == TYPE_ARRAY:
		for c in cond:
			if not evaluate_condition(c, node_index):
				return false
		return true
	
	if typeof(cond) == TYPE_DICTIONARY:
		
		if cond.has("any"):
			for c in cond["any"]:
				if evaluate_condition(c, node_index):
					return true
			return false
		
		return _check_dict_condition(cond, node_index)

	return true

func _check_dict_condition(cond, node_index):
	for key in cond.keys():
		var req = cond[key]
		var value = 0

		if key == "visit_count":
			var node_key = travel.current_region + ":" + str(node_index)
			value = game_state["visited_count"].get(node_key, 0)
		elif key == "no_repeat":
			if req == true and node_index == travel.current_node:
				return false
			continue
		elif key == "lacks_item":
			var player = game_state["player"]
			if player == null:
				return false
			var has_equipped = req in player.data.get("Trinkets", [])
			var has_in_bag   = player.get_inventory().get(req, 0) > 0
			if has_equipped or has_in_bag:
				return false
			continue
		elif key == "lacks_skill":
			var player = game_state["player"]
			if player == null:
				return false
			if req in player.get_skills():
				return false
			continue
		elif key == "player_name":
			var player = game_state["player"]
			if player == null:
				return false
			value = player.get_name()
		elif key == "player_class":
			var player = game_state["player"]
			if player == null:
				return false
			value = player.get_char_class()
		elif key == "current_region":
			value = travel.current_region
		elif game_state["vars"].has(key):
			value = game_state["vars"][key]
		elif game_state.has(key):
			value = game_state[key]
		else:
			return false

		if typeof(req) == TYPE_DICTIONARY:
			if req.has("min") and value < req["min"]:
				return false
			if req.has("max") and value > req["max"]:
				return false
		else:
			print(value)
			print(req)
			if value != req:
				return false

	return true

# ------------------------
# SAVE / LOAD
# ------------------------

func save_game(slot: int):
	if current_mode != GameMode.TRAVEL:
		return
	if in_combat:
		show_text("Cannot save during combat.")
		return
	if SaveManager.save(slot, self):
		show_text("Game saved to slot %d." % slot)
	else:
		show_text("Save failed.")

func load_game(slot: int):
	var save_data = SaveManager.load_save(slot)
	if save_data.is_empty():
		show_text("No save found in slot %d." % slot)
		return

	var rng_data = save_data.get("rng", {})
	if rng_data.is_empty():
		rng.randomize()
	else:
		rng.seed  = rng_data["seed"]
		rng.state = rng_data["state"]

	var gs = save_data.get("game_state", {})
	game_state["gold"]          = gs.get("gold", 0)
	game_state["vars"]          = gs.get("vars", {})
	game_state["flags"]         = gs.get("flags", {})
	game_state["visited_nodes"] = gs.get("visited_nodes", {})
	game_state["visited_count"] = gs.get("visited_count", {})
	game_state["used_events"]   = gs.get("used_events", {})
	game_state["area_progress"] = gs.get("area_progress", {})

	var player_data = save_data.get("player", {})
	if not player_data.is_empty():
		var char_data = player_data.get("data", {})
		var character = Character.new(char_data, armor_db, weapon_db, rng, true)
		character.load_from_save(player_data)
		character.recalculate_trinket_bonus(trinkets_db)
		game_state["player"] = character

	var travel_data = save_data.get("travel", {})
	in_combat = false
	current_mode = GameMode.TRAVEL
	var saved_region = travel_data.get("current_region", "Apple Woods")
	travel.current_region = saved_region
	if travel.town_db.has(saved_region):
		travel.enter_town(saved_region)
	else:
		travel.enter_node(
			travel_data.get("current_node", 0),
			travel_data.get("current_entrance", "ROAD"),
			false,  # don't re-register the visit we already counted
			travel_data.get("current_node_data", {}),
			travel_data.get("used_node_action", false)
		)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				save_game(current_slot)
				get_viewport().set_input_as_handled()
			KEY_F9:
				load_game(current_slot)
				get_viewport().set_input_as_handled()

# ------------------------
# CHAR CHANGES
# ------------------------

func add_progress(progress,reset=false,region=""):
	if region == "":
		region = game_state["region"]
	if reset or not game_state['area_progress'].has(region):
		game_state['area_progress'][region] = 0
	game_state["area_progress"][region] += progress
	
func register_visit(key):
	
	game_state["visited_nodes"][key] = true
	
	if not game_state["visited_count"].has(key):
		game_state["visited_count"][key] = 0
	
	game_state["visited_count"][key] += 1

func apply_damage(amount):
	var player = game_state["player"]
	
	if player != null:
		player.take_damage(amount)

func apply_effect(effect):
	var player = game_state.get("player")
	match effect.get("type", ""):
		"damage":
			if player:
				var dmg =effect.get("amount", 0)
				if player.get_hp() < dmg:
					dmg = player.get_hp() - 1
				player.take_damage(dmg)
		"heal":
			if player:
				player.heal(effect.get("amount", 0))
		"restore_mp":
			if player:
				player.restore_mp(effect.get("amount", 0))
		_:
			for key in effect.keys():
				if typeof(effect[key]) == TYPE_INT and game_state["vars"].has(key):
					game_state["vars"][key] += effect[key]

# ------------------------
# COMBAT ENDED
# ------------------------

func show_game_over():
	MyEventBus.emit("play_bgm",{"song":"gameover"})
	MyEventBus.emit("set_backdrop", {"backdrop": "gameover_backdrop.png"})
	dialogue.visible = false
	main_menu.visible = false
	game_ui._clear_ui()
	gameover.show_gameover()

func _on_gameover_retry():
	gameover.visible = false
	var saves = SaveManager.list_saves()
	if saves.is_empty():
		show_main_menu()
	else:
		dialogue.visible = true
		load_game(current_slot)

func _on_gameover_title():
	gameover.visible = false
	show_main_menu()

func _on_combat_ended(data: Dictionary):
	in_combat = false
	if not data.get("victory", false):
		var suppress := _suppress_defeat_game_over
		_suppress_defeat_game_over = false
		MyEventBus.emit("post_combat", {"victory": false})
		if not suppress:
			show_game_over()
		return
	game_ui.skip_xp_animation()
	var player = game_state["player"]
	for lvl_up in _pending_level_ups:
		player.apply_level_up(lvl_up["gains"])
		show_text(_format_level_up_text(lvl_up))
		await _gm_wait_for_continue()
	if player and not _pending_rewards.is_empty():
		game_state["gold"] = game_state["gold"] + _pending_rewards.get("gold", 0)
		if not player.data.has("Inventory"):
			player.data["Inventory"] = {}
		for item_name in _pending_rewards.get("drops", {}):
			await _process_item_acquisition(item_name, player)
	_pending_rewards = {}
	_pending_level_ups = []
	MyEventBus.emit("post_combat", {"victory": true})

func _format_level_up_text(lvl_up: Dictionary) -> String:
	var lines = ["[b][color=yellow]LEVEL UP![/color][/b]  Lv.%d" % lvl_up["level"]]
	var gains = lvl_up["gains"]
	if gains.is_empty():
		lines.append("No stat gains.")
	else:
		for stat in gains:
			lines.append("[color=cyan]+1 %s[/color]" % stat.to_upper())
	return "\n".join(lines)

func _offer_equip(item_name: String, player: Character, price: int = 0, from_shop: bool = false):
	var slot: String
	var new_item: Dictionary
	if weapon_db.has(item_name):
		slot = "weapon"
		new_item = weapon_db[item_name]
	else:
		slot = "armor"
		new_item = armor_db[item_name]

	var old_item = player.equipment.get(slot)
	if typeof(old_item) != TYPE_DICTIONARY or old_item.is_empty():
		old_item = null

	MyEventBus.emit("dialogue", { "text": _build_equip_comparison_text(item_name, new_item, old_item, slot) })

	var confirm_type: String
	var cancel_type: String
	var choices: Array
	var header: String
	if from_shop:
		confirm_type = "buy_equip"
		cancel_type = "cancel"
		choices = [
			{ "text": "Buy & Equip", "type": "buy_equip", "highlight": true },
			{ "text": "Cancel", "type": "cancel" }
		]
		header = "Buy for [color=yellow]%dG[/color]?" % price
	else:
		confirm_type = "equip"
		cancel_type = "keep"
		choices = [
			{ "text": "Equip", "type": "equip", "highlight": true },
			{ "text": "Keep in Bag", "type": "keep" }
		]
		header = "New Equipment Found!"

	var state = { "chosen": "", "done": false }
	MyInputRouter.push(func(choice):
		var t = choice.get("type", "")
		if t == confirm_type or t == cancel_type:
			state["chosen"] = t
			state["done"] = true
			MyInputRouter.pop()
	, "equip_prompt")

	MyEventBus.emit("show_choices", { "choices": choices, "header": header })

	while not state["done"]:
		await get_tree().process_frame

	var inv = player.data["Inventory"]
	if state["chosen"] == confirm_type:
		if from_shop:
			game_state["gold"] -= price
		if old_item and old_item.has("name"):
			inv[old_item["name"]] = inv.get(old_item["name"], 0) + 1
		player.equip(slot, new_item)
		var result_text = "[color=#00E676]%s equipped![/color]" % new_item.get("name", item_name)
		if from_shop:
			result_text += "\n[color=yellow]Gold: %dG[/color]" % game_state["gold"]
		MyEventBus.emit("continue_text", { "text": result_text })
		await _gm_wait_for_continue()
	elif not from_shop:
		inv[item_name] = inv.get(item_name, 0) + 1
		MyEventBus.emit("continue_text", { "text": "[color=#AAAAAA]%s added to bag, check inventory out of battle to equip.[/color]" % item_name })
		await _gm_wait_for_continue()

func _gm_wait_for_continue():
	var state = { "done": false }
	MyInputRouter.push(func(choice):
		if choice.get("type") == "continue":
			state["done"] = true
			MyInputRouter.pop()
	, "gm_wait")
	MyEventBus.emit("show_choices", {
		"choices": [{ "text": "Continue", "type": "continue" }]
	})
	while not state["done"]:
		await get_tree().process_frame

func _gm_wait_for_writing():
	while dialogue.is_typing:
		await get_tree().process_frame

func _build_equip_comparison_text(item_name: String, new_item: Dictionary, old_item, slot: String) -> String:
	var new_name = new_item.get("name", item_name)
	var old_name = "None" if not old_item else old_item.get("name", "?")

	var text = "[b]New %s Found![/b]\n" % slot.capitalize()
	text += "[b]%s[/b]" % new_name
	if new_item.has("wpn_type"):
		text += "  [i](%s)[/i]" % new_item["wpn_type"]
	if new_item.has("element"):
		text += "  [color=orange][%s][/color]" % new_item["element"]
	if new_item.has("description"):
		text += "\n" + new_item["description"]
	text += "\n\n"

	var new_stats: Dictionary = new_item.get("stats", {})
	var old_stats: Dictionary = {} if not old_item else old_item.get("stats", {})

	var all_stats: Array = []
	for s in new_stats:
		if not s in all_stats:
			all_stats.append(s)
	for s in old_stats:
		if not s in all_stats:
			all_stats.append(s)

	if all_stats.size() > 0:
		text += "[instant][table=5]"
		text += "[cell][/cell][cell][b]%s[/b][/cell][cell][/cell][cell][b]%s[/b][/cell][cell][/cell]" % [old_name, new_name]
		for stat in all_stats:
			var old_v: int = old_stats.get(stat, 0)
			var new_v: int = new_stats.get(stat, 0)
			var diff: int = new_v - old_v
			var new_v_str: String
			var diff_str: String
			if diff > 0:
				new_v_str = "[color=#00E676]%s[/color]" % str(new_v)
				diff_str = "[color=#00E676]+%d[/color]" % diff
			elif diff < 0:
				new_v_str = "[color=#F44336]%s[/color]" % str(new_v)
				diff_str = "[color=#F44336]%d[/color]" % diff
			else:
				new_v_str = str(new_v)
				diff_str = ""
			text += "[cell]%s:[/cell][cell][center]%s[/center][/cell][cell]→[/cell][cell][center]%s[/center][/cell][cell][center]%s[/center][/cell]" % [
				stat.to_upper(), str(old_v), new_v_str, diff_str
			]
		var oeffect = "N/A"
		if old_item.has("effect") and old_item["effect"] != "none":
			oeffect = "[color=cyan]%s[/color]" % old_item["effect"]
		var neffect = "N/A"
		if new_item.has("effect") and new_item["effect"] != "none":
			neffect = "[color=cyan]%s[/color]" % new_item["effect"]
			
		text += "[cell][b]Effect:[/b][/cell][cell][center]%s[/center][/cell][cell][/cell][cell][center]%s[/center][cell][/cell]" % [
			oeffect, neffect
		]
		text += "[/table][/instant]"

	return text

# ------------------------
# ITEM ACQUISITION
# ------------------------

func _process_item_acquisition(item_name: String, player: Character, price: int = 0, from_shop: bool = false):
	if not player.data.has("Inventory"):
		player.data["Inventory"] = {}
	if weapon_db.has(item_name) or armor_db.has(item_name):
		await _offer_equip(item_name, player, price, from_shop)
	elif item_name.begins_with("Book of "):
		var spell_name = item_name.substr(8)
		if spell_db.has(spell_name):
			await _offer_learn(spell_name, spell_db[spell_name], "spell", player, item_name, price, from_shop)
		else:
			player.data["Inventory"][item_name] = player.data["Inventory"].get(item_name, 0) + 1
	elif item_name.ends_with(" Scroll"):
		var skill_name = item_name.substr(0, item_name.length() - 7)
		if skill_db.has(skill_name):
			await _offer_learn(skill_name, skill_db[skill_name], "skill", player, item_name, price, from_shop)
		else:
			player.data["Inventory"][item_name] = player.data["Inventory"].get(item_name, 0) + 1
	elif trinkets_db.has(item_name):
		await _equip_trinket_acquisition(item_name, player, price, from_shop)
	else:
		player.data["Inventory"][item_name] = player.data["Inventory"].get(item_name, 0) + 1

func _equip_trinket_acquisition(item_name: String, player: Character, price: int = 0, from_shop: bool = false):
	if not player.data.has("Trinkets"):
		player.data["Trinkets"] = []
	var stackable = trinkets_db[item_name].get("stackable", false)
	var already_equipped = not stackable and item_name in player.data["Trinkets"]

	if from_shop:
		var data = trinkets_db[item_name]
		var preview = "[b]%s[/b]  [i](Trinket)[/i]" % item_name
		if data.has("description"):
			preview += "\n" + data["description"]
		if data.has("effect_description"):
			preview += "\n" + data["effect_description"]

		MyEventBus.emit("dialogue", { "text": preview })

		var state = { "done": false, "confirmed": false }
		MyInputRouter.push(func(choice):
			var t = choice.get("type", "")
			if t == "buy_equip" or t == "cancel":
				state["confirmed"] = (t == "buy_equip")
				state["done"] = true
				MyInputRouter.pop()
		, "trinket_prompt")
		MyEventBus.emit("show_choices", {
			"choices": [
				{ "text": "Buy & Equip", "type": "buy_equip", "highlight": true },
				{ "text": "Cancel", "type": "cancel" }
			],
			"header": "Buy for [color=yellow]%dG[/color]?" % price
		})
		while not state["done"]:
			await get_tree().process_frame

		if not state["confirmed"]:
			return

		game_state["gold"] -= price

	if already_equipped:
		player.data["Inventory"][item_name] = player.data["Inventory"].get(item_name, 0) + 1
		var text = "[color=#AAAAAA]%s kept in bag (already equipped).[/color]" % item_name
		if from_shop:
			text += "\n[color=yellow]Gold: %dG[/color]" % game_state["gold"]
		MyEventBus.emit("continue_text", {"text": text})
	else:
		player.data["Trinkets"].append(item_name)
		player.stats_changed.emit()
		var text = "[color=#00E676]%s equipped![/color]" % item_name
		if from_shop:
			text += "\n[color=yellow]Gold: %dG[/color]" % game_state["gold"]
		MyEventBus.emit("continue_text", {"text": text})
	await _gm_wait_for_continue()

func _offer_learn(learn_name: String, entry: Dictionary, kind: String, player: Character, item_name: String, price: int = 0, from_shop: bool = false):
	var known: bool
	if kind == "spell":
		known = player.get_spells().has(learn_name)
	else:
		known = player.get_skills().has(learn_name)

	MyEventBus.emit("dialogue", { "text": _build_learn_preview_text(learn_name, entry, kind, known) })

	var choices: Array
	var header: String
	var confirm_type: String
	var cancel_type: String

	if from_shop:
		confirm_type = "buy_learn"
		cancel_type = "cancel"
		choices = [
			{ "text": "Buy & Learn", "type": "buy_learn", "highlight": true },
			{ "text": "Cancel", "type": "cancel" }
		]
		header = "Buy for [color=yellow]%dG[/color]?" % price
	elif known:
		confirm_type = ""
		cancel_type = "learn_keep"
		choices = [{ "text": "Keep in Bag", "type": "learn_keep" }]
		header = "[color=yellow]Already Known[/color]"
	else:
		confirm_type = "learn_confirm"
		cancel_type = "learn_keep"
		choices = [
			{ "text": "Learn!", "type": "learn_confirm", "highlight": true },
			{ "text": "Keep in Bag", "type": "learn_keep" }
		]
		header = "New %s Found!" % kind.capitalize()

	var state = { "chosen": "", "done": false }
	MyInputRouter.push(func(choice):
		var t = choice.get("type", "")
		if t in ["learn_confirm", "learn_keep", "buy_learn", "cancel"]:
			state["chosen"] = t
			state["done"] = true
			MyInputRouter.pop()
	, "learn_prompt")

	MyEventBus.emit("show_choices", { "choices": choices, "header": header })

	while not state["done"]:
		await get_tree().process_frame

	var confirmed = (state["chosen"] == confirm_type and confirm_type != "")

	if confirmed:
		if from_shop:
			game_state["gold"] -= price
		var list_key = "Spells" if kind == "spell" else "Skills"
		if not player.data.has(list_key):
			player.data[list_key] = []
		player.data[list_key].append(learn_name)
		var result_text = "[color=#00E676]You learned [b]%s[/b]![/color]" % learn_name
		if from_shop:
			result_text += "\n[color=yellow]Gold: %dG[/color]" % game_state["gold"]
		MyEventBus.emit("continue_text", { "text": result_text })
		await _gm_wait_for_continue()
	elif not from_shop:
		var inv = player.data["Inventory"]
		inv[item_name] = inv.get(item_name, 0) + 1
		MyEventBus.emit("continue_text", { "text": "[color=#AAAAAA]%s kept in bag.[/color]" % item_name })
		await _gm_wait_for_continue()

func _build_learn_preview_text(learn_name: String, entry: Dictionary, kind: String, already_known: bool) -> String:
	var text = ""

	if already_known:
		text += "[color=yellow]You already know [b]%s[/b].[/color]\n\n" % learn_name

	text += "[b]%s[/b]" % learn_name

	if kind == "spell" and entry.has("element"):
		text += "  [color=%s][%s][/color]" % [_get_element_color(entry["element"]), entry["element"]]

	text += "  [i](%s)[/i]\n" % kind.capitalize()

	var type_str: String = entry.get("type", "attack")
	text += "Type: %s" % type_str.capitalize()

	if entry.has("cost") and int(entry["cost"]) > 0:
		text += "   MP Cost: [color=#4FC3F7]%d[/color]" % int(entry["cost"])

	if entry.has("cooldown") and int(entry["cooldown"]) > 0:
		text += "   Cooldown: [color=#FFB74D]%d turns[/color]" % int(entry["cooldown"])

	text += "\n\n"

	var stats: Dictionary = entry.get("stats", {})
	if stats.size() > 0:
		text += "[instant][table=4]"
		for stat in stats:
			text += "[cell][b]%s:[/b][/cell][cell]%s  [/cell]" % [stat.to_upper(), str(stats[stat])]
		text += "[/table][/instant]\n"

	var effect: String = entry.get("effect", "none")
	if effect != "none" and effect != "":
		var chance = entry.get("chance", 100)
		if int(chance) < 100:
			text += "Effect: [color=cyan]%s[/color] (%d%% chance)\n" % [effect.capitalize(), int(chance)]
		else:
			text += "Effect: [color=cyan]%s[/color]\n" % effect.capitalize()

	if entry.has("hits") and int(entry["hits"]) > 1:
		text += "Hits: [b]%d[/b]x\n" % int(entry["hits"])

	if not already_known:
		text += "\n[color=#CCCCCC]Learn this %s?[/color]" % kind

	return text

func _get_element_color(element: String) -> String:
	match element:
		"Fire":    return "#FF6E40"
		"Ice":     return "#80D8FF"
		"Wind":    return "#B9F6CA"
		"Earth":   return "#BCAAA4"
		"Water":   return "#40C4FF"
		"Light":   return "#FFF9C4"
		"Dark":    return "#CE93D8"
		"Thunder": return "#FFD740"
		"Poison":  return "#B39DDB"
	return "#FFFFFF"
