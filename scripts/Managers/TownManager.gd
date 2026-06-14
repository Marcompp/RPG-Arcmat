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
	var choices = []
	for shop_name in _tm.current_town_data.get("Shops", {}):
		choices.append({"text": shop_name, "type": "action", "tooltip": "Visit " + shop_name})
	choices.append({"text": "Leave", "type": "back", "tooltip": "Leave " + _tm.current_town})
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Where would you like to go?"})
	_tm.mode = TravelManager.TravelMode.TOWN

func handle_action(choice) -> void:
	if choice.get("type") == "back":
		_show_leave_confirm()
		return
	var shop_name = choice.get("text", "")
	var shops = _tm.current_town_data.get("Shops", {})
	if shops.has(shop_name):
		var shop = shops[shop_name]
		if shop.get("Kind", "") == "Shop":
			_tm._shop.enter_shop(shop_name, shop)
			return
	print("Unhandled town action: " + shop_name)

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
