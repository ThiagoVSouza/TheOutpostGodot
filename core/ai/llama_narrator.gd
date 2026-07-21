class_name LlamaNarrator
extends DslNarrator

## The real narrator (M3b): turns a turn's decided facts into player-facing prose against the
## model. The facts are already decided by code (D4) — the model only describes them, at a
## given verbosity, in the player's language (D29). No grammar (prose is free), but the system
## prompt binds it hard: describe the given outcome, invent no new facts or numbers.
##
## Selected in place of [FakeNarrator] when a real backend is active (see GameKernel).

const TIMEOUT: float = 30.0
const SYSTEM := "You are the game master of The Outpost, a Greco-Roman fantasy settlement " \
	+ "game. Narrate ONLY the outcome you are given, in vivid but concise prose. Never invent " \
	+ "resources, numbers, or events beyond the facts provided; higher verbosity means more " \
	+ "colour, not more facts."

## Rough token budgets per verbosity level.
const BUDGET := {"short": 60, "normal": 120, "long": 220}

var _kernel: GameKernel


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func narrate(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	var request := {
		"messages": [
			{"role": "system", "content": SYSTEM},
			{"role": "user", "content": _user_prompt(instruction, context, verbosity, language)},
		],
		"temperature": 0.7,
		"max_tokens": int(BUDGET.get(verbosity, 120)),
	}
	var out: Dictionary = await LlamaAiCall.run(_kernel, request, TIMEOUT)
	if not bool(out["ok"]):
		# A failed narration should not lose the turn's mechanics; surface a plain line.
		return "(The moment passes.)"
	return String(out["content"]).strip_edges()


func _user_prompt(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	return "Narrate: %s\nDecided facts: %s\nVerbosity: %s\nWrite the reply in language: %s" % [
		instruction, JSON.stringify(context), verbosity, language]
