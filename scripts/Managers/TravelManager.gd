extends Node

@onready var backdrop = $Backdrop

enum TravelMode {
	NODE_ACTIONS,
	CHOOSING_EXIT,
	REGION_EXIT,
	TOWN,
	TOWN_LEAVE_CONFIRM
}

var condition_callback = null

var mode = TravelMode.NODE_ACTIONS

var game_manager
var game_state

var world_data = {}
var monster_db = []
var region_db = {}
var town_db = {}

var current_town = ""
var current_town_data = null

var current_region = "":
	set(value):
		current_region = value
		if game_state:
			game_state["region"] = value
		_transition_backdrop(value)
		MyEventBus.emit("region_changed", {"region": value})
var current_node = 0
var current_entrance = 1

var current_node_data = null

func _ready():
	world_data = load_json("res://Database/area_nodes.json")
	monster_db = load_json("res://Database/monsters.json")
	region_db = load_json("res://Database/regions.json")
	town_db = load_json("res://Database/towns.json")

	MyEventBus.subscribe("character_selected", func(_data):
		current_region = "Apple Woods"
	)

	if world_data.is_empty():
		push_error("Falha ao carregar o JSON")
		return

# ------------------------
# FLOW
# ------------------------

func _evaluate_node(condition, curr_node):
	if condition_callback == null:
		return true
	
	return condition_callback.call(condition,curr_node)

func _set_current_node(node_index, entrance):
	current_node = node_index
	current_entrance = entrance
	var region = world_data[current_region]
	current_node_data = region[current_node]
	
func get_node_key():
	return current_region + ":" + str(current_node)

# ------------------------
# INPUT
# ------------------------

func handle_input(choice):
	match mode:
		TravelMode.NODE_ACTIONS:
			handle_node_action(choice)

		TravelMode.CHOOSING_EXIT:
			print('EXIT CHOICE')
			handle_exit_choice(choice)

		TravelMode.REGION_EXIT:
			_handle_region_exit()

		TravelMode.TOWN:
			_handle_town_action(choice)

		TravelMode.TOWN_LEAVE_CONFIRM:
			_handle_leave_confirm(choice)

# ------------------------
# NODES
# ------------------------

func show_node():
	MyEventBus.emit("clear_text",{})
	show_node_text(true)
	current_entrance = "default"
	mode = TravelMode.NODE_ACTIONS
	if current_node_data.get("type", "") == "EXIT":
		_show_region_exit_prompt()
	else:
		show_node_actions()

func enter_node(node_index, entrance, register: bool = true):
	_set_current_node(node_index, entrance)

	if register:
		register_visit()

	# 🔔 evento (para UI secundária, som, etc)
	MyEventBus.emit("node_entered", {
		"node": current_node_data,
		"entrance": entrance
	})

	# 🎯 fluxo principal continua aqui
	show_node()

func get_node_text(use_default=false):
	var key = get_node_key()
	
	var text = ""
	
	text += get_arrival_text(current_node_data, use_default)
	text += "\n\n" + get_dynamic_paragraph(current_node_data, key)
	#text += "\n\nWhat do you want to do?"
	
	current_entrance = 0
	return text

func show_node_text(use_default=false):
	var text = get_node_text(use_default)
	
	current_entrance = 0
	MyEventBus.emit("dialogue", {
		"text": text,
		"choices": [],
		"linebreak": false
	})

func show_node_actions():
	if game_manager:
		SaveManager.save(game_manager.current_slot, game_manager)
	MyEventBus.emit("show_choices",{'choices':[
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
	], "header": "What would you like to do?"})

func _show_region_exit_prompt():
	var region_info = region_db.get(current_region, {})
	var exit_text = region_info.get("ExitTxt", "You find the way out.")
	MyEventBus.emit("dialogue", {"text": "\n\n" + exit_text, "choices": [], "linebreak": false})
	MyEventBus.emit("show_choices", {"choices": [
		{"text": "Continue", "type": "action", "tooltip": "Leave " + current_region}
	], "header": ""})
	mode = TravelMode.REGION_EXIT

