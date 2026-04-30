
extends Node
class_name CombatManager

enum CombatState {
	PLAYER_TURN,
	CHOOSING_ACTION,
	CHOOSING_SKILL,
	CHOOSING_MAGIC,
	CHOOSING_ITEM,
	ENEMY_TURN,
	RESOLUTION,
	END
}

var state = CombatState.PLAYER_TURN

var player = null
var enemy = null

func _ready():
	MyEventBus.subscribe("choice_selected", _on_choice)

func show_text(text, choices = []):
	MyEventBus.emit("dialogue", {
		"text": text,
		"choices": choices
	})

func start_combat(p, e):
	player = p
	enemy = e
	
	
	var text = ""
	text += "You encounter %s\n\n" % enemy["name"]
	text += "%s is raring for a fight!" % enemy["name"]
	
	show_text(text)
	
	state = CombatState.PLAYER_TURN
	
	await wait_for_continue()
	
	start_player_turn()
	
func wait_for_continue():
	MyEventBus.emit("show_choices", {'choices':[
	{
		"text": "Continue",
		"type": "continue"
	}]})
	while true:
		var data = await MyEventBus.await_event_once("choice_selected")
		print('CONTINUE')
		if data.get("type") == "continue":
			print('CONTINUE')
			return
	
func start_player_turn():
	state = CombatState.CHOOSING_ACTION
	
	var p_hp = player["curr_stats"]["hp"]
	var e_hp = enemy["hp"]
	
	var text = ""
	text += "%s: %d hp.\n" % [enemy["name"], e_hp]
	text += "%s: %d hp.\n\n" % [player["Name"], p_hp]
	text += "What would you like to do?"
	
	show_text(text, [
		{ "text": "Attack", "type": "attack" },
		{ "text": "Skill", "type": "skill" },
		{ "text": "Magic", "type": "magic" },
		{ "text": "Item", "type": "item" }
	])
	
func _on_choice(choice):
	match state:
		
		CombatState.CHOOSING_ACTION:
			handle_main_action(choice)
		
		CombatState.CHOOSING_SKILL:
			open_skill_menu()
		
		CombatState.CHOOSING_MAGIC:
			print("Magic TBD")
			open_magic_menu()
		
		CombatState.CHOOSING_ITEM:
			print("Item TBD")
			open_item_menu()

func handle_main_action(choice):
	match choice["type"]:
		
		"attack":
			perform_attack()
		
		"skill":
			open_skill_menu()
		
		"magic":
			open_magic_menu()
		
		"item":
			open_item_menu()


func perform_attack():
	state = CombatState.RESOLUTION
	
	var weapon = player.get("Equip", {}).get("Weapon", "bare hands")
	var dmg = calculate_damage(player, enemy)
	
	enemy["hp"] -= dmg
	
	var text = ""
	text += "%s struck with %s!\n" % [player["Name"], weapon]
	text += "*SCREENSHAKE*\n"
	text += "[color=red]%d[/color] damage!" % dmg
	
	show_text(text)
	
	# 🔥 efeito visual (opcional)
	MyEventBus.emit("screenshake")
	
	await wait_for_continue()
	
	check_combat_end()

func open_skill_menu():
	state = CombatState.CHOOSING_SKILL
	
	var skills = player.get("Skills", [])
	var choices = []
	
	for s in skills:
		choices.append({
			"text": s,
			"type": "skill",
			"data": s
		})
	
	choices.append({
		"text": "Back",
		"type": "back"
	})
	
	MyEventBus.emit("show_choices", {'choices':choices})

func handle_skill(choice):
	if choice["type"] == "back":
		start_player_turn()
		return
	
	var skill = choice["data"]
	
	#use_skill(skill)
	end_player_turn()
	
func open_magic_menu():
	state = CombatState.CHOOSING_MAGIC
	
	var spells = player.get("Spells", [])
	var choices = []
	
	for s in spells:
		choices.append({
			"text": s,
			"type": "magic",
			"data": s
		})
	
	choices.append({ "text": "Back", "type": "back" })
	
	MyEventBus.emit("show_choices", {'choices':choices})
	
func open_item_menu():
	state = CombatState.CHOOSING_ITEM
	
	var items = player.get("inventory", [])
	var choices = []
	
	for i in items:
		choices.append({
			"text": i["name"],
			"type": "item",
			"data": i
		})
	
	choices.append({ "text": "Back", "type": "back" })
	
	MyEventBus.emit("show_choices", {'choices':choices})
	
func end_player_turn():
	state = CombatState.ENEMY_TURN
	await get_tree().create_timer(0.5).timeout
	
	enemy_turn()
	
func enemy_turn():
	var dmg = randi_range(1, 4)
	player["curr_stats"]["hp"] -= dmg
	
	var text = ""
	text += "[color=yellow]%s[/color] attacks!\n" % enemy["name"]
	text += "*SCREENSHAKE*\n"
	text += "%d damage!" % dmg
	
	show_text(text)
	
	MyEventBus.emit("screenshake")
	
	await wait_for_continue()
	
	check_combat_end()
	
func check_combat_end():
	if player["curr_stats"]["hp"] <= 0:
		end_combat(false)
		return
	
	if enemy["hp"] <= 0:
		end_combat(true)
		return
	
	start_player_turn()
	
func end_combat(victory):
	var text = ""
	
	if victory:
		text = "[color=yellow]%s[/color] was defeated!" % enemy["name"]
	else:
		text = "You were defeated..."
	
	show_text(text)
	
	await wait_for_continue()
	
	MyEventBus.emit("combat_ended", {
		"victory": victory
	})
	
func calculate_damage(p, e):
	var atk = p["curr_stats"]["str"]
	var def = e.get("def", 0)
	
	return max(1, atk - def + randi_range(0,2))
