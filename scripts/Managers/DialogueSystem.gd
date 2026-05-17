extends Control
class_name DialogueSystem

signal choice_selected(choice_data)

@onready var story_text = $StoryText
@onready var choice_label = $ChoiceLabel
@onready var buttons = [
	$Choices/ChoicesClip/ChoicesInner/Row1/Choice1,
	$Choices/ChoicesClip/ChoicesInner/Row1/Choice2,
	$Choices/ChoicesClip/ChoicesInner/Row2/Choice3,
	$Choices/ChoicesClip/ChoicesInner/Row2/Choice4,
	$Choices/Row0/Back
]
@onready var left_button   = $Choices/Row0/Left
@onready var right_button  = $Choices/Row0/Right
@onready var choices_clip  = $Choices/ChoicesClip
@onready var choices_inner = $Choices/ChoicesClip/ChoicesInner
@onready var fade = $LogPanel/Fade
@onready var log_panel = $LogPanel
@onready var log_panel_panel = $LogPanel/Panel
@onready var log_container = $LogPanel/Panel/ScrollContainer/LogContainer

var visible_choice_map = []

var typing_speed = 0.03
var typing_id = 0
var is_typing = false

var _command_map = {}
var _show_choices_after_typing = true
var _pending_choices = false
var choice_header = ""
var visible_chars = 0
var current_choices = []
var current_page: int = 0
var _is_sliding: bool = false

var condition_callback = null

var dialogue_log = []

func shake():
	var original = position
	
	for i in range(5):
		position = original + Vector2(randf_range(-5,5), randf_range(-5,5))
		await get_tree().create_timer(0.02).timeout
	
	position = original

# ------------------------
# PUBLIC API
# ------------------------

func play_node(node_data):
	hide_choices()
	current_choices = node_data.get("choices", [])
	choice_header = node_data.get("header","")
	current_page = 0
	start_typing(node_data.get("text", ""))

# NOVO: usado pelo GameManager
func set_choices(choices, header):
	current_choices = choices
	choice_header = header
	current_page = 0

	if is_typing:
		_pending_choices = true
		return

	_pending_choices = false
	show_choices()

# ------------------------
# TYPEWRITER
# ------------------------

func start_typing(text):
	print('START_TYPING')
	clear_text()
	_command_map = {}
	_show_choices_after_typing = true
	_pending_choices = false
	var clean = _parse_commands(text, 0)
	log_add_text(clean)
	story_text.text = clean
	typing_id += 1
	is_typing = true
	hide_choices()
	_type_text(typing_id)

func finish_typing():
	if not is_typing:
		return

	typing_id += 1
	is_typing = false
	var total = story_text.get_total_character_count()
	visible_chars = total
	story_text.visible_characters = visible_chars

	MyEventBus.emit("typing_finished", {"done": true})
	if _show_choices_after_typing or _pending_choices:
		_pending_choices = false
		show_choices()

func append_text(text):
	hide_choices()
	_show_choices_after_typing = false
	_pending_choices = false
	typing_id += 1
	var clean = _parse_commands(text, visible_chars)
	log_add_text(clean)
	story_text.text += clean
	is_typing = true
	_type_text(typing_id)

func _type_text(id):
	var total = story_text.get_total_character_count()
	while visible_chars < total:
		if not is_typing or id != typing_id:
			return

		if _command_map.has(visible_chars):
			var start_vc = visible_chars
			for cmd in _command_map[visible_chars]:
				if not is_typing or id != typing_id:
					return
				match cmd["type"]:
					"screenshake":
						shake()
					"wait":
						await get_tree().create_timer(cmd["duration"]).timeout
						if not is_typing or id != typing_id:
							return
					"instant":
						visible_chars = cmd["end_pos"]
						story_text.visible_characters = visible_chars
			if visible_chars == start_vc:
				visible_chars += 1
				story_text.visible_characters = visible_chars
				await get_tree().create_timer(typing_speed).timeout
		else:
			visible_chars += 1
			story_text.visible_characters = visible_chars
			await get_tree().create_timer(typing_speed).timeout

	if id != typing_id:
		return

	is_typing = false
	await get_tree().process_frame
	MyEventBus.emit("typing_finished", {"done": true})
	if _show_choices_after_typing or _pending_choices:
		_pending_choices = false
		show_choices()

