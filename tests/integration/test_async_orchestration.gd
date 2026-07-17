extends GutTest

## D22 contract tests: the seam is genuinely async, cancellation stops state changes,
## overlapping orchestrations are rejected, and the orchestrator-owned timeout fires.


## A backend that never answers — for timeout and cancel-hook tests.
class StuckAiBackend:
	extends AiBackend
	var last_request: AiRequest = null
	var cancel_hook_calls: int = 0

	func backend_id() -> String:
		return "stuck"

	func is_ready() -> bool:
		return true

	func generate(_request: Dictionary) -> AiRequest:
		var req := AiRequest.new()
		req.set_cancel_hook(func() -> void: cancel_hook_calls += 1)
		last_request = req
		return req


func _make_kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	return kernel


# --- AiRequest / fake-backend contract ---

func test_fake_backend_never_completes_synchronously() -> void:
	var fake := FakeAiBackend.new()
	var req := fake.generate({"intent": "general"})
	assert_false(req.is_finished(), "completion must be deferred, not in-call (D22)")
	var outcome: Dictionary = await req.wait()
	assert_true(bool(outcome["ok"]))
	assert_true(req.is_finished())


func test_wait_after_completion_returns_immediately() -> void:
	var req := AiRequest.new()
	req.complete({"narrative": "done"})
	var outcome: Dictionary = await req.wait()
	assert_true(bool(outcome["ok"]), "late awaiters must not hang on a finished request")
	assert_eq((outcome["response"] as Dictionary)["narrative"], "done")


func test_cancel_wins_over_late_completion() -> void:
	var req := AiRequest.new()
	req.cancel()
	req.complete({"narrative": "too late"})
	var outcome: Dictionary = await req.wait()
	assert_false(bool(outcome["ok"]))
	assert_true(bool(outcome["cancelled"]))
	assert_eq(String(outcome["error"]), "cancelled")


func test_double_complete_keeps_first_outcome() -> void:
	var req := AiRequest.new()
	req.complete({"n": 1})
	req.complete({"n": 2})
	req.fail("late failure")
	var outcome: Dictionary = await req.wait()
	assert_true(bool(outcome["ok"]))
	assert_eq(int((outcome["response"] as Dictionary)["n"]), 1)


func test_cancel_runs_backend_cancel_hook() -> void:
	var stuck := StuckAiBackend.new()
	var req := stuck.generate({})
	req.cancel()
	assert_eq(stuck.cancel_hook_calls, 1, "backend transport abort hook must run on cancel")


# --- orchestrator behavior ---

func test_cancel_mid_turn_stops_pipeline_and_state() -> void:
	var kernel := _make_kernel()
	var fake := kernel.ai as FakeAiBackend
	fake.queue_responses("forage", [
		{"tool_calls": [{"name": "roll_die", "args": {"sides": 6, "count": 1, "seed": 1}}]},
		{"commands": [{"name": "grant_resource", "args": {"resource": "food", "amount": 3}}],
			"narrative": "should never arrive"},
	])

	# Capture-lambda pattern: cancel() resumes the pipeline synchronously, so the
	# coroutine may already be completed by the time we look — awaiting it directly
	# would hang on its already-emitted completion signal.
	var holder := {}
	var runner := func() -> void:
		holder["result"] = await kernel.ai_orchestrator.handle_message("forage for food")
	runner.call()
	kernel.ai_orchestrator.cancel()
	if not holder.has("result"):
		await wait_frames(10)
	assert_true(holder.has("result"), "orchestration must finish after cancel")
	var result: Dictionary = holder["result"]

	assert_false(bool(result["ok"]))
	assert_eq(String(result["error"]), "cancelled")
	var resources: Dictionary = kernel.state.get_value("resources", {})
	assert_eq(int(resources.get("food", 0)), 0, "no state change after cancel")
	var trace: AiTrace = result["trace"]
	assert_true(trace.has_stage("cancelled"))


func test_busy_guard_rejects_overlapping_message() -> void:
	var kernel := _make_kernel()
	var holder := {}
	var runner := func() -> void:
		holder["first"] = await kernel.ai_orchestrator.handle_message("hello there outpost")
	runner.call()
	assert_true(kernel.ai_orchestrator.is_busy())
	var second: Dictionary = await kernel.ai_orchestrator.handle_message("me too")
	assert_false(bool(second["ok"]))
	assert_eq(String(second["error"]), "busy")
	if not holder.has("first"):
		await wait_frames(10)
	var result: Dictionary = holder["first"]
	assert_true(bool(result["ok"]), "the first orchestration is unaffected")
	assert_false(kernel.ai_orchestrator.is_busy())


func test_timeout_fails_a_stuck_backend() -> void:
	var kernel := _make_kernel()
	kernel.ai = StuckAiBackend.new()
	kernel.ai_orchestrator.ai_timeout_seconds = 0.05
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("hello there outpost")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["error"]), "timeout")
	var trace: AiTrace = result["trace"]
	assert_true(trace.has_stage("ai_failed"))
	assert_false(kernel.ai_orchestrator.is_busy(), "orchestrator recovers after timeout")


func test_orchestrator_idle_cancel_is_noop() -> void:
	var kernel := _make_kernel()
	kernel.ai_orchestrator.cancel()
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("hello there outpost")
	assert_true(bool(result["ok"]), "an idle cancel must not poison the next message")
