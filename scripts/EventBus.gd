extends Node
class_name EventBus

const EVT_CHARACTER_SELECTED = "character_selected"
const EVT_STATS_CHANGED = "stats_changed"
const EVT_NODE_ENTERED = "node_entered"
const EVT_CHOICE_SELECTED = "choice_selected"

var listeners = {}

func subscribe(event_name: String, callback: Callable):
	if not listeners.has(event_name):
		listeners[event_name] = []
	
	listeners[event_name].append(callback)
	
func subscribe_once(event_name: String, callback: Callable):
	var wrapper: Callable
	
	wrapper = func(data):
		unsubscribe(event_name, wrapper)
		callback.call(data)
	
	subscribe(event_name, wrapper)

func unsubscribe(event_name: String, callback: Callable):
	if listeners.has(event_name):
		listeners[event_name].erase(callback)

func emit(event_name: String, data := {}):
	print("Emit:", event_name)
	if not listeners.has(event_name):
		return
	
	for callback in listeners[event_name]:
		callback.call(data)

func await_event(event_name: String) -> Variant:
	var result = null
	var done = false
	
	var wrapper : Callable
	wrapper = func(data):
		unsubscribe(event_name, wrapper)
		result = data
		done = true
	
	subscribe(event_name, wrapper)
	
	while not done:
		await get_tree().process_frame
	
	return result
	
func await_event_once(event_name: String) -> Variant:
	var result = null
	var received = false
	
	var callback : Callable
	callback = func(data):
		result = data
		received = true
		unsubscribe(event_name, callback)
	
	subscribe(event_name, callback)
	while not received:
		await get_tree().process_frame
	
	return result
