# EventReader.gd
# Runs a scripted sequence of event steps in order using await.
#
# # â”€â”€ Step reference â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
#            "level":5,
#            "on_victory":[steps...], "on_defeat":[steps...]}
#              Starts a combat encounter and awaits its result.
#              Optional "level" overrides the enemy's default Lvl from the database.
#
#   sfx      {"type":"sfx",       "sound":"coin"}
#
#   set_var  {"type":"set_var",   "vars":{"quest_started":1, "talked_to_npc":true}}
#
#   effect   {"type":"effect",    "effect":{"type":"heal","amount":50}}
#
#   give_gold {"type":"give_gold","amount":100}
#              Adds gold to the player. Instant, no wait.
#              Optional "var":"var_name" uses that game var's value instead of "amount".
#              Optional "invert":true negates the resolved amount (for deductions).
#
#   give_item {"type":"give_item","item":"Iron Sword"}
#              Gives the player an item. If it is a weapon or armor, shows the
#              stat comparison screen and lets the player choose to equip or bag it.
#
#   learn_skill {"type":"learn_skill","skill":"Lunge"}
#              Adds the named skill to the player's skill list if not already known.
#
#   give_region_item {"type":"give_region_item"}
#              Picks one random item from the current region's Treasure list, shows
#              "Found [item]!" text, then gives the item. Requires TravelManager.
#
#   if      {"type":"if",      "condition":{...}, "then":[steps...], "else":[steps...]}
#              condition is passed to condition_callback if set; otherwise always true.
#
#   modify_stat {"type":"modify_stat", "stats":{"hp":5, "str":1}}
#                  Permanently increases base stats. hp/mp also raise max and heal by that amount.
#
#   event   {"type":"event",   "event":"event_name"}
#              Looks up the named event in events.json and runs its steps inline.
#              Requires event_callback to be set on the EventReader.
#
#   mark_used  {"type":"mark_used", "event":"golden_apple"}
#                 Marks the named event as used in game_state["used_events"].
#                 Check with conditions as {"event_name": false} (unused) or {"event_name": true} (used).
#
#   random  {"type":"random",  "outcomes":[steps_a, steps_b, steps_c]}
#              Picks one outcome at random (equal probability).
#              For weighted picks, use dicts instead of plain arrays:
#              "outcomes":[{"weight":3,"steps":[...]}, {"weight":1,"steps":[...]}]
#              weight defaults to 1 when omitted.
#              Optional "stat_weights":{"Lck":1} adds (stat_value * multiplier) to an
#              outcome's weight at runtime. Requires stat_callback to be set.
#              Optional "condition":{...} skips the outcome entirely if the condition fails.
#
#   game_over {"type":"game_over"}
#              Triggers the Game Over screen and stops the event sequence.
#
# â”€â”€ Usage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

## Assign to return a numeric player stat value by name, e.g. func(s): return player.get_stat(s)
var stat_callback := Callable()

## Assign to return the player's current gold total, e.g. func(): return game_state["gold"]
var gold_callback := Callable()

## Assign to return the player's 3 equipped die IDs, e.g. func(): return player.data["Dice"]
var player_dice_callback := Callable()

## Assign to format a die's tooltip, e.g. TravelManager._format_die_tooltip(die_id, die_data)
var die_tooltip_callback := Callable()

## Assign to return the player's display name, e.g. func(): return player.get_name()
var player_name_callback := Callable()

var rng: RandomNumberGenerator

## Assign to return a step array by event name, e.g. func(n): return events_db.get(n,{}).get("steps",[])
var event_callback := Callable()

## Assign to return database data by type. Called as db_callback.call("regions") or
## db_callback.call("region_events", region_name). Used by the debug_event_picker step.
var db_callback := Callable()

var _active := false
var was_stopped := false


func run(sequence: Array) -> void:
	_active = true
	was_stopped = false
	await _run_sequence(sequence)
	_active = false
	finished.emit()


func stop() -> void:
	_active = false
	was_stopped = true


