extends GutTest

## GrantResourceCommand: validation rules and the state mutation it applies.

func test_rejects_non_positive_amount() -> void:
	var state := GameState.new()
	assert_false(GrantResourceCommand.new("food", 0).validate(state).success, "zero is invalid")
	assert_false(GrantResourceCommand.new("food", -3).validate(state).success, "negative is invalid")


func test_rejects_empty_resource() -> void:
	var state := GameState.new()
	assert_false(GrantResourceCommand.new("", 5).validate(state).success)


func test_applies_and_accumulates() -> void:
	var state := GameState.new()
	GrantResourceCommand.new("food", 5).apply(state)
	GrantResourceCommand.new("food", 2).apply(state)
	var resources: Dictionary = state.get_value("resources", {})
	assert_eq(int(resources["food"]), 7, "grants accumulate")


func test_factory_builds_from_args() -> void:
	var cmd := GrantResourceCommand.from_args({"resource": "gold", "amount": 4})
	assert_eq(cmd.command_name(), "grant_resource")
	var state := GameState.new()
	cmd.apply(state)
	assert_eq(int((state.get_value("resources", {}) as Dictionary)["gold"]), 4)