func _parse_commands(raw_text: String, offset: int) -> String:
	var clean = ""
	var visible_pos = offset
	var i = 0
	while i < raw_text.length():
		if raw_text[i] != '[':
			clean += raw_text[i]
			visible_pos += 1
			i += 1
			continue
		var end = raw_text.find(']', i)
		if end == -1:
			clean += raw_text[i]
			visible_pos += 1
			i += 1
			continue
		var tag = raw_text.substr(i + 1, end - i - 1)
		if tag.begins_with("screenshake"):
			if not _command_map.has(visible_pos):
				_command_map[visible_pos] = []
			_command_map[visible_pos].append({"type": "screenshake"})
			i = end + 1
		elif tag.begins_with("wait="):
			var duration = tag.substr(5).to_float()
			if not _command_map.has(visible_pos):
				_command_map[visible_pos] = []
			_command_map[visible_pos].append({"type": "wait", "duration": duration})
			i = end + 1
		elif tag == "instant":
			var close_str = "[/instant]"
			var close = raw_text.find(close_str, end + 1)
			if close != -1:
				var inner = raw_text.substr(end + 1, close - end - 1)
				var inner_visible = _bbcode_visible_length(inner)
				if not _command_map.has(visible_pos):
					_command_map[visible_pos] = []
				_command_map[visible_pos].append({"type": "instant", "end_pos": visible_pos + inner_visible})
				clean += inner
				visible_pos += inner_visible
				i = close + close_str.length()
			else:
				clean += raw_text.substr(i, end - i + 1)
				i = end + 1
		elif tag == "/instant":
			i = end + 1
		else:
			clean += raw_text.substr(i, end - i + 1)
			i = end + 1
	return clean

func _bbcode_visible_length(text: String) -> int:
	var count = 0
	var i = 0
	while i < text.length():
		if text[i] == '[':
			var end = text.find(']', i)
			if end == -1:
				count += 1
				i += 1
			else:
				i = end + 1
		else:
			count += 1
			i += 1
	return count

func clear_text():
	typing_id += 1
	is_typing = false
	visible_chars = 0
	story_text.visible_characters = 0
	story_text.text = ""
	await get_tree().process_frame

# ------------------------
# CHOICES
# ------------------------

func evaluate_choice(choice):
	if choice.get("disabled", false):
		return false
	if not choice.has("condition"):
		return true

	if condition_callback == null:
		return true

	return condition_callback.call(choice["condition"])

func show_choices():
	hide_choices()
	visible_choice_map.clear()

	choice_label.text = "[b]" + choice_header + "[/b]"

	# Separate displayable normal choices from the back choice
	var displayable: Array = []
	for c in current_choices:
		if c.get("type", "") == "back":
			continue
		var enabled = evaluate_choice(c)
		if enabled or c.has("disabled_text") or c.has("disabled_tooltip"):
			displayable.append(c)

	var total_pages: int = max(1, ceili(float(displayable.size()) / 4.0))
	current_page = clamp(current_page, 0, total_pages - 1)

	var page_start: int = current_page * 4
	var page_choices: Array = displayable.slice(page_start, page_start + 4)

	left_button.visible  = current_page > 0
	right_button.visible = current_page < total_pages - 1

	for i in range(4):
		if i < page_choices.size():
			var choice = page_choices[i]
			var enabled = evaluate_choice(choice)
			var button = buttons[i]

			button.text = choice["disabled_text"] if (not enabled and choice.has("disabled_text")) else choice["text"]
			apply_button_style(button, choice, enabled)

			var tooltip = _get_tooltip_text(choice, enabled)
			button.tooltip_text = tooltip if tooltip else ""
			button.has_tooltip  = tooltip != "" and tooltip != null

			button.show()
			visible_choice_map.append(choice)
		else:
			buttons[i].hide()

	# Back button — always stays in Row0
	var back_button = buttons[4]
	var has_back = false
	for c in current_choices:
		if c.get("type", "") == "back":
			back_button.text = c["text"]
			apply_button_style(back_button, c, true)
			back_button.tooltip_text = _get_tooltip_text(c, true)
			back_button.show()
			has_back = true
			break
	if not has_back:
		back_button.hide()

