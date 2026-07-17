extends GutTest

## End-to-end vertical slice: player message -> FakeAiBackend (two-turn tool use) ->
## dice tool -> validated command -> game state -> narrative, all via the orchestrator.

func test_forage_flow_rolls_applies_command_and_narrates() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)

	var fake := kernel.ai as FakeAiBackend
	# The foraging message classifies to the "forage" intent; script the two turns.
	fake.queue_responses("forage", [
		{  # turn 1: the game master asks to roll a die
			"tool_calls": [{"name": "roll_die", "args": {"sides": 6, "count": 1, "seed": 42}}],
		},
		{  # turn 2: given the roll, grant food and narrate
			"commands": [{"name": "grant_resource", "args": {"resource": "food", "amount": 3}}],
			"narrative": "Your scouts return with baskets of food.",
		},
	])

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("I send scouts to forage the hills")

	assert_true(result["ok"], "the flow should succeed")
	assert_eq(result["narrative"], "Your scouts return with baskets of food.")
	assert_has(result["applied_commands"], "grant_resource", "the command was applied")

	var resources: Dictionary = kernel.state.get_value("resources", {})
	assert_eq(int(resources.get("food", 0)), 3, "state reflects the granted food")

	var trace: AiTrace = result["trace"]
	assert_true(trace.has_stage("tool_executed"), "trace records the dice roll")
	assert_true(trace.has_stage("command_result"), "trace records the command")
	assert_true(trace.has_stage("narrative"), "trace records the narrative")


func test_message_with_no_tools_still_narrates() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var fake := kernel.ai as FakeAiBackend
	fake.set_response("general", {"narrative": "The outpost is calm."})

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("How are the walls holding?")
	assert_true(result["ok"])
	assert_eq(result["narrative"], "The outpost is calm.")
	assert_eq((result["applied_commands"] as Array).size(), 0)
