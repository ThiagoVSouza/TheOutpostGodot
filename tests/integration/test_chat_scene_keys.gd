extends GutTest

## The dev keys that put a painted scene and its characters on the conversation board.
##
## Scaffolding, but scaffolding with one trap in it worth pinning: showing a scene **opens the board**,
## and opening the board puts the caret in the chat field. A focused [LineEdit] swallows every
## printable key, so without care the key that opened the scene is the last one that works and the
## next types a bracket into the conversation.


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	return screen


func _dock(screen: Control) -> ChatDock:
	return (screen.get("_shell") as HudShell).get("_chat_dock") as ChatDock


func test_the_board_opens_for_a_scene_but_does_not_keep_the_keyboard() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var input := screen.get("_input") as LineEdit

	screen.call("_show_chat_scene", 0)
	assert_true(shell.is_chat_expanded(), "a scene the player cannot see shows them nothing")
	assert_false(input.has_focus(),
		"and the field must not hold the keyboard, or the next dev key is typed into it")


func test_walking_the_catalogue_puts_a_scene_on_the_board_and_takes_it_off_again() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := _dock(screen)
	assert_false(dock.has_scene(), "the conversation opens with nothing painted on it")

	# One step per scene, then round to nothing.
	for step in ChatScenes.count():
		screen.call("_cycle_chat_scene")
		assert_true(dock.has_scene(), "step %d of the catalogue is a scene" % step)
	screen.call("_cycle_chat_scene")
	assert_false(dock.has_scene(), "and walking off the end takes the picture away")


func test_the_stage_fills_and_empties_without_disturbing_the_scene() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := _dock(screen)
	screen.call("_cycle_chat_scene")
	assert_true(dock.has_scene())

	# The character step is held on the screen and re-read every time the scene is drawn, so cycling
	# it must not put the picture away.
	for step in ChatScenes.CHARACTER_STEPS.size():
		screen.set("_chat_characters", step)
		screen.call("_show_chat_scene", screen.get("_chat_scene"))
		assert_true(dock.has_scene(), "the scene survives step %d" % step)
		assert_eq((dock.scene.get("_characters") as Array).size(),
			int(ChatScenes.CHARACTER_STEPS[step]), "and carries that many figures")


## The left figure is the mirror of the right one, so a pair face each other across the room rather
## than both looking the same way.
func test_a_pair_face_each_other() -> void:
	var staged := ChatScenes.characters(ChatScenes.CHARACTER_STEPS.size() - 1)
	assert_eq(staged.size(), 2)
	var sides: Array = []
	for character: Dictionary in staged:
		sides.append(int(character["side"]))
	assert_true(sides.has(1) and sides.has(-1), "one to each side of the band")
