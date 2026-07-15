extends GutTest

## WorkflowEngine: validation (capabilities + budget) and execution of the op set.

func test_validate_rejects_unknown_op() -> void:
	var engine := WorkflowEngine.new()
	var res := engine.validate_definition({"steps": [{"op": "delete_disk"}]}, engine.default_capabilities())
	assert_false(res.success, "op outside the whitelist is rejected")


func test_validate_rejects_missing_steps() -> void:
	var engine := WorkflowEngine.new()
	assert_false(engine.validate_definition({}, engine.default_capabilities()).success)


func test_validate_rejects_over_budget() -> void:
	var engine := WorkflowEngine.new()
	var steps: Array = []
	for _i in WorkflowEngine.MAX_STEPS + 1:
		steps.append({"op": "narrate", "text": "x"})
	assert_false(engine.validate_definition({"steps": steps}, engine.default_capabilities()).success)


func test_execute_runs_ops_and_applies_command() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boots; base_game registers grant_resource

	var narrations: Array = []
	kernel.events.subscribe("workflow_narrative", func(p: Dictionary) -> void: narrations.append(p["text"]))

	var definition := {
		"steps": [
			{"op": "read_state", "key": "resources.food", "as": "food", "default": 0},
			{"op": "narrate", "text": "food is ${food}"},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "gold", "amount": 2}},
		],
	}
	var res := kernel.workflows.execute(definition, kernel)

	assert_true(res.success, "valid workflow executes")
	assert_has(res.data["applied_commands"], "grant_resource")
	assert_eq(narrations, ["food is 0"], "interpolation uses default when state missing")
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("gold", 0)), 2)


func test_execute_skips_non_whitelisted_command() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var res := kernel.workflows.execute({
		"steps": [{"op": "run_command", "name": "not_whitelisted", "args": {}}],
	}, kernel)
	assert_true(res.success, "engine completes")
	assert_eq((res.data["applied_commands"] as Array).size(), 0, "no command applied")
