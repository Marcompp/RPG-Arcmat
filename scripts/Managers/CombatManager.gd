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

# ========================
# ENTRY
# ========================

func start_combat(p, e):
	player = p
	enemy = e
	
	MyInputRouter.push(_handle_combat_input, "combat")
	
	await _show_intro()
	await wait_for_continue()
	
	start_player_turn()

# ========================
# FLOW
# ========================

func start_player_turn():
	state = CombatState.CHOOSING_ACTION
	render_player_turn()

func end_player_turn():
	state = CombatState.ENEMY_TURN
	await get_tree().create_timer(0.5).timeout
	await enemy_turn()

# ========================
# RENDER
# ========================

func show_text(text, choices = []):
	MyEventBus.emit("dialogue", {
		"text": text,
		"choices": choices
	})

func render_player_turn():
	var text = "%s: %d hp.\n%s: %d hp.\n\nWhat would you like to do?" % [
		enemy["name"],
		enemy["hp"],
		player["Name"],
		player["curr_stats"]["hp"]
	]
	
	show_text(text, _main_choices())

func _show_intro():
	var text = "You encounter %s\n\n%s is raring for a fight!" % [
		enemy["name"],
		enemy["name"]
	]
	show_text(text)

# ========================
# CHOICES BUILDERS
# ========================

func _main_choices():
	return [
		{ "text": "Attack", "type": "attack" },
		{ "text": "Skill", "type": "skill" },
		{ "text": "Magic", "type": "magic" },
		{ "text": "Item", "type": "item" }
	]

func _build_list_menu(list, type):
	var choices = []
	
	for item in list:
		choices.append({
			"text": str(item),
			"type": type,
			"data": item
		})
	
	choices.append({ "text": "Back", "type": "back" })
	return choices

# ========================
# INPUT ROUTER
# ========================

func _handle_combat_input(choice):
	match state:
		
		CombatState.CHOOSING_ACTION:
			handle_main_action(choice)
		
		CombatState.CHOOSING_SKILL:
			handle_list_choice(choice, "skill")
		
		CombatState.CHOOSING_MAGIC:
			handle_list_choice(choice, "magic")
		
		CombatState.CHOOSING_ITEM:
			handle_list_choice(choice, "item")

# ========================
# ACTION HANDLERS
# ========================

func handle_main_action(choice):
	match choice["type"]:
		
		"attack":
			await perform_attack()
		
		"skill":
			open_menu("skill", player.get("Skills", []))
		
		"magic":
			open_menu("magic", player.get("Spells", []))
		
		"item":
			open_menu("item", player.get("inventory", []))

func open_menu(type, list):
	match type:
		"skill": state = CombatState.CHOOSING_SKILL
		"magic": state = CombatState.CHOOSING_MAGIC
		"item": state = CombatState.CHOOSING_ITEM
	
	show_text("Choose:", _build_list_menu(list, type))

func handle_list_choice(choice, type):
	if choice["type"] == "back":
		start_player_turn()
		return
	
	match type:
		"skill":
			await use_skill(choice["data"])
		"magic":
			await use_magic(choice["data"])
		"item":
			await use_item(choice["data"])

# ========================
# ACTIONS
# ========================

func perform_attack():
	state = CombatState.RESOLUTION
	
	var weapon = player.get("Equip", {}).get("Weapon", "bare hands")
	var dmg = calculate_damage(player, enemy)
	
	enemy["hp"] -= dmg
	
	var text = "[b]%s[/b] struck with %s!\n*SCREENSHAKE*\n[color=red]%d[/color] damage!" % [
		player["Name"], weapon, dmg
	]
	
	#show_text(text)
	MyEventBus.emit("continue_text", {
		"text": text + "\n"
	})
	MyEventBus.emit("screenshake")
	
	await wait_for_continue()
	check_combat_end()

func use_skill(skill):
	show_text("Used %s!" % skill)
	await wait_for_continue()
	end_player_turn()

func use_magic(spell):
	show_text("Cast %s!" % spell)
	await wait_for_continue()
	end_player_turn()

func use_item(item):
	show_text("Used %s!" % item)
	await wait_for_continue()
	end_player_turn()

# ========================
# ENEMY
# ========================

func enemy_turn():
	var dmg = randi_range(1, 4)
	MyEventBus.emit("take_damage",{'damage':dmg})
	
	var text = "[color=yellow]%s[/color] attacks!\n*SCREENSHAKE*\n%d damage!" % [
		enemy["name"], dmg
	]
	
	#show_text(text)
	MyEventBus.emit("continue_text", {
		"text": text + "\n"
	})
	MyEventBus.emit("screenshake")
	
	await wait_for_continue()
	state = CombatState.PLAYER_TURN
	check_combat_end()

# ========================
# END
# ========================

func check_combat_end():
	if player["curr_stats"]["hp"] <= 0:
		await end_combat(false)
		return
	
	if enemy["hp"] <= 0:
		await end_combat(true)
		return
	
	next_turn()

func next_turn():
	if state == CombatState.PLAYER_TURN:
		start_player_turn()
	else:
		enemy_turn()

func end_combat(victory):
	state = CombatState.END
	
	var text = "[color=yellow]%s[/color] was defeated!" % enemy["name"] \
		if  victory else "You were defeated..."
	
	#show_text(text)
	MyEventBus.emit("continue_text", {
		"text": text
	})
	await wait_for_continue()
	
	MyInputRouter.pop()
	MyEventBus.emit("combat_ended", { "victory": victory })

# ========================
# UTILS
# ========================

func wait_for_continue(): 
	var state = { "done": false } 
	
	MyInputRouter.push(func(choice): 
		print(choice) 
		if choice.get("type") == "continue": 
			state["done"] = true 
			print("DONE!") 
			MyInputRouter.pop() , 
		"wait") 
		
	MyEventBus.emit("show_choices", {
		'choices':[ 
			{ "text": "Continue", "type": "continue" } 
		]}) 
		
	while not state["done"]: 
		await get_tree().process_frame
		
		
func calculate_damage(p, e):
	var atk = p["curr_stats"]["str"]
	var def = e.get("def", 0)
	return max(1, atk - def + randi_range(0,2))
