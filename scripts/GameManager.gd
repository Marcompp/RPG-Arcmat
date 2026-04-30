extends Node

@onready var dialogue = $DialogueSystem
@onready var combat = $CombatManager
@onready var game_ui = $GameUI

# ========================
# CORE
# ========================

enum GameMode {
	CHARACTER_SELECT,
	NODE_ACTIONS,
	CHOOSING_EXIT,
	INVENTORY,
	REST,
	MONSTERS
}

var current_mode = GameMode.CHARACTER_SELECT

var characters = []

var world_data = {}

var current_region = "Apple Woods"
var current_node = 0
var current_entrance = 1

var in_combat = false

var current_node_data = null

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
		show_node_actions()
	)
	MyEventBus.subscribe("take_damage", func(data):
		apply_damage(data['damage'])
		show_node_actions()
	)
	#game_state["player"] = null
	game_state["gold"] = 0
	game_state["vars"] = {}
	game_state["flags"] = {}
	game_state["visited_nodes"] = {}
	game_state["visited_count"] = {}
	game_state["area_progress"] = 0
	game_ui.bind(game_state)
	
	world_data = load_json("res://Database/area_nodes.json")
	
	if world_data.is_empty():
		push_error("Falha ao carregar o JSON")
		return
	
	MyInputRouter.push(_handle_game_input, "exploration")
	#MyEventBus.subscribe("choice_selected", _on_choice)
	#dialogue.choice_selected.connect(_on_choice)
	
	dialogue.condition_callback = func(cond):
		return check_condition(cond, current_node)
	
	characters = load_json("res://Database/protags.json")
	

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
	dialogue.play_node({ "text": text })

func show_choices(choices):
	dialogue.set_choices(choices)
# ------------------------
# GAME FLOW
# ------------------------

func start_game():
	enter_node(0, "ROAD")

func _set_current_node(node_index, entrance):
	current_node = node_index
	current_entrance = entrance
	
	var region = world_data[current_region]
	current_node_data = region[current_node]

func show_node():
	show_node_text()
	current_mode = GameMode.NODE_ACTIONS
	show_node_actions()

func enter_node(node_index, entrance):
	_set_current_node(node_index, entrance)
	
	register_visit()
	
	# 🔔 evento (para UI secundária, som, etc)
	MyEventBus.emit("node_entered", {
		"node": current_node_data,
		"entrance": entrance
	})
	
	# 🎯 fluxo principal continua aqui
	show_node()

func register_visit():
	var key = get_node_key()
	
	game_state["visited_nodes"][key] = true
	
	if not game_state["visited_count"].has(key):
		game_state["visited_count"][key] = 0
	
	game_state["visited_count"][key] += 1
	

func get_node_key():
	return current_region + ":" + str(current_node)

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
	game_state["player"] = char
	
	apply_character_stats(char)
	
	MyEventBus.emit("character_selected", {
		"character": char
	})
	
	start_game()
	
func apply_character_stats(char):
	game_state["player"]["curr_stats"] = {}
	var hp = convert_rank_to_value(char["Stats"]["HP"]) + 5
	var mp = convert_rank_to_value(char["Stats"]["MP"])

	game_state.set_value("player.curr_stats", {
		"hp": hp,
		"mp": mp,
		"mhp": hp,
		"mmp": mp
	})
	game_state["player"]["curr_stats"]["str"] = convert_rank_to_value(char["Stats"]["Str"])
	game_state["player"]["curr_stats"]["mag"] = convert_rank_to_value(char["Stats"]["Mag"])
	game_state["player"]["curr_stats"]["agi"] = convert_rank_to_value(char["Stats"]["Agi"])
	game_state["player"]["curr_stats"]["dex"] = convert_rank_to_value(char["Stats"]["Dex"])
	game_state["player"]["curr_stats"]["lck"] = convert_rank_to_value(char["Stats"]["Lck"])
	game_state["player"]["curr_stats"]["def"] = convert_rank_to_value(char["Stats"]["Def"])
			
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
# UI STATES
# ------------------------

func show_node_text():
	var key = get_node_key()
	
	var text = ""
	
	text += get_arrival_text(current_node_data)
	text += "\n\n" + get_dynamic_paragraph(current_node_data, key)
	text += "\n\nWhat do you want to do?"
	
	dialogue.play_node({
		"text": text,
		"choices": []
	})

