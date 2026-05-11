extends Node

# ========================
# PLAYERS
# ========================

var bgm_player: AudioStreamPlayer
var ambiance_player: AudioStreamPlayer
var sfx_players: Array = []
const SFX_POOL_SIZE = 6

# ========================
# STATE
# ========================

var audio_db := {}
var current_region := ""
var in_combat := false
var current_bgm_key := ""
var current_ambiance_key := ""

var bgm_volume_db := 0.0
var ambiance_volume_db := -6.0
var sfx_volume_db := 0.0

var _bgm_tween: Tween = null
var _ambiance_tween: Tween = null

# ========================
# INIT
# ========================

func _ready():
	_setup_players()
	audio_db = load_json("res://Database/audio.json")

	MyEventBus.subscribe("character_selected", func(_d):
		play_bgm("title")
	)
	MyEventBus.subscribe("region_changed", func(data):
		current_region = data.get("region", "")
		if not in_combat:
			_play_region_audio(current_region)
	)
	MyEventBus.subscribe("start_combat", func(_d):
		in_combat = true
		play_bgm("combat")
		stop_ambiance()
	)
	MyEventBus.subscribe("combat_ended", func(_d):
		in_combat = false
		_play_region_audio(current_region)
	)
	MyEventBus.subscribe("play_sfx", func(data):
		play_sfx(data.get("sound", ""))
	)

func _setup_players():
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGMPlayer"
	add_child(bgm_player)
	bgm_player.finished.connect(func():
		if bgm_player.stream:
			bgm_player.play()
	)

	ambiance_player = AudioStreamPlayer.new()
	ambiance_player.name = "AmbiancePlayer"
	ambiance_player.volume_db = ambiance_volume_db
	add_child(ambiance_player)
	ambiance_player.finished.connect(func():
		if ambiance_player.stream:
			ambiance_player.play()
	)

	for i in SFX_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		p.name = "SFXPlayer" + str(i)
		add_child(p)
		sfx_players.append(p)

# ========================
# BGM
# ========================

func play_bgm(key: String):
	print('BGM PLAY')
	if key == current_bgm_key:
		return
	var path = _resolve_path("music", key)
	print(path)
	if path == "":
		return
	current_bgm_key = key
	var stream: AudioStream = load(path)

	if _bgm_tween:
		_bgm_tween.kill()
	_bgm_tween = create_tween()

	if bgm_player.playing:
		_bgm_tween.tween_property(bgm_player, "volume_db", -80.0, 0.5)
	_bgm_tween.tween_callback(func():
		bgm_player.stream = stream
		bgm_player.volume_db = -80.0
		bgm_player.play()
	)
	_bgm_tween.tween_property(bgm_player, "volume_db", bgm_volume_db, 0.5)

func stop_bgm():
	if not bgm_player.playing:
		return
	current_bgm_key = ""
	if _bgm_tween:
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(bgm_player, "volume_db", -80.0, 0.5)
	_bgm_tween.tween_callback(func():
		bgm_player.stream = null
		bgm_player.stop()
	)

# ========================
# AMBIANCE
# ========================

func play_ambiance(key: String):
	if key == current_ambiance_key:
		return
	var path = _resolve_path("ambiance", key)
	if path == "":
		return
	current_ambiance_key = key
	var stream: AudioStream = load(path)

	if _ambiance_tween:
		_ambiance_tween.kill()
	_ambiance_tween = create_tween()

	if ambiance_player.playing:
		_ambiance_tween.tween_property(ambiance_player, "volume_db", -80.0, 0.8)
	_ambiance_tween.tween_callback(func():
		ambiance_player.stream = stream
		ambiance_player.volume_db = -80.0
		ambiance_player.play()
	)
	_ambiance_tween.tween_property(ambiance_player, "volume_db", ambiance_volume_db, 0.8)

func stop_ambiance():
	if not ambiance_player.playing:
		return
	current_ambiance_key = ""
	if _ambiance_tween:
		_ambiance_tween.kill()
	_ambiance_tween = create_tween()
	_ambiance_tween.tween_property(ambiance_player, "volume_db", -80.0, 0.8)
	_ambiance_tween.tween_callback(func():
		ambiance_player.stream = null
		ambiance_player.stop()
	)

# ========================
# SFX
# ========================

func play_sfx(key: String):
	var path = _resolve_path("sfx", key)
	if path == "":
		return
	var player = _get_free_sfx_player()
	player.stream = load(path)
	player.volume_db = sfx_volume_db
	player.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in sfx_players:
		if not p.playing:
			return p
	return sfx_players[0]

# ========================
# VOLUME
# ========================

func set_bgm_volume(linear: float):
	bgm_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	if bgm_player.playing:
		bgm_player.volume_db = bgm_volume_db

func set_ambiance_volume(linear: float):
	ambiance_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	if ambiance_player.playing:
		ambiance_player.volume_db = ambiance_volume_db

func set_sfx_volume(linear: float):
	sfx_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))

# ========================
# INTERNAL
# ========================

func _play_region_audio(region_name: String):
	if not audio_db.has("regions") or not audio_db["regions"].has(region_name):
		return
	var data = audio_db["regions"][region_name]
	var music_key: String = data.get("music", "")
	var ambiance_key: String = data.get("ambiance", "")
	if music_key != "":
		play_bgm(music_key)
	if ambiance_key != "":
		play_ambiance(ambiance_key)
	elif ambiance_player.playing:
		stop_ambiance()

func _resolve_path(category: String, key: String) -> String:
	if not audio_db.has(category) or not audio_db[category].has(key):
		return ""
	var path: String = audio_db[category][key]
	if not ResourceLoader.exists(path):
		return ""
	return path

# ========================
# JSON
# ========================

func load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("Arquivo não encontrado: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Erro ao fazer parse do JSON: " + path)
		return {}
	return json.data
