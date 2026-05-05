extends Control

@onready var player_panel = $TopLeftWrapper
@onready var enemy_panel = $TopRightWrapper
@onready var gold_label = $TopCenterPanel/VBoxContainer/GoldContainer/GoldValue


var state

const PIXELS_PER_POINT = 10
const MAX_BAR_WIDTH = 500

var character = null

func _ready():
	player_panel.tooltip_text = ""
	player_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in player_panel.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#MyEventBus.subscribe("screenshake", func(data):
		#shake()
	#)
	
var displayed_gold = 0

func shake():
	var original = position
	
	for i in range(5):
		position = original + Vector2(randf_range(-5,5), randf_range(-5,5))
		await get_tree().create_timer(0.02).timeout
	
	position = original

func bind(game_state):
	state = game_state
	
	var player = state.get_value("player")
	if player:
		player_panel.bind_character(player)
	else:
		player_panel._clear_ui()
		
	var enemy = state.get_value("enemy")
	if enemy:
		enemy_panel.bind_character(enemy)
	else:
		enemy_panel._clear_ui()
	

	state.changed.connect(_on_state_changed)
	_refresh_all()
	
func _bind_character(char):
	if character:
		character.stats_changed.disconnect(_refresh_all)
	
	character = char
	character.stats_changed.connect(_refresh_all)

func _on_state_changed(path, value):
	if path.begins_with("player"):
		player_panel.bind_character(value)
	elif path.begins_with("enemy"):
		enemy_panel.bind_character(value)
	_refresh_all()

func _refresh_all():
	var player = state.get_value("player")
	if player == null:
		_clear_ui()
		return
	visible = true
	
	var gold = state.get_value("gold", 0)
	_update_gold(gold)
	
func _update_gold(value):
	if value > displayed_gold:
		flash_gold(Color(1, 1, 0.4)) # vermelho
	elif value < displayed_gold:
		flash_gold(Color(1, 0.4, 0.4)) # vermelho
	var tween = create_tween()
	tween.tween_method(_set_gold_text, displayed_gold, value, 0.3)
	displayed_gold = value
	
func flash_gold(color):
	gold_label.modulate = color
	await get_tree().create_timer(0.15).timeout
	gold_label.modulate = Color(1,1,1)

func _set_gold_text(val):
	gold_label.text = _format_number(int(val))
	
func _format_number(n):
	var s = str(n)
	var result = ""
	var count = 0
	
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "." + result
	
	return result

func _clear_ui():
	visible = false