# â”€â”€ Sequence execution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
			if not step.get("no_wait", false) and not step.get("no_continue",false):
				await _wait_for_continue()
			elif not step.get("no_wait",false):
				await MyEventBus.await_event("typing_finished")
			
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
		"show_node_actions":
			MyEventBus.emit("show_node_actions", {})
		"show_node":
			MyEventBus.emit("show_node", {})
		"exit_node":
			MyEventBus.emit("exit_node", step.get("exit", {}))
		"enter_town":
			MyEventBus.emit("enter_town_event", {"town": step.get("town", "")})
		"set_backdrop":
			MyEventBus.emit("set_backdrop", step)
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
		"modify_stat":
			MyEventBus.emit("modify_stat", {"stats": step.get("stats", {})})
		"mark_used":
			MyEventBus.emit("mark_event_used", {"event": step.get("event", "")})
		"give_gold":
			MyEventBus.emit("give_gold", {
				"amount": step.get("amount", 0),
				"var": step.get("var", ""),
				"invert": step.get("invert", false),
			})
		"give_item":
			await MyEventBus.emit_and_await("give_item", {"item": step.get("item", "")}, "give_item_done")
		"exchange_equip":
			MyEventBus.emit("exchange_equip", {"item": step.get("item", "")})
		"learn_skill":
			await MyEventBus.emit_and_await("learn_skill", {"skill": step.get("skill", "")}, "learn_skill_done")
		"give_region_item":
			var picked: Dictionary = await MyEventBus.emit_and_await("give_region_item_pick", {}, "give_region_item_picked")
			var item_name: String = picked.get("item", "")
			if not item_name.is_empty():
				await _run_step({"type": "text", "text": "Found %s!" % item_name})
				await MyEventBus.emit_and_await("give_item", {"item": item_name}, "give_item_done")
		"game_over":
			MyEventBus.emit("game_over", {})
			stop()
		"if":
			await _run_if(step)
		"random":
			await _run_random(step)
		"event":
			await _run_event_ref(step)
		"modify_node":
			MyEventBus.emit("modify_node", step.get("data",{}))
		"shop":
			MyEventBus.emit("open_event_shop", {"name": step.get("name", "Merchant"), "data": step.get("shop", {})})
			await MyEventBus.await_event("event_shop_closed")
		"debug_event_picker":
			await _run_debug_event_picker()
		"dice_game":
			var _dg := DiceGame.new()
			_dg.capture_input_fn = func() -> Dictionary: return await _capture_input()
			_dg.wait_for_continue_fn = func() -> Dictionary:
				MyEventBus.emit("show_choices", {
					"choices": [{"text": "Continue", "type": "continue"}],
					"header": ""
				})
				return await _capture_input()
			_dg.stat_callback = stat_callback
			_dg.gold_callback = gold_callback
			_dg.rng = rng			
			_dg.dice_db             = db_callback.call("dice")     if db_callback.is_valid() else {}
			_dg.faces_db            = db_callback.call("faces")    if db_callback.is_valid() else {}
			_dg.gamblers_db         = db_callback.call("gamblers") if db_callback.is_valid() else {}
			_dg.player_dice_callback = player_dice_callback
			_dg.die_tooltip_callback = die_tooltip_callback
			_dg.player_name_callback = player_name_callback
			var _outcome: String = await _dg.run(step)
			match _outcome:
				"win":  await _run_sequence(step.get("on_win", []))
				"tie":  await _run_sequence(step.get("on_tie", step.get("on_win", [])))
				"fold": await _run_sequence(step.get("on_fold", step.get("on_lose", [])))
				_:      await _run_sequence(step.get("on_lose", []))
		"quiz_game":
			var _qg := QuizGame.new()
			_qg.capture_input_fn = func() -> Dictionary: return await _capture_input()
			_qg.wait_for_continue_fn = func() -> Dictionary:
				MyEventBus.emit("show_choices", {
					"choices": [{"text": "Continue", "type": "continue"}],
					"header": ""
				})
				return await _capture_input()
			_qg.stat_callback = stat_callback
			_qg.condition_callback = condition_callback
			_qg.rng = rng
			_qg.questions_db = db_callback.call("questions") if db_callback.is_valid() else {}
			var _qoutcome: String = await _qg.run(step)
			match _qoutcome:
				"win": await _run_sequence(step.get("on_win", []))
				_:    await _run_sequence(step.get("on_lose", []))
		_:
			push_warning("EventReader: unknown step type '%s'" % step.get("type", "?"))


# â”€â”€ Step handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

func _run_choice(step: Dictionary) -> void:
	MyEventBus.emit("show_choices", {
		"choices": _normalize_choices(step.get("choices", [])),
		"header":  step.get("header",  ""),
	})

	var selected: Dictionary = await _capture_input()
	var branches: Dictionary = step.get("branches", {})

	# Branch match priority: key field â†’ choice text â†’ numeric index
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
	var combat_data := {"enemy": step.get("enemy", {})}
	if step.has("on_defeat"):
		combat_data["suppress_defeat_game_over"] = true
	if step.has("level"):
		combat_data["level"] = step["level"]
	if step.has("overrides"):
		combat_data["overrides"] = step["overrides"]
	MyEventBus.emit("start_combat", combat_data)
	var result: Dictionary = await MyEventBus.await_event("post_combat")

	if result.get("victory", false) and step.has("on_victory"):
		await _run_sequence(step["on_victory"])
	elif not result.get("victory", false):
		if step.has("on_defeat"):
			await _run_sequence(step["on_defeat"])
		else:
			await _run_sequence([{"type":"game_over"}])


