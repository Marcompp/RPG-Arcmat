class_name TravelManager
extends Node

@onready var backdrop = $Backdrop
@onready var back_backdrop = $Backdrop2

enum TravelMode {
	NODE_ACTIONS,
	CHOOSING_EXIT,
	REGION_EXIT,
	TOWN,
	TOWN_LEAVE_CONFIRM,
	TOWN_SHOP_MENU,
	TOWN_EXPLORE_MENU,
	SHOP,
	INVENTORY_MENU,
	INVENTORY_ITEMS,
	INVENTORY_WEAPONS,
	INVENTORY_ARMOR,
	INVENTORY_MISC,
	INVENTORY_TRINKETS,
	REST_MENU
}

const MAX_SPELLS = 4

var condition_callback = null

var mode = TravelMode.NODE_ACTIONS
var _in_town_context: bool = false

var game_manager
var game_state
var rng: RandomNumberGenerator

func _pick(arr: Array):
	return arr[rng.randi() % arr.size()]

var world_data = {}
var monster_db = []
var region_db = {}
var town_db = {}
var items_db = {}
var trinkets_db = {}
var events_db = {}

var current_town = ""
var current_town_data = null

var _town: TownManager
var _shop: ShopManager
var _inventory: InventoryManager

var current_region = "":
	set(value):
		current_region = value
		if game_state:
			game_state["region"] = value
		_transition_backdrop(value)
		MyEventBus.emit("region_changed", {"region": value})
var current_node = 0
var current_entrance = ""

var used_node_action = false
var current_node_data = null
var current_backdrop = ""

func _ready():
	world_data = load_json("res://Database/area_nodes.json")
	monster_db = load_json("res://Database/monsters.json")
	region_db = load_json("res://Database/regions.json")
	town_db = load_json("res://Database/towns.json")
	items_db    = load_json("res://Database/items.json")
	trinkets_db = load_json("res://Database/trinkets.json")
	events_db   = load_json("res://Database/events.json")

	MyEventBus.subscribe("character_selected", func(_data):
		current_region = "Apple Woods"
	)
	MyEventBus.subscribe("show_node_text", func(_data):
		show_node_text()
	)
	MyEventBus.subscribe("show_node_actions", func(_data):
		show_node_actions()
	)
	MyEventBus.subscribe("show_node", func(_data):
		show_node()
	)
	MyEventBus.subscribe("set_backdrop", func(data):
		_set_backdrop(data.get('backdrop',''))
	)
	MyEventBus.subscribe("modify_node", func(data):
		current_node_data.merge(data,true)
	)
	MyEventBus.subscribe("exit_node", func(exit):
		handle_exit(exit)
	)
	MyEventBus.subscribe("open_event_shop", func(data):
		_shop._shop_from_event = true
		_shop.enter_shop(data.get("name", "Merchant"), data.get("data", {}))
	)
	MyEventBus.subscribe("enter_town_event", func(data):
		_town.enter_town(data.get("town", ""))
	)
	MyEventBus.subscribe("give_region_item_pick", func(_data):
		var treasure: Array = region_db.get(current_region, {}).get("Treasure", [])
		treasure = _get_valid_treasure(treasure)
		if treasure.is_empty():
			MyEventBus.emit("give_region_item_picked", {"item": "Potion"})
			return
		var item: String = _pick(treasure)
		MyEventBus.emit("give_region_item_picked", {"item": item})
	)

	_town = TownManager.new(self)
	_shop = ShopManager.new(self)
	_inventory = InventoryManager.new(self)

	if world_data.is_empty():
		push_error("Falha ao carregar o JSON")
		return

# ------------------------
# FLOW
# ------------------------

func _evaluate_node(condition, curr_node):
	if condition_callback == null:
		return true
	
	if typeof(condition) == TYPE_DICTIONARY:
		if condition.get("visit_once", false):
			var key = current_region + ":" + str(curr_node)
			if game_state and game_state["visited_nodes"].get(key, false):
				return false
		
		if condition.get("no_repeat", false) and curr_node == current_node:
			return false
		var filtered = condition.duplicate()
		filtered.erase("visit_once")
		filtered.erase("no_repeat")
		if filtered.is_empty():
			return true
		return condition_callback.call(filtered, curr_node)
	
	return condition_callback.call(condition,curr_node)

