class_name InventoryManager
extends RefCounted

var _tm  # TravelManager

func _init(tm) -> void:
	_tm = tm

# ------------------------
# INVENTORY MENU
# ------------------------

func show_menu() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_MENU
	MyEventBus.emit("show_choices", {
		"choices": [
			{"text": "Items",    "type": "action", "tooltip": "Use consumable items"},
			{"text": "Weapons",  "type": "action", "tooltip": "Change your equipped weapon"},
			{"text": "Armor",    "type": "action", "tooltip": "Change your equipped armor"},
			{"text": "Trinkets", "type": "action", "tooltip": "View and manage equipped trinkets"},
			{"text": "Misc",     "type": "action", "tooltip": "View other items"},
			{"text": "Back",     "type": "back",   "tooltip": "Return"}
		],
		"header": "Inventory"
	})

func handle_menu(choice) -> void:
	if choice.get("type") == "back":
		if _tm._in_town_context:
			_tm._town.show_town_actions()
		else:
			_tm.show_node_actions()
		return
	match choice["text"]:
		"Items":    show_items()
		"Weapons":  show_weapons()
		"Armor":    show_armor()
		"Trinkets": show_trinkets()
		"Misc":     show_misc()

# ------------------------
# ITEMS
# ------------------------

func show_items() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_ITEMS
	var player = _tm.game_state["player"]
	var inv = player.get_inventory()
	var choices = []
	var invalid_choices = []
	for item_name in inv:
		var data = _tm.items_db.get(item_name, {})
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
				"tooltip": _tm._format_item_tooltip(item_name, data)
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

func handle_items(choice) -> void:
	if choice.get("type") == "back":
		show_menu()
		return
	if choice.get("type") == "item":
		await _use_item_overworld(choice.get("data", ""))
		show_items()

func _use_item_overworld(item_name: String) -> void:
	var player = _tm.game_state["player"]
	var data = _tm.items_db.get(item_name, {})
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
	await _tm.game_manager._gm_wait_for_continue()

# ------------------------
# WEAPONS
# ------------------------

func show_weapons() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_WEAPONS
	var player = _tm.game_state["player"]
	var inv = player.get_inventory()
	var equipped = player.get_weapon()
	var equipped_name = equipped.get("name", "") if equipped and not equipped.is_empty() else ""
	var choices = []
	if not equipped_name.is_empty():
		choices.append({
			"text": "[Equipped] " + equipped_name, "type": "none",
			"disabled": true, "disabled_text": "[Equipped] " + equipped_name,
			"disabled_tooltip": _tm._format_equip_tooltip(equipped)
		})
	for item_name in inv:
		if not _tm.game_manager.weapon_db.has(item_name):
			continue
		choices.append({
			"text": item_name, "type": "weapon", "data": item_name,
			"tooltip": _tm._format_equip_tooltip(_tm.game_manager.weapon_db[item_name])
		})
	if choices.is_empty() or (choices.size() == 1 and choices[0]["type"] == "none"):
		choices.append({
			"text": "(No other weapons)", "type": "none",
			"disabled": true, "disabled_text": "(No other weapons)"
		})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Weapons", "fixed_sizes": fixed_sizes})

func handle_weapons(choice) -> void:
	if choice.get("type") == "back":
		show_menu()
		return
	if choice.get("type") == "weapon":
		await _equip_item("weapon", choice.get("data", ""))
		show_weapons()

# ------------------------
# ARMOR
# ------------------------

func show_armor() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_ARMOR
	var player = _tm.game_state["player"]
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
			"disabled_tooltip": _tm._format_equip_tooltip(equipped)
		})
	for item_name in inv:
		if not _tm.game_manager.armor_db.has(item_name):
			continue
		choices.append({
			"text": item_name, "type": "armor", "data": item_name,
			"tooltip": _tm._format_equip_tooltip(_tm.game_manager.armor_db[item_name])
		})
	if choices.is_empty() or (choices.size() == 1 and choices[0]["type"] == "none"):
		choices.append({
			"text": "(No other armor)", "type": "none",
			"disabled": true, "disabled_text": "(No other armor)"
		})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Armor", "fixed_sizes": fixed_sizes})

func handle_armor(choice) -> void:
	if choice.get("type") == "back":
		show_menu()
		return
	if choice.get("type") == "armor":
		await _equip_item("armor", choice.get("data", ""))
		show_armor()

