extends GutTest


class TestServerManager:
	extends LlamaServerManager

	var health_answers: Array[bool] = []
	var spawned_arguments := PackedStringArray()
	var spawn_calls := 0
	var killed_processes: Array[int] = []
	var capabilities := ModelCapabilities.new("Windows", 32768, 32768)

	func _probe_health(completion: Callable) -> void:
		var healthy: bool = health_answers.pop_front() if not health_answers.is_empty() else false
		completion.call_deferred(healthy)

	func _runtime_capabilities() -> ModelCapabilities:
		return capabilities

	func _path_exists(_path: String) -> bool:
		return true

	func _create_server_process(_path: String, arguments: PackedStringArray) -> int:
		spawn_calls += 1
		spawned_arguments = arguments
		return 4242

	func _kill_process(process_id: int) -> void:
		killed_processes.append(process_id)


class TestRemoteBackend:
	extends RemoteLlamaBackend

	var calls := 0
	var last_request: AiRequest = null

	func _init() -> void:
		pass

	func generate(_request: Dictionary) -> AiRequest:
		calls += 1
		last_request = AiRequest.new()
		return last_request


func test_cold_start_launches_profile_and_becomes_ready() -> void:
	var manager := _manager()
	manager.health_answers = [false, true]
	manager.ensure_started()
	var reused: bool = await manager.server_ready
	assert_false(reused)
	assert_true(manager.is_ready())
	assert_true(manager.owns_process())
	assert_eq(manager.spawn_calls, 1)
	assert_eq(manager.spawned_arguments, PackedStringArray([
		"-m", "model.gguf", "-ngl", "99", "-c", "16384", "-np", "4",
		"--cache-reuse", "256", "-rea", "off", "-t", "8",
		"--host", "127.0.0.1", "--port", "8099", "--no-webui",
	]))
	manager.shutdown()
	assert_eq(manager.killed_processes, [4242])
	await get_tree().process_frame


func test_healthy_existing_server_is_reused_and_never_killed() -> void:
	var manager := _manager()
	manager.health_answers = [true]
	manager.ensure_started()
	var reused: bool = await manager.server_ready
	assert_true(reused)
	assert_eq(manager.spawn_calls, 0)
	assert_false(manager.owns_process())
	manager.shutdown()
	assert_eq(manager.killed_processes, [])
	await get_tree().process_frame


func test_capability_rejection_fails_before_spawning() -> void:
	var manager := _manager()
	manager.health_answers = [false]
	manager.capabilities = ModelCapabilities.new("Windows", 1024, 32768)
	manager.ensure_started()
	var reason: String = await manager.server_failed
	assert_eq(reason, "model_capability_insufficient_ram")
	assert_eq(manager.spawn_calls, 0)
	await get_tree().process_frame


func test_unhealthy_started_process_times_out_and_is_cleaned_up() -> void:
	var manager := _manager()
	manager.health_answers = [false, false]
	manager.startup_timeout_seconds = 0.0
	manager.ensure_started()
	var reason: String = await manager.server_failed
	assert_eq(reason, "server_start_timeout_or_port_in_use")
	assert_eq(manager.killed_processes, [4242])
	await get_tree().process_frame


func test_local_backend_waits_for_readiness_then_uses_remote_transport() -> void:
	var manager := _manager()
	manager.health_answers = [false, true]
	var remote := TestRemoteBackend.new()
	var backend := LocalLlamaBackend.new(manager, remote)
	var request := backend.generate({"message": "hello"})
	assert_false(request.is_finished())
	await manager.server_ready
	await get_tree().process_frame
	assert_eq(remote.calls, 1)
	remote.last_request.complete({"content": "ready"})
	var outcome := await request.wait()
	assert_true(bool(outcome["ok"]))
	assert_eq(String((outcome["response"] as Dictionary)["backend"]), "local-llama")
	manager.shutdown()
	await get_tree().process_frame


func test_cancel_before_server_ready_does_not_open_remote_request() -> void:
	var manager := _manager()
	manager.state = LlamaServerManager.State.STARTING
	var remote := TestRemoteBackend.new()
	var backend := LocalLlamaBackend.new(manager, remote)
	var request := backend.generate({"message": "hello"})
	request.cancel()
	manager.server_ready.emit(false)
	await get_tree().process_frame
	assert_eq(remote.calls, 0)
	var outcome := await request.wait()
	assert_true(bool(outcome["cancelled"]))
	await get_tree().process_frame


func _manager() -> TestServerManager:
	var profile := ModelProfile.new()
	profile.profile_id = "test"
	profile.display_name = "Test"
	profile.platform = "Windows"
	profile.backend = ModelProfile.BACKEND_CUDA
	profile.server_executable_path = "server.exe"
	profile.weights_path = "model.gguf"
	profile.gpu_layers = 99
	profile.context_total = 16384
	profile.parallel_slots = 4
	profile.routing_family_count = 4
	profile.cache_reuse_tokens = 256
	profile.reasoning_enabled = false
	profile.threads = 8
	profile.required_available_ram_mib = 4096
	profile.required_available_vram_mib = 4096
	var manager := TestServerManager.new(profile)
	add_child_autofree(manager)
	return manager
