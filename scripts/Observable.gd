extends RefCounted
class_name Observable

signal changed(path, value)

var data = {}

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
