extends Node

@onready var backdrop = $Backdrop

enum TravelMode {
	NODE_ACTIONS,
	CHOOSING_EXIT
}

var condition_callback = null

var mode = TravelMode.NODE_ACTIONS

var game_manager
var game_state

var world_data = {}
var monster_db = []
var region_db = {}

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

# ------------------------
# NODES
# ------------------------

func show_node():
	MyEventBus.emit("clear_text",{})
	show_node_text(true)
	current_entrance = "default"
	mode = TravelMode.NODE_ACTIONS
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

	var encounter_rate = current_node_data.get("encounter_rate", 0.75)
	var monster = null
	var encounter_roll = randf()
	#print(encounter_roll)
	if encounter_roll < encounter_rate:
		print("entrou")
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
	
	return valid.pick_random()

# ------------------------
# ENCOUNTER
# ------------------------

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
	if not is_node_ready() or backdrop == null:
		return
	if not region_db.has(region_name):
		return
	var filename = region_db[region_name].get("Backdrop", "")
	if filename == "":
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
