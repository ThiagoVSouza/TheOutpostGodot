class_name AiRequest
extends RefCounted

## Handle for one in-flight AI generation (D22).
##
## [method AiBackend.generate] returns one of these immediately; the backend finishes it
## later — always asynchronously, never inside the same call — via [method complete] or
## [method fail]. The orchestrator (and only the orchestrator) owns pacing concerns like
## timeouts; backends own their transport (HTTP abort, thread stop) through the cancel
## hook. Await the outcome with [method wait]; it is safe to call after completion.

## Incremental output, for backends that stream tokens. Optional: a backend may
## complete without ever emitting chunks.
signal chunk(text: String)

## Terminal success. Emitted at most once, mutually exclusive with [signal failed].
signal completed(response: Dictionary)

## Terminal failure (backend error, timeout, or cancellation). Emitted at most once.
signal failed(error: String)

## Aggregate terminal signal: emitted after [signal completed] or [signal failed]
## with the same outcome dictionary [method wait] returns.
signal finished(outcome: Dictionary)

var _done: bool = false
var _cancelled: bool = false
var _outcome: Dictionary = {}
var _cancel_hook: Callable = Callable()


## True once the request has terminally completed, failed or been cancelled.
func is_finished() -> bool:
	return _done


func was_cancelled() -> bool:
	return _cancelled


## Await the terminal outcome:
##   { ok: bool, response: Dictionary, error: String, cancelled: bool }
## Returns immediately if the request already finished, so late awaiters never hang.
func wait() -> Dictionary:
	if _done:
		return _outcome
	await finished
	return _outcome


## Request cancellation. Safe to call at any time; a no-op once finished. Runs the
## backend's cancel hook (abort HTTP, stop thread) and then fails the request with
## error "cancelled".
func cancel() -> void:
	if _done:
		return
	_cancelled = true
	if _cancel_hook.is_valid():
		_cancel_hook.call()
	fail("cancelled")


# --- backend-facing API ---

## Backends register how to abort their transport. Called at most once, before the
## request is failed with "cancelled".
func set_cancel_hook(hook: Callable) -> void:
	_cancel_hook = hook


## Emit a streamed fragment. Ignored after the request finished.
func emit_chunk(text: String) -> void:
	if _done:
		return
	chunk.emit(text)


## Terminally succeed. Ignored if already finished (e.g. cancelled or timed out first) —
## this guard is what makes late timer/transport callbacks harmless.
func complete(response: Dictionary) -> void:
	if _done:
		return
	_done = true
	# Drop the hook: it typically captures the backend, and a retained backend->request->
	# hook->backend cycle would leak both (RefCounted cannot collect cycles).
	_cancel_hook = Callable()
	_outcome = {"ok": true, "response": response, "error": "", "cancelled": false}
	completed.emit(response)
	finished.emit(_outcome)


## Terminally fail. Ignored if already finished.
func fail(error: String) -> void:
	if _done:
		return
	_done = true
	_cancel_hook = Callable()
	_outcome = {"ok": false, "response": {}, "error": error, "cancelled": _cancelled}
	failed.emit(error)
	finished.emit(_outcome)


## An already-failed request, for abstract/misconfigured backends. The failure is
## recorded synchronously; awaiters still get the outcome via the [method wait] guard.
static func make_failed(error: String) -> AiRequest:
	var req := AiRequest.new()
	req.fail(error)
	return req
