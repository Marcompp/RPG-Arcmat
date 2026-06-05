extends Control

signal new_game_requested
signal continue_requested(slot: int)
signal options_requested

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
	_clear_save_list()

	# Outer wrapper: title (fixed) + scroll (expanding) + back (fixed)
	_save_list = VBoxContainer.new()
	_save_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	_save_list.add_theme_constant_override("separation", 10)
	add_child(_save_list)

	var title = Label.new()
	title.text = "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.custom_minimum_size = Vector2(0, 60)
	_save_list.add_child(title)

	# Scroll area expands to fill remaining vertical space
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_save_list.add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var saves = SaveManager.list_saves()
	var first_load_btn: Button = null
	for info in saves:
		var row = _make_save_row(info)
		rows.add_child(row)
		if first_load_btn == null:
			first_load_btn = row.get_child(0)

	var back = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(400, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): setup(SaveManager.list_saves().size() > 0))
	_save_list.add_child(back)

	if first_load_btn:
		first_load_btn.grab_focus()

func _make_save_row(info: Dictionary) -> HBoxContainer:
	var meta = info["meta"]
	var slot: int = info["slot"]

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Load button
	var load_btn = Button.new()
	load_btn.text = "Slot %d   %s - %s, %s  Lv.%d\n%s" % [
		slot,
		meta.get("current_region", "Unknown"),
		meta.get("character_name", "Unknown"),
		meta.get("character_class", ""),
		meta.get("level", 1),
		meta.get("datetime", "")
	]
	load_btn.custom_minimum_size = Vector2(480, 64)
	load_btn.pressed.connect(func(): continue_requested.emit(slot))
	row.add_child(load_btn)

	# Duplicate button
	var dup_btn = Button.new()
	dup_btn.text = "Copy"
	dup_btn.custom_minimum_size = Vector2(64, 0)
	dup_btn.pressed.connect(func():
		SaveManager.duplicate_save(slot)
		_show_save_list()
	)
	row.add_child(dup_btn)

	# Delete button (shown first)
	var del_btn = Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(72, 0)

	# Confirmation buttons (hidden until Delete is pressed)
	var confirm_btn = Button.new()
	confirm_btn.text = "Sure?"
	confirm_btn.custom_minimum_size = Vector2(72, 0)
	confirm_btn.visible = false

	var cancel_btn = Button.new()
	cancel_btn.text = "No"
	cancel_btn.custom_minimum_size = Vector2(48, 0)
	cancel_btn.visible = false

	del_btn.pressed.connect(func():
		del_btn.visible = false
		confirm_btn.visible = true
		cancel_btn.visible = true
		confirm_btn.grab_focus()
	)
	confirm_btn.pressed.connect(func():
		SaveManager.delete_save(slot)
		_show_save_list()
	)
	cancel_btn.pressed.connect(func():
		confirm_btn.visible = false
		cancel_btn.visible = false
		del_btn.visible = true
		del_btn.grab_focus()
	)

	row.add_child(del_btn)
	row.add_child(confirm_btn)
	row.add_child(cancel_btn)

	return row

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
	options_requested.emit()

func _on_quit_button_pressed():
	get_tree().quit()
