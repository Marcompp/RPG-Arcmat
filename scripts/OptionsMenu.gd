extends Control

signal closed

@onready var options_container = $OptionsPanel/OptionsMargin/AllContainer/OptionsContainer
@onready var back_button       = $OptionsPanel/OptionsMargin/AllContainer/ExitContainer/BackButton

func _ready():
	visible = false
	_populate_options()
	back_button.pressed.connect(func():
		visible = false
		closed.emit()
	)

func show_options():
	visible = true
	back_button.grab_focus()

# ========================
# POPULATE
# ========================

func _populate_options():
	_add_section_label("Audio")
	_add_slider_row("BGM Volume", SettingsManager.bgm_volume * 100.0, func(v):
		SettingsManager.bgm_volume = v / 100.0
		SettingsManager.save_settings()
		get_parent().audio.set_bgm_volume(SettingsManager.bgm_volume)
	)
	_add_slider_row("Ambiance Volume", SettingsManager.ambiance_volume * 100.0, func(v):
		SettingsManager.ambiance_volume = v / 100.0
		SettingsManager.save_settings()
		get_parent().audio.set_ambiance_volume(SettingsManager.ambiance_volume)
	)
	_add_slider_row("SFX Volume", SettingsManager.sfx_volume * 100.0, func(v):
		SettingsManager.sfx_volume = v / 100.0
		SettingsManager.save_settings()
		get_parent().audio.set_sfx_volume(SettingsManager.sfx_volume)
	)

	options_container.add_child(HSeparator.new())

	_add_section_label("Gameplay")
	_add_slider_row("Text Speed", _typing_speed_to_slider(SettingsManager.typing_speed), func(v):
		SettingsManager.typing_speed = _slider_to_typing_speed(v)
		SettingsManager.save_settings()
		get_parent().dialogue.typing_speed = SettingsManager.typing_speed
	)

# ========================
# HELPERS
# ========================

func _add_section_label(text: String):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	options_container.add_child(lbl)

func _add_slider_row(label_text: String, initial_value: float, on_change: Callable):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	options_container.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(lbl)

	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl = Label.new()
	val_lbl.text = "%d" % int(initial_value)
	val_lbl.custom_minimum_size = Vector2(36, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v):
		val_lbl.text = "%d" % int(v)
		on_change.call(v)
	)

# typing_speed (sec/char) → slider 0–100, 100 = fastest / instant
func _typing_speed_to_slider(ts: float) -> float:
	if ts <= 0.0:
		return 100.0
	return clampf((1.0 - (ts - 0.01) / 0.09) * 100.0, 0.0, 99.0)

func _slider_to_typing_speed(v: float) -> float:
	if v >= 100.0:
		return 0.0
	return lerp(0.10, 0.01, v / 99.0)
