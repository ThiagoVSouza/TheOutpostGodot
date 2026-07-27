extends SceneTree

## Dev check: drives ONE real orchestrator turn through a real model and fails if
## chat framing leaked into the prose a player reads.
##
## It exists for the same reason `capture_screens.gd` does: the GUT suite is
## deliberately model-free, so it proves the wiring and says nothing about what
## the narrator actually writes. This caught a bug 413 green tests could not —
## the Gemma 3 turn markers were being sent to a Gemma 4 model, which did not
## fail, it just echoed the framing back and a turn on the phone narrated
## "<start_of_turn>The foraging party returns empty-handed.</start_of_turn>".
##
## Run it after touching the chat template, the model profile, or the model file:
##   $env:OUTPOST_AI_BACKEND="in-process-llama"
##   $env:OUTPOST_MODEL_PROFILE="gemma_e2b_desktop_cuda"
##   & $GODOT --headless --path . -s res://tools/check_llama_turn.gd

const MARKERS := ["<start_of_turn>", "</start_of_turn>", "<|turn>", "<turn|>", "<end_of_turn>"]

var _kernel: Node


func _initialize() -> void:
	await process_frame
	_kernel = root.get_node("Kernel")
	_kernel.session.begin_new_game({"hero_name": "Livia"})
	_run()


func _run() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while not _kernel.ai.is_ready():
		if Time.get_ticks_msec() > deadline:
			printerr("FAIL: backend never ready")
			quit(1)
			return
		await process_frame

	var start := Time.get_ticks_msec()
	var result: Dictionary = await _kernel.ai_orchestrator.handle_message("I send scouts to forage the hills.")
	var wall := Time.get_ticks_msec() - start
	var narrative := String(result.get("narrative", ""))

	print("wall_ms=", wall)
	print("NARRATIVE: ", narrative)

	var leaked: Array[String] = []
	for marker in MARKERS:
		if narrative.contains(marker):
			leaked.append(marker)
	if not leaked.is_empty():
		printerr("FAIL: chat markers leaked into player-visible prose: ", leaked)
		quit(1)
		return
	if not bool(result.get("ok", false)):
		printerr("FAIL: turn not ok: ", result.get("error", ""))
		quit(1)
		return
	print("PASS: clean prose, no turn markers")
	quit(0)


func _process(_delta: float) -> bool:
	return false
