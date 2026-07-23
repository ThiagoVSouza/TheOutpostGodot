extends GutTest

## The player can finally answer a pending question (M4/B4b). B1 kept the suspended instance
## and gave it a resume path; until now nothing could show it or reply to it, so the whole
## confirm → suspend → resume path had never been exercised by anything a player touches.
##
## These use the *autoload* Kernel, not a fresh GameKernel: `chat_screen.gd` talks to `Kernel`
## directly, the same arrangement `test_input_router.gd` uses.

const ASK_WORKFLOW := {
	"op": "workflow", "id": "test_confirm", "version": 1, "origin": "test", "params": {},
	"steps": [
		{"op": "confirm", "msg": "confirm.burn", "scope": {"target": "granary"}},
		{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 4}},
	]
}


func before_each() -> void:
	# Each test starts with no unanswered questions and no food, whatever ran before it.
	for instance: WorkflowInstance in Kernel.workflow_instances.pending().duplicate():
		Kernel.workflow_instances.forget(instance.instance_id)
	Kernel.state.set_value("resources", {})


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	return screen


func _log(screen: Control) -> String:
	return (screen.get("_log_label") as RichTextLabel).get_parsed_text()


func _food() -> int:
	return int((Kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


## Suspend a real workflow and hand its instance to the store, exactly as a turn would.
func _ask() -> WorkflowInstance:
	Kernel.workflow_registry.register(ASK_WORKFLOW)
	var instance := WorkflowInstance.create("test_confirm", 1, {}, 0)
	await WorkflowExecutor.for_kernel(Kernel).run(ASK_WORKFLOW, instance)
	Kernel.workflow_instances.remember(instance)
	return instance


func test_a_question_asked_before_the_game_closed_is_put_back_to_the_player() -> void:
	# The GATE 0 call for M4: re-present, never silently cancel.
	var instance := await _ask()

	var screen := _screen()  # stands in for the next launch — _ready runs the resume path

	assert_true((screen.get("_pending_row") as HBoxContainer).visible,
		"the question is showing on entry")
	assert_string_contains(String(screen.get("_pending_instance")), instance.instance_id)
	assert_string_contains(_log(screen), "confirm.burn", "and it is in the conversation")
	assert_string_contains(_log(screen), "granary", "with the scope the workflow asked about")


func test_a_pending_question_locks_input_until_it_is_answered() -> void:
	await _ask()
	var screen := _screen()

	# A confirm guards an action the rules have not applied yet; letting a new turn run
	# alongside it would leave the world in a state neither answer describes.
	assert_false((screen.get("_input") as LineEdit).editable, "typing is locked")
	assert_true((screen.get("_send_button") as Button).disabled, "and so is Send")

	await screen.call("_answer", false)

	assert_true((screen.get("_input") as LineEdit).editable, "answering unlocks it")


func test_answering_yes_applies_what_the_question_was_guarding() -> void:
	await _ask()
	var screen := _screen()

	await screen.call("_answer", true)

	assert_eq(_food(), 4, "the command after the confirm ran")
	assert_false((screen.get("_pending_row") as HBoxContainer).visible, "the question is gone")
	assert_eq(Kernel.workflow_instances.count(), 0, "and is no longer pending")
	assert_string_contains(_log(screen), "Yes", "the player's answer is in the conversation")


func test_answering_no_changes_nothing() -> void:
	await _ask()
	var screen := _screen()

	await screen.call("_answer", false)

	assert_eq(_food(), 0, "a declined confirmation applies nothing")
	assert_eq(Kernel.workflow_instances.count(), 0, "and the question is not left hanging")
	assert_string_contains(_log(screen), "No")


func test_the_same_question_cannot_be_answered_twice_by_double_clicking() -> void:
	await _ask()
	var screen := _screen()

	await screen.call("_answer", true)
	await screen.call("_answer", true)

	# The handle is cleared before the resume runs, so a second press has nothing to send —
	# and B1's store would reject it anyway. Both halves matter: this is real money.
	assert_eq(_food(), 4, "granted exactly once")


func test_no_question_means_no_row_and_a_usable_input() -> void:
	var screen := _screen()

	assert_false((screen.get("_pending_row") as HBoxContainer).visible)
	assert_true((screen.get("_input") as LineEdit).editable)


func test_starting_a_new_game_drops_the_question_from_the_old_one() -> void:
	await _ask()
	var screen := _screen()
	assert_true((screen.get("_pending_row") as HBoxContainer).visible)

	screen.call("_on_new_game")

	# The load-leak rule (D34) reaching the UI: a question belonging to a settlement the player
	# has left must not be sitting in front of them in a different one.
	assert_false((screen.get("_pending_row") as HBoxContainer).visible)
	assert_true(String(screen.get("_pending_instance")).is_empty())
	assert_true((screen.get("_input") as LineEdit).editable)
