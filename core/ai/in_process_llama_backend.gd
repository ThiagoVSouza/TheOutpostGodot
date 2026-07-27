class_name InProcessLlamaBackend
extends AiBackend

## M6 Phase 1: binds libllama in-process via the outpost_llama GDExtension
## (LlamaInferenceEngine) instead of M2's subprocess+HTTP transport, which
## cannot ship on mobile. Desktop CPU proof; GPU offload and the Android
## build are follow-on M6 work, not this backend's concern - the engine
## itself is platform-agnostic, only [ModelProfile.gpu_layers] changes.

enum State { STOPPED, LOADING, READY, FAILED }

var profile: ModelProfile
var state: State = State.STOPPED

var _engine: Object
var _pending_by_request_id: Dictionary = {} # int -> AiRequest
var _pending_before_ready: Array[Callable] = []


func _init(selected_profile: ModelProfile) -> void:
	profile = selected_profile
	# The GDExtension is built, not vendored (see gdextension/README.md), so a
	# fresh clone that has not run the build has no such class. Fail as a normal
	# unavailable backend rather than crashing on a null engine.
	if not ClassDB.class_exists("LlamaInferenceEngine"):
		state = State.FAILED
		return
	_engine = ClassDB.instantiate("LlamaInferenceEngine")
	_engine.generation_completed.connect(_on_generation_completed)
	_engine.generation_failed.connect(_on_generation_failed)
	_engine.model_load_completed.connect(_on_model_load_completed)
	_engine.model_load_failed.connect(_on_model_load_failed)


func backend_id() -> String:
	return "in-process-llama"


func is_ready() -> bool:
	return state == State.READY


func ensure_started() -> void:
	if state != State.STOPPED or profile == null or _engine == null:
		return
	state = State.LOADING
	_engine.begin_load_model(profile.weights_path, profile.gpu_layers, profile.context_total)


func generate(request: Dictionary) -> AiRequest:
	var ai_request := AiRequest.new()
	if profile == null:
		_defer_failure(ai_request, "model_profile_unavailable")
		return ai_request
	if state == State.FAILED:
		_defer_failure(ai_request, "engine_load_failed")
		return ai_request
	if state == State.READY:
		_begin_generate(ai_request, request)
		return ai_request

	ensure_started()
	_pending_before_ready.append(func() -> void:
		if ai_request.is_finished():
			return
		if state == State.READY:
			_begin_generate(ai_request, request)
		else:
			ai_request.fail("engine_load_failed")
	)
	return ai_request


## T5 recovery: a failed in-process load has no external process to restart,
## so the only recovery available is trying the load again from a clean state.
func attempt_recovery(_attempt: int) -> AiRequest:
	var probe := AiRequest.new()
	if state == State.READY:
		(func() -> void: probe.complete({})).call_deferred()
		return probe
	state = State.STOPPED
	_engine.unload_model()
	_pending_before_ready.append(func() -> void:
		if probe.is_finished():
			return
		if state == State.READY:
			probe.complete({})
		else:
			probe.fail("engine_load_failed")
	)
	ensure_started()
	return probe


func _begin_generate(ai_request: AiRequest, request: Dictionary) -> void:
	var request_id: int = _engine.generate(request)
	_pending_by_request_id[request_id] = ai_request
	ai_request.set_cancel_hook(func() -> void: _engine.cancel(request_id))


func _on_generation_completed(request_id: int, response: Dictionary) -> void:
	var ai_request: AiRequest = _pending_by_request_id.get(request_id)
	if ai_request == null:
		return
	_pending_by_request_id.erase(request_id)
	response["backend"] = backend_id()
	ai_request.complete(response)


func _on_generation_failed(request_id: int, error: String) -> void:
	var ai_request: AiRequest = _pending_by_request_id.get(request_id)
	if ai_request == null:
		return
	_pending_by_request_id.erase(request_id)
	ai_request.fail(error)


func _on_model_load_completed() -> void:
	state = State.READY
	_flush_pending()


func _on_model_load_failed(error: String) -> void:
	state = State.FAILED
	# Say so loudly. On a phone this is almost always "the weights are not on the
	# device", and the symptom a player would otherwise see is an AI that is
	# simply never available, with nothing in the log explaining why.
	push_error("InProcessLlamaBackend: model load failed (%s) for weights_path '%s'" % [
		error, profile.weights_path if profile != null else "<no profile>"])
	_flush_pending()


func _flush_pending() -> void:
	var callbacks := _pending_before_ready
	_pending_before_ready = []
	for callback in callbacks:
		callback.call()


func _defer_failure(ai_request: AiRequest, error: String) -> void:
	(func() -> void: ai_request.fail(error)).call_deferred()
