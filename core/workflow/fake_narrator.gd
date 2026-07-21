class_name FakeNarrator
extends DslNarrator

## Deterministic stand-in for the real AI narrator (mirrors how `FakeAiBackend` stands in for
## a model). It invents nothing — it echoes the instruction and the decided facts back in a
## fixed, readable shape, so tests can assert that the narrate op passed the right bounded
## inputs through the seam. The real narrator (M3b) replaces this with a grammar-constrained
## `AiBackend` call; the op and its contract do not change when it does.
func narrate(instruction: String, context: Dictionary, verbosity: String, language: String) -> String:
	var facts: Array = []
	var keys: Array = context.keys()
	keys.sort()  # deterministic order regardless of how the workflow built the dict
	for k in keys:
		facts.append("%s=%s" % [k, str(context[k])])
	var tail := " (%s)" % ", ".join(facts) if not facts.is_empty() else ""
	return "[%s|%s] %s%s" % [verbosity, language, instruction, tail]
