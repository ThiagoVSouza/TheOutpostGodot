class_name FakeNarrator
extends DslNarrator

## Deterministic stand-in for the real AI narrator (mirrors how `FakeAiBackend` stands in for
## a model, and like it completes asynchronously — never in the same frame — so reentrancy and
## cancellation bugs surface in tests rather than first appearing with a real model). It
## invents nothing: it echoes the instruction and the decided facts back in a fixed, readable
## shape, so tests can assert the narrate op passed the right bounded inputs through the seam.
func narrate(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	await _yield()
	var facts: Array = []
	var keys: Array = context.keys()
	keys.sort()  # deterministic order regardless of how the workflow built the dict
	for k in keys:
		facts.append("%s=%s" % [k, str(context[k])])
	var tail := " (%s)" % ", ".join(facts) if not facts.is_empty() else ""
	return "[%s|%s] %s%s" % [verbosity, language, instruction, tail]