func show_node_actions():
	dialogue.set_choices([
		{ 
			"text": "Continue",
			"type": "action",
			"tooltip": "Continue your journey"
		},
		{ 
			"text": "Search for Monsters",
			"type": "action",
			"tooltip": "Stay in place and look for monsters to fight"
		},
		{ 
			"text": "Inventory",
			"type": "action",
			"tooltip": "View your inventory"
		},
		{ 
			"text": "Rest",
			"type": "action",
			"tooltip": "Recover health, but risk being attacked"
		}
	])

func show_exit_choices():
	var choices = []
	
	for exit in current_node_data.get("exits", []):
		choices.append({
			"text": exit.get("choice", "Continue"),
			"type": "exit",
			"data": exit
		})
	
	choices.append({
		"text": "Back",
		"type": "back",
		"tooltip": "Cancel choice selection"
	})
	
	dialogue.set_choices(choices)

# ------------------------
# INPUT
# ------------------------

func _handle_game_input(choice):
	if in_combat:
		return  # ignora tudo

	match current_mode:
		GameMode.CHARACTER_SELECT:
			handle_character_select(choice)
		
		GameMode.NODE_ACTIONS:
			handle_node_action(choice)
		
		GameMode.CHOOSING_EXIT:
			handle_exit_choice(choice)
			
# ------------------------
# ACTIONS
# ------------------------

func handle_node_action(choice):
	match choice["text"]:
		
		"Continue":
			current_mode = GameMode.CHOOSING_EXIT
			show_exit_choices()
		
		"Search for Monsters":
			start_combat()
			print("Combat TBD")
		
		"Inventory":
			print("Inventory TBD")
		
		"Rest":
			print("Rest TBD")

func start_combat():
	in_combat = true
	var enemy = {
		"name": "Slime",
		"hp": 10,
		"def": 1
	}
	
	combat.start_combat(game_state["player"], enemy)

# ------------------------
# EXITS
# ------------------------

func handle_exit_choice(choice):
	if choice.get("type") == "back":
		current_mode = GameMode.NODE_ACTIONS
		show_node_actions()
		return
	
	var exit = choice.get("data", {})
	
	current_entrance = exit.get("leads_to", current_entrance)
	
	game_state["area_progress"] += exit.get("value", 1)
	
	apply_exit_vars(exit)
	
	var next_node = pick_next_node(current_entrance)
	
	enter_node(next_node, current_entrance)
	
func get_valid_nodes(entrance):
	var region = world_data[current_region]
	var valid = []
	
	for i in range(region.size()):
		var node = region[i]
		
		if entrance in node.get("entrances", []):
			if check_condition(node.get("condition", {}), i):
				valid.append(i)
	
	return valid

func pick_next_node(entrance):
	var valid = get_valid_nodes(entrance)
	
	if valid.is_empty():
		return current_node
	
	return valid.pick_random()

# ------------------------
# VAR SYSTEM
# ------------------------

func apply_exit_vars(exit_data):
	if not exit_data.has("var"):
		return
	
	for key in exit_data["var"].keys():
		var instruction = exit_data["var"][key]
		
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
# TEXT SYSTEM
# ------------------------

func get_arrival_text(node):
	if not node.has("arrival"):
		return ""
	
	var arrival = node["arrival"]
	
	if arrival.has(current_entrance):
		return arrival[current_entrance].pick_random()
	
	if arrival.has("default"):
		return arrival["default"].pick_random()
	
	return ""

func get_dynamic_paragraph(node, node_key):
	if not node.has("description"):
		return node.get("name", "???")
	
	var valid = []
	
	for p in node["description"]:
		var ok = true
		
		if typeof(p) == TYPE_STRING:
			valid.append({ "text": p })
		else:
			if p.has("condition"):
				ok = check_condition(p["condition"], node_key)
			
			if ok and p.has("chance"):
				if randf() > p["chance"]:
					ok = false
			
			if ok:
				valid.append(p)
	
	if valid.is_empty():
		return node.get("name", "???")
	
	var chosen = valid.pick_random()
	
	if chosen.has("effect"):
		apply_effect(chosen["effect"])
	
	return chosen.get("text", "")

func apply_damage(amount):
	var hp = game_state.get_value("player.curr_stats.hp", 0)
	game_state.set_value("player.curr_stats.hp", hp - amount)

func apply_effect(effect):
	var changed = false

	for key in effect.keys():
		if typeof(effect[key]) == TYPE_INT:
			if game_state["vars"].has(key):
				game_state["vars"][key] += effect[key]
			
	if changed:
		MyEventBus.emit("stats_changed", game_state["player"]["curr_stats"])