func _set_current_node(node_index, entrance, node_data={}):
	current_node = node_index
	current_entrance = entrance
	var region = world_data[current_region]
	current_node_data = region[current_node].duplicate()
	current_node_data.merge(node_data, true)
	var node_backdrop = current_node_data.get("backdrop", "")
	if node_backdrop != "":
		_set_backdrop(node_backdrop)
	else:
		_transition_backdrop(current_region)
	
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
			handle_exit_choice(choice)

		TravelMode.REGION_EXIT:
			_handle_region_exit()

		TravelMode.TOWN:
			_town.handle_action(choice)

		TravelMode.TOWN_LEAVE_CONFIRM:
			_town.handle_leave_confirm(choice)

		TravelMode.TOWN_SHOP_MENU:
			_town.handle_shop_submenu(choice)

		TravelMode.TOWN_EXPLORE_MENU:
			_town.handle_explore_submenu(choice)

		TravelMode.SHOP:
			_shop.handle_action(choice)

		TravelMode.INVENTORY_MENU:
			_inventory.handle_menu(choice)

		TravelMode.INVENTORY_ITEMS:
			_inventory.handle_items(choice)

		TravelMode.INVENTORY_WEAPONS:
			_inventory.handle_weapons(choice)

		TravelMode.INVENTORY_ARMOR:
			_inventory.handle_armor(choice)

		TravelMode.INVENTORY_MISC:
			_inventory.handle_misc(choice)

		TravelMode.INVENTORY_TRINKETS:
			_inventory.handle_trinkets(choice)

		TravelMode.REST_MENU:
			_handle_rest_menu(choice)

# ------------------------
# NODES
# ------------------------

func show_node():
	MyEventBus.emit("clear_text",{})
	show_node_text(true)
	current_entrance = "default"  # reset after showing arrival text
	if current_node_data.get("type", "") == "EXIT":
		_show_region_exit_prompt()
	else:
		show_node_actions()

func _setup_node(node_index: int, entrance: String, register: bool = true, node_data_override: Dictionary = {}, used_action: bool = false):
	_set_current_node(node_index, entrance, node_data_override)
	var _base_state: int = rng.state
	if not current_node_data.has("_exit_rng_states"):
		var _node_exits = current_node_data.get("exits", [])
		var _exit_states: Array = []
		for i in range(_node_exits.size()):
			rng.state = _base_state
			for _j in range(i + 1):
				rng.randi()
			_exit_states.append(rng.state)
			current_node_data["_exit_rng_states"] = _exit_states
	if not current_node_data.has("_rng_state"):
		current_node_data["_rng_state"] = _base_state
	rng.state = _base_state
	used_node_action = used_action
	if register:
		register_visit()
	MyEventBus.emit("node_entered", {
		"node": current_node_data,
		"entrance": entrance
	})

func enter_node(node_index, entrance, register: bool = true, node_data_override: Dictionary = {}, used_action: bool = false):
	_setup_node(node_index, entrance, register, node_data_override, used_action)
	show_node()

func get_node_text(use_default=false):
	var text = ""
	text += get_arrival_text(current_node_data, use_default)
	text += "\n\n" + get_dynamic_paragraph(current_node_data)
	current_entrance = ""
	return text

func show_node_text(use_default=false):
	var text = get_node_text(use_default)
	MyEventBus.emit("dialogue", {
		"text": text,
		"choices": [],
		"linebreak": false
	})

