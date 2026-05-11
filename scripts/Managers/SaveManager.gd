extends Node

const SAVE_DIR = "user://saves/"
const SAVE_EXT = ".json"

func save(slot: int, game_manager) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var player: Character = game_manager.game_state["player"]
	if player == null:
		push_error("SaveManager: no player to save")
		return false

	var save_data = {
		"meta": {
			"timestamp": Time.get_unix_time_from_system(),
			"datetime": Time.get_datetime_string_from_system(),
			"character_name": player.get_name(),
			"character_class": player.get_char_class(),
			"level": player.get_level()
		},
		"player": player.serialize(),
		"game_state": {
			"gold": game_manager.game_state["gold"],
			"vars": game_manager.game_state["vars"].duplicate(true),
			"flags": game_manager.game_state["flags"].duplicate(true),
			"visited_nodes": game_manager.game_state["visited_nodes"].duplicate(true),
			"visited_count": game_manager.game_state["visited_count"].duplicate(true),
			"area_progress": game_manager.game_state["area_progress"]
		},
		"travel": {
			"current_region": game_manager.travel.current_region,
			"current_node": game_manager.travel.current_node,
			"current_entrance": game_manager.travel.current_entrance
		}
	}

	var path = SAVE_DIR + "save_%02d" % slot + SAVE_EXT
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	print("[SaveManager] Slot %d saved — %s Lv.%d @ %s:%d (%s)" % [
		slot,
		save_data["meta"]["character_name"],
		save_data["meta"]["level"],
		save_data["travel"]["current_region"],
		save_data["travel"]["current_node"],
		save_data["meta"]["datetime"]
	])
	return true

func load_save(slot: int) -> Dictionary:
	var path = SAVE_DIR + "save_%02d" % slot + SAVE_EXT
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var content = file.get_as_text()
	var json = JSON.new()
	if json.parse(content) != OK:
		push_error("SaveManager: failed to parse %s" % path)
		return {}

	return json.data

func list_saves() -> Array:
	var saves = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves

	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(SAVE_EXT):
			var slot_str = filename.replace("save_", "").replace(SAVE_EXT, "")
			if slot_str.is_valid_int():
				var slot = slot_str.to_int()
				var data = load_save(slot)
				if not data.is_empty():
					saves.append({
						"slot": slot,
						"meta": data.get("meta", {})
					})
		filename = dir.get_next()

	saves.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return saves

func delete_save(slot: int) -> bool:
	var path = SAVE_DIR + "save_%02d" % slot + SAVE_EXT
	if not FileAccess.file_exists(path):
		return false
	var dir = DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	return dir.remove("save_%02d" % slot + SAVE_EXT) == OK

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "save_%02d" % slot + SAVE_EXT)

func next_slot() -> int:
	var slot = 1
	while has_save(slot):
		slot += 1
	return slot
