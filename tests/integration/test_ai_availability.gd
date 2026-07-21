extends GutTest

## T5 policy tests (D16 amendment): a backend failure blocks orchestration with a
## visible unavailable state, at most three bounded automatic recovery attempts run
## per outage, a deliberate player retry starts a new sequence, and no game state
## changes while unavailable.
##
## Ribosome note (D30): the orchestrator no longer calls the backend directly — the model is
## reached through the executor's runner/narrator seams, which report failures to availability.
## With fakes here, these tests open an outage via `ai_availability.report_failure(...)`
## directly; the recovery machinery (attempt_recovery, retry, events) is unchanged and still
## driven through `kernel.ai`.


## Configurable failing backend: generate() fails while `generate_fails` is true;
## recovery attempts consume `recovery_results` (true = healthy) and count calls.
class FlakyBackend:
	extends AiBackend
	var generate_fails: bool = true
	var generate_calls: int = 0
	var recovery_attempts: int = 0
	var recovery_results: Array = []

	func backend_id() -> String:
		return "flaky"

	func is_ready() -> bool:
		return true

	func generate(_request: Dictionary) -> AiRequest:
		generate_calls += 1
		var req := AiRequest.new()
		var fail_now := generate_fails
		(func() -> void:
			if fail_now:
				req.fail("connection_refused")
			else:
				req.complete({"narrative": "The connection holds."})).call_deferred()
		return req

	func attempt_recovery(_attempt: int) -> AiRequest:
		recovery_attempts += 1
		var healthy := false
		if not recovery_results.is_empty():
			healthy = bool(recovery_results.pop_front())
		var probe := AiRequest.new()
		(func() -> void:
			if healthy:
				probe.complete({})
			else:
				probe.fail("health_check_failed")).call_deferred()
		return probe


var _events_seen: Array = []


func _make_kernel_with_flaky(recovery_results: Array) -> Dictionary:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var flaky := FlakyBackend.new()
	flaky.recovery_results = recovery_results
	kernel.ai = flaky
	kernel.ai_availability.backoff_seconds = [0.0, 0.0, 0.0]
	_events_seen = []
	kernel.events.subscribe(AiAvailability.EVENT_NAME, func(payload: Dictionary) -> void:
		_events_seen.append(payload))
	return {"kernel": kernel, "flaky": flaky}


func _await_state(availability: AiAvailability, target: int, frames: int = 60) -> void:
	for i in range(frames):
		if availability.state() == target:
			return
		await wait_frames(1)


# --- outage entry and the three-attempt bound ---

func test_backend_failure_opens_outage_and_parks_after_three_attempts() -> void:
	var setup := _make_kernel_with_flaky([])  # every recovery probe fails
	var kernel: GameKernel = setup["kernel"]
	var flaky: FlakyBackend = setup["flaky"]

	# The seams report a backend failure to availability; with fakes here, open it directly.
	kernel.ai_availability.report_failure("connection_refused")
	assert_true(kernel.ai_availability.is_blocked(), "failure opens the outage immediately")

	await _await_state(kernel.ai_availability, AiAvailability.State.UNAVAILABLE)
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.UNAVAILABLE)
	assert_eq(flaky.recovery_attempts, 3, "exactly three automatic attempts per outage")

	await wait_frames(10)
	assert_eq(flaky.recovery_attempts, 3, "no fourth automatic attempt ever runs")


func test_blocked_orchestration_refuses_without_backend_or_state_change() -> void:
	var setup := _make_kernel_with_flaky([])
	var kernel: GameKernel = setup["kernel"]

	kernel.ai_availability.report_failure("connection_refused")
	await _await_state(kernel.ai_availability, AiAvailability.State.UNAVAILABLE)

	var blocked: Dictionary = await kernel.ai_orchestrator.handle_message("forage for food")
	assert_false(bool(blocked["ok"]))
	assert_eq(String(blocked["error"]), "unavailable")
	var resources: Dictionary = kernel.state.get_value("resources", {})
	assert_eq(int(resources.get("food", 0)), 0, "no state change while unavailable")
	var trace: AiTrace = blocked["trace"]
	assert_true(trace.has_stage("unavailable"))


# --- recovery success paths ---

func test_recovery_success_mid_sequence_restores_availability() -> void:
	var setup := _make_kernel_with_flaky([false, true])  # attempt 2 succeeds
	var kernel: GameKernel = setup["kernel"]
	var flaky: FlakyBackend = setup["flaky"]

	kernel.ai_availability.report_failure("connection_refused")
	await _await_state(kernel.ai_availability, AiAvailability.State.AVAILABLE)
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.AVAILABLE)
	assert_eq(flaky.recovery_attempts, 2, "sequence stops at the first healthy probe")

	var after: Dictionary = await kernel.ai_orchestrator.handle_message("hello again outpost")
	assert_true(bool(after["ok"]), "orchestration works again after recovery")


func test_player_retry_starts_a_new_bounded_sequence() -> void:
	var setup := _make_kernel_with_flaky([])  # first sequence exhausts
	var kernel: GameKernel = setup["kernel"]
	var flaky: FlakyBackend = setup["flaky"]

	kernel.ai_availability.report_failure("connection_refused")
	await _await_state(kernel.ai_availability, AiAvailability.State.UNAVAILABLE)
	assert_eq(flaky.recovery_attempts, 3)

	flaky.recovery_results = [true]
	kernel.ai_availability.retry()
	await _await_state(kernel.ai_availability, AiAvailability.State.AVAILABLE)
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.AVAILABLE)
	assert_eq(flaky.recovery_attempts, 4, "retry ran exactly one more probe")


func test_retry_is_ignored_unless_parked_unavailable() -> void:
	var setup := _make_kernel_with_flaky([])
	var kernel: GameKernel = setup["kernel"]
	var flaky: FlakyBackend = setup["flaky"]

	kernel.ai_availability.retry()  # AVAILABLE: no-op
	await wait_frames(5)
	assert_eq(flaky.recovery_attempts, 0)
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.AVAILABLE)


# --- what does NOT open an outage ---

func test_cancellation_does_not_open_an_outage() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var holder := {}
	var runner := func() -> void:
		holder["result"] = await kernel.ai_orchestrator.handle_message("hello there outpost")
	runner.call()
	kernel.ai_orchestrator.cancel()
	if not holder.has("result"):
		await wait_frames(10)
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.AVAILABLE,
		"cancellation is not an outage")


func test_fake_backend_default_flow_never_blocks() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("hello there outpost")
	assert_true(bool(result["ok"]))
	assert_eq(kernel.ai_availability.state(), AiAvailability.State.AVAILABLE)


# --- event stream for the UI ---

func test_events_announce_recovering_unavailable_and_restored() -> void:
	var setup := _make_kernel_with_flaky([])
	var kernel: GameKernel = setup["kernel"]
	var flaky: FlakyBackend = setup["flaky"]

	kernel.ai_availability.report_failure("connection_refused")
	await _await_state(kernel.ai_availability, AiAvailability.State.UNAVAILABLE)
	flaky.recovery_results = [true]
	kernel.ai_availability.retry()
	await _await_state(kernel.ai_availability, AiAvailability.State.AVAILABLE)

	var states: Array = []
	for payload_v in _events_seen:
		states.append(String((payload_v as Dictionary).get("state", "")))
	assert_true(states.count("unavailable") >= 1, "unavailable announced")
	assert_true(states.count("recovering") >= 4, "outage entry + each attempt announced")
	assert_eq(states.back(), "available", "restoration is the last announcement")