func show_node_actions():
	_in_town_context = false
	mode = TravelMode.NODE_ACTIONS
	if game_manager and game_manager.game_state.has("player"):
		if game_manager.game_state["player"].get_hp() > 0:
			SaveManager.save(game_manager.current_slot, game_manager)
	var node_action = current_node_data.get("action", {}) if current_node_data else {}
	var action_name = node_action.get("name", "Search for Monsters")
	var action_tooltip = node_action.get("tooltip", "Stay in place and look for monsters to fight")
	var event_key = node_action.get("event", "")
	var event_entry = events_db.get(event_key, {})
	var action_used = game_state and (node_action.get("disabled", false) \
		or (not node_action.get("repeatable", true) and used_node_action) \
		or (not event_entry.get("repeatable", true) and \
			game_state["used_events"].get(event_key, false)))
	var action_choice: Dictionary
	if action_used:
		action_choice = {
			"text": action_name,
			"type": "node_action_done",
			"disabled": true,
			"disabled_text": action_name,
			"disabled_tooltip": node_action.get("disabled_tooltip", "Already done"),
		}
	else:
		action_choice = {
			"text": action_name,
			"type": "node_action",
			"tooltip": action_tooltip,
			"data": node_action
		}
	MyEventBus.emit("show_choices",{'choices':[
		{
			"text": "Continue",
			"type": "action",
			"tooltip": "Continue your journey"
		},
		action_choice,
		{
			"text": "Inventory",
			"type": "action",
			"tooltip": "View your inventory"
		},{
			"text": "Rest",
			"type": "action",
			"tooltip": "Save and close your session"
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
	MyEventBus.emit("add_progress", {"progress": 0, "region":next_name})
	_full_heal_player()
	if town_db.has(next_name):
		_town.enter_town(next_name)
	else:
		current_region = next_name
		enter_node(0, "default")

# ------------------------
# ACTIONS
# ------------------------

func handle_node_action(choice):
	if choice.get("type") == "node_action":
		await _handle_node_specific_action(choice.get("data", {}))
		return
	match choice["text"]:
		"Continue":
			mode = TravelMode.CHOOSING_EXIT
			show_exit_choices()

		"Inventory":
			_inventory.show_menu()

		"Rest":
			_show_rest_menu()

func _show_rest_menu():
	mode = TravelMode.REST_MENU
	MyEventBus.emit("show_choices", {
		"choices": [
			{"text": "Back to title screen", "type": "action", "tooltip": "Save and return to the title screen"},
			{"text": "Close Game",           "type": "action", "tooltip": "Save and quit the game"},
			{"text": "Back",                 "type": "back",   "tooltip": "Return to node actions"}
		],
		# "header": "Save and close session?"
	})

func _handle_rest_menu(choice):
	match choice.get("text"):
		"Back to title screen":
			game_manager.show_main_menu()
		"Close Game":
			get_tree().quit()
		_:
			if _in_town_context:
				_town.show_town_actions()
			else:
				show_node_actions()

func _handle_node_specific_action(action_data: Dictionary) -> void:
	if current_node_data.has("_rng_state"):
		rng.state = current_node_data["_rng_state"]
	var event_name = action_data.get("event", "")
	if event_name != "":
		var event_def = events_db.get(event_name, {})
		if not event_def.is_empty():
			if not action_data.get("repeatable", true):
				game_state["used_events"][event_name] = true
			used_node_action = true
			await _run_node_event(event_def)
			current_node_data["_rng_state"] = rng.state
			return
		push_warning("Node action event not found: " + event_name)
	if event_name != "":
		game_state["used_events"][event_name] = true
	used_node_action = true
	var monster = _pick_encounter_monster()
	current_node_data["_rng_state"] = rng.state
	if monster:
		MyEventBus.emit("continue_text", {
			"text": "Suddenly, a [b]" + monster["Name"] + "[/b] appears!"
		})
		await game_manager._gm_wait_for_continue()
		MyEventBus.emit("start_combat", {"enemy":monster})
		var result = await MyEventBus.await_event("post_combat")
		if result.get("victory", false):
			show_node()
	else:
		MyEventBus.emit("continue_text", {"text": "You search the area, but find nothing..."})
		await game_manager._gm_wait_for_continue()
		show_node_actions()

# ------------------------
# TOWN
# ------------------------

func enter_town(town_name: String) -> void:
	_town.enter_town(town_name)

func _full_heal_player():
	if not game_state or not game_state.has("player"):
		return
	var player = game_state["player"]
	player.heal(player.get_mhp())
	player.restore_mp(player.get_mmp())

# ------------------------
# EXITS
# ------------------------

func show_exit_choices():
	var choices = []
	
	var exits = current_node_data.get("exits", [])
	for i in range(exits.size()):
		var exit = exits[i]
		choices.append({
			"text": exit.get("choice", "Continue"),
			"type": "exit",
			"data": exit,
			"exit_index": i
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
		show_node_actions()
		return

	var exit_index: int = choice.get("exit_index", -1)
	var exit_states: Array = current_node_data.get("_exit_rng_states", [])
	if exit_index >= 0 and exit_index < exit_states.size():
		rng.state = exit_states[exit_index]

	var exit = choice.get("data", {})
	var event = {}
	if exit.has('events'):
		event = _pick_event(exit['events'])
	if event:
		await _run_node_event(event)
	else:
		handle_exit(exit)

func handle_exit(exit):
	current_entrance = exit.get("leads_to", current_entrance)
	
	MyEventBus.emit("add_progress", {"progress": exit.get("value", 1), "region": current_region})
	apply_exit_vars(exit)

	var next_node = pick_next_node(current_entrance)
	
	var travel_text = exit.get("travel_text", "You press on for a while.")
	var text = travel_text + "\n\n...\n[wait=0.2]\n...[wait=0.2]"
	MyEventBus.emit("dialogue", {"text": text})
	await game_manager._gm_wait_for_writing()
	_setup_node(next_node, current_entrance)
	text = get_node_text(false)
	MyEventBus.emit("continue_text", {"text": text})

	var boss_monster = _get_boss_encounter(current_node_data)
	var monster = null
	var event = null
	if boss_monster:
		monster = boss_monster
	else:
		var encounter_rate = exit.get('encounter_rate', current_node_data.get("encounter_rate", 0.75))
		var encounter_roll = rng.randf()
		if encounter_roll < encounter_rate:
			monster = _pick_monster(exit.get("enemies", current_node_data.get("enemies", []) if current_node_data else []))
	if monster:
		MyEventBus.emit("continue_text", {
			"text": "Suddenly, a [b]" + monster["Name"] + "[/b] appears!"
		})
		await game_manager._gm_wait_for_continue()
		MyEventBus.emit("start_combat", {"enemy":monster})
		var result = await MyEventBus.await_event("post_combat")
		if result.get("victory", false):
			show_node()
	else:
		if not exit.get('forbid_event',false):
			event = _pick_node_event(current_node_data)
		if event:
			await _run_node_event(event)
		else:
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
		push_error("pick_next_node: no valid nodes for entrance '%s' in '%s' — player stuck at node %d" % [entrance, current_region, current_node])
		return current_node

	var region_length = region_db.get(current_region, {}).get("Length", INF)
	var progress = game_state.get("area_progress").get(current_region,0) if game_state else 0
	var region_nodes = world_data[current_region]

	if progress >= region_length:
		var exit_nodes = valid.filter(func(i): return region_nodes[i].get("type", "") == "EXIT")
		if not exit_nodes.is_empty():
			return _pick(exit_nodes)
	else:
		valid = valid.filter(func(i): return region_nodes[i].get("type", "") != "EXIT")
		if valid.is_empty():
			push_error("pick_next_node: all valid nodes for entrance '%s' in '%s' are EXIT type but progress (%d) < length (%d) — player stuck" % [entrance, current_region, progress, region_length])
			return current_node

	return _pick(valid)

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
	var node_enemies: Array = current_node_data.get("enemies", []) if current_node_data else []
	return _pick_monster(node_enemies)

func _pick_monster(node_enemies):
	var pool = []
	for monster in monster_db:
		var rarity = monster.get("Rarity", null)
		if rarity == null or (typeof(rarity) != TYPE_INT and typeof(rarity) != TYPE_FLOAT) or rarity <= 0:
			continue
		if not node_enemies.is_empty():
			if monster.get("Name", "") in node_enemies:
				pool.append({"data": monster, "weight": rarity})
		else:
			if monster.get("Location", "") != current_region:
				continue
			pool.append({"data": monster, "weight": rarity})

	if pool.is_empty():
		return null

	var total = 0
	for entry in pool:
		total += int(entry["weight"])

	var roll = rng.randi() % total
	var cumulative = 0
	for entry in pool:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry["data"]

	return pool[-1]["data"]

func _pick_node_event(node_data: Dictionary) -> Dictionary:
	var event_refs: Array = node_data.get("events", [])
	return _pick_event(event_refs)

func _pick_event(event_refs: Array) -> Dictionary:
	if event_refs.is_empty():
		return {}

	var valid := []
	for ref in event_refs:
		var event_key = ref.get("event", "")
		if not events_db.get(event_key, {}).get("repeatable", true) and game_state["used_events"].get(event_key, false):
			continue
		var cond = ref.get("condition", {})
		if not (cond as Dictionary).is_empty() and not _evaluate_node(cond, current_node):
			continue
		var event_def: Dictionary = events_db.get(ref.get("event", ""), {})
		if event_def.is_empty():
			push_warning("EventReader: unknown event '%s'" % ref.get("event", ""))
			continue
		valid.append({"chance": ref.get("chance", 1.0), "def": event_def})

	var triggered := valid.filter(func(e) -> bool:
		return rng.randf() < e["chance"]
	)

	if triggered.is_empty():
		return {}

	return _pick(triggered)["def"]

func _run_node_event(event_def: Dictionary) -> bool:
	var steps: Array = event_def.get("steps", [])
	if steps.is_empty():
		return false

	var reader := EventReader.new()
	add_child(reader)
	reader.rng = rng
	if condition_callback != null:
		reader.condition_callback = func(cond): return condition_callback.call(cond, current_node)
	reader.stat_callback = func(stat: String) -> int:
		var p = game_manager.game_state.get("player")
		return p.get_stat(stat) if p else 0
	reader.event_callback = func(event_name: String) -> Array:
		return events_db.get(event_name, {}).get("steps", [])
	reader.db_callback = func(type: String, arg: String = "") -> Variant:
		match type:
			"regions": return region_db
			"region_events":
				var nodes: Array = world_data.get(arg, [])
				var arrival_seen := {}
				var action_seen := {}
				var exit_seen := {}
				var arrival_events: Array = []
				var action_events: Array = []
				var exit_events: Array = []
				for node in nodes:
					for ev in node.get("events", []):
						var n: String = ev.get("event", "")
						if n and not arrival_seen.has(n):
							arrival_seen[n] = true
							arrival_events.append(n)
					var action_ev: String = node.get("action", {}).get("event", "")
					if action_ev and not action_seen.has(action_ev):
						action_seen[action_ev] = true
						action_events.append(action_ev)
					for exit in node.get("exits", []):
						for ev in exit.get("events", []):
							var n: String = ev.get("event", "")
							if n and not exit_seen.has(n):
								exit_seen[n] = true
								exit_events.append(n)
				var categories := {}
				if not arrival_events.is_empty():
					categories["Arrival"] = arrival_events
				if not action_events.is_empty():
					categories["Action"] = action_events
				if not exit_events.is_empty():
					categories["Exit"] = exit_events
				return categories
		return null
	await reader.run(steps)
	var stopped: bool = reader.was_stopped
	reader.queue_free()
	return stopped

func _try_node_event(node_data: Dictionary) -> void:
	var event_def = _pick_node_event(node_data)
	if not event_def.is_empty():
		await _run_node_event(event_def)

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
		return _pick(arrival[current_entrance])

	if arrival.has("default"):
		return _pick(arrival["default"])
	
	return ""

func get_dynamic_paragraph(node):
	if not node.has("description"):
		return node.get("name", "???")

	var valid = []

	for p in node["description"]:
		var ok = true

		if typeof(p) == TYPE_STRING:
			valid.append({ "text": p })
		else:
			if p.has("condition"):
				ok = _evaluate_node(p["condition"], current_node)
			
			if ok and p.has("chance"):
				if rng.randf() > p["chance"]:
					ok = false
			
			if ok:
				valid.append(p)
	
	if valid.is_empty():
		return node.get("name", "???")
	
	var chosen = _pick(valid)
	
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
	if filename == "" or filename == current_backdrop:
		return
	if not is_node_ready() or backdrop == null:
		return
	var path = "res://assets/backgrounds/" + filename
	if not ResourceLoader.exists(path):
		push_error("Backdrop não encontrado: " + path)
		return
	current_backdrop = filename
	var texture = load(path)
	back_backdrop.texture = texture
	var tween = create_tween()
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): backdrop.texture = texture)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.4)

# ------------------------
# INVENTORY TOOLTIPS
# ------------------------

func _format_item_tooltip(item_name: String, data: Dictionary) -> String:
	var lines = []
	if data.has("description"):
		lines.append(data["description"]+"\n")

	var stats = data.get("stats", {})
	var mgt = stats.get("mgt", 0)
	if mgt < 0:
		lines.append("Heals %d HP" % abs(mgt))
	var mp = stats.get("mp", 0)
	if mp < 0:
		lines.append("Restores %d MP" % abs(mp))
	var effect = data.get("effect", "none")
	if effect == "stat_clear":
		lines.append("Clears status effects")
	elif effect != "none" and effect != "":
		lines.append("Effect: " + effect.capitalize())
	return "\n".join(lines) if not lines.is_empty() else item_name

func _format_equip_tooltip(item: Dictionary) -> String:
	var lines = [item.get("name", "?")]
	if item.has("description"):
		lines.append(item["description"]+"\n")
	if item.has("wpn_type"):
		lines.append("Type: " + item["wpn_type"])
	if item.has("element"):
		lines.append("Element: " + item["element"])
	var stats = item.get("stats", {})
	var stat_parts = []
	for s in ["mgt", "acc", "wgt", "crit", "mys", "def"]:
		if stats.has(s):
			stat_parts.append("%s: %d" % [s.to_upper(), stats[s]])
	if not stat_parts.is_empty():
		lines.append("  ".join(stat_parts))
	var effect = item.get("effect", "none")
	if effect != "none" and effect != "":
		lines.append("Effect: " + effect.capitalize())
	return "\n".join(lines)

func _format_trinket_tooltip(trinket_name: String, data: Dictionary) -> String:
	var lines = [trinket_name]
	if data.has("description"):
		lines.append(data["description"])
	if data.has("effect_description"):
		lines.append(data["effect_description"])
	return "\n".join(lines)

func _get_valid_treasure(treasure):
	var n_treasure = []
	var known_spells = []
	var known_skills = []
	var inventory = []
	var equipment = []
	var equipped_trinkets = []
	if game_manager and game_manager.game_state.has("player"):
			var player = game_manager.game_state["player"]
			known_spells     = player.get_spells()
			known_skills     = player.get_skills()
			inventory        = player.get_inventory()
			equipment        = player.get_owned_equipment()
			equipped_trinkets = player.get_trinkets()
	for item_name in treasure:
		if item_name.begins_with("Book of "):
			var spell_name = item_name.substr(8)
			if known_spells.has(spell_name) or inventory.has(item_name) or len(known_spells) >= MAX_SPELLS:
				continue
		elif item_name.ends_with(" Scroll"):
			var skill_name = item_name.substr(0, item_name.length() - 7)
			if known_skills.has(skill_name) or inventory.has(item_name):
				continue
		elif equipment.any(func(item): return item.get("name", "") == item_name):
			continue
		elif trinkets_db.has(item_name) and not trinkets_db[item_name].get("stackable", false):
			if item_name in equipped_trinkets or inventory.has(item_name):
				continue
		n_treasure.append(item_name)
	return n_treasure

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
