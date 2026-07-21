class_name DslAiRunner
extends RefCounted

## The seam the `ai` op speaks to: given a classification [PromptFamily] and bounded facts,
## returns **one** value from the family's closed set. A coroutine (D22/D30): the real
## `AiBackend`-backed runner suspends on its request — assembling the prompt, applying the D19
## grammar, parsing the D20 pipe — while [FakeAiRunner] yields a frame. The result being in-set
## is the family's guarantee (grammar); the executor re-checks it defensively.
func classify(_family: PromptFamily, _facts: Dictionary) -> String:
	await _yield()
	return ""


## Yield one frame so the seam is genuinely asynchronous, guarded so it is safe even if ever
## called outside a running SceneTree.
func _yield() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame
