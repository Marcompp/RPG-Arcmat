extends Node

@onready var dialogue = $DialogueSystem
@onready var travel = $TravelManager
@onready var combat = $CombatManager
@onready var game_ui = $GameUI

# ========================
# CORE
# ========================

enum GameMode {
	CHARACTER_SELECT,
	CHARACTER_CONFIRM,
	TRAVEL,
	INVENTORY,
	REST,
	MONSTERS
}

var current_mode = GameMode.CHARACTER_SELECT

var characters = []
var armor_db = {}
var weapon_db = {}

var in_combat = false

var pending_character = null

var game_state = GameState.new()

signal character_updated(char)

func get_var(key, default := 0):
	return game_state["vars"].get(key, default)

# ------------------------
# INIT
# ------------------------

func _ready():
	MyEventBus.subscribe("combat_ended", func(_data):
		in_combat = false
		travel.show_node_actions()
	)
	MyEventBus.subscribe("register_visit", func(data):
		register_visit(data.get('key',0))
	)
	MyEventBus.subscribe("add_progress", func(data):
		add_progress(data.get('progress',0),data.get('reset',false))
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
	#game_state["player"] = null
	game_state["gold"] = 0
	game_state["vars"] = {}
	game_state["flags"] = {}
	game_state["visited_nodes"] = {}
	game_state["visited_count"] = {}
	game_state["area_progress"] = 0
	game_ui.bind(game_state)
	
	MyInputRouter.push(_handle_game_input, "exploration")
	#MyEventBus.subscribe("choice_selected", _on_choice)
	#dialogue.choice_selected.connect(_on_choice)
	
	dialogue.condition_callback = func(cond):
		return check_condition(cond, travel.current_node)
	travel.condition_callback = func(cond, current_node):
		return check_condition(cond, current_node)
	
	characters = load_json("res://Database/protags.json")
	armor_db = load_json("res://Database/armors.json")
	weapon_db = load_json("res://Database/weapons.json")
	

	start_character_selection()

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
	
func build_character_tooltip(char):
	var t = char["Name"] + "  Lv.1"
	#Name
	t += "\nClass: " + char["Class"]
	
	# ------------------------
	# STATS (2 por linha)
	# ------------------------
	t += "\n\nStats:\n"
	
	var stat_keys = char["Stats"].keys()
	
	t += "[table=5]"

	for i in range(0, stat_keys.size(), 2):
		var k1 = stat_keys[i]
		var r1 = str(char["Stats"][k1])
		var c1 = get_rank_color(r1)
		
		t += "[cell]" + k1 + ": [/cell]"
		t += "[cell][b][color=" + c1 + "]" + r1 + "[/color][/b][/cell]"
		t += "[cell]   [/cell]"
		
		if i + 1 < stat_keys.size():
			var k2 = stat_keys[i + 1]
			var r2 = str(char["Stats"][k2])
			var c2 = get_rank_color(r2)
			
			t += "[cell]" + k2 + ": [/cell]"
			t += "[cell][b][color=" + c2 + "]" + r2 + "[/color][/b][/cell]"
		else:
			t += "[cell][/cell][cell][/cell]"

	t += "[/table]"
	
	# Equip
	if char.has("Equip") and typeof(char["Equip"]) == TYPE_DICTIONARY:
		t += "\nStarting Equipment:\n"
		for e in char["Equip"]:
			t += e + ": " + char["Equip"][e] + "\n"
	
	# Skills
	if char["Skills"].size() > 0:
		t += "\nStarting Skill:\n"
		for s in char["Skills"]:
			t += "- " + s + "\n"
	
	# Spells
	if char["Spells"].size() > 0:
		t += "\nStarting Spells:\n"
		for s in char["Spells"]:
			t += "- " + s + "\n"
	t += "\n"
	
	return t.strip_edges()

func show_character_choices():
	var choices = []
	
	for char in characters:
		choices.append({
			"text": char["Name"] + ", the " + char["Class"],
			"type": "character",
			"data": char,
			"tooltip": build_character_tooltip(char)
		})
	
	dialogue.set_choices(choices)
	
func handle_character_select(choice):
	var char = choice.get("data", {})
	pending_character = char
	
	show_character_confirm(char)
	
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
	# EQUIP
	# ------------------------
	if char.has("Equip"):
		text += "[b]Equipment[/b]\n"
		for e in char["Equip"]:
			text += "- " + char["Equip"][e] + "\n"
		text += "\n"
	
	# ------------------------
	# SKILLS
	# ------------------------
	if char["Skills"].size() > 0:
		text += "[b]Skills[/b]\n"
		for s in char["Skills"]:
			text += "- " + s + "\n"
		text += "\n"
	
	# ------------------------
	# SPELLS
	# ------------------------
	if char["Spells"].size() > 0:
		text += "[b]Spells[/b]\n"
		for s in char["Spells"]:
			text += "- " + s + "\n"
		text += "\n"
	
	# ------------------------
	# WARNING
	# ------------------------
	text += "[color=yellow]This choice cannot be undone.[/color]"
	
	show_text(text)
	
	dialogue.set_choices([
		{ "text": "▶ Start Journey", "type": "confirm_character" },
		{ "text": "◀ Choose Another", "type": "back" }
	])
	
func confirm_character():
	var char = pending_character
	var character = Character.new(char, equipment_db)
	game_state["player"] = character
	
	#character.stats_changed.connect(_on_character_stats_changed)
	
	MyEventBus.emit("character_selected", {
		"character": char
	})
	
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

func start_combat(data):
	in_combat = true
	var enemy = data.get('enemy', {
		"Name": "Slime",
		"Stats": {
		"Hp": 10,
		"Def": 1
		}
	})
	var enmy = Character.new(enemy, equipment_db)
	
	# 🔥 ESSENCIAL
	game_state.set_value("enemy", enmy)
	
	combat.start_combat(game_state["player"], enmy)


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
		
		return _check_dict_condition(cond)
	
	return true

func _check_dict_condition(cond):
	for key in cond.keys():
		var value = 0
		
		if game_state["vars"].has(key):
			value = game_state["vars"][key]
		elif game_state.has(key):
			value = game_state[key]
		else:
			return false
		
		var req = cond[key]
		
		if typeof(req) == TYPE_DICTIONARY:
			if req.has("min") and value < req["min"]:
				return false
			if req.has("max") and value > req["max"]:
				return false
		else:
			if value != req:
				return false
	
	return true

# ------------------------
# CHAR CHANGES
# ------------------------

func add_progress(progress,reset=false):
	if reset:
		game_state['area_progress'] = 0
	game_state["area_progress"] += progress
	
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
	var changed = false

	for key in effect.keys():
		if typeof(effect[key]) == TYPE_INT:
			if game_state["vars"].has(key):
				game_state["vars"][key] += effect[key]
			
	if changed:
		MyEventBus.emit("stats_changed", game_state["player"]["curr_stats"])
