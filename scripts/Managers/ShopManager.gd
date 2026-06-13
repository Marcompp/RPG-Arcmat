class_name ShopManager
extends RefCounted

var _tm  # TravelManager

var current_shop_name := ""
var current_shop_data: Dictionary = {}
var _greeted_shops: Dictionary = {}
var _shop_from_event := false

func _init(tm) -> void:
	_tm = tm

func _pick(arr: Array):
	return arr[_tm.rng.randi() % arr.size()]

# ------------------------
# SHOP
# ------------------------

func enter_shop(shop_name: String, shop_data: Dictionary) -> void:
	current_shop_name = shop_name
	current_shop_data = shop_data
	_tm.mode = TravelManager.TravelMode.SHOP

	var shop_backdrop = shop_data.get("Backdrop", "")
	if shop_backdrop != "":
		_tm._set_backdrop(shop_backdrop)

	MyEventBus.emit("clear_text", {})

	var greeted = _greeted_shops.get(_tm.current_town + ":" + shop_name, false)
	var text = ""
	if not greeted:
		text = shop_data.get("WelcomeText", "")
		_greeted_shops[_tm.current_town + ":" + shop_name] = true
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

func show_shop_stock() -> void:
	var stock = current_shop_data.get("Stock", {})
	var shop_type = current_shop_data.get("ShopType", "Item")
	var gold = _tm.game_state["gold"] if _tm.game_state else 0
	var choices = []

	for item_name in stock:
		var price: int = int(stock[item_name])
		var data = _get_shop_item_data(item_name)
		var label = "%s — %dG" % [item_name, price]

		if _player_already_owns(item_name):
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
				"tooltip": _format_shop_tooltip(item_name, data)
			})
		else:
			choices.append({
				"text": label,
				"type": "shop_buy_disabled",
				"disabled": true,
				"disabled_text": label,
				"disabled_tooltip": "Not enough gold (you have %dG)" % gold
			})

	choices.append({"text": "Leave", "type": "back", "tooltip": "Return to " + _tm.current_town})
	MyEventBus.emit("show_choices", {
		"choices": choices,
		"header": "%s   [color=yellow]%dG[/color]" % [current_shop_name, gold]
	})

func handle_action(choice) -> void:
	if choice.get("type") == "back":
		_tm._transition_backdrop(_tm.current_region)
		if _shop_from_event:
			_shop_from_event = false
			_tm.mode = TravelManager.TravelMode.NODE_ACTIONS
			MyEventBus.emit("event_shop_closed", {})
		else:
			_tm.mode = TravelManager.TravelMode.TOWN
			_tm._town.return_to_town()
		return
	if choice.get("type") == "shop_buy":
		var data = choice.get("data", {})
		await _buy_item(data["item"], data["price"])

func _buy_item(item_name: String, price: int) -> void:
	if not _tm.game_state or _tm.game_state["gold"] < price:
		return

	_tm.game_state["gold"] -= price

	var player = _tm.game_state["player"]
	if not player.data.has("Inventory"):
		player.data["Inventory"] = {}

	var remaining = _tm.game_state["gold"]
	MyEventBus.emit("continue_text", {
		"text": "Bought [b]%s[/b] for [color=yellow]%dG[/color].\n[color=yellow]Gold: %dG[/color]" % [item_name, price, remaining]
	})
	await MyEventBus.emit_and_await("give_item", {"item": item_name}, "give_item_done")
	show_shop_stock()

func _player_has_equip(item_name: String) -> bool:
	var player = _tm.game_state["player"]
	var inv = player.get_inventory()
	if inv.get(item_name, 0) > 0:
		return true
	for slot in player.equipment:
		var item = player.equipment[slot]
		if typeof(item) == TYPE_DICTIONARY and item.get("name", "") == item_name:
			return true
	return false

func _player_already_owns(item_name: String) -> bool:
	var player = _tm.game_state["player"]
	var inv = player.get_inventory()
	if _tm.game_manager.weapon_db.has(item_name) or _tm.game_manager.armor_db.has(item_name):
		return _player_has_equip(item_name)
	if _tm.trinkets_db.has(item_name) and not _tm.trinkets_db[item_name].get("stackable", false):
		return item_name in player.get_trinkets() or inv.has(item_name)
	if item_name.begins_with("Book of "):
		var spell_name = item_name.substr(8)
		return player.get_spells().has(spell_name) or inv.has(item_name) or player.get_spells().size() >= _tm.MAX_SPELLS
	if item_name.ends_with(" Scroll"):
		var skill_name = item_name.substr(0, item_name.length() - 7)
		return player.get_skills().has(skill_name) or inv.has(item_name)
	return false

func _get_shop_item_data(item_name: String) -> Dictionary:
	if _tm.game_manager.weapon_db.has(item_name):
		return _tm.game_manager.weapon_db[item_name]
	if _tm.game_manager.armor_db.has(item_name):
		return _tm.game_manager.armor_db[item_name]
	if _tm.trinkets_db.has(item_name):
		return _tm.trinkets_db[item_name]
	return _tm.items_db.get(item_name, {})

func _format_shop_tooltip(item_name: String, data: Dictionary) -> String:
	if data.is_empty():
		return item_name
	if _tm.game_manager.weapon_db.has(item_name) or _tm.game_manager.armor_db.has(item_name):
		return _tm._format_equip_tooltip(data)
	if _tm.trinkets_db.has(item_name):
		return _tm._format_trinket_tooltip(item_name, data)
	return _tm._format_item_tooltip(item_name, data)
