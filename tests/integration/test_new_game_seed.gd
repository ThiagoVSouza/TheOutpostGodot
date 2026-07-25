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


func test_the_wizards_narration_choice_reaches_the_narrator() -> void:
	# The Settings step's payoff: the stored preference is what the executor resolves an authored
	# `verbosity` against, so choosing "Long" has to move the level the narrator is actually asked
	# to write at — not merely sit in the profile.
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia",
		GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_LONG})

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_LONG)
	# The `opening` beat is authored `long`; at this preference it resolves past what any author
	# writes, which is the whole point of the ladder being wider than the authored literals.
	assert_eq(kernel.narration.resolve("long"), "full")


func test_average_narration_is_a_real_middle_not_a_second_short() -> void:
	# The wizard offers three lengths, so they have to be three. `normal` earns its own base on the
	# ladder: without one it falls back to short's, and two of the three cards behave identically.
	var kernel := _kernel()
	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_NORMAL})
	var average := kernel.narration.resolve("normal")

	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT})
	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT, "the new game's choice applied")
	assert_ne(average, kernel.narration.resolve("normal"), "average reads longer than short")


func test_a_loaded_game_does_not_inherit_the_previous_games_narration_choice() -> void:
	# `narration` is not in the save (it is derived), so the only thing standing between a load and
	# the last game's setting is the kernel re-deriving it. A game saved at Short, loaded while Long
	# is in force, must read Short.
	var kernel := _kernel()
	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT})
	var saved: Dictionary = {"version": 1, "state": {
		GameSession.PROFILE_STATE_KEY: {GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT},
	}}
	kernel.narration.level = NarrationSettings.LEVEL_LONG

	kernel.saves.restore(kernel, saved)

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT,
		"the loaded game's own preference governs it")


func test_a_game_with_no_stored_preference_reads_as_unset_not_inherited() -> void:
	# An older save predating the wizard has no profile. It gets the default, not whatever the
	# session happened to be set to — "unset" and "inherit the last game" are different answers.
	var kernel := _kernel()
	kernel.narration.level = NarrationSettings.LEVEL_LONG

	kernel.saves.restore(kernel, {"version": 1, "state": {}})

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT)


func test_the_wizards_flag_is_stored_for_the_game_to_show() -> void:
	# The chat screen's header reads this back through FlagValue.from_dict, so what the wizard
	# stored has to survive the round trip — the flag the player designed, not a default.
	var kernel := _kernel()
	var designed := {"shapeColor": "#2f5fc0", "texture": "pattern07", "textureColor": "#f3c43f",
		"emblem": "emblem04", "emblemColor": "#f7f7f2"}
	kernel.session.begin_new_game({GameSession.OUTPOST_FLAG_STATE_KEY: designed})

	var stored: Dictionary = kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {})
	var value := FlagValue.from_dict(stored)
	assert_eq(value.shape_color, Color.html("#2f5fc0"), "the cloth colour survived")
	assert_eq(value.texture, "pattern07")
	assert_eq(value.emblem, "emblem04")


func test_begin_new_game_replaces_a_previous_game() -> void:
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "First"})
	kernel.session.begin_new_game({"hero_name": "Second"})

	# start_new clears before seeding, so the second game does not inherit the first's hero name
	# and the plot is created fresh (create_plan would reject a duplicate otherwise).
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Second")
	assert_eq((kernel.state.get_value("plans", {}) as Dictionary).size(), 1, "one plot, not two")
