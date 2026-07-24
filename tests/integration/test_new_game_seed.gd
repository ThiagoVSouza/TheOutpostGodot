extends GutTest

## begin_new_game seeds a living world (the in-game phase): the module seed hook runs through the
## whitelisted CommandBus, producing a named hero, a small cast with dispositions, starting
## resources, and one ticking plot — then announces new_game_started.

const SCRATCH_WORK := "user://test_seed_work"


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boots + loads base_game (which overrides seed_new_game)
	kernel.workspace = SaveWorkspace.new(SCRATCH_WORK)
	kernel.session.autosave_enabled = false  # no disk writes during the test
	return kernel


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_WORK):
		return
	var dir := DirAccess.open(SCRATCH_WORK)
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_WORK, file])
	DirAccess.remove_absolute(SCRATCH_WORK)


func test_begin_new_game_seeds_the_cast_resources_and_a_ticking_plot() -> void:
	var kernel := _kernel()
	var started: Array = []
	kernel.events.subscribe("new_game_started", func(p: Dictionary) -> void: started.append(p))

	kernel.session.begin_new_game({"hero_name": "Livia"})

	# The named hero and the rest of the cast, with dispositions.
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Livia")
	assert_true(Entities.exists(kernel.state, "steward"), "the cast was created")
	assert_eq(Entities.disposition(kernel.state, "king"), 10)

	# Starting resources.
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 20)

	# One background plot, due within a few days so it ticks in a short hands-on session (the
	# placeholder pacing that makes the living-world loop observable in-game).
	var plans: Dictionary = kernel.state.get_value("plans", {})
	assert_true(plans.has("steward_extortion"), "a starting plot exists")
	assert_true(Plans.due(plans, 2).is_empty(), "not yet due on day 2")
	assert_false(Plans.due(plans, 3).is_empty(), "due by day 3")

	# The facts the narrated opening will dress (the screen plays the `opening` workflow over them),
	# and the announcement.
	var opening: Dictionary = kernel.state.get_value("opening", {})
	assert_eq(String(opening.get("hero", "")), "Livia", "the opening carries the hero's name")
	assert_eq(started.size(), 1, "new_game_started fired once")


func test_letting_days_pass_ticks_the_seeded_plot_in_play() -> void:
	# The in-play time-advance deliverable end to end: a freshly seeded game, then game days pass
	# (as the "let a day pass" control does — via the clock, not a direct ticker call), and the
	# seeded plot ticks on its own subscription and surfaces a chronicle emit.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	var chronicled: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: chronicled.append(p))

	kernel.session.begin_new_game({"hero_name": "Livia"})
	var before := int((kernel.state.get_value("plans", {})["steward_extortion"]["direction"]
		as Dictionary)["intensity"])

	kernel.clock.advance(3)  # reach the plot's wake day
	# The tick suspends a frame at its ai step (FakeAiRunner yields), so let it finish.
	for _i in range(5):
		await get_tree().process_frame

	var after := int((kernel.state.get_value("plans", {})["steward_extortion"]["direction"]
		as Dictionary)["intensity"])
	assert_gt(after, before, "the seeded plot escalated as the days passed")
	var ticked := chronicled.filter(func(p: Dictionary) -> bool:
		return String(p.get("msg", "")) == "base_game.plan_ticked")
	assert_false(ticked.is_empty(), "the tick surfaced a chronicle line in play")


func test_the_opening_workflow_narrates_over_the_seeded_facts() -> void:
	# What the chat screen plays on first entry to a fresh game: the authored `opening` workflow
	# narrates over the seed's facts (D30 — the opening is a workflow, not a static string, and the
	# narrator is handed the decided facts rather than inventing them, D4).
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia"})
	var facts: Dictionary = kernel.state.get_value("opening", {})
	var definition: Variant = kernel.workflow_registry.get_definition("opening")
	assert_true(definition is Dictionary, "base_game authors an opening workflow")

	var instance := WorkflowInstance.create("opening", 1, facts, 0)
	var result: RefCounted = await WorkflowExecutor.for_kernel(kernel).run(
		definition as Dictionary, instance, AiTrace.new())

	var prose := String(result.get("narration"))
	assert_false(prose.is_empty(), "the opening produced narration")
	assert_string_contains(prose, "Livia", "the narrator was handed the hero's name")


func test_begin_new_game_replaces_a_previous_game() -> void:
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "First"})
	kernel.session.begin_new_game({"hero_name": "Second"})

	# start_new clears before seeding, so the second game does not inherit the first's hero name
	# and the plot is created fresh (create_plan would reject a duplicate otherwise).
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Second")
	assert_eq((kernel.state.get_value("plans", {}) as Dictionary).size(), 1, "one plot, not two")
