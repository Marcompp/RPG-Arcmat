class_name CombatUtils

static func parse_action_text(text: String, values: Dictionary) -> String:
	for key in values:
		text = text.replace("[" + key + "]", str(values[key]))
	return text

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json  = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON parse error: " + path)
		return {}
	return json.data
