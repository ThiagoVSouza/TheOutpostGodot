extends GutTest

## D22 contract tests: the AiRequest seam is genuinely async and cancellable, and the
## orchestrator rejects overlapping turns (busy guard). Per-call timeout and cancel of an
## in-flight model call moved to the AI runner/narrator seams with the ribosome (D30), so
## those orchestrator-level tests retired with the M2 tool-calling path.


## A backend that never answers — for the cancel-hook test.
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


func test_orchestrator_idle_cancel_is_noop() -> void:
	var kernel := _make_kernel()
	kernel.ai_orchestrator.cancel()
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("hello there outpost")
	assert_true(bool(result["ok"]), "an idle cancel must not poison the next message")
