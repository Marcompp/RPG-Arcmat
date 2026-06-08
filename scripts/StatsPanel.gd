#extends Panel
extends Control

var character = null
var state

var _rest_pos: Vector2 = Vector2.ZERO
var _death_tween: Tween = null
var _death_gen: int = 0
var _bars_tween: Tween = null
var _shake_count: int = 0
var _dead: bool = false

@onready var name_label = $Panel/VBoxContainer/NameContainer/NameLabel
@onready var status_container = $Panel/VBoxContainer/NameContainer/StatusContainer

var _status_db: Dictionary = {}
var _trinkets_db: Dictionary = {}
var _element_db: Dictionary = {}
var _last_trinket_states: Dictionary = {}
var _element_color: Color = Color.BLACK
#@onready var gold_label = $TopCenterPanel/VBoxContainer/GoldContainer/GoldValue

@onready var hp_bar = $Panel/VBoxContainer/HPContainer/Control/HPBar
@onready var hp_text = $Panel/VBoxContainer/HPContainer/Control/HPText

@onready var mp_bar = $Panel/VBoxContainer/MPContainer/Control/MPBar
@onready var mp_text = $Panel/VBoxContainer/MPContainer/Control/MPText

@onready var trinket_container = $TrinketContainer
@onready var panel = $Panel

const PIXELS_PER_POINT = 5
const MAX_BAR_WIDTH = 170

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


func _ready():
	tooltip_text = " "  # obrigatório
	mouse_filter = Control.MOUSE_FILTER_STOP
	_disable_mouse_on_children(self)
	_status_db   = _load_status_db()
	_trinkets_db = _load_trinkets_db()
	_element_db  = _load_element_db()

func _load_trinkets_db() -> Dictionary:
	if not FileAccess.file_exists("res://Database/trinkets.json"):
		return {}
	var file = FileAccess.open("res://Database/trinkets.json", FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func _load_element_db() -> Dictionary:
	if not FileAccess.file_exists("res://Database/element.json"):
		return {}
	var file = FileAccess.open("res://Database/element.json", FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func _load_status_db() -> Dictionary:
	if not FileAccess.file_exists("res://Database/status.json"):
		return {}
	var file = FileAccess.open("res://Database/status.json", FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func update_statuses(effects: Array) -> void:
	for child in status_container.get_children():
		child.queue_free()
	for s in effects:
		status_container.add_child(_make_status_icon(s["type"], s["duration"]))

func update_trinkets(trinkets: Array, states: Dictionary = {}) -> void:
	if not states.is_empty():
		_last_trinket_states = states
	for child in trinket_container.get_children():
		child.queue_free()
	var counts: Dictionary = {}
	for t in trinkets:
		counts[t] = counts.get(t, 0) + 1
	for trinket_name in counts:
		var state = _last_trinket_states.get(trinket_name, {})
		trinket_container.add_child(_make_trinket_icon(trinket_name, counts[trinket_name], state))

func _make_trinket_icon(name: String, count: int, state: Dictionary = {}) -> Control:
	var data: Dictionary = _trinkets_db.get(name, {})
	const ICON_SIZE := 20

	var root := Control.new()
	root.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	# Tooltip
	var display_name = data.get("name", name)
	if count > 1:
		display_name += " x%d" % count
	var description = data.get("description", "")
	var tooltip = display_name + ("\n" + description if description != "" else "")
	var effect = data.get("effect", "")
	if effect == "duelist_combo" and not state.is_empty() and state.get("combo", 0) > 0:
		tooltip += "\nCurrent Combo: %d" % state.get("combo", 0)
	root.tooltip_text = tooltip

	# Icon
	var tex_rect := TextureRect.new()
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_file: String = data.get("icon", "trinket.png")
	var tex_path := "res://assets/icons/" + icon_file
	if not ResourceLoader.exists(tex_path):
		tex_path = "res://assets/icons/trinket.png"
	if ResourceLoader.exists(tex_path):
		tex_rect.texture = load(tex_path)
	root.add_child(tex_rect)

	# Badge: combo count takes priority over stack count
	var combo = state.get("combo", 0)
	var badge_text = ""
	if effect == "duelist_combo" and combo > 0:
		badge_text = str(combo)
	elif count > 1:
		badge_text = "x%d" % count
	if badge_text != "":
		var badge := Label.new()
		badge.text = badge_text
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 2)
		badge.anchor_left     = 1.0
		badge.anchor_right    = 1.0
		badge.anchor_top      = 1.0
		badge.anchor_bottom   = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		badge.mouse_filter    = Control.MOUSE_FILTER_IGNORE
		root.add_child(badge)

	return root

func _make_status_icon(key: String, duration: int) -> Control:
	var data: Dictionary = _status_db.get(key, {})
	const ICON_SIZE := 20

	var root := Control.new()
	root.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.tooltip_text = "%s (%d turn%s)" % [
		data.get("name", key), duration, "s" if duration != 1 else ""
	]

	var tex_rect := TextureRect.new()
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_file: String = data.get("icon", "")
	var tex_path := "res://assets/icons/" + icon_file
	if icon_file != "" and ResourceLoader.exists(tex_path):
		tex_rect.texture = load(tex_path)
	root.add_child(tex_rect)

	if duration > 0:
		var badge := Label.new()
		badge.text = str(duration)
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 2)
		badge.anchor_left     = 1.0
		badge.anchor_right    = 1.0
		badge.anchor_top      = 1.0
		badge.anchor_bottom   = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		badge.mouse_filter    = Control.MOUSE_FILTER_IGNORE
		root.add_child(badge)

	return root

func shake():
	if _death_tween != null:
		return
	var base_pos = position  # captura posição real no momento do shake
	_shake_count += 1
	for i in range(5):
		position = base_pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		await get_tree().create_timer(0.02).timeout
	_shake_count -= 1
	if _shake_count == 0:
		position = base_pos

func bind(game_state):
	state = game_state
	
	var player = state.get_value("player")
	if player:
		bind_character(player)
	
	state.changed.connect(_on_state_changed)
	_refresh_all()
	
func bind_character(char):
	_dead = false
	_cancel_death_anim()
	_bind_character(char)
	_refresh_all()
	
var _mp_react_next: bool = false

func _bind_character(char):
	if character:
		character.stats_changed.disconnect(_refresh_all)
		if character.mp_hit.is_connected(_on_mp_hit):
			character.mp_hit.disconnect(_on_mp_hit)

	character = char
	character.stats_changed.connect(_refresh_all)
	character.mp_hit.connect(_on_mp_hit)

func _on_mp_hit():
	_mp_react_next = true

func _on_state_changed(path, value):
	if path.begins_with("player"):
		bind_character(value)
	_refresh_all()

func _refresh_all():
	if character == null:
		_clear_ui()
		return
	if _dead:
		return
	visible = true
	modulate.a = 1.0

	if _bars_tween:
		_bars_tween.kill()
	_bars_tween = create_tween().set_parallel(true)

	var name = character.get_name()
	var cls = character.get_char_class()
	var hp = character.get_hp()
	var mhp = character.get_mhp()
	var mp = character.get_mp()
	var mmp = character.get_mmp()

	var lv = character.get_level()
	if cls != "":
		name_label.text = "[b]%s[/b]  Lv %d %s   " % [name, lv, cls]
	else:
		name_label.text = "Lv %d %s   " % [lv, name]

	_resize_bar(hp_bar, mhp, _bars_tween)
	_resize_bar(mp_bar, mmp, _bars_tween)
	_update_bar(hp_bar, hp, mhp, hp_text, true, _bars_tween)
	_update_bar(mp_bar, mp, mmp, mp_text, _mp_react_next, _bars_tween)
	_mp_react_next = false
	update_trinkets(character.get_trinkets())
	_update_element_color()


func _update_element_color():
	var elem = character.get_element()
	var hex = _element_db.get(elem, {}).get("color", "#000000")
	if elem == "Neutral":
		hex = "#000000"
	# self.self_modulate = Color(hex)
	_element_color = Color(hex+"33")
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), _element_color)

