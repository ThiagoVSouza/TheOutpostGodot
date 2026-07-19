class_name LocalLlamaBackend
extends AiBackend

## Async desktop backend that waits for [LlamaServerManager] before using T2's HTTP
## transport. It keeps the D22 request contract intact during a cold model load.


class PendingRequest:
	extends RefCounted

	var outer: AiRequest
	var inner: AiRequest = null

	func _init(request: AiRequest) -> void:
		outer = request

	func begin(remote: RemoteLlamaBackend, request: Dictionary, identity: String) -> void:
		if outer == null or outer.is_finished():
			return
		inner = remote.generate(request)
		inner.chunk.connect(_on_chunk)
		inner.completed.connect(func(response: Dictionary) -> void: _on_completed(response, identity))
		inner.failed.connect(_on_failed)

	func cancel() -> void:
		if inner != null and not inner.is_finished():
			inner.cancel()

	func on_outer_failed(_error: String) -> void:
		cancel()
		_release()

	func on_outer_completed(_response: Dictionary) -> void:
		_release()

	func _on_chunk(text: String) -> void:
		if outer != null:
			outer.emit_chunk(text)

	func _on_completed(response: Dictionary, identity: String) -> void:
		if outer != null and not outer.is_finished():
			response["backend"] = identity
			outer.complete(response)

	func _on_failed(error: String) -> void:
		if outer != null and not outer.is_finished():
			outer.fail(error)

	func _release() -> void:
		outer = null
		inner = null


var server_manager: LlamaServerManager
var remote_backend: RemoteLlamaBackend
var _pending_requests: Array[PendingRequest] = []


func _init(manager: LlamaServerManager, remote: RemoteLlamaBackend) -> void:
	server_manager = manager
	remote_backend = remote


func backend_id() -> String:
	return "local-llama"


func is_ready() -> bool:
	return is_instance_valid(server_manager) and server_manager.is_ready()


func generate(request: Dictionary) -> AiRequest:
	var outer := AiRequest.new()
	var pending := PendingRequest.new(outer)
	_pending_requests.append(pending)
	outer.set_cancel_hook(pending.cancel)
	outer.failed.connect(func(error: String) -> void:
		pending.on_outer_failed(error)
		_pending_requests.erase(pending)
	)
	outer.completed.connect(func(response: Dictionary) -> void:
		pending.on_outer_completed(response)
		_pending_requests.erase(pending)
	)
	if not is_instance_valid(server_manager) or not is_instance_valid(remote_backend):
		_defer_failure(outer, "local_server_manager_unavailable")
		return outer

	var begin_remote := pending.begin.bind(remote_backend, request, backend_id())
	if server_manager.is_ready():
		begin_remote.call_deferred()
		return outer
	server_manager.server_ready.connect(
		func(_reused_existing: bool) -> void: begin_remote.call(),
		CONNECT_ONE_SHOT
	)
	server_manager.server_failed.connect(
		func(reason: String) -> void:
			if not outer.is_finished():
				outer.fail(reason),
		CONNECT_ONE_SHOT
	)
	server_manager.ensure_started()
	return outer


## T5 recovery: the first attempt of an outage runs a full manager restart cycle —
## shutdown (killing only a process we own) then the normal startup sequence, which
## reuses a healthy external server or relaunches a dead owned one. This is the
## "one process restart per outage" bound: later attempts only re-probe health.
func attempt_recovery(attempt: int) -> AiRequest:
	if not is_instance_valid(server_manager) or not is_instance_valid(remote_backend):
		var probe := AiRequest.new()
		_defer_failure(probe, "local_server_manager_unavailable")
		return probe
	if attempt == 1:
		return _recover_via_manager()
	return remote_backend.attempt_recovery(attempt)


func _recover_via_manager() -> AiRequest:
	var probe := AiRequest.new()
	server_manager.server_ready.connect(
		func(_reused_existing: bool) -> void:
			if not probe.is_finished():
				probe.complete({}),
		CONNECT_ONE_SHOT
	)
	server_manager.server_failed.connect(
		func(reason: String) -> void:
			if not probe.is_finished():
				probe.fail(reason),
		CONNECT_ONE_SHOT
	)
	server_manager.restart()
	return probe


func _defer_failure(request: AiRequest, error: String) -> void:
	(func() -> void: request.fail(error)).call_deferred()