func _run_random(step: Dictionary) -> void:
	var outcomes: Array = step.get("outcomes", [])
	if outcomes.is_empty():
		return

	# Build a flat weighted pool. Each entry is either a plain Array (steps)
	# or a dict {"weight": N, "stat_weights": {...}, "steps": [...]}.
	var pool: Array = []
	for outcome in outcomes:
		if outcome is Array:
			pool.append({"weight": 1, "stat_weights": {}, "steps": outcome})
		elif outcome is Dictionary:
			if not _check_condition(outcome.get("condition", {})):
				continue
			pool.append({
				"weight": outcome.get("weight", 1),
				"stat_weights": outcome.get("stat_weights", {}),
				"steps": outcome.get("steps", []),
			})

	var total: int = 0
	for entry in pool:
		total += _effective_weight(entry)

	var roll := rng.randi() % total
	var cumulative := 0
	for entry in pool:
		cumulative += _effective_weight(entry)
		if roll < cumulative:
			await _run_sequence(entry["steps"])
			return


func _effective_weight(entry: Dictionary) -> int:
	var w: int = entry["weight"]
	var sw: Dictionary = entry.get("stat_weights", {})
	if sw.is_empty() or not stat_callback.is_valid():
		return w
	for stat_name in sw:
		w += stat_callback.call(stat_name) * sw[stat_name]
	return max(w, 0)


func _run_event_ref(step: Dictionary) -> void:
	if not event_callback.is_valid():
		push_warning("EventReader: event_callback not set")
		return
	var steps: Array = event_callback.call(step.get("event", ""))
	if steps.is_empty():
		push_warning("EventReader: unknown event '%s'" % step.get("event", ""))
		return
	await _run_sequence(steps)


func _run_debug_event_picker() -> void:
	if not db_callback.is_valid():
		push_warning("EventReader: debug_event_picker requires db_callback")
		return

	# Phase 1: pick a region
	var regions: Dictionary = db_callback.call("regions")
	var region_choices: Array = []
	for region_name: String in regions.keys():
		region_choices.append({"choice": region_name, "key": region_name})
	region_choices.append({"text": "Back", "key": "back", "type": "back"})

	MyEventBus.emit("show_choices", {
		"choices": _normalize_choices(region_choices),
		"header":  "Which region?",
	})
	var region_pick: Dictionary = await _capture_input()
	var chosen_region: String = region_pick.get("key", region_pick.get("choice", ""))
	if chosen_region.is_empty() or chosen_region == "back":
		return

	# Phase 2: pick a category (Arrival / Action / Exit)
	var categories: Dictionary = db_callback.call("region_events", chosen_region)
	if categories.is_empty():
		MyEventBus.emit("show_choices", {
			"choices": [{"text": "Continue", "type": "continue"}],
			"header":  "No events for " + chosen_region,
		})
		await _capture_input()
		return

	var category_choices: Array = []
	for cat_name: String in categories.keys():
		category_choices.append({"choice": cat_name, "key": cat_name})
	category_choices.append({"text": "Back", "key": "back", "type": "back"})

	MyEventBus.emit("show_choices", {
		"choices": _normalize_choices(category_choices),
		"header":  chosen_region + " â€” category?",
	})
	var cat_pick: Dictionary = await _capture_input()
	var chosen_category: String = cat_pick.get("key", cat_pick.get("choice", ""))
	if chosen_category.is_empty() or chosen_category == "back":
		return

	# Phase 3: pick an event from the chosen category
	var event_names: Array = categories[chosen_category]
	var event_choices: Array = []
	for event_name: String in event_names:
		event_choices.append({"choice": event_name, "key": event_name})
	event_choices.append({"text": "Back", "key": "back", "type": "back"})

	MyEventBus.emit("show_choices", {
		"choices": _normalize_choices(event_choices),
		"header":  chosen_region + " [" + chosen_category + "] â€” which event?",
	})
	var event_pick: Dictionary = await _capture_input()
	var chosen_event: String = event_pick.get("key", event_pick.get("choice", ""))
	if chosen_event.is_empty() or chosen_event == "back":
		return

	# Phase 4: run the chosen event inline
	if not event_callback.is_valid():
		push_warning("EventReader: event_callback not set")
		return
	var steps: Array = event_callback.call(chosen_event)
	if not steps.is_empty():
		await _run_sequence(steps)


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


# â”€â”€ Input capture â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
