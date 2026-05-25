extends Control

signal retry_requested
signal title_screen_requested

const MESSAGES = [
	"The road claims another soul.\nBut the journey is not yet over.",
	"Darkness swallows the fallen.\nRise, and face what lies ahead.",
	"Even the bravest stumble.\nDust yourself off and try again."
]

@onready var message_label = $VBoxContainer/MessageLabel
@onready var retry_btn     = $VBoxContainer/RetryButton
@onready var title_btn     = $VBoxContainer/TitleButton
@onready var quit_btn      = $VBoxContainer/QuitButton

func _ready():
	visible = false
	retry_btn.pressed.connect(func(): retry_requested.emit())
	title_btn.pressed.connect(func(): title_screen_requested.emit())
	quit_btn.pressed.connect(func(): get_tree().quit())

func show_gameover():
	message_label.text = MESSAGES[randi() % MESSAGES.size()]
	visible = true
	retry_btn.grab_focus()
