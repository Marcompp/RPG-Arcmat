extends Control

signal new_game_requested
signal continue_requested(slot: int)

@onready var main_buttons    = $VBoxContainer
@onready var continue_button = $VBoxContainer/ContinueButton
@onready var new_game_button = $VBoxContainer/NewGameButton

var _save_list: VBoxContainer = null

func _ready():
	new_game_button.pressed.connect(_on_new_game_button_pressed)
	continue_button.pressed.connect(_on_continue_button_pressed)
	$VBoxContainer/OptionsButton.pressed.connect(_on_options_button_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_button_pressed)

func setup(has_saves: bool):
	_clear_save_list()
	main_buttons.visible = true
	continue_button.visible = has_saves
	if has_saves:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()

# ------------------------
# SAVE LIST
# ------------------------

func _show_save_list():
	main_buttons.visible = false

	_save_list = VBoxContainer.new()
	_save_list.layout_mode = 1
	_save_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	_save_list.add_theme_constant_override("separation", 14)
	add_child(_save_list)

	var title = Label.new()
	title.text = "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.custom_minimum_size = Vector2(0, 60)
	_save_list.add_child(title)

	var saves = SaveManager.list_saves()
	var first_btn: Button = null
	for info in saves:
		var meta = info["meta"]
		var btn = Button.new()
		btn.text = "Slot %d –  %s, Lv.%d %s\n%s" % [
			info["slot"],
			meta.get("character_name", "Unknown"),
			meta.get("level", 1),
			meta.get("character_class", "Unknown"),
			meta.get("datetime", "")
		]
		btn.custom_minimum_size = Vector2(400, 64)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var slot = info["slot"]
		btn.pressed.connect(func(): continue_requested.emit(slot))
		_save_list.add_child(btn)
		if first_btn == null:
			first_btn = btn

	var back = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(400, 52)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): setup(true))
	_save_list.add_child(back)

	if first_btn:
		first_btn.grab_focus()

func _clear_save_list():
	if _save_list:
		_save_list.queue_free()
		_save_list = null

# ------------------------
# BUTTON CALLBACKS
# ------------------------

func _on_new_game_button_pressed():
	new_game_requested.emit()

func _on_continue_button_pressed():
	_show_save_list()

func _on_options_button_pressed():
	pass

func _on_quit_button_pressed():
	get_tree().quit()