func hide_choices():
	choice_label.text = ""
	for b in buttons:
		b.hide()
		b.tooltip_text = ""
		b.has_tooltip = false
		
func apply_button_style(button, choice, enabled):
	button.modulate = Color(1,1,1,1)
	# button.disabled = false

	if not enabled:
		button.modulate = Color(0.5, 0.5, 0.5)
		# button.disabled = true
		return

	if choice.get("highlight", false):
		button.modulate = Color(1.2, 1.1, 0.6)

# ------------------------
# PAGINATION / SLIDE
# ------------------------

const CLIP_PADDING = 1

func _sync_choices_size():
	var min_h = choices_inner.get_minimum_size().y
	choices_clip.custom_minimum_size = Vector2(0, min_h + CLIP_PADDING * 2)
	choices_inner.size = Vector2(max(0.0, choices_clip.size.x - CLIP_PADDING * 2), min_h)
	if not _is_sliding:
		choices_inner.position = Vector2(CLIP_PADDING, CLIP_PADDING)

func _on_left_pressed():
	if not _is_sliding:
		_slide_to_page(current_page - 1, -1)

func _on_right_pressed():
	if not _is_sliding:
		_slide_to_page(current_page + 1, 1)

func _slide_to_page(new_page: int, direction: int):
	_is_sliding = true
	var w = choices_clip.size.x

	var tween_out = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween_out.tween_property(choices_inner, "position:x", CLIP_PADDING - direction * w, 0.15)
	await tween_out.finished

	current_page = new_page
	show_choices()
	choices_inner.position.x = CLIP_PADDING + direction * w
	_sync_choices_size()

	var tween_in = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween_in.tween_property(choices_inner, "position:x", float(CLIP_PADDING), 0.15)
	await tween_in.finished

	_is_sliding = false

#----------------------
#LOG
#----------------------

func log_add_text(text):
	dialogue_log.append({
		"type": "text",
		"content": text
	})
	
func log_add_choice(text):
	dialogue_log.append({
		"type": "choice",
		"content": text
	})
	
func rebuild_log_ui():
	# limpa UI
	for child in log_container.get_children():
		child.queue_free()
	
	for entry in dialogue_log:
		var label = Label.new()
		
		if entry["type"] == "text":
			label.text = entry["content"] + "\n"
			label.modulate = Color(1,1,1)
		
		elif entry["type"] == "choice":
			label.text = "> " + entry["content"]+"\n"
			label.modulate = Color(0.8, 1.0, 0.6) # verdinho
		
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		log_container.add_child(label)
	
	await get_tree().process_frame
	
	# scroll automático pro fim
	var scroll = log_container.get_parent()
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

# ---------------------
# TOOLTIP
# ---------------------

func _make_custom_tooltip(text):
	print('WTF TOOLTIP')
	if text == null or text == "" or text == "null":
		return null  # 🔥 não cria tooltip
	var label = Label.new()
	
	label.text = text
	
	# fonte monoespaçada
	var font = load("res://Fonts/JetBrainsMono-Regular.ttf")
	label.add_theme_font_override("font", font)
	
	label.add_theme_font_size_override("font_size", 80)
	
	# padding (opcional, mas melhora MUITO)
	label.add_theme_constant_override("margin_left", 6)
	label.add_theme_constant_override("margin_top", 4)
	label.add_theme_constant_override("margin_right", 6)
	label.add_theme_constant_override("margin_bottom", 4)
	
	return label

