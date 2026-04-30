extends RefCounted
class_name GameState

signal changed(path, value)

var data = {}

# ------------------------
# COMPAT (estilo antigo)
# ------------------------

func _get(key):
	return data.get(key)

func _set(key, value):
	data[key] = value
	
	# dispara mudança raiz
	emit_signal("changed", key, value)
	
	# 🔥 opcional: propagar subpaths
	if typeof(value) == TYPE_DICTIONARY:
		_emit_nested(key, value)
	
	return true

func _emit_nested(prefix, dict):
	for k in dict.keys():
		var path = prefix + "." + k
		emit_signal("changed", path, dict[k])
		
		if typeof(dict[k]) == TYPE_DICTIONARY:
			_emit_nested(path, dict[k])

func has(key):
	return data.has(key)

# ------------------------
# NOVO SISTEMA (path)
# ------------------------

func set_value(path: String, value):
	var keys = path.split(".")
	var ref = data
	
	for i in range(keys.size() - 1):
		if not ref.has(keys[i]):
			ref[keys[i]] = {}
		ref = ref[keys[i]]
	
	ref[keys[-1]] = value
	emit_signal("changed", path, value)

func get_value(path: String, default = null):
	var keys = path.split(".")
	var ref = data
	
	for k in keys:
		if not ref.has(k):
			return default
		ref = ref[k]
	
	return ref
