# EventReader.gd
# Runs a scripted sequence of event steps in order using await.
#
# ── Step reference ─────────────────────────────────────────────────────────────
#
#   text    {"type":"text",    "text":"Hello!",   "no_wait":false, "linebreak":false}
#              Shows text with typewriter. Waits for player to continue unless no_wait is true.
#
#   append  {"type":"append",  "text":"More.",    "wait":false,    "linebreak":false}
#              Appends text to the current box. Set wait:true to pause for input after.
#
#   clear          {"type":"clear"}
#                     Clears the text box.
#
#   show_node_text {"type":"show_node_text", "no_wait":false}
#                     Re-displays the current node's description text.
#                     Waits for player input unless no_wait is true.
#
#   wait    {"type":"wait"}
#              Shows a Continue button and waits for input.
#
#   choice  {"type":"choice",  "header":"...",    "choices":[{"choice":"A","key":"a"}, ...],
#            "branches":{"a": [steps...], "b": [steps...]}}
#              Shows choices. Branches matched by key > choice text > numeric index.
#
#   combat  {"type":"combat",  "enemy":"SlimeName",
#            "on_victory":[steps...], "on_defeat":[steps...]}
#              Starts a combat encounter and awaits its result.
#
#   sfx      {"type":"sfx",       "sound":"coin"}
#
#   set_var  {"type":"set_var",   "vars":{"quest_started":1, "talked_to_npc":true}}
#
#   effect   {"type":"effect",    "effect":{"type":"heal","amount":50}}
#
#   give_gold {"type":"give_gold","amount":100}
#              Adds gold to the player. Instant, no wait.
#
#   give_item {"type":"give_item","item":"Iron Sword"}
#              Gives the player an item. If it is a weapon or armor, shows the
#              stat comparison screen and lets the player choose to equip or bag it.
#
#   if      {"type":"if",      "condition":{...}, "then":[steps...], "else":[steps...]}
#              condition is passed to condition_callback if set; otherwise always true.
#
#   random  {"type":"random",  "outcomes":[steps_a, steps_b, steps_c]}
#              Picks one outcome at random (equal probability).
#              For weighted picks, use dicts instead of plain arrays:
#              "outcomes":[{"weight":3,"steps":[...]}, {"weight":1,"steps":[...]}]
#              weight defaults to 1 when omitted.
#
#   game_over {"type":"game_over"}
#              Triggers the Game Over screen and stops the event sequence.
#
# ── Usage ──────────────────────────────────────────────────────────────────────
#
#   var reader = EventReader.new()
#   add_child(reader)
#   reader.condition_callback = func(c): return game_manager.check_condition(c, node_idx)
#   await reader.run([
#       {"type": "text",   "text": "A figure steps out of the shadows."},
#       {"type": "choice", "header": "What do you do?",
#        "choices": [{"choice": "Fight", "key": "fight"}, {"choice": "Flee", "key": "flee"}],
#        "branches": {
#            "fight": [{"type": "combat", "enemy": "Bandit"}],
#            "flee":  [{"type": "text",   "text": "You run into the night."}],
#        }},
#   ])
#   reader.queue_free()

class_name EventReader
extends Node

signal finished
signal _step_done

## Assign to GameManager.check_condition (or similar) to enable "if" step evaluation.
var condition_callback := Callable()

var _active := false


func run(sequence: Array) -> void:
	_active = true
	await _run_sequence(sequence)
	_active = false
	finished.emit()


func stop() -> void:
	_active = false


# ── Sequence execution ─────────────────────────────────────────────────────────

func _run_sequence(steps: Array) -> void:
	for step in steps:
		if not _active:
			return
		await _run_step(step)


