extends Control

@onready var story_text = $StoryText
@onready var choices_container = $Choices
@onready var buttons = [
	$Choices/Row1/Choice1,
	$Choices/Row1/Choice2,
	$Choices/Row2/Choice3,
	$Choices/Row2/Choice4
]

var full_text = ""
var visible_chars = 0
var typing_speed = 0.03
var typing_id = 0
var is_typing = false
var current_choices = []

var story = {
	"start": {
		"text": "Você acorda em uma floresta escura. Há dois caminhos à frente.",
		"choices": [
			{"text": "Ir pela esquerda", "next": "left"},
			{"text": "Ir pela direita", "next": "right"}
		]
	},
	"left": {
		"text": "Você encontra um lobo! O que faz?",
		"choices": [
			{"text": "Lutar", "next": "fight"},
			{"text": "Fugir", "next": "start"}
		]
	},
	"right": {
		"text": "Você encontra um tesouro escondido! Parabéns!",
		"choices": [
			{"text": "Recomeçar", "next": "start"}
		]
	},
	"fight": {
		"text": "Você derrotou o lobo! Vitória!",
		"choices": [
			{"text": "Recomeçar", "next": "start"}
		]
	}
}

func _ready():
	load_node("start")
	
func _input(event):
	if event.is_pressed():
		if is_typing:
			finish_typing()
	if event.is_action_pressed("ui_accept"):
		if is_typing:
			finish_typing()

func load_node(node_name):
	show_choices()
	# Esconde todos os botões
	for b in buttons:
		b.hide()
	var node = story[node_name]
	
	# Inicia texto com efeito
	start_typing(node["text"])
	
	# Salva escolhas temporariamente
	current_choices = node["choices"]

func start_typing(text):
	typing_id += 1  # invalida os anteriores

	full_text = text
	story_text.text = ""
	visible_chars = 0
	is_typing = true
	type_text(typing_id)

func type_text(id):
	while visible_chars < full_text.length():
		if not is_typing or id != typing_id:
			return
		story_text.text += full_text[visible_chars]
		visible_chars += 1
		await get_tree().create_timer(typing_speed).timeout
	is_typing = false
	show_choices()
	
func finish_typing():
	typing_id +=1
	is_typing = false
	story_text.text = full_text
	visible_chars = full_text.length()
	
	show_choices()
	
func show_choices():
	for i in range(4):
		if i < current_choices.size():
			var choice = current_choices[i] # 👈 captura segura

			buttons[i].text = choice["text"]
			buttons[i].show()
			buttons[i].pressed.connect(func():
				load_node(choice["next"])
			, CONNECT_ONE_SHOT)
		else:
			buttons[i].hide()
