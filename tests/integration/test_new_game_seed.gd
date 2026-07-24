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

	# One background plot, already due at its wake so the ticker will run it.
	var plans: Dictionary = kernel.state.get_value("plans", {})
	assert_true(plans.has("steward_extortion"), "a starting plot exists")
	assert_false(Plans.due(plans, 30).is_empty(), "and it is due at its wake day")

	# The opening the game screen shows, and the announcement.
	assert_string_contains(String(kernel.state.get_value("opening_line", "")), "Livia")
	assert_eq(started.size(), 1, "new_game_started fired once")


func test_begin_new_game_replaces_a_previous_game() -> void:
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "First"})
	kernel.session.begin_new_game({"hero_name": "Second"})

	# start_new clears before seeding, so the second game does not inherit the first's hero name
	# and the plot is created fresh (create_plan would reject a duplicate otherwise).
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Second")
	assert_eq((kernel.state.get_value("plans", {}) as Dictionary).size(), 1, "one plot, not two")
