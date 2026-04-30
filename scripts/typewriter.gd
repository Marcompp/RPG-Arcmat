extends Control

@onready var label = $Panel/Label
@onready var timer = $Panel/Timer
@onready var choices_box = $Panel/VBoxContainer

var full_text = ""
var visible_characters = 0
var typing_speed = 0.03  # seconds per character
var is_typing = false
var waiting_for_input = false

func _ready():
	timer.wait_time = typing_speed
	timer.timeout.connect(_on_timer_timeout)
	start_dialogue("Hello there! This text will type out.")

func start_dialogue(text):
	full_text = text
	label.text = text
	label.visible_characters = 0
	visible_characters = 0
	is_typing = true
	waiting_for_input = false
	choices_box.hide()
	timer.start()

func _on_timer_timeout():
	if visible_characters < full_text.length():
		visible_characters += 1
		label.visible_characters = visible_characters
	else:
		timer.stop()
		is_typing = false
		waiting_for_input = true
		
		
func show_choices():
	waiting_for_input = false
	choices_box.show()

	var buttons = choices_box.get_children()

	buttons[0].text = "Yes"
	buttons[1].text = "No"
	buttons[2].text = "Maybe"
	buttons[3].text = "Leave"

	for i in range(buttons.size()):
		buttons[i].pressed.connect(_on_choice_selected.bind(i))
		
func _on_choice_selected(index):
	match index:
		0:
			start_dialogue("You chose Yes!")
		1:
			start_dialogue("You chose No!")
		2:
			start_dialogue("You chose Maybe!")
		3:
			start_dialogue("Goodbye!")

	choices_box.hide()
	
func _input(event):
	if event.is_action_pressed("ui_accept"):
		if is_typing:
			# Skip typing
			label.visible_characters = full_text.length()
			timer.stop()
			is_typing = false
			waiting_for_input = true

		elif waiting_for_input:
			show_choices()