func _handle_region_exit():
	var next_name = region_db.get(current_region, {}).get("Next", "")
	if next_name == "" or (not world_data.has(next_name) and not town_db.has(next_name)):
		push_error("Próxima área inválida: " + next_name)
		return
	MyEventBus.emit("add_progress", {"progress": 0, "reset": true})
	if town_db.has(next_name):
		enter_town(next_name)
	else:
		current_region = next_name
		enter_node(0, "default")

# ------------------------
# ACTIONS
# ------------------------

func handle_node_action(choice):
	match choice["text"]:
		"Continue":
			mode = TravelMode.CHOOSING_EXIT
			show_exit_choices()
		
		"Search for Monsters":
			MyEventBus.emit(
				"start_combat", {}
			)
			print("Combat TBD")
		
		"Inventory":
			print("Inventory TBD")
		
		"Rest":
			print("Rest TBD")

# ------------------------
# TOWN
# ------------------------

func enter_town(town_name):
	current_town = town_name
	current_town_data = town_db[town_name]
	current_region = town_name
	MyEventBus.emit("clear_text", {})
	var arrival = current_town_data.get("arrival", [])
	var ambience = current_town_data.get("ambience", [])
	var text = arrival.pick_random() if not arrival.is_empty() else town_name
	if not ambience.is_empty():
		text += "\n\n" + ambience.pick_random()
	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_town_actions()

func show_town_actions():
	if game_manager:
		SaveManager.save(game_manager.current_slot, game_manager)
	var choices = []
	for shop_name in current_town_data.get("Shops", {}):
		choices.append({"text": shop_name, "type": "action", "tooltip": "Visit " + shop_name})
	choices.append({"text": "Leave", "type": "back", "tooltip": "Leave " + current_town})
	MyEventBus.emit("show_choices", {"choices": choices, "header": current_town})
	mode = TravelMode.TOWN

func _handle_town_action(choice):
	if choice.get("type") == "back":
		_show_leave_confirm()
		return
	print("Shop TBD: " + choice.get("text", ""))

func _show_leave_confirm():
	MyEventBus.emit("show_choices", {"choices": [
		{"text": "Yes", "type": "action", "tooltip": "Leave " + current_town},
		{"text": "No",  "type": "back",   "tooltip": "Stay in " + current_town}
	], "header": "Leave " + current_town + "?"})
	mode = TravelMode.TOWN_LEAVE_CONFIRM

func _handle_leave_confirm(choice):
	if choice.get("text") == "Yes":
		var next_name = current_town_data.get("Next", "")
		if next_name == "" or not world_data.has(next_name):
			push_error("Próxima região inválida para " + current_town + ": " + next_name)
			return
		var exit_text = current_town_data.get("ExitTxt", "")
		if exit_text != "":
			MyEventBus.emit("continue_text", {"text": exit_text})
			await game_manager._gm_wait_for_continue()
		current_region = next_name
		enter_node(0, "default")
	else:
		show_town_actions()

# ------------------------
# EXITS
# ------------------------

func show_exit_choices():
	print('SHOW_EXIT_CHOICES')
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
	
	MyEventBus.emit("show_choices", {
		"choices": choices
	})

func handle_exit_choice(choice):
	if choice.get("type") == "back":
		mode = TravelMode.NODE_ACTIONS
		show_node_actions()
		return

	var exit = choice.get("data", {})
	current_entrance = exit.get("leads_to", current_entrance)

	MyEventBus.emit("add_progress", {"progress": exit.get("value", 1)})
	apply_exit_vars(exit)

	var next_node = pick_next_node(current_entrance)
	_set_current_node(next_node, current_entrance)
	register_visit()

	MyEventBus.emit("node_entered", {
		"node": current_node_data,
		"entrance": current_entrance
	})

	var travel_text = exit.get("travel_text", "You press on for a while.")
	var text = travel_text + "\n\n...\n[wait=0.2]\n...\n[wait=0.2]\n\n"
	text += get_node_text(false)
	MyEventBus.emit("dialogue", {"text": text})

	var boss_monster = _get_boss_encounter(current_node_data)
	var monster = null
	if boss_monster:
		monster = boss_monster
	else:
		var encounter_rate = current_node_data.get("encounter_rate", 0.75)
		var encounter_roll = randf()
		if encounter_roll < encounter_rate:
			monster = _pick_encounter_monster()
	if monster:
		MyEventBus.emit("continue_text", {
			"text": "Suddenly, a [b]" + monster["Name"] + "[/b] appears!"
		})
		await game_manager._gm_wait_for_continue()
		MyEventBus.emit("start_combat", {"enemy": monster})
	else:
		mode = TravelMode.NODE_ACTIONS
		show_node_actions()

