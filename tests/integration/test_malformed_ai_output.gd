extends GutTest

## The orchestrator must never crash or apply unvetted actions on bad AI output.

func test_unknown_tool_and_non_whitelisted_command_are_rejected() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var fake := kernel.ai as FakeAiBackend
	fake.queue_responses("forage", [
		{"tool_calls": [{"name": "nonexistent_tool", "args": {}}]},
		{"commands": [{"name": "delete_everything", "args": {}}], "narrative": "..."},
	])

	var result := kernel.ai_orchestrator.handle_message("forage for food")

	assert_true(result["ok"], "should degrade gracefully, not crash")
	assert_eq((result["applied_commands"] as Array).size(), 0, "no unvetted command applied")
	var trace: AiTrace = result["trace"]
	assert_true(trace.has_stage("tool_rejected"), "unknown tool is rejected in trace")
	assert_true(trace.has_stage("command_rejected"), "non-whitelisted command is rejected in trace")


func test_empty_message_hits_guardrails() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var result := kernel.ai_orchestrator.handle_message("    ")
	assert_false(result["ok"])
	assert_eq(result["error"], "guardrails")


func test_empty_ai_response_is_handled() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var fake := kernel.ai as FakeAiBackend
	fake.queue_responses("general", [{}])  # backend returns nothing usable
	var result := kernel.ai_orchestrator.handle_message("hello there outpost")
	assert_false(result["ok"])
	assert_eq(result["error"], "empty_response")


func test_garbage_field_types_do_not_crash() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var fake := kernel.ai as FakeAiBackend
	# tool_calls/commands are the wrong types; orchestrator should treat them as empty.
	fake.queue_responses("general", [
		{"tool_calls": "not-an-array", "commands": 42, "narrative": "ok"},
	])
	var result := kernel.ai_orchestrator.handle_message("status report please")
	assert_true(result["ok"])
	assert_eq(result["narrative"], "ok")
	assert_eq((result["applied_commands"] as Array).size(), 0)
