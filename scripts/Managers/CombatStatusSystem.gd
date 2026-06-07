extends RefCounted
class_name CombatStatusSystem

var status_effects: Dictionary
var cooldowns: Dictionary
var status_db: Dictionary
var player
var enemies: Array
var get_display_name: Callable

func _init(
	p_status_effects: Dictionary,
	p_cooldowns: Dictionary,
	p_status_db: Dictionary,
	p_player,
	p_enemies: Array,
	p_get_display_name: Callable
) -> void:
	status_effects  = p_status_effects
	cooldowns       = p_cooldowns
	status_db       = p_status_db
	player          = p_player
	enemies         = p_enemies
	get_display_name = p_get_display_name

func _who_for(target) -> String:
	if target == player:
		return "player"
	for i in range(enemies.size()):
		if enemies[i] == target:
			return "enemy_%d" % i
	return "player"

func tick_cooldowns(who: String) -> void:
	for skill in cooldowns[who]:
		cooldowns[who][skill] = max(0, cooldowns[who][skill] - 1)

func add_status(target, effect: String, magnitude: int = -1) -> void:
	var who      = _who_for(target)
	var duration = magnitude if magnitude > 0 else status_db.get(effect, {}).get("duration", 3)
	for s in status_effects[who]:
		if s["type"] == effect:
			s["duration"] += duration
			emit_status_update(who)
			return
	status_effects[who].append({ "type": effect, "duration": duration })
	apply_stat_modifiers(who)
	emit_status_update(who)

func apply_stat_modifiers(who: String) -> void:
	var target   = player if who == "player" else enemies[int(who.split("_")[1])]
	var combined: Dictionary = {}
	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		for stat in data.get("stats", {}):
			combined[stat] = combined.get(stat, 1.0) * float(data["stats"][stat])
	target.set_stat_multipliers(combined)

func process_statuses(who: String) -> bool:
	var target    = player if who == "player" else enemies[int(who.split("_")[1])]
	var remaining = []
	var need_wait = false

	for s in status_effects[who]:
		var data = status_db.get(s["type"], {})
		if not data.is_empty():
			var damage_frac: float = data.get("damage", 0.0)
			var heal_frac:   float = data.get("heal",   0.0)
			var upkeep:      String = data.get("upkeep_text", "")

			if damage_frac > 0.0:
				var dmg = max(1, int(target.get_max_hp() * damage_frac))
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(upkeep, { "TARGET": get_display_name.call(target) }) + "[wait=0.1]" })
				target.take_damage(dmg)
				MyEventBus.emit("continue_text", { "text": "[screenshake][instant][color=red]%d[/color] damage![/instant]" % dmg, "linebreak": false })
				need_wait = true
			elif heal_frac > 0.0:
				var hp = max(1, int(target.get_max_hp() * heal_frac))
				if upkeep != "":
					MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(upkeep, { "TARGET": get_display_name.call(target) }) + "[wait=0.1]" })
				target.heal(hp)
				MyEventBus.emit("continue_text", { "text": "[instant]Gained [color=green]%d[/color] HP![/instant]" % hp, "linebreak": false })
				need_wait = true

		s["duration"] -= 1
		if s["duration"] > 0:
			remaining.append(s)
		else:
			var end_text: String = data.get("end_text", "")
			if end_text != "":
				MyEventBus.emit("continue_text", { "text": CombatUtils.parse_action_text(end_text, { "TARGET": get_display_name.call(target) }) + "\n" })
				need_wait = true

	status_effects[who] = remaining
	apply_stat_modifiers(who)
	emit_status_update(who)
	return need_wait

func emit_status_update(who: String) -> void:
	MyEventBus.emit("status_changed", { "who": who, "effects": status_effects[who] })