# ------------------------
# EQUIP SHARED
# ------------------------

func _equip_item(slot: String, item_name: String) -> void:
	var player = _tm.game_state["player"]
	var db = _tm.game_manager.weapon_db if slot == "weapon" else _tm.game_manager.armor_db
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
	await _tm.game_manager._gm_wait_for_continue()

# ------------------------
# MISC
# ------------------------

func show_misc() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_MISC
	var player = _tm.game_state["player"]
	var inv = player.get_inventory()
	var choices = []
	for item_name in inv:
		if _tm.items_db.has(item_name) or _tm.game_manager.weapon_db.has(item_name) or _tm.game_manager.armor_db.has(item_name):
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

func handle_misc(choice) -> void:
	if choice.get("type") == "back":
		show_menu()

# ------------------------
# TRINKETS
# ------------------------

func show_trinkets() -> void:
	_tm.mode = TravelManager.TravelMode.INVENTORY_TRINKETS
	var player   = _tm.game_state["player"]
	var equipped = player.get_trinkets()
	var inv      = player.get_inventory()
	var choices  = []

	var equipped_counts: Dictionary = {}
	for trinket_name in equipped:
		equipped_counts[trinket_name] = equipped_counts.get(trinket_name, 0) + 1
	for trinket_name in equipped_counts:
		var tdata     = _tm.trinkets_db.get(trinket_name, {})
		var count     = equipped_counts[trinket_name]
		var stackable = tdata.get("stackable", false)
		var display_name = tdata.get("name", trinket_name)
		var label     = "[Equipped] " + display_name + (" x%d" % count if stackable and count > 1 else "")
		choices.append({
			"text": label, "type": "trinket_unequip",
			"data": trinket_name,
			"tooltip": _tm._format_trinket_tooltip(trinket_name, tdata)
		})

	for item_name in inv:
		if not _tm.trinkets_db.has(item_name):
			continue
		var tdata     = _tm.trinkets_db.get(item_name, {})
		var count     = inv[item_name]
		var stackable = tdata.get("stackable", false)
		var display_name = tdata.get("name", item_name)
		var label     = display_name + (" x%d" % count if stackable and count > 1 else "")
		if not stackable and item_name in equipped:
			choices.append({
				"text": label, "type": "none",
				"disabled": true, "disabled_text": label,
				"disabled_tooltip": "[Already equipped]\n" + _tm._format_trinket_tooltip(item_name, tdata)
			})
		else:
			choices.append({
				"text": label, "type": "trinket_equip", "data": item_name,
				"tooltip": _tm._format_trinket_tooltip(item_name, tdata)
			})

	if choices.is_empty():
		choices.append({"text": "(No trinkets)", "type": "none", "disabled": true, "disabled_text": "(No trinkets)"})
	choices.append({"text": "Back", "type": "back"})
	var fixed_sizes = len(choices) > 3
	MyEventBus.emit("show_choices", {"choices": choices, "header": "Trinkets", "fixed_sizes": fixed_sizes})

func handle_trinkets(choice) -> void:
	if choice.get("type") == "back":
		show_menu()
		return
	if choice.get("type") == "trinket_unequip":
		await _unequip_trinket(choice.get("data", ""))
		show_trinkets()
	elif choice.get("type") == "trinket_equip":
		await _equip_trinket(choice.get("data", ""))
		show_trinkets()

func _unequip_trinket(trinket_name: String) -> void:
	var player = _tm.game_state["player"]
	player.data["Trinkets"].erase(trinket_name)
	player.data["Inventory"][trinket_name] = player.data["Inventory"].get(trinket_name, 0) + 1
	player.recalculate_trinket_bonus(_tm.game_manager.trinkets_db)
	MyEventBus.emit("continue_text", {"text": "[color=#FF6B6B]%s unequipped.[/color]" % trinket_name})
	await _tm.game_manager._gm_wait_for_continue()

func _equip_trinket(trinket_name: String) -> void:
	var player = _tm.game_state["player"]
	player.consume_item(trinket_name)
	if not player.data.has("Trinkets"):
		player.data["Trinkets"] = []
	player.data["Trinkets"].append(trinket_name)
	player.recalculate_trinket_bonus(_tm.game_manager.trinkets_db)
	MyEventBus.emit("continue_text", {"text": "[color=#00E676]%s equipped![/color]" % trinket_name})
	await _tm.game_manager._gm_wait_for_continue()
