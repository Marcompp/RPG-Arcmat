class_name TownManager
extends RefCounted

var _tm  # TravelManager

func _init(tm) -> void:
	_tm = tm

func _pick(arr: Array):
	return arr[_tm.rng.randi() % arr.size()]

# ------------------------
# TOWN
# ------------------------

func enter_town(town_name: String) -> void:
	_tm.current_town = town_name
	_tm.current_town_data = _tm.town_db[town_name]
	_tm.current_region = town_name
	MyEventBus.emit("clear_text", {})
	var arrival = _tm.current_town_data.get("arrival", [])
	var ambience = _tm.current_town_data.get("ambience", [])
	var text = _pick(arrival) if not arrival.is_empty() else town_name
	if not ambience.is_empty():
		text += "\n\n" + _pick(ambience)
	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_town_actions()

func return_to_town() -> void:
	MyEventBus.emit("clear_text", {})
	var arrival = _tm.current_town_data.get("shop_exit", [])
	var ambience = _tm.current_town_data.get("ambience", [])
	var text = _pick(arrival) if not arrival.is_empty() else "You go back out into %s." % [_tm.current_town]
	if not ambience.is_empty():
		text += "\n\n" + _pick(ambience)
	MyEventBus.emit("dialogue", {"text": text, "choices": [], "linebreak": false})
	show_town_actions()

func show_town_actions() -> void:
	if _tm.game_manager:
		SaveManager.save(_tm.game_manager.current_slot, _tm.game_manager)
	_tm._in_town_context = true
	var shops = _tm.current_town_data.get("Shops", {})
	var locations = _tm.current_town_data.get("Locations", {})
	var shop_cfg = _tm.current_town_data.get("ShopMenu", {})
	var explore_cfg = _tm.current_town_data.get("ExploreMenu", {})
	var choices = []
	if not shops.is_empty():
		choices.append({
			"text": shop_cfg.get("text", "Shop"),
			"type": "action",
			"tooltip": shop_cfg.get("tooltip", "Visit the shops")
		})
	if not locations.is_empty():
		choices.append({
			"text": explore_cfg.get("text", "Explore"),
			"type": "action",
			"tooltip": explore_cfg.get("tooltip", "Explore the town")
		})
	choices.append({"text": "Inventory", "type": "action", "tooltip": "View your inventory"})
	choices.append({"text": "Rest",      "type": "action", "tooltip": "Save and close your session"})
	choices.append({"text": "Leave Town","type": "back",   "tooltip": "Leave " + _tm.current_town})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "What would you like to do?"})
	_tm.mode = TravelManager.TravelMode.TOWN

func handle_action(choice) -> void:
	if choice.get("type") == "back":
		_show_leave_confirm()
		return
	var shops = _tm.current_town_data.get("Shops", {})
	var locations = _tm.current_town_data.get("Locations", {})
	var shop_cfg = _tm.current_town_data.get("ShopMenu", {})
	var explore_cfg = _tm.current_town_data.get("ExploreMenu", {})
	var text = choice.get("text", "")
	if text == shop_cfg.get("text", "Shop"):
		if shops.size() == 1:
			var sname = shops.keys()[0]
			_enter_shop_entry(sname, shops[sname])
		else:
			show_shop_submenu()
	elif text == explore_cfg.get("text", "Explore"):
		if locations.size() == 1:
			var lname = locations.keys()[0]
			_enter_shop_entry(lname, locations[lname])
		else:
			show_explore_submenu()
	elif text == "Inventory":
		_tm._inventory.show_menu()
	elif text == "Rest":
		_tm._show_rest_menu()
	elif text == "Leave Town":
		_show_leave_confirm()
	else:
		print("Unhandled town action: " + text)

# ------------------------
# SHOP SUBMENU
# ------------------------

func show_shop_submenu() -> void:
	var menu_cfg = _tm.current_town_data.get("ShopMenu", {})
	var choices = []
	for shop_name in _tm.current_town_data.get("Shops", {}):
		choices.append({"text": shop_name, "type": "action", "tooltip": "Visit " + shop_name})
	choices.append({"text": "Back", "type": "back", "tooltip": "Back to " + _tm.current_town})
	MyEventBus.emit("show_choices", {
		"choices": choices,
		"header": menu_cfg.get("header", "Which shop?")
	})
	_tm.mode = TravelManager.TravelMode.TOWN_SHOP_MENU

func handle_shop_submenu(choice) -> void:
	if choice.get("type") == "back":
		show_town_actions()
		return
	var shop_name = choice.get("text", "")
	var shops = _tm.current_town_data.get("Shops", {})
	if shops.has(shop_name):
		_enter_shop_entry(shop_name, shops[shop_name])
	else:
		print("Unknown shop: " + shop_name)

# ------------------------
# EXPLORE SUBMENU
# ------------------------

func show_explore_submenu() -> void:
	var menu_cfg = _tm.current_town_data.get("ExploreMenu", {})
	var choices = []
	for loc_name in _tm.current_town_data.get("Locations", {}):
		choices.append({"text": loc_name, "type": "action", "tooltip": "Visit " + loc_name})
	choices.append({"text": "Back", "type": "back", "tooltip": "Back to " + _tm.current_town})
	MyEventBus.emit("show_choices", {
		"choices": choices,
		"header": menu_cfg.get("header", "Where would you like to go?")
	})
	_tm.mode = TravelManager.TravelMode.TOWN_EXPLORE_MENU

func handle_explore_submenu(choice) -> void:
	if choice.get("type") == "back":
		show_town_actions()
		return
	var loc_name = choice.get("text", "")
	var locations = _tm.current_town_data.get("Locations", {})
	if locations.has(loc_name):
		_enter_shop_entry(loc_name, locations[loc_name])
	else:
		print("Unknown location: " + loc_name)

func _enter_shop_entry(entry_name: String, entry_data: Dictionary) -> void:
	_tm._shop.enter_shop(entry_name, entry_data)

# ------------------------
# LEAVE
# ------------------------

func _show_leave_confirm() -> void:
	MyEventBus.emit("show_choices", {"choices": [
		{"text": "Yes", "type": "action", "tooltip": "Leave " + _tm.current_town},
		{"text": "No",  "type": "back",   "tooltip": "Stay in " + _tm.current_town}
	], "header": "Leave " + _tm.current_town + "?"})
	_tm.mode = TravelManager.TravelMode.TOWN_LEAVE_CONFIRM

func handle_leave_confirm(choice) -> void:
	if choice.get("text") == "Yes":
		var next_name = _tm.current_town_data.get("Next", "")
		if next_name == "" or (not _tm.world_data.has(next_name) and not _tm.town_db.has(next_name)):
			push_error("Próxima região inválida para " + _tm.current_town + ": " + next_name)
			return
		var exit_text = _tm.current_town_data.get("ExitTxt", "")
		if exit_text != "":
			MyEventBus.emit("continue_text", {"text": exit_text})
			await _tm.game_manager._gm_wait_for_continue()
		var exit_event_name = _tm.current_town_data.get("ExitEvent", "")
		if exit_event_name != "":
			var event_def = _tm.events_db.get(exit_event_name, {})
			if not event_def.is_empty() and not _tm.game_state["used_events"].get(exit_event_name, false):
				var stopped: bool = await _tm._run_node_event(event_def)
				if stopped:
					return
				if not event_def.get("repeatable", true):
					_tm.game_state["used_events"][exit_event_name] = true
		_tm._full_heal_player()
		_tm.current_region = next_name
		_tm.enter_node(0, "default")
	else:
		show_town_actions()