func _get_tooltip_text(choice, enabled):
	# tooltip explícito
	if choice.has("tooltip"):
		return choice["tooltip"]
	
	# fallback inteligente (opcional)
	if not enabled:
		if choice.has("disabled_tooltip"):
			return choice["disabled_tooltip"]
		if choice.has("condition"):
			return format_condition_tooltip(choice["condition"])
	
	return ""

func format_condition_tooltip(cond):
	if typeof(cond) != TYPE_DICTIONARY:
		return ""
	
	var parts = []
	
	for key in cond.keys():
		var req = cond[key]
		
		if typeof(req) == TYPE_DICTIONARY:
			if req.has("min"):
				parts.append(key.capitalize() + " ≥ " + str(req["min"]))
			if req.has("max"):
				parts.append(key.capitalize() + " ≤ " + str(req["max"]))
		else:
			parts.append(key.capitalize() + " = " + str(req))
	
	return ", ".join(parts)

# ------------------------
# INPUT
# ------------------------

func _input(event):
	if event.is_pressed() and is_typing:
		finish_typing()

# ------------------------
# INIT
# ------------------------

func _ready():
	MyEventBus.subscribe("screenshake", func(data):
		shake()
	)
	for i in range(buttons.size()):
		buttons[i].pressed.connect(_on_button_pressed.bind(i))
	MyEventBus.subscribe("show_choices", func(data):
		set_choices(data.get("choices", []), data.get("header", ""))
	)
	MyEventBus.subscribe("dialogue", func(data):
		play_node(data)
	)
	MyEventBus.subscribe("clear_text", func(data):
		clear_text()
	)
	MyEventBus.subscribe("continue_text", func(data):
		var linebreak = "\n\n" if data.get("linebreak",true) else "\n" 
		append_text(linebreak + data.get("text", ""))
	)
	left_button.pressed.connect(_on_left_pressed)
	right_button.pressed.connect(_on_right_pressed)
	choices_inner.minimum_size_changed.connect(_sync_choices_size)
	choices_clip.resized.connect(_sync_choices_size)
	story_text.bbcode_enabled = true
	$LogButton.pressed.connect(toggle_log)
	$LogPanel/CloseButton.pressed.connect(close_log)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	fade.gui_input.connect(_on_fade_clicked)
	log_panel_panel.resized.connect(_update_pivot)
	_update_pivot()

func _update_pivot():
	log_panel_panel.pivot_offset = log_panel_panel.size / 2

# ------------------------
# BUTTON CLICK
# ------------------------

func _on_button_pressed(index):
	print("BOTÃO CLICADO", index)

	var choice = null
	
	# botão Back (último)
	if index == 4:
		for c in current_choices:
			if c.get("type", "") == "back":
				choice = c
	else:
		if index < current_choices.size():
			choice = visible_choice_map[index]
	
	if not evaluate_choice(choice):
		return
		
	log_add_choice(choice["text"])
	MyEventBus.emit("choice_selected", choice)
	#emit_signal("choice_selected", choice)
	
#----------------------
#LOG BUTTONS
#----------------------

func open_log():
	log_panel.show()
	
	fade.modulate.a = 0
	log_panel_panel.scale = Vector2(0.9, 0.9)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# fade escuro
	tween.tween_property(fade, "modulate:a", 0.6, 0.2)
	
	# painel aparece suave
	tween.tween_property(log_panel_panel, "scale", Vector2(1,1), 0.2)
	tween.tween_property(log_panel_panel, "modulate:a", 1.0, 0.2)
	rebuild_log_ui()

func close_log():
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(fade, "modulate:a", 0.0, 0.15)
	tween.tween_property(log_panel_panel, "scale", Vector2(0.9, 0.9), 0.15)
	tween.tween_property(log_panel_panel, "modulate:a", 0.0, 0.15)
	
	await tween.finished
	
	log_panel.hide()

func toggle_log():
	if log_panel.visible:
		close_log()
	else:
		open_log()


func _on_fade_clicked(event):
	if event is InputEventMouseButton and event.pressed:
		close_log()
