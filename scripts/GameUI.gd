extends Control

@onready var tlpanel = $TopLeftWrapper
@onready var name_label = $TopLeftWrapper/TopLeftPanel/VBoxContainer/NameLabel
@onready var gold_label = $TopCenterPanel/VBoxContainer/GoldContainer/GoldValue

@onready var hp_bar = $TopLeftWrapper/TopLeftPanel/VBoxContainer/HPContainer/Control/HPBar
@onready var hp_text = $TopLeftWrapper/TopLeftPanel/VBoxContainer/HPContainer/Control/HPText

@onready var mp_bar = $TopLeftWrapper/TopLeftPanel/VBoxContainer/MPContainer/Control/MPBar
@onready var mp_text = $TopLeftWrapper/TopLeftPanel/VBoxContainer/MPContainer/Control/MPText

var state

const PIXELS_PER_POINT = 10
const MAX_BAR_WIDTH = 500

const bar_colors = {
	"hp": [
		Color(0.2, 1.0, 0.2),
		Color(1.0, 0.8, 0.2),
		Color(1.0, 0.2, 0.2)
	],
	"mp": [
		Color(0.3, 0.6, 1.0),
		Color(0.3, 0.6, 1.0),
		Color(0.5, 0.5, 0.5)
	]
}

var character = null

func _ready():
	tlpanel.tooltip_text = ""
	tlpanel.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in tlpanel.get_children():
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
		_bind_character(player)
	
	state.changed.connect(_on_state_changed)
	_refresh_all()
	
func _bind_character(char):
	if character:
		character.stats_changed.disconnect(_refresh_all)
	
	tlpanel.character = char  # 🔥 ESSENCIAL
	
	character = char
	character.stats_changed.connect(_refresh_all)

func _on_state_changed(path, value):
	if path.begins_with("player"):
		_bind_character(value)
	_refresh_all()

func _refresh_all():
	var player = state.get_value("player")
	if player == null:
		_clear_ui()
		return
	visible = true
	
	var gold = state.get_value("gold", 0)
	_update_gold(gold)
	
	var name = character.get_name()
	var cls = character.get_char_class()
	
	var hp = character.get_hp()
	var mhp = character.get_mhp()
	var mp = character.get_mp()
	var mmp = character.get_mmp()

	# Nome
	name_label.text = "[b]%s[/b]  Lv 1 %s" % [name, cls]

	# resize baseado no max
	_resize_bar(hp_bar, mhp)
	_resize_bar(mp_bar, mmp)

	# Barras
	_update_bar(hp_bar, hp, mhp)
	_update_bar(mp_bar, mp, mmp)

	# Texto pequeno opcional
	hp_text.text = "%d/%d" % [hp,mhp]
	mp_text.text = "%d/%d" % [mp,mmp]


func _update_bar(bar, value, max_value):
	if max_value <= 0:
		max_value = 1
	bar.max_value = max_value
	
	var ratio = float(value) / max_value
	
	if value < bar.value:
		flash_red()
	
	_update_bar_color(bar, ratio)
	
	var tween = create_tween()
	tween.tween_property(bar, "value", value, 0.2)
	
func _resize_bar(bar, max_value):
	var width = max_value * PIXELS_PER_POINT
	
	var scale_factor = 1.0
	
	if width > MAX_BAR_WIDTH:
		scale_factor = MAX_BAR_WIDTH / width
		width = MAX_BAR_WIDTH
	
	bar.custom_minimum_size.x = width
	var tween = create_tween()
	tween.tween_property(bar, "size:x", width, 0.2)
	
func _update_bar_color(bar, ratio):
	var colors = []
	if bar == hp_bar:
		colors = bar_colors["hp"]
	elif bar == mp_bar:
		colors = bar_colors["mp"]
	if ratio >= 0.5:
		bar.modulate = colors[0] # verde
	elif ratio >= 0.25:
		bar.modulate = colors[1] # amarelo
	else:
		bar.modulate = colors[2] # vermelho
	
func _update_hp_color(ratio):
	if ratio >= 0.5:
		hp_bar.modulate = Color(0.2, 1.0, 0.2) # verde
	elif ratio >= 0.25:
		hp_bar.modulate = Color(1.0, 0.8, 0.2) # amarelo
	else:
		hp_bar.modulate = Color(1.0, 0.2, 0.2) # vermelho
	
func _update_mp_color(ratio):
	if ratio >= 0.5:
		mp_bar.modulate = Color(0.3, 0.6, 1.0) # azul
	elif ratio < 0.25:
		mp_bar.modulate = Color(0.5, 0.5, 0.5) # cinza
	else:
		mp_bar.modulate = Color(0.3, 0.6, 1.0) # mantém azul
	
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
	
func flash_red():
	tlpanel.modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	tlpanel.modulate = Color(1,1,1)

func _clear_ui():
	visible = false
	name_label.text = ""
	hp_bar.value = 0
	mp_bar.value = 0
	hp_text.text = ""
	mp_text.text = ""
