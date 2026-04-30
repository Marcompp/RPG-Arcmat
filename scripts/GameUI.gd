extends Control

@onready var name_label = $TopLeftPanel/NameLabel
@onready var stats_label = $TopLeftPanel/StatsLabel

var state

func _ready():
	MyEventBus.subscribe("screenshake", func():
		shake()
	)
func shake():
	var original = position
	
	for i in range(5):
		position = original + Vector2(randf_range(-5,5), randf_range(-5,5))
		await get_tree().create_timer(0.02).timeout
	
	position = original

func bind(game_state):
	state = game_state
	state.changed.connect(_on_state_changed)
	
	# sync inicial
	_refresh_all()

func _on_state_changed(path, value):
	print("STATE CHANGED:", path, value)
	if path.begins_with("player"):
		_refresh_all()

func _refresh_all():
	print("REFRESH UI")
	print(state.get_value("player"))
	if state.get_value("player.Name") == null:
		_clear_ui()
		return
	print('NÃO BLOQUEADO')
	var name = state.get_value("player.Name", "???")
	var cls = state.get_value("player.Class", "")
	
	var hp = state.get_value("player.curr_stats.hp", 0)
	var mhp = state.get_value("player.curr_stats.mhp", 0)
	
	var mp = state.get_value("player.curr_stats.mp", 0)
	var mmp = state.get_value("player.curr_stats.mmp", 0)
	
	name_label.text = "%s, Lv 1 %s" % [name, cls]
	var hp_text = "HP: %d/%d" % [hp, mhp]
	var mp_text = "MP: %d/%d" % [mp, mmp]
	stats_label.text = hp_text + "\n" + mp_text

func _clear_ui():
	name_label.text = ""
	stats_label.text = ""
