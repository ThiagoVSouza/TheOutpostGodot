class_name LlamaAiCall
extends RefCounted

## One real model call, shared by [LlamaAiRunner] (classification) and [LlamaNarrator]
## (prose). This is where the AI touches the game in M3b — and where the pieces the ribosome
## orchestrator shed re-attach: the orchestrator-owned **timeout** and the T5 **availability**
## reporting now live at the seam that actually calls the backend (D22/D30). A real turn makes
## a few of these; each is an in-memory await (D30), never a checkpoint.

## Default per-call timeout; the runner/narrator pass their own.
const DEFAULT_TIMEOUT: float = 30.0


## Run one request against `kernel.ai`, race it against a timeout, and report a genuine failure
## (never a cancellation) to availability so T5 opens the outage. Returns:
##   { ok: bool, content: String, error: String }
static func run(kernel: GameKernel, request: Dictionary, timeout_seconds: float = DEFAULT_TIMEOUT) -> Dictionary:
	var req := kernel.ai.generate(request)
	_arm_timeout(req, timeout_seconds)
	var outcome: Dictionary = await req.wait()

	if bool(outcome.get("ok", false)):
		var response: Dictionary = outcome.get("response", {})
		return {"ok": true, "content": String(response.get("content", "")), "error": ""}

	var error := String(outcome.get("error", ""))
	# A real backend failure (never a cancellation) opens a T5 outage.
	if not bool(outcome.get("cancelled", false)) and kernel.ai_availability != null:
		kernel.ai_availability.report_failure(error)
	return {"ok": false, "content": "", "error": error if not error.is_empty() else "backend_error"}


## Race the request against a SceneTreeTimer (D22). A late timer firing after completion is
## harmless — AiRequest.fail() is a no-op once finished; the weakref keeps a pending timeout
## from extending a finished request's lifetime.
static func _arm_timeout(req: AiRequest, timeout_seconds: float) -> void:
	if timeout_seconds <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var wr: WeakRef = weakref(req)
	tree.create_timer(timeout_seconds).timeout.connect(func() -> void:
		var live: AiRequest = wr.get_ref()
		if live != null:
			live.fail("timeout"))
