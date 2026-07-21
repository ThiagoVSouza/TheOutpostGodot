extends GutTest

## The dev playground: the pure trace-rendering (readable breakdown of a turn) and that the
## screen is registered and selectable. The UI itself is driven manually; this pins the parts
## that can regress silently.

const Playground := preload("res://modules/base_game/screens/playground_screen.gd")


func test_render_trace_breaks_down_a_turn() -> void:
	var trace := AiTrace.new()
	trace.add("turn_started", {"source": "typed"})
	trace.add("workflow_ai", {"family": "classify_intent", "value": "forage"})
	trace.add("workflow_dispatched", {"to": "forage", "segment": 1})
	trace.add("workflow_command", {"command": "grant_resource", "ok": true})
	trace.add("workflow_narrated", {"text": "The scouts return with food."})
	trace.add("workflow_completed", {})

	var out := Playground.render_trace(trace)

	assert_string_contains(out, "forage", "the classified intent is shown")
	assert_string_contains(out, "grant_resource", "the command is shown")
	assert_string_contains(out, "The scouts return with food.", "the narration is shown")
	assert_string_contains(out, "completed", "the terminal status is shown")


func test_render_trace_shows_a_failed_guardrail() -> void:
	var trace := AiTrace.new()
	trace.add("turn_started", {"source": "typed"})
	trace.add("workflow_require_failed", {"fail_code": "empty_message"})
	trace.add("workflow_failed", {"fail_code": "empty_message"})
	var out := Playground.render_trace(trace)
	assert_string_contains(out, "empty_message", "a failed guardrail surfaces in the breakdown")


func test_playground_screen_is_registered_and_chat_is_default_start() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	assert_true(kernel.screens.has("base_game.playground"), "the playground screen is available")
	assert_eq(kernel.screens.start_screen_id(), "base_game.chat",
		"the plain chat is the default start; the playground is opt-in via OUTPOST_PLAYGROUND=1")
