extends Control

@onready var output: RichTextLabel = $MarginContainer/VBoxContainer/Output
@onready var input: LineEdit = $MarginContainer/VBoxContainer/Input

var rng := RandomNumberGenerator.new()

# --- World Data ---
var rooms := {
	"beach": {
		"desc": "You stand on a moonlit beach. Waves whisper. Paths lead [b]north[/b] to a village and [b]east[/b] into jungle.",
		"exits": {"north": "village", "east": "jungle"},
		"items": ["shell"],
		"enemies": []
	},
	"village": {
		"desc": "A sleepy coastal village. Lanterns sway. Paths lead [b]south[/b] to the beach and [b]east[/b] toward old ruins.",
		"exits": {"south": "beach", "east": "ruins"},
		"items": ["bandage"],
		"enemies": [{"id":"rat","name":"giant rat","hp":6,"atk":2}]
	},
	"jungle": {
		"desc": "Dense palms and chirping insects. A barely visible trail goes [b]west[/b] and [b]north[/b] to mossy stones.",
		"exits": {"west": "beach", "north": "ruins"},
		"items": ["stick"],
		"enemies": []
	},
	"ruins": {
		"desc": "Cracked pillars around a sunken altar. Exits lead [b]south[/b] to jungle and [b]west[/b] to the village.",
		"exits": {"south": "jungle", "west": "village"},
		"items": ["idol"],
		"enemies": [{"id":"snake","name":"temple viper","hp":10,"atk":3}]
	}
}

# Player state
var current_room := "beach"
var inventory: Array[String] = []
var player := {
	"hp": 12,
	"max_hp": 12,
	"atk": 3
}

func _ready() -> void:
	rng.randomize()
	output.clear()
	println("[b]Welcome to Strand of Stars[/b] — a teeny text RPG. Type [b]help[/b] for commands.")
	look()
	# Submit by pressing Enter in the line edit:
	input.text_submitted.connect(_on_input_submitted)
	input.grab_focus()

func _on_input_submitted(t: String) -> void:
	var cmd := t.strip_edges()
	input.clear()
	if cmd == "":
		return
	println("[color=#a0a0ff]> %s[/color]" % cmd)
	handle_command(cmd)

# --- Printing helpers ---
func println(text: String) -> void:
	output.append_text(text + "\n")
	# Auto-scroll to bottom
	await get_tree().process_frame
	output.scroll_to_line(output.get_line_count())

func br() -> void:
	println("")

# --- Core Actions ---
func look() -> void:
	var r = rooms[current_room]
	println("\n[b]%s[/b]" % current_room.capitalize())
	println(r.desc)
	if r.items.size() > 0:
		println("Items here: " + ", ".join(r.items))
	if r.enemies.size() > 0:
		var names := []
		for e in r.enemies:
			names.append(e.name)
		println("You see: " + ", ".join(names))
	println("Exits: " + ", ".join(r.exits.keys()))

func move(dir: String) -> void:
	var r = rooms[current_room]
	if not r.exits.has(dir):
		println("You can't go %s from here." % dir)
		return
	current_room = r.exits[dir]
	look()
	# Chance for an ambush when entering a room with enemies
	check_enemy_aggro()

func take_item(item: String) -> void:
	var r = rooms[current_room]
	if item in r.items:
		r.items.erase(item)
		inventory.append(item)
		println("You take the %s." % item)
	else:
		println("No %s here." % item)

func drop_item(item: String) -> void:
	if item in inventory:
		inventory.erase(item)
		rooms[current_room].items.append(item)
		println("You drop the %s." % item)
	else:
		println("You don't have a %s." % item)

func show_inventory() -> void:
	if inventory.is_empty():
		println("Your inventory is empty.")
		return
	println("Inventory: " + ", ".join(inventory))

func show_stats() -> void:
	println("HP: %d / %d | ATK: %d" % [player.hp, player.max_hp, player.atk])

func use_item(item: String) -> void:
	if not (item in inventory):
		println("You don't have a %s." % item)
		return
	match item:
		"bandage":
			var healed := clampi(6, 0, player.max_hp - player.hp)
			player.hp += healed
			inventory.erase(item)
			println("You wrap a bandage. Healed %d HP." % healed)
			return
		"stick":
			println("You brandish the stick. It's… a stick. (+1 ATK while carried)")
			return
		_:
			println("You can't figure out how to use the %s." % item)

func effective_atk() -> int:
	var bonus := 1 if ("stick" in inventory) else 0
	return player.atk + bonus

# --- Combat ---
func current_enemies() -> Array:
	return rooms[current_room].enemies

