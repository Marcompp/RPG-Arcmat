extends Node
class_name InputRouter

var stack = []  # [{ id, handler, context }]

func _ready():
	MyEventBus.subscribe("choice_selected", _on_choice)

func _on_choice(choice):
	dispatch(choice)

# ------------------------
# STACK CONTROL
# ------------------------

func push(handler: Callable, context := "default"):
	stack.append({
		"handler": handler,
		"context": context
	})
	print("PUSH →", context)

func pop():
	if stack.is_empty():
		return
	
	var popped = stack.pop_back()
	print("POP ←", popped["context"])

func clear():
	stack.clear()

func current():
	if stack.is_empty():
		return null
	return stack[-1]

# ------------------------
# INPUT DISPATCH
# ------------------------

func dispatch(choice):
	if stack.is_empty():
		print("⚠ No input handler")
		return
	
	var top = stack[-1]
	var handler: Callable = top["handler"]
	
	if handler.is_valid():
		handler.call(choice)