func _run_step(step: Dictionary) -> void:
	print(step.get("type", ""))
	match step.get("type", ""):
		"text":
			var evtxt = "dialogue"
			if not step.get("clear", true):
				evtxt = "continue_text"
				 
			MyEventBus.emit(evtxt, {
				"text":      step.get("text",      ""),
				"linebreak": step.get("linebreak", true),
			})
			if not step.get("no_wait", false):
				# await MyEventBus.await_event("typing_finished")
				await _wait_for_continue()
		"append":
			MyEventBus.emit("continue_text", {
				"text":      step.get("text",      ""),
				"linebreak": step.get("linebreak", false),
			})
			if step.get("wait", false):
				await MyEventBus.await_event("typing_finished")
				await _wait_for_continue()
		"clear":
			MyEventBus.emit("clear_text", {})
		"show_node_text":
			MyEventBus.emit("show_node_text", {})
			if not step.get("no_wait", true):
				await _wait_for_continue()
		"show_node":
			MyEventBus.emit("show_node", {})
		"wait":
			await _wait_for_continue()
		"choice":
			print('CHOICE')
			await _run_choice(step)
		"combat":
			await _run_combat(step)
		"sfx":
			MyEventBus.emit("play_sfx", {"sound": step.get("sound", "")})
		"set_var":
			MyEventBus.emit("change_vars", step.get("vars", {}))
		"effect":
			MyEventBus.emit("apply_effect", step.get("effect", {}))
		"give_gold":
			MyEventBus.emit("give_gold", {"amount": step.get("amount", 0)})
		"give_item":
			await MyEventBus.emit_and_await("give_item", {"item": step.get("item", "")}, "give_item_done")
		"game_over":
			MyEventBus.emit("game_over", {})
			stop()
		"if":
			await _run_if(step)
		"random":
			await _run_random(step)
		_:
			push_warning("EventReader: unknown step type '%s'" % step.get("type", "?"))


# ── Step handlers ──────────────────────────────────────────────────────────────

func _run_choice(step: Dictionary) -> void:
	MyEventBus.emit("show_choices", {
		"choices": _normalize_choices(step.get("choices", [])),
		"header":  step.get("header",  ""),
	})

	var selected: Dictionary = await _capture_input()
	var branches: Dictionary = step.get("branches", {})

	# Branch match priority: key field → choice text → numeric index
	var key = selected.get("key", selected.get("choice", ""))
	var idx = selected.get("index", -1)

	var branch: Array = []
	if branches.has(key):
		branch = branches[key]
	elif idx >= 0 and branches.has(idx):
		branch = branches[idx]

	if not branch.is_empty():
		await _run_sequence(branch)


func _run_combat(step: Dictionary) -> void:
	MyEventBus.emit("start_combat", {"enemy": step.get("enemy", {})})
	var result: Dictionary = await MyEventBus.await_event("post_combat")

	if result.get("victory", false) and step.has("on_victory"):
		await _run_sequence(step["on_victory"])
	elif not result.get("victory", false) and step.has("on_defeat"):
		await _run_sequence(step["on_defeat"])


func _run_random(step: Dictionary) -> void:
	var outcomes: Array = step.get("outcomes", [])
	if outcomes.is_empty():
		return

	# Build a flat weighted pool. Each entry is either a plain Array (steps)
	# or a dict {"weight": N, "steps": [...]}.
	var pool: Array = []
	for outcome in outcomes:
		if outcome is Array:
			pool.append({"weight": 1, "steps": outcome})
		elif outcome is Dictionary:
			pool.append({"weight": outcome.get("weight", 1), "steps": outcome.get("steps", [])})

	var total: int = 0
	for entry in pool:
		total += entry["weight"]

	var roll := randi() % total
	var cumulative := 0
	for entry in pool:
		cumulative += entry["weight"]
		if roll < cumulative:
			await _run_sequence(entry["steps"])
			return


func _run_if(step: Dictionary) -> void:
	var passed: bool = _check_condition(step.get("condition", {}))
	var branch_key := "then" if passed else "else"
	if step.has(branch_key):
		await _run_sequence(step[branch_key])


func _normalize_choices(choices: Array) -> Array:
	return choices.map(func(c: Dictionary) -> Dictionary:
		if c.has("text") or not c.has("choice"):
			return c
		var n := c.duplicate()
		n["text"] = n["choice"]
		return n
	)


func _check_condition(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if condition_callback.is_valid():
		return condition_callback.call(cond)
	return true


# ── Input capture ──────────────────────────────────────────────────────────────

func _wait_for_continue() -> void:
	MyEventBus.emit("show_choices", {
		"choices": [{"text": "Continue", "type": "continue"}],
		"header":  "",
	})
	await _capture_input()


func _capture_input() -> Dictionary:
	# Use an Array as a reference box so the lambda mutation is visible outside.
	var box: Array = [{}]
	MyInputRouter.push(func(choice: Dictionary) -> void:
		box[0] = choice
		MyInputRouter.pop()
		_step_done.emit()
	, "event_reader")
	await _step_done
	return box[0]
