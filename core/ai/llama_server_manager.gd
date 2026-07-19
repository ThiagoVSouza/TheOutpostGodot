class_name LlamaServerManager
extends Node

## Owns the desktop llama-server process for one [ModelProfile].
##
## Startup is deliberately signal-driven: callers can request readiness without ever
## blocking a frame. A healthy server already listening on the configured endpoint is
## reused, while only a PID created by this manager is terminated during shutdown.

signal server_ready(reused_existing: bool)
signal server_failed(reason: String)

enum State { STOPPED, STARTING, READY, FAILED }

const HEALTH_POLL_SECONDS := 0.25
const HEALTH_REQUEST_TIMEOUT_SECONDS := 1.0
const DEFAULT_STARTUP_TIMEOUT_SECONDS := 45.0

var profile: ModelProfile
var endpoint_base_url: String
var state: State = State.STOPPED
var startup_timeout_seconds := DEFAULT_STARTUP_TIMEOUT_SECONDS

var _process_id := -1
var _owns_process := false
var _startup_deadline_ms := 0


func _init(selected_profile: ModelProfile = null, endpoint: String = "http://127.0.0.1:8099") -> void:
	profile = selected_profile
	endpoint_base_url = endpoint.rstrip("/")


func is_ready() -> bool:
	return state == State.READY


func owns_process() -> bool:
	return _owns_process


func ensure_started() -> void:
	if state == State.READY:
		server_ready.emit(not _owns_process)
		return
	if state == State.STARTING:
		return
	state = State.STARTING
	call_deferred("_begin_startup")


func shutdown() -> void:
	if _owns_process and _process_id > 0:
		_kill_process(_process_id)
	_process_id = -1
	_owns_process = false
	if state != State.FAILED:
		state = State.STOPPED


## T5 recovery: tear down and run the full startup sequence again. The health probe
## in startup reuses a healthy external server and relaunches a dead owned one, so
## this is safe to call from any state — including READY with a silently dead process.
func restart() -> void:
	shutdown()
	state = State.STOPPED
	ensure_started()


func _exit_tree() -> void:
	shutdown()


func _begin_startup() -> void:
	if state != State.STARTING:
		return
	_probe_health(_on_existing_health)


func _on_existing_health(healthy: bool) -> void:
	if state != State.STARTING:
		return
	if healthy:
		_process_id = -1
		_owns_process = false
		state = State.READY
		server_ready.emit(true)
		return
	_launch_server()


func _launch_server() -> void:
	if profile == null:
		_fail("model_profile_unavailable")
		return
	var gate := profile.capability_gate(_runtime_capabilities())
	if not bool(gate.get("allowed", false)):
		_fail("model_capability_%s" % String(gate.get("reason", "rejected")))
		return
	if not _path_exists(profile.server_executable_path):
		_fail("server_executable_missing")
		return
	if not _path_exists(profile.weights_path):
		_fail("model_weights_missing")
		return
	var process_id := _create_server_process(profile.server_executable_path, _launch_arguments())
	if process_id <= 0:
		_fail("server_spawn_failed")
		return
	_process_id = process_id
	_owns_process = true
	_startup_deadline_ms = Time.get_ticks_msec() + int(startup_timeout_seconds * 1000.0)
	_poll_started_server()


func _launch_arguments() -> PackedStringArray:
	var arguments := profile.server_arguments()
	var port := _endpoint_port()
	arguments.append_array(PackedStringArray([
		"--host", "127.0.0.1",
		"--port", str(port),
		"--no-webui",
	]))
	return arguments


func _poll_started_server() -> void:
	if state != State.STARTING:
		return
	_probe_health(_on_started_health)


func _on_started_health(healthy: bool) -> void:
	if state != State.STARTING:
		return
	if healthy:
		state = State.READY
		server_ready.emit(false)
		return
	if Time.get_ticks_msec() >= _startup_deadline_ms:
		_fail("server_start_timeout_or_port_in_use")
		return
	get_tree().create_timer(HEALTH_POLL_SECONDS).timeout.connect(_poll_started_server, CONNECT_ONE_SHOT)


func _fail(reason: String) -> void:
	if state != State.STARTING:
		return
	if _owns_process and _process_id > 0:
		_kill_process(_process_id)
	_process_id = -1
	_owns_process = false
	state = State.FAILED
	server_failed.emit(reason)


func _health_url() -> String:
	return "%s/health" % endpoint_base_url


func _endpoint_port() -> int:
	var authority := endpoint_base_url.trim_prefix("http://").trim_prefix("https://")
	var port_text := authority.get_slice(":", 1).get_slice("/", 0)
	if port_text.is_valid_int():
		return port_text.to_int()
	return 8099


## Overridable seams keep lifecycle tests independent of a real model and GPU.
func _runtime_capabilities() -> ModelCapabilities:
	return ModelRuntimeProbe.probe()


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _create_server_process(path: String, arguments: PackedStringArray) -> int:
	return OS.create_process(path, arguments, false)


func _kill_process(process_id: int) -> void:
	OS.kill(process_id)


func _probe_health(completion: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = HEALTH_REQUEST_TIMEOUT_SECONDS
	add_child(request)
	request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			if is_instance_valid(request) and not request.is_queued_for_deletion():
				request.queue_free()
			completion.call(result == HTTPRequest.RESULT_SUCCESS and response_code == 200),
		CONNECT_ONE_SHOT
	)
	call_deferred("_start_health_request", request, completion)


func _start_health_request(request: HTTPRequest, completion: Callable) -> void:
	if not is_instance_valid(request) or request.is_queued_for_deletion():
		return
	var start_error := request.request(_health_url(), PackedStringArray(), HTTPClient.METHOD_GET)
	if start_error != OK:
		request.queue_free()
		completion.call_deferred(false)
