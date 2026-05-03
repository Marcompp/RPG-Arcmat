# TooltipButton.gd
extends Button

var has_tooltip := false

func _get_tooltip(at_position):
	print('_GET_TOOLTIP')
	if not has_tooltip:
		return "" # 🔥 impede tooltip de existir
		
	if tooltip_text == null:
		return ""
		
	if tooltip_text == "" or tooltip_text.strip_edges().to_lower() == "null":
		return ""
	
	return tooltip_text

func _make_custom_tooltip(text):
	print("TOOLTIP CHAMADO")
	if text == null or text == "" or text == "null":
		return null  # 🔥 não cria tooltip

	var label = RichTextLabel.new()
	label.text = text
	label.custom_minimum_size = Vector2(250, 0)
	
	var font = load("res://Fonts/JetBrainsMono-Regular.ttf")
	label.add_theme_font_override("normal_font", font)
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	
	return label
