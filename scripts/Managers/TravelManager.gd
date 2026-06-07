extends Node

@onready var backdrop = $Backdrop
@onready var back_backdrop = $Backdrop2

enum TravelMode {
	NODE_ACTIONS,
	CHOOSING_EXIT,
	REGION_EXIT,
	TOWN,
	TOWN_LEAVE_CONFIRM,
	SHOP,
	INVENTORY_MENU,
	INVENTORY_ITEMS,
	INVENTORY_WEAPONS,
	INVENTORY_ARMOR,
	INVENTORY_MISC
}

var condition_callback = null

var mode = TravelMode.NODE_ACTIONS

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
var events_db = {}

var current_town = ""
var current_town_data = null

var current_shop_name = ""
var current_shop_data = null
var _greeted_shops: Dictionary = {}
var _shop_from_event := false

var current_region = "":
	set(value):
		current_region = value
		if game_state:
			game_state["region"] = value
		_transition_backdrop(value)
		MyEventBus.emit("region_changed", {"region": value})
var current_node = 0
var current_entrance = 1

var used_node_action = false
var current_node_data = null
var current_backdrop = ""

func _ready():
	world_data = load_json("res://Database/area_nodes.json")
	monster_db = load_json("res://Database/monsters.json")
	region_db = load_json("res://Database/regions.json")
	town_db = load_json("res://Database/towns.json")
	items_db = load_json("res://Database/items.json")
	events_db = load_json("res://Database/events.json")

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
		_shop_from_event = true
		enter_shop(data.get("name", "Merchant"), data.get("data", {}))
	)
	MyEventBus.subscribe("enter_town_event", func(data):
		enter_town(data.get("town", ""))
	)
	MyEventBus.subscribe("give_region_item_pick", func(_data):
		var treasure: Array = region_db.get(current_region, {}).get("Treasure", [])
		if treasure.is_empty():
			MyEventBus.emit("give_region_item_picked", {"item": ""})
			return
		var item: String = _pick(treasure)
		MyEventBus.emit("give_region_item_picked", {"item": item})
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
			print('EXIT CHOICE')
			handle_exit_choice(choice)

		TravelMode.REGION_EXIT:
			_handle_region_exit()

		TravelMode.TOWN:
			_handle_town_action(choice)

		TravelMode.TOWN_LEAVE_CONFIRM:
			_handle_leave_confirm(choice)

		TravelMode.SHOP:
			_handle_shop_action(choice)

		TravelMode.INVENTORY_MENU:
			_handle_inventory_menu(choice)

		TravelMode.INVENTORY_ITEMS:
			_handle_inventory_items(choice)

		TravelMode.INVENTORY_WEAPONS:
			_handle_inventory_weapons(choice)

		TravelMode.INVENTORY_ARMOR:
			_handle_inventory_armor(choice)

		TravelMode.INVENTORY_MISC:
			_handle_inventory_misc(choice)

# ------------------------
# NODES
# ------------------------

func show_node():
	MyEventBus.emit("clear_text",{})
	show_node_text(true)
	current_entrance = "default"
	if current_node_data.get("type", "") == "EXIT":
		_show_region_exit_prompt()
	else:
		show_node_actions()

func enter_node(node_index, entrance, register: bool = true, node_data_override: Dictionary = {}, used_action: bool = false):
	_set_current_node(node_index, entrance, node_data_override)

	if register:
		register_visit()
	used_node_action = used_action

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
	mode = TravelMode.NODE_ACTIONS
	if game_manager and game_manager.game_state.has("player"):
		if game_manager.game_state["player"].get_hp() > 0:
			SaveManager.save(game_manager.current_slot, game_manager)
	var node_action = current_node_data.get("action", {}) if current_node_data else {}
	var action_name = node_action.get("name", "Search for Monsters")
	var action_tooltip = node_action.get("tooltip", "Stay in place and look for monsters to fight")
	print(used_node_action)
	print(node_action)
	print(node_action.get("repeatable", true))
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
	MyEventBus.emit("add_progress", {"progress": 0, "region":next_name})
	_full_heal_player()
	if town_db.has(next_name):
		enter_town(next_name)
	else:
		current_region = next_name
		enter_node(0, "default")

# ------------------------
# ACTIONS
# ------------------------

func handle_node_action(choice):
	print(choice)
	if choice.get("type") == "node_action":
		await _handle_node_specific_action(choice.get("data", {}))
		return
	match choice["text"]:
		"Continue":
			mode = TravelMode.CHOOSING_EXIT
			show_exit_choices()

		"Inventory":
			_show_inventory_menu()

		"Rest":
			print("Rest TBD")

func _handle_node_specific_action(action_data: Dictionary) -> void:
	var event_name = action_data.get("event", "")
	print(event_name)
	if event_name != "":
		var event_def = events_db.get(event_name, {})
		print('EVENT DEF')
		print(event_def)
		if not event_def.is_empty():
			var stopped = await _run_node_event(event_def)
			if not action_data.get("repeatable", true):
				game_state["used_events"][event_name] = true
			used_node_action = true
			# if not stopped:
			# 	show_node_actions()
			return
		push_warning("Node action event not found: " + event_name)
	game_state["used_events"][event_name] = true
	used_node_action = true
	var monster = _pick_encounter_monster()
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

func enter_town(town_name):
	current_town = town_name
	current_town_data = town_db[town_name]
	current_region = town_name
	MyEventBus.emit("clear_text", {})
	var arrival = current_town_data.get("arrival", [])
	var ambience = current_town_data.get("ambience", [])
	var text = _pick(arrival) if not arrival.is_empty() else town_name
	if not ambience.is_empty():
		text += "\n\n" + _pick(ambience)
	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_town_actions()

func return_to_town():
	MyEventBus.emit("clear_text", {})
	var arrival = current_town_data.get("shop_exit", [])
	var ambience = current_town_data.get("ambience", [])
	var text = _pick(arrival) if not arrival.is_empty() else "You go back out into %s." % [current_town]
	if not ambience.is_empty():
		text += "\n\n" + _pick(ambience)
	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_town_actions()

func show_town_actions():
	if game_manager:
		SaveManager.save(game_manager.current_slot, game_manager)
	var choices = []
	for shop_name in current_town_data.get("Shops", {}):
		choices.append({"text": shop_name, "type": "action", "tooltip": "Visit " + shop_name})
	choices.append({"text": "Leave", "type": "back", "tooltip": "Leave " + current_town})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Where would you like to go?"})
	mode = TravelMode.TOWN

func _handle_town_action(choice):
	if choice.get("type") == "back":
		_show_leave_confirm()
		return
	var shop_name = choice.get("text", "")
	var shops = current_town_data.get("Shops", {})
	if shops.has(shop_name):
		var shop = shops[shop_name]
		if shop.get("Kind", "") == "Shop":
			enter_shop(shop_name, shop)
			return
	print("Unhandled town action: " + shop_name)

func _show_leave_confirm():
	MyEventBus.emit("show_choices", {"choices": [
		{"text": "Yes", "type": "action", "tooltip": "Leave " + current_town},
		{"text": "No",  "type": "back",   "tooltip": "Stay in " + current_town}
	], "header": "Leave " + current_town + "?"})
	mode = TravelMode.TOWN_LEAVE_CONFIRM

func _handle_leave_confirm(choice):
	if choice.get("text") == "Yes":
		var next_name = current_town_data.get("Next", "")
		if next_name == "" or (not world_data.has(next_name) and not town_db.has(next_name)):
			push_error("Próxima região inválida para " + current_town + ": " + next_name)
			return
		var exit_text = current_town_data.get("ExitTxt", "")
		if exit_text != "":
			MyEventBus.emit("continue_text", {"text": exit_text})
			await game_manager._gm_wait_for_continue()
		var exit_event_name = current_town_data.get("ExitEvent", "")
		if exit_event_name != "":
			var event_def = events_db.get(exit_event_name, {})
			if not event_def.is_empty() and not game_state["used_events"].get(exit_event_name, false):
				await _run_node_event(event_def)
				if not event_def.get("repeatable", true):
					game_state["used_events"][exit_event_name] = true
		_full_heal_player()
		current_region = next_name
		enter_node(0, "default")
	else:
		show_town_actions()

func _full_heal_player():
	if not game_state or not game_state.has("player"):
		return
	var player = game_state["player"]
	player.heal(player.get_mhp())
	player.restore_mp(player.get_mmp())

# ------------------------
# SHOP
# ------------------------

func enter_shop(shop_name: String, shop_data: Dictionary):
	current_shop_name = shop_name
	current_shop_data = shop_data
	mode = TravelMode.SHOP

	var shop_backdrop = shop_data.get("Backdrop", "")
	if shop_backdrop != "":
		_set_backdrop(shop_backdrop)

	MyEventBus.emit("clear_text", {})

	var greeted = _greeted_shops.get(current_town + ":" + shop_name, false)
	var text = ""
	if not greeted:
		text = shop_data.get("WelcomeText", "")
		_greeted_shops[current_town + ":" + shop_name] = true
	else:
		var other = shop_data.get("OtherText", [])
		if not other.is_empty():
			text = _pick(other)

	var ambience = shop_data.get("ambience", [])
	if not ambience.is_empty():
		var amb = _pick(ambience)
		text = (text + "\n\n" + amb) if text != "" else amb

	if text == "":
		text = "Welcome to " + shop_name + "."

	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_shop_stock()

func show_shop_stock():
	var stock = current_shop_data.get("Stock", {})
	var shop_type = current_shop_data.get("ShopType", "Item")
	var gold = game_state["gold"] if game_state else 0
	var choices = []

	for item_name in stock:
		var price: int = int(stock[item_name])
		var data = _get_shop_item_data(item_name, shop_type)
		var label = "%s — %dG" % [item_name, price]

		if shop_type == "Equip" and _player_has_equip(item_name):
			choices.append({
				"text": item_name + " — SOLD OUT",
				"type": "shop_sold_out",
				"disabled": true,
				"disabled_text": item_name + " — SOLD OUT",
				"disabled_tooltip": "You already own this item"
			})
		elif gold >= price:
			choices.append({
				"text": label,
				"type": "shop_buy",
				"data": {"item": item_name, "price": price, "shop_type": shop_type},
				"tooltip": _format_shop_tooltip(item_name, data, shop_type)
			})
		else:
			choices.append({
				"text": label,
				"type": "shop_buy_disabled",
				"disabled": true,
				"disabled_text": label,
				"disabled_tooltip": "Not enough gold (you have %dG)" % gold
			})

	choices.append({"text": "Leave", "type": "back", "tooltip": "Return to " + current_town})
	MyEventBus.emit("show_choices", {
		"choices": choices,
		"header": "%s   [color=yellow]%dG[/color]" % [current_shop_name, gold]
	})

func _handle_shop_action(choice):
	if choice.get("type") == "back":
		_transition_backdrop(current_region)
		if _shop_from_event:
			_shop_from_event = false
			mode = TravelMode.NODE_ACTIONS
			MyEventBus.emit("event_shop_closed", {})
		else:
			mode = TravelMode.TOWN
			return_to_town()
		return
	if choice.get("type") == "shop_buy":
		var data = choice.get("data", {})
		await _buy_item(data["item"], data["price"])

func _buy_item(item_name: String, price: int):
	if not game_state or game_state["gold"] < price:
		return

	game_state["gold"] -= price

	var player = game_state["player"]
	if not player.data.has("Inventory"):
		player.data["Inventory"] = {}
	# player.data["Inventory"][item_name] = player.data["Inventory"].get(item_name, 0) + 1

	var remaining = game_state["gold"]
	MyEventBus.emit("continue_text", {
		"text": "Bought [b]%s[/b] for [color=yellow]%dG[/color].\n[color=yellow]Gold: %dG[/color]" % [item_name, price, remaining]
	})
	MyEventBus.emit_and_await("give_item", {"item": item_name}, "give_item_done")
	
	await game_manager._gm_wait_for_continue()
	show_shop_stock()

func _player_has_equip(item_name: String) -> bool:
	var player = game_state["player"]
	var inv = player.get_inventory()
	if inv.get(item_name, 0) > 0:
		return true
	for slot in player.equipment:
		var item = player.equipment[slot]
		if typeof(item) == TYPE_DICTIONARY and item.get("name", "") == item_name:
			return true
	return false

func _get_shop_item_data(item_name: String, shop_type: String) -> Dictionary:
	match shop_type:
		"Item":
			return items_db.get(item_name, {})
		"Equip":
			if game_manager.weapon_db.has(item_name):
				return game_manager.weapon_db[item_name]
			return game_manager.armor_db.get(item_name, {})
	return {}

func _format_shop_tooltip(item_name: String, data: Dictionary, shop_type: String) -> String:
	if data.is_empty():
		return item_name
	match shop_type:
		"Item":
			return _format_item_tooltip(item_name, data)
		"Equip":
			return _format_equip_tooltip(data)
	return item_name

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
		show_node_actions()
		return

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
	_set_current_node(next_node, current_entrance)
	used_node_action = false
	register_visit()

	MyEventBus.emit("node_entered", {
		"node": current_node_data,
		"entrance": current_entrance
	})
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
		print('EMPTY POOL')
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
		if not events_db.get(ref,{}).get("repeatable", true) and game_state["used_events"].get(ref, false):
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
# INVENTORY
# ------------------------

func _show_inventory_menu():
	mode = TravelMode.INVENTORY_MENU
	MyEventBus.emit("show_choices", {
		"choices": [
			{"text": "Items",   "type": "action", "tooltip": "Use consumable items"},
			{"text": "Weapons", "type": "action", "tooltip": "Change your equipped weapon"},
			{"text": "Armor",   "type": "action", "tooltip": "Change your equipped armor"},
			{"text": "Misc",    "type": "action", "tooltip": "View other items"},
			{"text": "Back",    "type": "back",   "tooltip": "Return"}
		],
		"header": "Inventory"
	})

func _handle_inventory_menu(choice):
	if choice.get("type") == "back":
		show_node_actions()
		return
	match choice["text"]:
		"Items":   _show_inventory_items()
		"Weapons": _show_inventory_weapons()
		"Armor":   _show_inventory_armor()
		"Misc":    _show_inventory_misc()

# --- Items ---

func _show_inventory_items():
	mode = TravelMode.INVENTORY_ITEMS
	var player = game_state["player"]
	var inv = player.get_inventory()
	var choices = []
	var invalid_choices = []
	for item_name in inv:
		var data = items_db.get(item_name, {})
		if data.is_empty() or not data.get("consumable", false):
			continue
		var count = inv[item_name]
		var label = data.get("nome", item_name) + " x%d" % count
		if data.get("type", "self") != "self" or data.get("battle_only", false):
			invalid_choices.append({
				"text": label, "type": "item_disabled",
				"disabled": true, "disabled_text": label,
				"disabled_tooltip": "Can only be used in combat"
			})
		else:
			choices.append({
				"text": label, "type": "item", "data": item_name,
				"tooltip": _format_item_tooltip(item_name, data)
			})
	choices = choices + invalid_choices
	if choices.is_empty():
		choices.append({
			"text": "(No items)", "type": "none",
			"disabled": true, "disabled_text": "(No items)"
		})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Items", "fixed_sizes": fixed_sizes})

func _handle_inventory_items(choice):
	if choice.get("type") == "back":
		_show_inventory_menu()
		return
	if choice.get("type") == "item":
		await _use_item_overworld(choice.get("data", ""))
		_show_inventory_items()

func _use_item_overworld(item_name: String):
	var player = game_state["player"]
	var data = items_db.get(item_name, {})
	if data.is_empty():
		return
	var stats = data.get("stats", {})
	var lines = ["Used [color=cyan]%s[/color]!" % data.get("nome", item_name)]
	var mgt = stats.get("mgt", 0)
	if mgt < 0:
		var heal_amt = abs(mgt)
		player.heal(heal_amt)
		lines.append("[color=green]+%d HP[/color]" % heal_amt)
	var mp = stats.get("mp", 0)
	if mp < 0:
		var mp_amt = abs(mp)
		player.restore_mp(mp_amt)
		lines.append("[color=cyan]+%d MP[/color]" % mp_amt)
	var effect = data.get("effect", "none")
	if effect == "stat_clear":
		lines.append("[color=green]Status effects cleared![/color]")
	player.consume_item(item_name)
	MyEventBus.emit("continue_text", {"text": "\n".join(lines)})
	await game_manager._gm_wait_for_continue()

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

# --- Weapons ---

func _show_inventory_weapons():
	mode = TravelMode.INVENTORY_WEAPONS
	var player = game_state["player"]
	var inv = player.get_inventory()
	var equipped = player.get_weapon()
	var equipped_name = equipped.get("name", "") if equipped and not equipped.is_empty() else ""
	var choices = []
	if not equipped_name.is_empty():
		choices.append({
			"text": "[Equipped] " + equipped_name, "type": "none",
			"disabled": true, "disabled_text": "[Equipped] " + equipped_name,
			"disabled_tooltip": _format_equip_tooltip(equipped)
		})
	for item_name in inv:
		if not game_manager.weapon_db.has(item_name):
			continue
		choices.append({
			"text": item_name, "type": "weapon", "data": item_name,
			"tooltip": _format_equip_tooltip(game_manager.weapon_db[item_name])
		})
	if choices.is_empty() or (choices.size() == 1 and choices[0]["type"] == "none"):
		choices.append({
			"text": "(No other weapons)", "type": "none",
			"disabled": true, "disabled_text": "(No other weapons)"
		})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Weapons", "fixed_sizes":fixed_sizes})

func _handle_inventory_weapons(choice):
	if choice.get("type") == "back":
		_show_inventory_menu()
		return
	if choice.get("type") == "weapon":
		await _equip_item("weapon", choice.get("data", ""))
		_show_inventory_weapons()

# --- Armor ---

func _show_inventory_armor():
	mode = TravelMode.INVENTORY_ARMOR
	var player = game_state["player"]
	var inv = player.get_inventory()
	var equipped = player.equipment.get("armor", {})
	var equipped_name = ""
	if equipped and typeof(equipped) == TYPE_DICTIONARY and not equipped.is_empty():
		equipped_name = equipped.get("name", "")
	var choices = []
	if not equipped_name.is_empty():
		choices.append({
			"text": "[Equipped] " + equipped_name, "type": "none",
			"disabled": true, "disabled_text": "[Equipped] " + equipped_name,
			"disabled_tooltip": _format_equip_tooltip(equipped)
		})
	for item_name in inv:
		if not game_manager.armor_db.has(item_name):
			continue
		choices.append({
			"text": item_name, "type": "armor", "data": item_name,
			"tooltip": _format_equip_tooltip(game_manager.armor_db[item_name])
		})
	if choices.is_empty() or (choices.size() == 1 and choices[0]["type"] == "none"):
		choices.append({
			"text": "(No other armor)", "type": "none",
			"disabled": true, "disabled_text": "(No other armor)"
		})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Armor", "fixed_sizes":fixed_sizes})

func _handle_inventory_armor(choice):
	if choice.get("type") == "back":
		_show_inventory_menu()
		return
	if choice.get("type") == "armor":
		await _equip_item("armor", choice.get("data", ""))
		_show_inventory_armor()

# --- Equip shared ---

func _equip_item(slot: String, item_name: String):
	var player = game_state["player"]
	var db = game_manager.weapon_db if slot == "weapon" else game_manager.armor_db
	var new_item = db.get(item_name, {})
	if new_item.is_empty():
		return
	var old_item = player.equipment.get(slot, {})
	if old_item and typeof(old_item) == TYPE_DICTIONARY and not old_item.is_empty():
		var old_name = old_item.get("name", "")
		if not old_name.is_empty():
			player.data["Inventory"][old_name] = player.data["Inventory"].get(old_name, 0) + 1
	player.consume_item(item_name)
	player.equip(slot, new_item)
	MyEventBus.emit("continue_text", {
		"text": "[color=#00E676]%s equipped![/color]" % new_item.get("name", item_name)
	})
	await game_manager._gm_wait_for_continue()

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

# --- Misc ---

func _show_inventory_misc():
	mode = TravelMode.INVENTORY_MISC
	var player = game_state["player"]
	var inv = player.get_inventory()
	var choices = []
	for item_name in inv:
		if items_db.has(item_name) or game_manager.weapon_db.has(item_name) or game_manager.armor_db.has(item_name):
			continue
		var count = inv[item_name]
		choices.append({
			"text": "%s x%d" % [item_name, count], "type": "none",
			"disabled": true, "disabled_text": "%s x%d" % [item_name, count]
		})
	if choices.is_empty():
		choices.append({
			"text": "(Nothing here)", "type": "none",
			"disabled": true, "disabled_text": "(Nothing here)"
		})
	choices.append({"text": "Back", "type": "back"})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Misc"})

func _handle_inventory_misc(choice):
	if choice.get("type") == "back":
		_show_inventory_menu()

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
