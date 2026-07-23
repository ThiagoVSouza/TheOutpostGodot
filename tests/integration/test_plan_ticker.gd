extends GutTest

## The plan-format walking skeleton, end to end (M5, D36): a due background plan runs its tick
## workflow, the model picks a transition from the closed set, and the command owns the numbers —
## intensity nudge, hysteresis band, code-owned revenge spawn — with the result living in
## GameState. FakeAiRunner makes the model's choice deterministic; the point is that everything
## downstream of that choice is code.


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boot registers the family, command and plan_tick workflow
	return kernel


func _seed_steward(kernel: GameKernel, humiliated: bool = false, next_wake: int = 30) -> void:
	var plan := Plans.new_plan("steward", "steward_extortion", "plan_tick", ["steward", "lord"],
		"The steward is extorting the lord.", next_wake)
	(plan["flags"] as Dictionary)["lord_humiliated"] = humiliated
	kernel.state.set_value("plans", {"steward": plan})


func _plans(kernel: GameKernel) -> Dictionary:
	return kernel.state.get_value("plans", {})


func test_a_due_plan_ticks_and_the_command_moves_its_intensity() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel)

	await kernel.plan_ticker.tick_due(30)

	var steward: Dictionary = _plans(kernel)["steward"]
	assert_eq(int((steward["direction"] as Dictionary)["intensity"]), 52, "escalate nudged +12 from 40")
	assert_eq((steward["history"] as Array).size(), 1, "the tick was recorded")


func test_a_plan_whose_wake_has_not_arrived_does_not_tick() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel, false, 100)  # due at day 100

	await kernel.plan_ticker.tick_due(30)

	var steward: Dictionary = _plans(kernel)["steward"]
	assert_eq(int((steward["direction"] as Dictionary)["intensity"]), 40, "untouched — not due yet")


func test_repeated_escalation_reaches_boiling_and_spawns_the_revenge_plot() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel, true)  # the lord has humiliated the steward

	# Each tick re-arms next_wake forward, so advance the day past it before the next.
	var day := 30
	for _i in range(3):
		await kernel.plan_ticker.tick_due(day)
		day = int((_plans(kernel)["steward"] as Dictionary)["next_wake"])

	var steward: Dictionary = _plans(kernel)["steward"]
	assert_eq(String((steward["direction"] as Dictionary)["band"]), "boiling", "40 -> 52 -> 64 -> 76")
	assert_true(_plans(kernel).has("steward_revenge"),
		"reaching boiling with the lord humiliated spawned the revenge plot — code's call, not the model's")


func test_resolve_ends_the_plan_through_the_workflow() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "resolve")
	_seed_steward(kernel)

	await kernel.plan_ticker.tick_due(30)

	var steward: Dictionary = _plans(kernel)["steward"]
	assert_eq(String((steward as Dictionary)["status"]), "resolved")
	assert_eq(Plans.due(_plans(kernel), 999).size(), 0, "and it is never due again")


func test_the_model_only_picks_a_label_every_number_is_the_rules() -> void:
	# Whatever the model returns, the intensity is one the nudge table produces from 40 — never a
	# value the model could have invented (D4).
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "de_escalate")
	_seed_steward(kernel)

	await kernel.plan_ticker.tick_due(30)

	assert_eq(int((_plans(kernel)["steward"]["direction"] as Dictionary)["intensity"]), 28)


func test_a_tick_shows_the_model_the_latest_memory_about_its_subjects() -> void:
	# The stub is gone (D37): the "latest development" a tick feeds the model is now the most
	# recent memory about the plan's subjects, retrieved by entity-tag + recency.
	var kernel := _kernel()
	_seed_steward(kernel)  # subjects: ["steward", "lord"]
	kernel.memories.record("The lord refused the steward's demand before the whole court.", ["lord"], 20)
	kernel.memories.record("An older, unrelated grievance.", ["steward"], 5)

	var plan: Dictionary = _plans(kernel)["steward"]
	var latest := kernel.plan_ticker._latest_development(plan, 30)
	assert_string_contains(latest, "refused the steward's demand", "the newest matching memory")


func test_a_tick_falls_back_when_nothing_is_remembered_yet() -> void:
	var kernel := _kernel()
	_seed_steward(kernel)

	var plan: Dictionary = _plans(kernel)["steward"]
	var latest := kernel.plan_ticker._latest_development(plan, 30)
	assert_string_contains(latest, "nothing new", "a plan can tick before anything about it is on record")


func test_a_tick_records_its_development_as_a_memory() -> void:
	# The write side (D37): a tick leaves a memory of what changed, tagged with the plan's subjects.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel)

	await kernel.plan_ticker.tick_due(30)

	var recalled := kernel.memories.retrieve(["steward"], 5, 30)
	assert_eq(recalled.size(), 1, "the tick left one memory about its subjects")
	assert_string_contains(String((recalled[0] as Dictionary)["text"]), "rose further",
		"and the memory reflects the transition the model chose")


func test_the_loop_is_self_sustaining() -> void:
	# The whole point: a tick's development becomes the next tick's retrieved context, with no
	# external writer. The plan feeds itself.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel)

	await kernel.plan_ticker.tick_due(30)  # records "rose further", re-arms its wake

	var plan: Dictionary = _plans(kernel)["steward"]
	var next_latest := kernel.plan_ticker._latest_development(plan, 90)
	assert_string_contains(next_latest, "rose further",
		"what the last tick recorded is what the next tick shows the model")


func test_the_first_tick_records_but_reads_the_neutral_fallback() -> void:
	# Ordering: the tick reads its development *before* it records this one, so a plan's very first
	# tick still gets the fallback rather than reading a memory it is about to write.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel)

	var plan_before: Dictionary = _plans(kernel)["steward"]
	assert_string_contains(kernel.plan_ticker._latest_development(plan_before, 30), "nothing new")

	await kernel.plan_ticker.tick_due(30)
	assert_eq(kernel.memories.count(), 1, "and after the tick there is exactly one memory")


func test_the_day_passed_subscription_drives_ticks_from_the_clock() -> void:
	# The production wiring: the ticker runs off the calendar, not only when a test calls it.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	_seed_steward(kernel, false, 5)

	kernel.clock.advance(6)
	# The tick suspends one frame at the ai step (FakeAiRunner yields), so let it finish.
	for _i in range(5):
		await get_tree().process_frame

	assert_eq(int((_plans(kernel)["steward"]["direction"] as Dictionary)["intensity"]), 52,
		"advancing the clock past the wake day ran the tick")
