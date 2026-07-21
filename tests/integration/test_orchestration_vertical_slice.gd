extends GutTest

## End-to-end ribosome turn (M3b, D30): a player message runs the one entry workflow —
## guardrails → ai classify intent → dispatch → a seeded roll → grant_resource + narrate —
## and the game master's reply is the workflow's narration. FakeAiRunner + FakeNarrator make
## it deterministic; the reward is code-owned, never a model number (D4).


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boot registers base_game's families, tables, workflows
	return kernel


func test_forage_turn_classifies_dispatches_and_narrates() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", "forage")

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("I forage the hills for food")

	assert_true(bool(result["ok"]), "the turn completes")
	assert_false(String(result["narrative"]).strip_edges().is_empty(), "the game master replies in prose")

	var trace: AiTrace = result["trace"]
	assert_true(trace.has_stage("workflow_ai"), "the intent was classified")
	assert_true(trace.has_stage("workflow_dispatched"), "it handed off to the forage workflow")
	assert_true(trace.has_stage("workflow_narrated"), "and narrated the decided outcome")

	# The seeded roll decides hit/miss; either way the reward is the table's 5, never a model
	# number — the whole point of D4.
	var food := int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))
	assert_true(food == 0 or food == 5, "food is 0 (miss) or exactly 5 from the rule table (hit)")


func test_unrecognized_intent_is_acknowledged_not_resolved() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", "general")

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("I ponder the meaning of the stars")

	assert_true(bool(result["ok"]))
	assert_false(String(result["narrative"]).strip_edges().is_empty(), "acknowledged in prose")
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 0,
		"a remark with no mechanical stake changes no state")
	var trace: AiTrace = result["trace"]
	assert_false(trace.has_stage("workflow_dispatched"), "no hand-off — the entry workflow narrated directly")


func test_empty_message_is_stopped_by_the_entry_guardrail() -> void:
	var kernel := _kernel()
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("   ")
	# The cheap length pre-check passes; the entry workflow's require guardrail fails it.
	assert_false(bool(result["ok"]))
	assert_eq(String(result["error"]), "empty_message")
