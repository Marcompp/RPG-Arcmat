extends VBoxContainer

var character = null

func _get_tooltip(at_position):
	if character == null:
		return ""
	return build_character_tooltip(character)

func _make_custom_tooltip(text):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.bbcode_text = text
	label.fit_content = true
	return label

func build_character_tooltip(char):
	var t = "[b]%s[/b]\nHP: %d/%d" % [
		char.get_name(),
		char.get_hp(),
		char.get_mhp()
	]
	return t
