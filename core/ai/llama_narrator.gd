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
	+ "colour, not more facts. If the facts say nothing was resolved, say so plainly and do " \
	+ "not imply that anyone acted or that anything came of it. " + NO_LABELS

## Some decided facts are *categories* the rules used to pick the outcome — an outcome band like
## "steady" or "bountiful". They are given so the prose can take on their colour, but the model's
## instinct is to append them as a verdict ("The outcome is steady."), which reads like a debug
## line in the middle of the fiction. This is the same failure as the raw die leaking: a
## mechanical term surfacing as narration.
const NO_LABELS := "Some facts are category words describing how well it went; let them shape " \
	+ "your word choice, but never name them or state the category as a sentence of its own."

## `topics` is a different output *form*, not a shorter length (see [NarrationSettings]), so it
## gets its own binding: a bare list of what happened, for players who want the ledger and not
## the prose.
const SYSTEM_TOPICS := "You are the game master of The Outpost, a Greco-Roman fantasy " \
	+ "settlement game. Report ONLY the outcome you are given as a short bulleted list, one " \
	+ "short clause per line, each line starting with '- '. No prose, no preamble, no closing " \
	+ "line. Never invent resources, numbers, or events beyond the facts provided. Each line " \
	+ "states something that happened in the settlement, in the past tense. Never restate the " \
	+ "request itself and never write a line that tells someone to do something. " + NO_LABELS

## Playground-only (see [member NarrationSettings.loose]): drops the binding to the given facts
## so we can see what the model reaches for unprompted. NOT a shipping mode — it gives up D4.
const SYSTEM_LOOSE := "You are the game master of The Outpost, a Greco-Roman fantasy " \
	+ "settlement game. Narrate the moment vividly. You may embellish freely."

## Rough token budgets per resolved level.
const BUDGET := {"topics": 80, "short": 60, "normal": 120, "long": 220, "full": 350}

var _kernel: GameKernel


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func narrate(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	var request := {
		"messages": [
			{"role": "system", "content": _system_prompt(verbosity)},
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


## Pick the binding for this call. The verbosity handed in is already resolved against the
## player's preference by the executor, so `topics` arriving here means the player asked for it.
func _system_prompt(verbosity: String) -> String:
	if _kernel != null and _kernel.narration != null and _kernel.narration.loose:
		return SYSTEM_LOOSE
	if verbosity == NarrationSettings.LEVEL_TOPICS:
		return SYSTEM_TOPICS
	return SYSTEM


func _user_prompt(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	# "What happened" rather than "Narrate": an authored instruction is a description of the
	# event the rules already resolved, and labelling it as a task makes the model treat the
	# sentence itself as the thing to report (most visibly at `topics`, which listed the
	# instruction back as a bullet).
	return "What happened: %s\nDecided facts: %s\nVerbosity: %s\nWrite the reply in language: %s" % [
		instruction, JSON.stringify(context), verbosity, language]
