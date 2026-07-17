class_name QuizGame
extends RefCounted

# The Trial of Wit — a 5-question quiz minigame, influenced by INT.
# Instantiate, wire the Callables, then: var outcome = await game.run(step)
# Returns "win" or "lose".  Outcome sequences are run by the caller.

# Highlight-chance multiplier per tier: chance% = INT * rate (0 = never highlights).
const HIGHLIGHT_RATE := {
	"easy": 2.0,
	"medium": 1.5,
	"hard": 1.0,
	"impossible": 0.5,
	"trick": 0.0,
}

const DEFAULT_CORRECT_RESPONSES := [
	"\"Ding ding ding!\" The clown claps theatrically. \"Give the genius a hand!\"",
	"\"...Huh. Actually correct.\" They sound almost offended by it.",
	"\"Ooh, look at the big brain over here!\" They spin in place, delighted.",
	"\"Correct!\" A pause. \"I hate that you got that one.\"",
]

const DEFAULT_WRONG_RESPONSES := [
	"\"Ehhh, wrong!\" A little bell dings sadly somewhere behind the booth.",
	"\"Nope!\" They shake their head with exaggerated sympathy. \"So close. Not really, but so close.\"",
	"\"Incorrect~\" they sing-song, already scribbling something down.",
	"\"Wrong answer!\" They mime a dramatic gasp. \"Tragic. Truly tragic.\"",
]

## Callable() -> Dictionary  — resolves with the chosen choice dict
var capture_input_fn: Callable
## Callable() -> void  — shows Continue button and waits for player
var wait_for_continue_fn: Callable
## Callable(stat_name: String) -> int
var stat_callback: Callable
## Callable(condition: Dictionary) -> bool  — evaluates a "known_if" condition
var condition_callback: Callable
var rng: RandomNumberGenerator
## Question bank, keyed by difficulty tier -> Array of question dicts (see Database/questions.json)
var questions_db: Dictionary


func run(step: Dictionary) -> String:
	var required_correct: int = step.get("required_correct", 3)
	var difficulties: Array = step.get("difficulties", ["easy"])

	var pool: Array = []
	for tier in difficulties:
		for q in questions_db.get(tier, []):
			pool.append({"tier": tier, "q": q})
	_shuffle(pool)
	var picks: Array = pool.slice(0, min(5, pool.size()))

	MyEventBus.emit("dialogue", {
		"text": "The Gamer Clown produces an oversized card from absolutely nowhere.\n\n\"Five questions. Answer wisely!\""
	})
	await wait_for_continue_fn.call()

	var int_stat: int = stat_callback.call("int") if stat_callback.is_valid() else 0
	var correct_count := 0

	for i in range(picks.size()):
		var entry: Dictionary = picks[i]
		var tier: String = entry["tier"]
		var q: Dictionary = entry["q"]
		var correct_idx: int = q.get("correct", -1)
		var answers: Array = q.get("answers", [])

		var highlight := false
		if correct_idx >= 0:
			if q.has("known_if") and condition_callback.is_valid() and condition_callback.call(q["known_if"]):
				highlight = true
			else:
				var chance: float = int_stat * (HIGHLIGHT_RATE.get(tier, 0.0) as float) / 100.0
				highlight = rng.randf() < chance

		MyEventBus.emit("dialogue", {
			"text": "Question %d/%d:\n%s" % [i + 1, picks.size(), q.get("prompt", "")]
		})

		var choices: Array = []
		for a in range(answers.size()):
			var text: String = answers[a]
			if highlight and a == correct_idx:
				text = "[color=lightgreen]%s[/color]" % text
			choices.append({"text": text, "key": str(a)})
		MyEventBus.emit("show_choices", {"choices": choices, "header": ""})

		var picked: Dictionary = await capture_input_fn.call()
		var picked_idx: int = int(picked.get("key", "-1"))
		var got_it: bool = correct_idx >= 0 and picked_idx == correct_idx
		if got_it:
			correct_count += 1

		var responses: Array = q.get("correct_responses" if got_it else "wrong_responses", [])
		if responses.is_empty():
			responses = DEFAULT_CORRECT_RESPONSES if got_it else DEFAULT_WRONG_RESPONSES
		MyEventBus.emit("dialogue", {"text": responses[rng.randi() % responses.size()]})
		await wait_for_continue_fn.call()

	var result: String = "win" if correct_count >= required_correct else "lose"
	MyEventBus.emit("dialogue", {
		"text": "You got %d out of %d correct." % [correct_count, picks.size()]
	})
	await wait_for_continue_fn.call()
	return result


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
