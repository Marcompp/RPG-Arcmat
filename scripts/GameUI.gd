extends Control

@onready var player_panel = $TopLeft/TopLeftWrapper
@onready var enemy_panel = $TopRightWrapper
@onready var gold_label = $TopLeft/MoneyPanel/VBoxContainer/GoldContainer/GoldValue
@onready var area_label = $TopCenterPanel/VBoxContainer/AreaLabel
@onready var xp_bar = $TopLeft/TopLeftWrapper/XPBar
@onready var xp_text = $TopLeft/MoneyPanel/VBoxContainer/XPContainer/Control/XPText

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
	MyEventBus.subscribe("character_defeated", func(data):
		if data["victory"]:
			enemy_panel.death_animation()
		else:
			player_panel.death_animation()
	)
	MyEventBus.subscribe("combat_ended", func(_data):
		enemy_panel._clear_ui()
	)
	var xp_fill = StyleBoxFlat.new()
	xp_fill.bg_color = Color(0, 0.8, 1.0)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
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
		_bind_character(player)
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
	if path == "player":
		# Reconnect stats_changed to the new character instance
		if value != null:
			_bind_character(value)
		player_panel.bind_character(value)
	elif path.begins_with("player"):
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

	area_label.text = "[b]"+ state.get_value("region", "") +"[/b]"

	var xp_to_next = player.get_xp_to_next_level()
	var cur_xp = player.get_xp()
	xp_bar.max_value = xp_to_next
	xp_bar.value = cur_xp
	xp_text.text = "%d/%d" % [cur_xp, xp_to_next]
	
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

var _xp_tween: Tween = null
var _xp_skip := false

func animate_xp_gain(old_xp: int, old_level: int, level_ups: Array) -> void:
	_xp_skip = false
	var cur_xp = float(old_xp)
	var cur_level = old_level

	xp_bar.max_value = float(int(100.0 * pow(1.5, cur_level - 1)))
	xp_bar.value = cur_xp

	for _lvl in level_ups:
		var threshold = float(int(100.0 * pow(1.5, cur_level - 1)))
		xp_bar.max_value = threshold
		_xp_tween = create_tween()
		_xp_tween.tween_property(xp_bar, "value", threshold, 0.6)
		while _xp_tween and _xp_tween.is_running():
			if _xp_skip:
				return
			await get_tree().process_frame
		if _xp_skip:
			return
		await get_tree().create_timer(0.15).timeout
		if _xp_skip:
			return
		xp_bar.value = 0.0
		cur_level += 1

	var player = state.get_value("player")
	if not player:
		return
	xp_bar.max_value = float(player.get_xp_to_next_level())
	_xp_tween = create_tween()
	_xp_tween.tween_property(xp_bar, "value", float(player.get_xp()), 0.5)
	while _xp_tween and _xp_tween.is_running():
		if _xp_skip:
			return
		await get_tree().process_frame
	xp_bar.value = float(player.get_xp())
	xp_text.text = "%d/%d" % [player.get_xp(), player.get_xp_to_next_level()]
	_xp_tween = null

func skip_xp_animation() -> void:
	_xp_skip = true
	if _xp_tween and _xp_tween.is_running():
		_xp_tween.kill()
	_xp_tween = null
	var player = state.get_value("player")
	if player:
		xp_bar.max_value = float(player.get_xp_to_next_level())
		xp_bar.value = float(player.get_xp())
		xp_text.text = "%d/%d" % [player.get_xp(), player.get_xp_to_next_level()]
