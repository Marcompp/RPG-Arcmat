extends Node

const SETTINGS_PATH = "user://settings.cfg"

var bgm_volume: float = 1.0
var ambiance_volume: float = 0.5
var sfx_volume: float = 1.0
var typing_speed: float = 0.03

func _ready():
	load_settings()

func load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	bgm_volume    = cfg.get_value("audio",    "bgm",          bgm_volume)
	ambiance_volume = cfg.get_value("audio",  "ambiance",     ambiance_volume)
	sfx_volume    = cfg.get_value("audio",    "sfx",          sfx_volume)
	typing_speed  = cfg.get_value("gameplay", "typing_speed", typing_speed)

func save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("audio",    "bgm",          bgm_volume)
	cfg.set_value("audio",    "ambiance",     ambiance_volume)
	cfg.set_value("audio",    "sfx",          sfx_volume)
	cfg.set_value("gameplay", "typing_speed", typing_speed)
	cfg.save(SETTINGS_PATH)