func apply_exit_vars(exit_data):
	if not exit_data.has("var"):
		return
		
	MyEventBus.emit("change_vars",exit_data["var"])
		
# ------------------------
# LOGIC
# ------------------------

func get_valid_nodes(entrance):
	var region = world_data[current_region]
	var valid = []
	
	for i in range(region.size()):
		var node = region[i]
		
		if entrance in node.get("entrances", []):
			if _evaluate_node(node.get("condition", {}), i):
				valid.append(i)
	
	return valid

func pick_next_node(entrance):
	var valid = get_valid_nodes(entrance)

	if valid.is_empty():
		return current_node

	var region_length = region_db.get(current_region, {}).get("Length", INF)
	var progress = game_state.get("area_progress") if game_state else 0
	var region_nodes = world_data[current_region]

	if progress >= region_length:
		var exit_nodes = valid.filter(func(i): return region_nodes[i].get("type", "") == "EXIT")
		if not exit_nodes.is_empty():
			return exit_nodes.pick_random()
	else:
		valid = valid.filter(func(i): return region_nodes[i].get("type", "") != "EXIT")
		if valid.is_empty():
			return current_node

	return valid.pick_random()

# ------------------------
# ENCOUNTER
# ------------------------

func _get_boss_encounter(node_data) -> Variant:
	var boss_name = node_data.get("boss", "")
	if boss_name == "":
		return null
	for monster in monster_db:
		if monster.get("Name", "") == boss_name:
			return monster
	push_error("Boss não encontrado no banco de monstros: " + boss_name)
	return null

func _pick_encounter_monster():
	var pool = []
	for monster in monster_db:
		#print(monster)
		if monster.get("Location", "") != current_region:
			print(current_region)
			print(monster.get("Location", ""))
			continue
		var rarity = monster.get("Rarity", null)
		if rarity == null or (typeof(rarity) != TYPE_INT and typeof(rarity) != TYPE_FLOAT) or rarity <= 0:
			continue
		pool.append({"data": monster, "weight": rarity})

	if pool.is_empty():
		print('EMPTY POOL')
		return null

	var total = 0
	for entry in pool:
		total += int(entry["weight"])

	var roll = randi() % total
	var cumulative = 0
	for entry in pool:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry["data"]

	return pool[-1]["data"]

# ------------------------
# VISIT
# ------------------------

func register_visit():
	var key = get_node_key()
	MyEventBus.emit("register_visit",{"key":key})

# ------------------------
# TEXT SYSTEM
# ------------------------

func get_arrival_text(node, use_default=false):
	if not node.has("arrival"):
		return ""
	
	var arrival = node["arrival"]
	
	if arrival.has(current_entrance) and not use_default:
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
				ok = _evaluate_node(p["condition"], node_key)
			
			if ok and p.has("chance"):
				if randf() > p["chance"]:
					ok = false
			
			if ok:
				valid.append(p)
	
	if valid.is_empty():
		return node.get("name", "???")
	
	var chosen = valid.pick_random()
	
	if chosen.has("effect"):
		MyEventBus.emit("apply_effect",chosen["effect"])
	
	return chosen.get("text", "")


# ------------------------
# BACKDROP
# ------------------------

func _transition_backdrop(region_name):
	if region_db.has(region_name):
		_set_backdrop(region_db[region_name].get("Backdrop", ""))
	elif town_db.has(region_name):
		_set_backdrop(town_db[region_name].get("Backdrop", ""))

func _set_backdrop(filename):
	if not is_node_ready() or backdrop == null or filename == "":
		return
	var path = "res://assets/backgrounds/" + filename
	if not ResourceLoader.exists(path):
		push_error("Backdrop não encontrado: " + path)
		return
	var texture = load(path)
	var tween = create_tween()
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): backdrop.texture = texture)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.4)

# ------------------------
# UTILS
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
