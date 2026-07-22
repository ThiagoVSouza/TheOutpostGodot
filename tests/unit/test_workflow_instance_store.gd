extends GutTest

## The owner of suspended instances (M4/B1). D25 made instances resumable and A3 proved the
## snapshot round-trips; until this store existed nothing held one between suspension and wake,
## so there was nothing to save.


func _suspended(instance_id: String, wake: Dictionary) -> WorkflowInstance:
	var instance := WorkflowInstance.create("demo", 1, {}, 0)
	instance.instance_id = instance_id
	instance.status = WorkflowInstance.Status.SUSPENDED
	instance.wake = wake
	return instance


func test_it_remembers_and_returns_a_suspended_instance() -> void:
	var store := WorkflowInstanceStore.new()
	store.remember(_suspended("wfi_1", {"type": "confirmation"}))

	assert_true(store.has("wfi_1"))
	assert_eq(store.count(), 1)
	assert_eq(store.get_instance("wfi_1").workflow_id, "demo")


func test_it_refuses_instances_that_are_not_suspended() -> void:
	var store := WorkflowInstanceStore.new()
	var done := WorkflowInstance.create("demo", 1, {}, 0)
	done.status = WorkflowInstance.Status.COMPLETED

	store.remember(done)
	store.remember(null)

	# A completed instance has nothing to wake; storing one would leak a save entry forever.
	assert_eq(store.count(), 0, "only suspended instances are owned")


func test_forgetting_is_idempotent() -> void:
	var store := WorkflowInstanceStore.new()
	store.remember(_suspended("wfi_1", {"type": "confirmation"}))

	store.forget("wfi_1")
	store.forget("wfi_1")
	store.forget("never_existed")

	assert_eq(store.count(), 0)
	assert_null(store.get_instance("wfi_1"), "a forgotten instance is gone")


func test_pending_preserves_insertion_order() -> void:
	var store := WorkflowInstanceStore.new()
	store.remember(_suspended("wfi_1", {"type": "confirmation"}))
	store.remember(_suspended("wfi_2", {"type": "confirmation"}))

	# The oldest pending question is the one a UI should ask first.
	var ids: Array = []
	for instance: WorkflowInstance in store.pending():
		ids.append(instance.instance_id)
	assert_eq(ids, ["wfi_1", "wfi_2"])


func test_it_separates_player_questions_from_calendar_waits() -> void:
	var store := WorkflowInstanceStore.new()
	store.remember(_suspended("ask", {"type": "confirmation"}))
	store.remember(_suspended("soon", {"type": "game_time", "at_day": 5}))
	store.remember(_suspended("later", {"type": "game_time", "at_day": 40}))

	assert_eq(store.pending_confirmations().size(), 1, "one question is waiting on the player")
	var due: Array = store.due_at_day(10)
	assert_eq(due.size(), 1, "only the wait the calendar has reached is due")
	assert_eq((due[0] as WorkflowInstance).instance_id, "soon")


func test_the_store_survives_a_json_round_trip() -> void:
	var store := WorkflowInstanceStore.new()
	var instance := _suspended("wfi_1", {"type": "confirmation", "msg": "burn the granary?"})
	instance.locals = {"target": "granary"}
	instance.roll_count = 3
	instance.pc_stack = [{"sel": "then", "at": 1, "pc": 0}]
	store.remember(instance)

	# Through actual JSON text, not just a dictionary copy — the save file is text, and this is
	# where "1 parses back as a float" style surprises show up.
	var restored := WorkflowInstanceStore.new()
	restored.from_dict(JSON.parse_string(JSON.stringify(store.to_dict())) as Dictionary)

	assert_eq(restored.count(), 1)
	var back := restored.get_instance("wfi_1")
	assert_eq(back.workflow_id, "demo")
	assert_eq(back.status, WorkflowInstance.Status.SUSPENDED)
	assert_eq(String(back.wake["msg"]), "burn the granary?")
	assert_eq(String(back.locals["target"]), "granary")
	assert_eq(back.roll_count, 3, "the roll counter survives, so resumed rolls stay deterministic")
	assert_eq(back.pc_stack.size(), 1, "and the resume point survives")


func test_loading_replaces_rather_than_merges() -> void:
	var store := WorkflowInstanceStore.new()
	store.remember(_suspended("stale", {"type": "confirmation"}))

	store.from_dict({"suspended": [_suspended("fresh", {"type": "confirmation"}).to_dict()]})

	assert_false(store.has("stale"), "loading a save does not leave the old session's questions behind")
	assert_true(store.has("fresh"))


func test_a_corrupt_entry_costs_one_action_not_the_whole_load() -> void:
	var store := WorkflowInstanceStore.new()
	var good := _suspended("good", {"type": "confirmation"}).to_dict()
	var completed := WorkflowInstance.create("demo", 1, {}, 0)  # status running, not suspended

	store.from_dict({"suspended": ["not a dictionary", {"instance_id": ""},
		completed.to_dict(), good]})

	assert_eq(store.count(), 1, "the valid entry still loads")
	assert_true(store.has("good"))
