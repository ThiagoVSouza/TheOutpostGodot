class_name LlamaAiRunner
extends DslAiRunner

## The real classification runner (M3b): resolves a [PromptFamily] against the model. It asks
## the model to pick one value from the family's closed set, **grammar-constrained at the
## sampler** (D19) so an out-of-set answer is unsampleable, and reasons in English regardless
## of the player's language (D29). Deterministic sampling (temperature 0) — classification is a
## verdict, not creative writing.
##
## Selected in place of [FakeAiRunner] when a real backend is active (see GameKernel).

const TIMEOUT: float = 20.0
const SYSTEM := "You are the intent classifier for a Greco-Roman strategy game. Given the " \
	+ "player's message and context, answer with exactly one of the allowed labels and nothing " \
	+ "else. Reason in English regardless of the message's language."

var _kernel: GameKernel


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func classify(family: PromptFamily, facts: Dictionary) -> String:
	if family.options.is_empty():
		return ""
	var request := {
		"messages": [
			{"role": "system", "content": SYSTEM},
			{"role": "user", "content": _user_prompt(family, facts)},
		],
		"grammar": gbnf_for_options(family.options),
		"temperature": 0.0,
		"max_tokens": 8,
	}
	var out: Dictionary = await LlamaAiCall.run(_kernel, request, TIMEOUT)
	if not bool(out["ok"]):
		return ""  # the executor fails the instance; T5 has already been told
	var value := String(out["content"]).strip_edges()
	return value if family.options.has(value) else ""  # grammar guarantees this; guard anyway


func _user_prompt(family: PromptFamily, facts: Dictionary) -> String:
	return "%s\nContext: %s\nLabel:" % [_allowed_block(family), JSON.stringify(facts)]


## The allowed set, with each label's meaning when the family supplies one. Descriptions matter
## more than they look: with bare words the classifier reads "I sing to the goats" as `forage`
## (goats → animals → food) rather than the catch-all, because nothing tells it the catch-all
## exists for messages with no mechanical stake.
func _allowed_block(family: PromptFamily) -> String:
	if family.descriptions.is_empty():
		return "Allowed labels: %s" % ", ".join(Array(family.options))
	var lines: Array = ["Allowed labels:"]
	for option in family.options:
		var described := String(family.descriptions.get(option, ""))
		lines.append("- %s: %s" % [option, described] if not described.is_empty() else "- %s" % option)
	return "\n".join(lines)


## A GBNF grammar that admits exactly one of the options (D19): `root ::= "a" | "b" | ...`.
static func gbnf_for_options(options: PackedStringArray) -> String:
	var alts: Array = []
	for opt in options:
		alts.append("\"%s\"" % String(opt).replace("\\", "\\\\").replace("\"", "\\\""))
	return "root ::= %s" % " | ".join(alts)
