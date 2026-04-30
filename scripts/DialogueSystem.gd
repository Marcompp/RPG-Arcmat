extends Control
class_name DialogueSystem

signal choice_selected(choice_data)

@onready var story_text = $StoryText
@onready var buttons = [
	$Choices/Row1/Choice1,
	$Choices/Row1/Choice2,
	$Choices/Row2/Choice3,
	$Choices/Row2/Choice4,
	$Choices/Row0/Back
]

var visible_choice_map = []

var typing_speed = 0.03
var typing_id = 0
var is_typing = false

var full_text = ""
var visible_chars = 0
var current_choices = []

var condition_callback = null

# ------------------------
# PUBLIC API
# ------------------------

func play_node(node_data):
	hide_choices()
	current_choices = node_data.get("choices", [])
	start_typing(node_data.get("text", ""))

# NOVO: usado pelo GameManager
func set_choices(choices):
	current_choices = choices
	
	# se ainda estiver digitando, espera terminar
	if is_typing:
		return
	
	show_choices()

# ------------------------
# TYPEWRITER
# ------------------------

func start_typing(text):
	typing_id += 1
	
	full_text = text
	story_text.text = ""
	visible_chars = 0
	is_typing = true
	
	type_text(typing_id)

func type_text(id):
	while visible_chars < full_text.length():
		if not is_typing or id != typing_id:
			return
			
		story_text.text += full_text[visible_chars]
		visible_chars += 1
		await get_tree().create_timer(typing_speed).timeout
	
	if id != typing_id:
		return
	
	is_typing = false
	show_choices()

func finish_typing():
	if not is_typing:
		return
	
	typing_id += 1
	
	is_typing = false
	story_text.text = full_text
	visible_chars = full_text.length()
	
	show_choices()

# ------------------------
# CHOICES
# ------------------------

func evaluate_choice(choice):
	if not choice.has("condition"):
		return true
	
	if condition_callback == null:
		return true
	
	return condition_callback.call(choice["condition"])

func show_choices():
	hide_choices()
	visible_choice_map.clear()
	
	var visible_index = 0
	
	# primeiros 4 botões = escolhas normais
	for i in range(4):
		if i < current_choices.size() and current_choices[i].get("type", "") != "back":
			var choice = current_choices[i]
			
			var enabled = evaluate_choice(choice)
			
			if not enabled and not (choice.has("disabled_text") or choice.has("disabled_tooltip")):
				continue
			# não passar de 4 botões visíveis
			if visible_index >= 4:
				break
			
			var button = buttons[visible_index]
			# texto
			if not enabled and choice.has("disabled_text"):
				button.text = choice["disabled_text"]
			else:
				button.text = choice["text"]
			# visual highlight
			apply_button_style(button, choice, enabled)
			
			# tooltip
			var tooltip = _get_tooltip_text(choice, enabled)

			if tooltip == "" or tooltip == null:
				button.tooltip_text = ""
				button.has_tooltip = false
			else:
				button.tooltip_text = tooltip
				button.has_tooltip = true
			
			button.show()
			visible_choice_map.append(choice)
			visible_index += 1
		else:
			buttons[i].hide()
	
	# botão 4 = Back (especial)
	var back_button = buttons[4]
	var has_back = false
	
	for c in current_choices:
		if c.get("type", "") == "back":
			back_button.text = c["text"]
			back_button.disabled = false
			apply_button_style(back_button, c, true)
			# tooltip
			back_button.tooltip_text = _get_tooltip_text(c, true)
			back_button.show()
			has_back = true
			break
	
	if not has_back:
		back_button.hide()

func hide_choices():
	for b in buttons:
		b.hide()
		b.tooltip_text = ""
		b.has_tooltip = false
		
func apply_button_style(button, choice, enabled):
	
	# reset (IMPORTANTE)
	button.modulate = Color(1,1,1,1)
	
	if not enabled:
		button.modulate = Color(0.5, 0.5, 0.5)
		return
	
	if choice.get("highlight", false):
		button.modulate = Color(1.2, 1.1, 0.6) # leve dourado

# ---------------------
# TOOLTIP
# ---------------------

func _make_custom_tooltip(text):
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
	if not enabled and choice.has("condition"):
		return format_condition_tooltip(choice["condition"])
	
	return null

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
	for i in range(buttons.size()):
		buttons[i].pressed.connect(_on_button_pressed.bind(i))
	MyEventBus.subscribe("show_choices", func(data):
		set_choices(data.get("choices", []))
	)
	MyEventBus.subscribe("dialogue", func(data):
		play_node(data)
	)

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
		
	MyEventBus.emit("choice_selected", choice)
	#emit_signal("choice_selected", choice)