func _update_bar(bar, value, max_value, label: RichTextLabel = null, react_to_hit: bool = false, tween: Tween = null):
	if max_value <= 0:
		max_value = 1
	bar.max_value = max_value

	var ratio = float(value) / max_value

	if react_to_hit and value < bar.value:
		shake()
		flash_red()

	_update_bar_color(bar, ratio)

	var from: float = bar.value
	if tween:
		tween.tween_property(bar, "value", float(value), 0.2)
		if label:
			tween.tween_method(
				func(v: float): label.text = "%s/%d" % [_format_stat_value(int(v), max_value), max_value],
				from, float(value), 0.2
			)
	else:
		bar.value = float(value)
		if label:
			label.text = "%s/%d" % [_format_stat_value(int(value), max_value), max_value]
	
func _resize_bar(bar, max_value, tween: Tween = null):
	var width = max_value * PIXELS_PER_POINT
	print(width)

	if width > MAX_BAR_WIDTH:
		width = MAX_BAR_WIDTH

	if tween:
		tween.tween_property(bar, "custom_minimum_size:x", width, 0.2)
	else:
		bar.custom_minimum_size.x = width
	
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
	
func _format_stat_value(value: int, max_value: int) -> String:
	var ratio = float(value) / max(max_value, 1)

	var color: String
	var outline: String
	if value <= 0:
		color   = "#6E6E6E"
		outline = "#000000"
	elif ratio < 0.05:
		color   = "#B71C1C"
		outline = "#000000"
	elif ratio < 0.25:
		color   = "#FFD54F"
		outline = "000000"
	elif value >= max_value:
		color   = "#00E676"
		outline = "#000000"
		#outline = "#00E676"
	else:
		color   = "#FFFFFF"
		outline = "000000"

	var inner := "[b]%s[/b]" % str(value).pad_zeros(str(max_value).length())
	if outline != "":
		inner = "[outline_size=2][outline_color=%s]%s[/outline_color][/outline_size]" % [outline, inner]
	return "[color=%s]%s[/color]" % [color, inner]

