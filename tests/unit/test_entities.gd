extends GutTest

## The entity engine block (M5/M7): the model helpers over GameState["entities"], and the two
## whitelisted commands that mutate the cast. No content here — just the machinery.


func _world() -> GameState:
	var state := GameState.new()
	CreateEntityCommand.new("king", Entities.CHARACTER, "The King", 10).apply(state)
	CreateEntityCommand.new("steward", Entities.CHARACTER, "The Steward", -20, ["greedy"]).apply(state)
	CreateEntityCommand.new("outpost", Entities.LOCATION, "The Outpost").apply(state)
	return state


# --- helpers ---

func test_new_entity_clamps_disposition() -> void:
	assert_eq(int(Entities.new_entity("x", Entities.CHARACTER, "X", 500)["disposition"]), 100)
	assert_eq(int(Entities.new_entity("y", Entities.CHARACTER, "Y", -500)["disposition"]), -100)


func test_by_type_filters() -> void:
	var state := _world()
	assert_eq(Entities.by_type(state, Entities.CHARACTER).size(), 2)
	assert_eq(Entities.by_type(state, Entities.LOCATION).size(), 1)
	assert_eq(Entities.by_type(state, Entities.FACTION).size(), 0)


func test_resolve_gives_subjects_identity_and_skips_unknowns() -> void:
	var state := _world()
	# A plan's subjects, some real, one dangling — resolve returns only the real ones.
	var resolved := Entities.resolve(state, ["steward", "ghost", "outpost"])
	assert_eq(resolved.size(), 2)
	assert_eq(Entities.names(state, ["steward", "king"]), ["The Steward", "The King"])


func test_disposition_reads_the_current_value() -> void:
	var state := _world()
	assert_eq(Entities.disposition(state, "king"), 10)
	assert_eq(Entities.disposition(state, "nobody"), 0, "an unknown entity reads neutral, not an error")


# --- create_entity command ---

func test_create_rejects_blank_id_unknown_type_and_duplicates() -> void:
	var state := _world()
	assert_false(CreateEntityCommand.new("", Entities.CHARACTER, "X").validate(state).success, "blank id")
	assert_false(CreateEntityCommand.new("z", "monster", "Z").validate(state).success, "unknown type")
	assert_false(CreateEntityCommand.new("king", Entities.CHARACTER, "Dup").validate(state).success,
		"a duplicate id must not overwrite an existing entity")


func test_create_applies() -> void:
	var state := GameState.new()
	CreateEntityCommand.new("hero", Entities.CHARACTER, "Marcus", 0, ["brave"]).apply(state)
	var hero := Entities.get_entity(state, "hero")
	assert_eq(String(hero["name"]), "Marcus")
	assert_eq(Array(hero["traits"]), ["brave"])
	assert_eq(String(hero["status"]), "active")


func test_create_factory_builds_from_args() -> void:
	var cmd := CreateEntityCommand.from_args({"id": "guild", "type": "faction", "name": "Merchants"})
	assert_eq(cmd.command_name(), "create_entity")
	var state := GameState.new()
	cmd.apply(state)
	assert_true(Entities.exists(state, "guild"))


# --- adjust_disposition command ---

func test_adjust_moves_and_clamps_disposition() -> void:
	var state := _world()
	AdjustDispositionCommand.new("king", 25).apply(state)
	assert_eq(Entities.disposition(state, "king"), 35, "10 + 25")
	AdjustDispositionCommand.new("king", 1000).apply(state)
	assert_eq(Entities.disposition(state, "king"), 100, "clamped at the ceiling")


func test_adjust_rejects_a_missing_entity() -> void:
	var state := _world()
	assert_false(AdjustDispositionCommand.new("nobody", 5).validate(state).success)


func test_adjust_factory_builds_from_args() -> void:
	var state := _world()
	AdjustDispositionCommand.from_args({"id": "steward", "delta": -30}).apply(state)
	assert_eq(Entities.disposition(state, "steward"), -50, "-20 + -30")
