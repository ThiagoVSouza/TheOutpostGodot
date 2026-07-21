class_name DslNarrator
extends RefCounted

## The seam the `narrate` op speaks to (A5, D4 amendment #3): turns the decided facts of a
## turn into bounded, player-facing prose. Its inputs are deliberately fixed — an
## **instruction** (what to narrate), the **context** it may draw on, a **verbosity** level,
## and an **output language** (D29) — so that raising verbosity *decorates* the outcome
## rather than inventing new facts. The narrator never adjudicates: every number it is handed
## was already decided by code (D4).
##
## The method is a **coroutine** (D22/D30): narration is an in-memory await inside the
## executing instance — the real AiBackend-backed narrator suspends on its request; the fakes
## yield a frame. It is never a checkpoint (an AI call does not persist a snapshot, D30).
func narrate(_instruction: String, _context: Dictionary, _verbosity: String, _language: String) -> String:
	await _yield()
	return ""


## Yield one frame so the seam is genuinely asynchronous, guarded so it is safe even if ever
## called outside a running SceneTree (returns immediately then).
func _yield() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame
