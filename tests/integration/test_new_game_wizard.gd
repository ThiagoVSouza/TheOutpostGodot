extends GutTest

## The new-game wizard (Background -> Location -> Identity -> Settings): step navigation, and that
## the choices made on every step reach `begin_new_game` intact.
##
## Uses the *autoload* Kernel, not a fresh GameKernel: `new_game_screen.gd` talks to `Kernel`
## directly, the same arrangement `test_confirmation_ui.gd` and `test_input_router.gd` use.

## The screen's script, for its constants — a `.tscn`-rooted screen with no `class_name`, so a
## preload is how the step list is shared rather than duplicated as a literal here. Same arrangement
## as `test_settings_screen.gd`.
const WizardScreen := preload("res://core/screens/new_game_screen.gd")

func before_each() -> void:
	# The real app sets this once from the boot scene (core/bootstrap/boot.gd); nothing plays that
	# role in a headless test run, so router.goto would otherwise be a no-op with a push_error.
	var host := Control.new()
	add_child_autofree(host)
	Kernel.router.set_host(host)


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("core.new_game")
	add_child_autofree(screen)
	return screen


func test_starts_on_the_background_step() -> void:
	var screen := _screen()
	assert_eq(int(screen.get("_current_step")), 0)


func test_next_advances_through_every_step_and_back_reverses() -> void:
	var screen := _screen()
	for _i in range(3):
		screen.call("_on_next")
	assert_eq(int(screen.get("_current_step")), 3, "four steps, zero-indexed")

	screen.call("_on_back")
	assert_eq(int(screen.get("_current_step")), 2)


func test_back_on_the_first_step_returns_to_the_main_menu() -> void:
	var screen := _screen()
	screen.call("_on_back")
	assert_eq(Kernel.router.current_id(), "core.main_menu")


func test_finishing_the_wizard_seeds_the_choices_made() -> void:
	var screen := _screen()
	screen.set("_selected_background", "knight")
	screen.set("_selected_location", "mountains")
	screen.set("_selected_verbosity", "long")
	screen.set("_sex", "female")
	(screen.get("_name_field") as LineEdit).text = "Livia"
	(screen.get("_outpost_name_field") as LineEdit).text = "Stonegate"
	var flag: FlagValue = screen.get("_flag_value")
	flag.shape_color = Color.html("#2f5fc0")

	for _i in range(3):
		screen.call("_on_next")
	screen.call("_on_next")  # the last step's Next button reads "Start"

	assert_eq(Kernel.router.current_id(), "core.loading", "the seeded game is entered")
	assert_eq(String(Entities.get_entity(Kernel.state, "hero").get("name", "")), "Livia")
	assert_eq(String(Entities.get_entity(Kernel.state, "outpost").get("name", "")), "Stonegate")

	var profile: Dictionary = Kernel.state.get_value("profile", {})
	assert_eq(String(profile.get("background", "")), "knight")
	assert_eq(String(profile.get("outpost_location", "")), "mountains")
	assert_eq(String(profile.get("sex", "")), "female")
	assert_eq(String(profile.get("verbosity", "")), "long")

	var flag_dict: Dictionary = Kernel.state.get_value("outpost_flag", {})
	assert_eq(String(flag_dict.get("shapeColor", "")), "#2f5fc0")


func test_defaults_are_used_when_the_player_changes_nothing() -> void:
	var screen := _screen()
	for _i in range(4):
		screen.call("_on_next")

	assert_eq(String(Entities.get_entity(Kernel.state, "hero").get("name", "")), "Marcus")
	assert_eq(String(Entities.get_entity(Kernel.state, "outpost").get("name", "")), "Ravenwatch")


func test_every_step_fits_the_width_it_is_designed_for() -> void:
	# Same guard as the settings page, and it caught the same thing here: a Godot container does not
	# clip, so a step whose *minimum* width exceeds the viewport runs off the right edge with no
	# scrollbar to reach it. The Identity step wanted 1052 of 720 when its two columns were an HBox —
	# invisible on a desktop, and half the flag designer gone on a phone.
	#
	# Every step, not just the first: they are separate layouts and only the one on show contributes
	# to the page's minimum, so a regression in step 3 is silent until someone walks to step 3.
	#
	# **The screen has to be laid out at the design width before it is measured.** A test node with no
	# size gets whatever Godot's default is — about 1100 square here — and [CardPager] answers that
	# honestly by showing three cards, so the page reports the minimum width of a *desktop* layout and
	# the assertion is about a screen nobody is looking at. This measured 1105 before the size was
	# forced and 529 after: the widget was right and the test was asking the wrong question.
	var design := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var host := Control.new()
	host.size = design
	add_child_autofree(host)
	var screen: Control = Kernel.screens.instantiate("core.new_game")
	host.add_child(screen)
	# The host carries the size and the screen fills it. Setting `size` on the screen directly instead
	# would be overridden by its own full-rect anchors, and Godot says so with a warning the runner
	# counts as a failure.
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(2)

	var page: Control = null
	for child in screen.get_children():
		if child is MarginContainer:
			page = child as MarginContainer
			break
	assert_not_null(page, "the wizard's content is wrapped in a MarginContainer")
	if page == null:
		return
	var steps: Array = WizardScreen.STEP_TITLES
	for step in steps.size():
		var needed := page.get_combined_minimum_size().x
		assert_lte(needed, design.x, "the %s step needs %.0f of the %.0f it is designed for"
			% [steps[step], needed, design.x])
		# Not past the last one: `_on_next` there is Start, which would seed a game.
		if step < steps.size() - 1:
			screen.call("_on_next")
			await wait_process_frames(1)


## The card's prose sits in a ScrollContainer, and a ScrollContainer keeps mouse events in its own
## area — so adding one silently left the painting as the only clickable part of the card. These pin
## down the rule that fixed it: a press and release in the same place is a choice, a press that
## travelled is a scroll.
## The *card's* scroll, found via the card's own plate. Taking the first ScrollContainer in the tree
## instead finds the step body's, which is an ancestor of every card — and emitting into that proves
## nothing, which is exactly how the first version of this test passed while the bug was still there.
func _card_scroll(screen: Control) -> ScrollContainer:
	for node in _descendants(screen):
		if not (node is Button and (node as Button).toggle_mode):
			continue
		for inside in _descendants(node.get_parent()):
			if inside is ScrollContainer:
				return inside as ScrollContainer
	return null


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


func _mouse(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func test_tapping_a_cards_prose_chooses_that_card() -> void:
	var screen := _screen()
	screen.set("_selected_background", "scholar")
	var scroll := _card_scroll(screen)
	assert_not_null(scroll, "a card wraps its prose in a scroll region")
	if scroll == null:
		return

	var at := Vector2(40, 40)
	scroll.gui_input.emit(_mouse(true, at))
	scroll.gui_input.emit(_mouse(false, at))
	assert_eq(String(screen.get("_selected_background")), "wealthy_merchant",
		"a tap on the prose picks the card it belongs to, not just a tap on the painting")


func test_dragging_a_cards_prose_scrolls_without_choosing() -> void:
	var screen := _screen()
	screen.set("_selected_background", "scholar")
	var scroll := _card_scroll(screen)
	if scroll == null:
		return

	scroll.gui_input.emit(_mouse(true, Vector2(40, 120)))
	scroll.gui_input.emit(_mouse(false, Vector2(40, 20)))
	assert_eq(String(screen.get("_selected_background")), "scholar",
		"a press that travelled was a scroll, and must leave the choice alone")