func death_animation():
	_dead = true
	if _death_tween:
		_death_tween.kill()

	_rest_pos = position  # captura posição real AGORA, após o container ter feito layout
	_death_gen += 1
	var gen = _death_gen

	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(self, "position:y", _rest_pos.y + 80, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.35)

	await get_tree().create_timer(0.45).timeout

	if gen != _death_gen:
		return
	_death_tween = null
	_clear_ui()

func _cancel_death_anim():
	_death_gen += 1
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
		position = _rest_pos  # só reseta se havia animação rodando
	modulate.a = 1.0

func flash_red():
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	modulate = Color(1,1,1)

func _clear_ui():
	_cancel_death_anim()
	if _bars_tween:
		_bars_tween.kill()
		_bars_tween = null
	modulate.a = 0
	name_label.text = ""
	hp_bar.value = 0
	mp_bar.value = 0
	hp_text.text = ""
	mp_text.text = ""
	position = _rest_pos
	for child in status_container.get_children():
		child.queue_free()
	for child in trinket_container.get_children():
		child.queue_free()

#----------------
#Funcionalidades Tooltip:
#-----------------
	
func _disable_mouse_on_children(node):
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_disable_mouse_on_children(child)

func _get_tooltip(at_position):
	print("HOVER OK")
	if character == null:
		return ""
	return build_character_tooltip(character)

func _make_custom_tooltip(text):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = text
	
	
	# 🔥 ESSENCIAL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# 🔥 define largura
	label.custom_minimum_size = Vector2(250, 0)
	
	label.scroll_active = false
	label.fit_content = true
	return label

func build_character_tooltip(char):
	var t = ""
	
	# ========================
	# HEADER
	# ========================
	t += "[b]%s[/b]  Lv.%d\n" % [char.get_name(), char.get_level()]
	var char_class = char.get_char_class()
	if char_class and char_class != "":
		t += "Class: %s\n" % char.get_char_class()
	var curr_element = char.get_element()
	if curr_element != "Neutral":
		var elcolor = _element_db.get(curr_element, {}).get("color", "#FFFFFF")
		t += "[color=%s]Element: %s[/color]\n" % [elcolor, curr_element]
	t += "\n"
	
	# ========================
	# HP / MP
	# ========================
	t += "HP: %d / %d\n" % [char.get_hp(), char.get_mhp()]
	t += "MP: %d / %d\n\n" % [char.get_mp(), char.get_mmp()]
	
	# ========================
	# STATS GRID
	# ========================
	t += "[b]Stats[/b]\n"
	t += "[table=5]"
	
	var stats = char.base_stats
	
	var keys = ["str","int","agi","dex","def","lck"]

	for i in range(0, keys.size(), 2):
		var k1 = keys[i]
		var base1 = char.base_stats.get(k1, 0)
		var bonus1 = char.get_equipment_bonus(k1)
		var total1 = base1 + bonus1
		
		var c1 = get_stat_color(bonus1)
		var text1 = "%d" % total1
		
		#if bonus1 != 0:
			#text1 += " (%+d)" % bonus1
		
		if c1 != "":
			text1 = "[color=%s]%s[/color]" % [c1, text1]
		
		t += "[cell]%s:[/cell][cell][b]%s[/b][/cell][cell]   [/cell]" % [k1.to_upper(), text1]
		
		# segunda coluna
		if i + 1 < keys.size():
			var k2 = keys[i + 1]
			var base2 = char.base_stats.get(k2, 0)
			var bonus2 = char.get_equipment_bonus(k2)
			var total2 = base2 + bonus2
			
			var c2 = get_stat_color(bonus2)
			var text2 = "%d" % total2
			
			#if bonus2 != 0:
				#text2 += " (%+d)" % bonus2
			
			if c2 != "":
				text2 = "[color=%s]%s[/color]" % [c2, text2]
			
			t += "[cell]%s:[/cell][cell][b]%s[/b][/cell]" % [k2.to_upper(), text2]
			
	t += "[/table]\n\n"
	
	# ========================
	# EQUIPMENT
	# ========================
	var equip = char.get_equipment() if char.has_method("get_equipment") else {}
	
	if equip.size() > 0:
		t += "[b]Equipment[/b]\n"
		for slot in equip:
			t += "%s: %s\n" % [slot.capitalize(), equip[slot]["name"]]
		t += "\n"
	
	# # ========================
	# # SKILLS
	# # ========================
	# var skills = char.data.get("Skills", [])
	# if skills.size() > 0:
	# 	t += "[b]Skills[/b]\n"
	# 	for s in skills:
	# 		t += "- %s\n" % s
	# 	t += "\n"
	
	# # ========================
	# # SPELLS
	# # ========================
	# var spells = char.data.get("Spells", [])
	# if spells.size() > 0:
	# 	t += "[b]Spells[/b]\n"
	# 	for s in spells:
	# 		t += "- %s\n" % s
	# 	t += "\n"
	
	return t.strip_edges()


func get_stat_color(bonus):
	if bonus > 0:
		return "#00E676" # verde
	elif bonus < 0:
		return "#FFD54F" # amarelo
	return "" # sem cor
