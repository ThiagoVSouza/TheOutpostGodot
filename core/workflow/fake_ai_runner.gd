class_name FakeAiRunner
extends DslAiRunner

## Deterministic stand-in for the real classifier (mirrors `FakeAiBackend`/`FakeNarrator`, and
## like them completes off-frame so reentrancy/cancellation bugs surface in tests). It returns
## a scripted value per family, or the family's first option by default — so classification is
## stable and testable without a model. Tests use [method set_result] to drive a specific
## branch, and can deliberately return an out-of-set value to exercise the rejection path.
var _results: Dictionary = {}  # family_id -> value


func set_result(family_id: String, value: String) -> void:
	_results[family_id] = value


func classify(family: PromptFamily, _facts: Dictionary) -> String:
	await _yield()
	if _results.has(family.id):
		return String(_results[family.id])
	return family.options[0] if not family.options.is_empty() else ""
