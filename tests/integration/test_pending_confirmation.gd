extends GutTest

## A turn that asks the player a question, survives being put down, and is answered later
## (M4/B1). Before the instance store, the orchestrator returned "pending_confirmation" and
## discarded the instance — the question could never be answered and never be saved.

const ENTRY := AiOrchestrator.ENTRY_WORKFLOW_ID


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	# Replace base_game's entry workflow with one that stops to ask. Same id, so the
	# orchestrator's one hardcoded fixed point (D30) still finds it.
	var registered: CommandResult = kernel.workflow_registry.register({
		"op": "workflow", "id": ENTRY, "version": 1, "origin": "test",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "confirm", "msg": "confirm.burn", "scope": {"action": "burn"}},
			{"op": "run_command", "name": "grant_resource",
			 "args": {"resource": "food", "amount": 4}},
			{"op": "narrate", "instruction": "the granary burns", "context": {},
			 "verbosity": "short", "language": "en"},
		]
	})
	assert_true(registered.success, "the asking entry workflow registers")
	return kernel


func _food(kernel: GameKernel) -> int:
	return int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


func test_a_suspended_turn_is_owned_not_dropped() -> void:
	var kernel := _kernel()

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("burn the granary")

	assert_true(bool(result["ok"]), "asking a question is a successful turn")
	assert_eq(String(result["error"]), "pending_confirmation")
	assert_eq(kernel.workflow_instances.count(), 1, "the instance is owned, not dropped")
	assert_false(String(result["pending_instance"]).is_empty(), "the caller gets a handle to answer with")
	assert_eq(kernel.workflow_instances.pending_confirmations().size(), 1)
	assert_eq(_food(kernel), 0, "nothing past the confirm has been applied")


func test_answering_yes_resumes_and_applies() -> void:
	var kernel := _kernel()
	var asked: Dictionary = await kernel.ai_orchestrator.handle_message("burn the granary")

	var answered: Dictionary = await kernel.ai_orchestrator.resume(
		String(asked["pending_instance"]), {"confirmed": true})

	assert_true(bool(answered["ok"]))
	assert_eq(_food(kernel), 4, "the command after the confirm ran exactly once")
	assert_eq(kernel.workflow_instances.count(), 0, "an answered question is no longer pending")
	assert_true((answered["trace"] as AiTrace).has_stage("turn_resumed"), "the resume is traced")


func test_answering_no_cancels_and_changes_nothing() -> void:
	var kernel := _kernel()
	var asked: Dictionary = await kernel.ai_orchestrator.handle_message("burn the granary")

	var answered: Dictionary = await kernel.ai_orchestrator.resume(
		String(asked["pending_instance"]), {"confirmed": false})

	assert_false(bool(answered["ok"]))
	assert_eq(String(answered["error"]), "cancelled")
	assert_eq(_food(kernel), 0, "a declined confirmation applies nothing")
	assert_eq(kernel.workflow_instances.count(), 0, "and the question is not left hanging")


func test_the_same_question_cannot_be_answered_twice() -> void:
	var kernel := _kernel()
	var asked: Dictionary = await kernel.ai_orchestrator.handle_message("burn the granary")
	var handle := String(asked["pending_instance"])

	await kernel.ai_orchestrator.resume(handle, {"confirmed": true})
	var again: Dictionary = await kernel.ai_orchestrator.resume(handle, {"confirmed": true})

	assert_false(bool(again["ok"]))
	assert_eq(String(again["error"]), "unknown_instance")
	assert_eq(_food(kernel), 4, "the exactly-once guarantee holds — no double grant")


func test_a_question_this_session_cannot_answer_is_kept_not_discarded() -> void:
	var kernel := _kernel()
	var asked: Dictionary = await kernel.ai_orchestrator.handle_message("burn the granary")
	var handle := String(asked["pending_instance"])
	# Stands in for a module being disabled, or a workflow registered at runtime that therefore
	# does not exist after a restart — found in the real app, not in tests.
	var orphan := kernel.workflow_instances.get_instance(handle)
	orphan.workflow_id = "a_workflow_this_session_does_not_have"

	var answered: Dictionary = await kernel.ai_orchestrator.resume(handle, {"confirmed": true})

	assert_false(bool(answered["ok"]))
	assert_eq(String(answered["error"]), "unknown_workflow")
	assert_false(kernel.ai_orchestrator.can_resume(handle), "UI is told not to offer it")
	# D34's rule reaching here: discarding would destroy a pending action that re-enabling the
	# module would have made answerable again, and the player never asked for that.
	assert_eq(kernel.workflow_instances.count(), 1, "the player's pending action is kept")

	# Registering the workflow makes it answerable again.
	orphan.workflow_id = ENTRY
	assert_true(kernel.ai_orchestrator.can_resume(handle))
	var retried: Dictionary = await kernel.ai_orchestrator.resume(handle, {"confirmed": true})
	assert_true(bool(retried["ok"]))
	assert_eq(_food(kernel), 4)


func test_a_pending_question_survives_a_restart() -> void:
	# The milestone's headline: put the game down mid-question, pick it up, answer it.
	var before := _kernel()
	var asked: Dictionary = await before.ai_orchestrator.handle_message("burn the granary")
	var handle := String(asked["pending_instance"])
	var saved := JSON.stringify(before.workflow_instances.to_dict())

	# A genuinely fresh kernel — nothing carried over but the serialized text.
	var after := _kernel()
	after.workflow_instances.from_dict(JSON.parse_string(saved) as Dictionary)

	assert_eq(after.workflow_instances.pending_confirmations().size(), 1,
		"the question is waiting to be re-presented")
	var answered: Dictionary = await after.ai_orchestrator.resume(handle, {"confirmed": true})
	assert_true(bool(answered["ok"]), "and it resumes in the new session")
	assert_eq(_food(after), 4, "finishing exactly what it was going to do")
