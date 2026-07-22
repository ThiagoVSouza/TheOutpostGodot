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

	# The seeded roll picks an outcome band; the band picks the reward from the rule table.
	# Whatever the die does, the amount is one of the table's values and never a model number —
	# the whole point of D4.
	var food := int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))
	assert_true(food in [0, 3, 5], "food is exactly one of forage_yield's values, got %d" % food)


func test_the_raw_roll_never_reaches_the_narrator() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", "forage")

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("I forage the hills for food")

	# The die is still rolled and still traced — it just becomes a qualitative band before
	# anything downstream sees it. A number in the narrator's context is a number the model can
	# repeat back ("the high roll of nineteen"), which breaks the fiction even when it is true.
	var trace: AiTrace = result["trace"]
	var narrated: Dictionary = trace.entries_for("workflow_narrated")[0]
	var context: Dictionary = narrated.get("context", {})
	assert_false(context.has("roll"), "no raw die in the narration context")
	assert_true(String(narrated["instruction"]).contains("foraging party"),
		"the instruction describes the event")


func test_each_intent_reaches_its_own_workflow() -> void:
	# Widening the closed set past forage/general is what gives out-of-set input somewhere
	# sensible to go (D17 also wants more than three actions). Each label must actually route.
	for intent in ["forage", "hunt", "rest", "build"]:
		var kernel := _kernel()
		(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", intent)

		var result: Dictionary = await kernel.ai_orchestrator.handle_message("do the thing")

		assert_true(bool(result["ok"]), "the '%s' turn completes" % intent)
		var trace: AiTrace = result["trace"]
		assert_true(trace.has_stage("workflow_dispatched"), "'%s' handed off" % intent)
		assert_eq(String(trace.entries_for("workflow_dispatched")[0].get("to", "")), intent,
			"'%s' reached the workflow of the same name" % intent)
		assert_true(trace.has_stage("workflow_narrated"), "'%s' narrated its outcome" % intent)


func test_resting_resolves_without_a_roll_and_changes_nothing() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", "rest")

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("we rest for the day")

	assert_true(bool(result["ok"]))
	var trace: AiTrace = result["trace"]
	assert_false(trace.has_stage("workflow_rolled"), "a turn that warrants no roll does not roll one")
	assert_eq((kernel.state.get_value("resources", {}) as Dictionary).size(), 0, "and grants nothing")


func test_building_is_refused_in_fiction_when_the_stores_are_short() -> void:
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_intent", "build")

	# A fresh outpost has no food entry at all — the comparison must read that as "not enough"
	# rather than erroring, and the player must get prose, not a failure code.
	var result: Dictionary = await kernel.ai_orchestrator.handle_message("build a granary")

	assert_true(bool(result["ok"]), "a refusal is still a completed turn")
	var narrated: Dictionary = (result["trace"] as AiTrace).entries_for("workflow_narrated")[0]
	assert_true(String(narrated["instruction"]).contains("does not begin"),
		"the narrator is told plainly that the work did not start")


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
