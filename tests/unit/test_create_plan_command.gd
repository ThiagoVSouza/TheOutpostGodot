extends GutTest

## CreatePlanCommand (M5): the whitelisted way a plan first enters GameState["plans"], filling the
## gap where nothing in production ever created one.


func test_rejects_blank_and_duplicate_ids() -> void:
	var state := GameState.new()
	assert_false(CreatePlanCommand.new("", "steward_extortion").validate(state).success, "blank id")
	CreatePlanCommand.new("p1", "steward_extortion").apply(state)
	assert_false(CreatePlanCommand.new("p1", "steward_extortion").validate(state).success,
		"a duplicate must not clobber a live plot")


func test_applies_a_plans_new_plan_shaped_dict() -> void:
	var state := GameState.new()
	CreatePlanCommand.new("p1", "steward_extortion", "plan_tick", ["steward", "hero"],
		"The steward pressures the lord.", 30).apply(state)
	var plan: Dictionary = (state.get_value("plans", {}) as Dictionary)["p1"]
	assert_eq(String(plan["template"]), "steward_extortion")
	assert_eq(String(plan["tick_workflow"]), "plan_tick")
	assert_eq(Array(plan["subjects"]), ["steward", "hero"])
	assert_eq(int(plan["next_wake"]), 30)
	assert_eq(String(plan["status"]), "active")


func test_a_created_plan_is_due_at_its_wake() -> void:
	var state := GameState.new()
	CreatePlanCommand.new("p1", "steward_extortion", "plan_tick", ["steward"], "…", 30).apply(state)
	assert_eq(Plans.due(state.get_value("plans", {}), 30), ["p1"],
		"once created it is a normal plan the ticker picks up")


func test_factory_builds_from_args() -> void:
	var cmd := CreatePlanCommand.from_args(
		{"id": "p2", "template": "t", "subjects": ["a"], "next_wake": 10})
	assert_eq(cmd.command_name(), "create_plan")
	var state := GameState.new()
	cmd.apply(state)
	assert_true((state.get_value("plans", {}) as Dictionary).has("p2"))