func find_enemy(token: String) -> Dictionary:
	for e in current_enemies():
		if token in e.name or token == e.id:
			return e
	return {}

func attack(target: String) -> void:
	var enemies := current_enemies()
	if enemies.is_empty():
		println("There's nothing to fight.")
		return
	var foe := find_enemy(target)
	if foe.is_empty():
		# default to first enemy
		foe = enemies[0]
	println("You strike the %s." % foe.name)
	var dmg := rng.randi_range(effective_atk() - 1, effective_atk() + 1)
	dmg = max(1, dmg)
	foe.hp -= dmg
	println(" → %s takes %d damage (HP %d)." % [foe.name, dmg, max(0, foe.hp)])
	if foe.hp <= 0:
		println("The %s collapses!" % foe.name)
		enemies.erase(foe)
		return
	# enemy counterattacks
	enemy_attack()

func enemy_attack() -> void:
	var enemies: Array = current_enemies()
	if enemies.is_empty():
		return

	var idx: int = rng.randi_range(0, enemies.size() - 1)
	var foe: Dictionary = enemies[idx]

	# Safely extract typed fields
	var foe_name: String = String(foe.get("name", "enemy"))
	var foe_atk: int = int(foe.get("atk", 1))

	var dmg: int = rng.randi_range(foe_atk - 1, foe_atk + 1)
	dmg = max(1, dmg)

	player.hp = int(player.hp) - dmg

	println("The %s hits you for %d! (HP %d/%d)" % [
		foe_name, dmg, max(0, int(player.hp)), int(player.max_hp)
	])

	if int(player.hp) <= 0:
		println("[b][color=red]You have fallen...[/color][/b]")
		println("Type [b]restart[/b] to try again.")


func check_enemy_aggro() -> void:
	var enemies := current_enemies()
	if enemies.is_empty():
		return
	if rng.randi_range(0, 100) < 30:
		println("Something moves in the shadows...")
		enemy_attack()

func try_restart() -> void:
	player.hp = player.max_hp
	inventory.clear()
	current_room = "beach"
	# Reset enemies and items to initial state (clone from a fresh template)
	rooms = {
		"beach": {"desc": rooms.beach.desc, "exits": rooms.beach.exits, "items": ["shell"], "enemies": []},
		"village": {"desc": rooms.village.desc, "exits": rooms.village.exits, "items": ["bandage"], "enemies": [{"id":"rat","name":"giant rat","hp":6,"atk":2}]},
		"jungle": {"desc": rooms.jungle.desc, "exits": rooms.jungle.exits, "items": ["stick"], "enemies": []},
		"ruins": {"desc": rooms.ruins.desc, "exits": rooms.ruins.exits, "items": ["idol"], "enemies": [{"id":"snake","name":"temple viper","hp":10,"atk":3}]}
	}
	println("[color=lime]You feel time rewind...[/color]")
	look()

# --- Parser ---
func handle_command(raw: String) -> void:
	var text := raw.to_lower()
	var parts := text.split(" ", false, 2) # at most 2 chunks
	var verb := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""

	match verb:
		"help":
			println("Commands: help, look, go <dir>, n/s/e/w, take <item>, drop <item>, use <item>, inv, stats, attack <enemy>, examine <thing>, restart")
			return
		"look", "l":
			look(); return
		"go":
			if arg == "": println("Go where?")
			else: move(arg)
			return
		"n": move("north"); return
		"s": move("south"); return
		"e": move("east"); return
		"w": move("west"); return
		"take", "get", "grab":
			if arg == "": println("Take what?")
			else: take_item(arg)
			return
		"drop":
			if arg == "": println("Drop what?")
			else: drop_item(arg)
			return
		"inv", "inventory", "i":
			show_inventory(); return
		"stats":
			show_stats(); return
		"use":
			if arg == "": println("Use what?")
			else: use_item(arg)
			return
		"attack", "hit", "strike":
			if arg == "": attack("")
			else: attack(arg)
			return
		"examine", "x":
			if arg == "": println("Examine what?")
			elif arg in rooms[current_room].items or arg in inventory:
				println(examine_text(arg))
			else:
				println("You see nothing special about that.")
			return
		"restart":
			try_restart(); return
		_:
			println("Unknown command. Type [b]help[/b].")

func examine_text(item: String) -> String:
	match item:
		"shell": return "A pearly shell that hums softly if you listen."
		"bandage": return "Clean cloth. Restores some HP when used."
		"stick": return "A sturdy stick. Not elegant, but serviceable. (+1 ATK while carried)"
		"idol": return "A small stone idol with star-shaped eyes. Probably valuable."
		_: return "Nothing special."
