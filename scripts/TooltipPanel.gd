extends Panel

var character = null

func _ready():
	tooltip_text = " "  # obrigatório
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_disable_mouse_on_children(self)
	




	
	
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
	label.bbcode_text = text
	
	
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
	t += "[b]%s[/b]  Lv.1\n" % char.get_name()
	t += "Class: %s\n\n" % char.get_char_class()
	
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
	
	var keys = ["str","mag","agi","dex","def","lck"]

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
	
	# ========================
	# SKILLS
	# ========================
	var skills = char.data.get("Skills", [])
	if skills.size() > 0:
		t += "[b]Skills[/b]\n"
		for s in skills:
			t += "- %s\n" % s
		t += "\n"
	
	# ========================
	# SPELLS
	# ========================
	var spells = char.data.get("Spells", [])
	if spells.size() > 0:
		t += "[b]Spells[/b]\n"
		for s in spells:
			t += "- %s\n" % s
		t += "\n"
	
	return t.strip_edges()


func get_stat_color(bonus):
	if bonus > 0:
		return "#00E676" # verde
	elif bonus < 0:
		return "#FFD54F" # amarelo
	return "" # sem cor
