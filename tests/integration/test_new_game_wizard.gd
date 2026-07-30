extends GutTest

## The new-game wizard (Background -> Location -> Hero -> Banner -> Settings): step navigation, and
## that the choices made on every step reach `begin_new_game` intact.
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
	for _i in range(4):
		screen.call("_on_next")
	assert_eq(int(screen.get("_current_step")), 4, "five steps, zero-indexed")

	screen.call("_on_back")
	assert_eq(int(screen.get("_current_step")), 3)


func test_back_on_the_first_step_returns_to_the_main_menu() -> void:
	var screen := _screen()
	screen.call("_on_back")
	assert_eq(Kernel.router.current_id(), "core.main_menu")


func test_finishing_the_wizard_seeds_the_choices_made() -> void:
	var screen := _screen()
	screen.set("_selected_background", "knight")
	screen.set("_selected_location", "mountains")
	screen.set("_selected_verbosity", "long")
	screen.set("_selected_language", "pt-BR")
	screen.set("_sex", "female")
	(screen.get("_name_field") as LineEdit).text = "Livia"
	(screen.get("_outpost_name_field") as LineEdit).text = "Stonegate"
	var flag: FlagValue = screen.get("_flag_value")
	flag.shape_color = Color.html("#2f5fc0")

	for _i in range(4):
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
	assert_eq(String(profile.get("language", "")), "pt-BR")

	var flag_dict: Dictionary = Kernel.state.get_value("outpost_flag", {})
	assert_eq(String(flag_dict.get("shapeColor", "")), "#2f5fc0")


func test_defaults_are_used_when_the_player_changes_nothing() -> void:
	var screen := _screen()
	for _i in range(5):
		screen.call("_on_next")

	assert_eq(String(Entities.get_entity(Kernel.state, "hero").get("name", "")), "Marcus")
	assert_eq(String(Entities.get_entity(Kernel.state, "outpost").get("name", "")), "Ravenwatch")
	var profile: Dictionary = Kernel.state.get_value("profile", {})
	assert_true(AppSettings.is_language(String(profile.get("language", ""))))


func test_settings_offers_every_supported_language() -> void:
	var screen := _screen()
	var picker := screen.find_child("LanguagePicker", true, false) as LanguagePicker
	assert_not_null(picker)
	if picker == null:
		return
	assert_eq(picker.option_count(), 24)
	assert_eq(picker.custom_minimum_size.y, LanguagePicker.FIELD_HEIGHT)
	var expected: Array[String] = []
	for entry: Dictionary in AppSettings.LANGUAGES:
		expected.append(String(entry["code"]))
	assert_eq(picker.option_codes(), expected)
	assert_not_null(picker.icon)
	picker.open_picker()
	var modal := picker.active_modal()
	assert_not_null(modal)
	assert_eq(float(modal.get("_preferred_content_height")),
		LanguagePicker.PICKER_CONTENT_HEIGHT)
	var choices := 0
	for node in modal.find_children("*", "Button", true, false):
		if node.has_meta("language_code"):
			choices += 1
			assert_eq((node as Button).custom_minimum_size.y, LanguagePicker.OPTION_HEIGHT)
			assert_eq((node as Button).mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(choices, 24)
	screen.call("on_hardware_back")


func test_banner_is_five_compact_properties() -> void:
	var screen := _screen()
	var properties: Dictionary = screen.get("_banner_property_buttons")
	assert_eq(properties.size(), 5)
	assert_true(properties.has_all(["shape_color", "texture", "texture_color", "emblem",
		"emblem_color"]))


func test_pattern_and_emblem_modals_expose_every_option_with_none_first() -> void:
	var screen := _screen()
	screen.call("_open_shape_picker", "Choose a pattern", "pattern",
		WizardScreen.FLAG_PATTERN_COUNT)
	var patterns := _flag_thumbnails(screen.get("_active_picker") as PickerModal)
	assert_eq(patterns.size(), WizardScreen.FLAG_PATTERN_COUNT + 1)
	assert_eq(patterns[0].option_id, FlagValue.NONE)
	screen.call("on_hardware_back")

	screen.call("_open_shape_picker", "Choose an emblem", "emblem",
		WizardScreen.FLAG_EMBLEM_COUNT)
	var emblems := _flag_thumbnails(screen.get("_active_picker") as PickerModal)
	assert_eq(emblems.size(), WizardScreen.FLAG_EMBLEM_COUNT + 1)
	assert_eq(emblems[0].option_id, FlagValue.NONE)


func test_modal_choices_and_custom_color_update_the_flag() -> void:
	var screen := _screen()
	var flag: FlagValue = screen.get("_flag_value")
	screen.call("_open_shape_picker", "Choose a pattern", "pattern",
		WizardScreen.FLAG_PATTERN_COUNT)
	var pattern07 := _flag_thumbnails(screen.get("_active_picker") as PickerModal)[7]
	pattern07.button_pressed = true
	assert_eq(flag.texture, "pattern07")
	screen.call("on_hardware_back")

	screen.call("_open_color_picker", "Pattern colour", "texture_color")
	var picker := _first_color_picker(screen.get("_active_picker") as PickerModal)
	assert_not_null(picker)
	if picker == null:
		return
	assert_false(picker.color_modes_visible)
	assert_false(picker.sliders_visible)
	assert_false(picker.hex_visible)
	assert_false(picker.presets_visible)
	assert_false(picker.sampler_visible)
	var custom := Color.html("#6c3fb5")
	picker.color = custom
	picker.color_changed.emit(custom)
	assert_eq(flag.texture_color, custom)
	var chips: Dictionary = screen.get("_banner_property_swatches")
	var style := (chips["texture_color"] as PanelContainer).get_theme_stylebox("panel") \
		as StyleBoxFlat
	assert_eq(style.bg_color, custom, "the compact row shows the custom colour it will edit")


func test_randomize_keeps_the_painted_controls_in_sync() -> void:
	var screen := _screen()
	screen.call("_randomize_flag")
	var flag: FlagValue = screen.get("_flag_value")
	var properties: Dictionary = screen.get("_banner_property_buttons")
	assert_string_contains((properties["texture"] as Button).text,
		str(int(flag.texture.substr(7))))
	assert_string_contains((properties["emblem"] as Button).text,
		str(int(flag.emblem.substr(6))))
	var chips: Dictionary = screen.get("_banner_property_swatches")
	var shape_style := (chips["shape_color"] as PanelContainer).get_theme_stylebox("panel") \
		as StyleBoxFlat
	assert_eq(shape_style.bg_color, flag.shape_color)


func test_hero_sex_cards_change_the_seeded_attribute() -> void:
	var screen := _screen()
	var female := _button_named(screen, "Female")
	assert_not_null(female)
	if female == null:
		return
	female.button_pressed = true
	assert_eq(String(screen.get("_sex")), "female")


## The card's prose sits under a [CardScroll], which is a control the *card's own button* cannot see
## past — and twice now that has quietly cost the card two thirds of its click. Nothing about it is
## visible in a screenshot: the card still looks like a card, and the half of it carrying the writing
## simply stops choosing anything. Both of these drive the scroll's handler directly rather than the
## viewport's, because the handler is where the whole tap-versus-drag rule lives.
func test_a_tap_on_a_cards_prose_picks_the_card() -> void:
	var screen := _screen()
	var scrolls := _card_scrolls(screen)
	assert_gt(scrolls.size(), 1, "the background step builds a scroll region per card")
	if scrolls.size() < 2:
		return
	_tap(scrolls[1], Vector2(20, 20), Vector2(20, 20))
	assert_eq(String(screen.get("_selected_background")), String(WizardScreen.BACKGROUNDS[1]["id"]),
		"the second card's prose chooses the second card")


func test_dragging_a_cards_prose_scrolls_it_without_choosing_it() -> void:
	var screen := _screen()
	var scrolls := _card_scrolls(screen)
	if scrolls.size() < 2:
		return
	var before := String(screen.get("_selected_background"))
	_tap(scrolls[1], Vector2(20, 120), Vector2(20, 20))
	assert_eq(String(screen.get("_selected_background")), before,
		"a drag reads the card, it does not pick it")


## Every [CardScroll] under [param node], in the order the cards were built — so index *i* is the
## scroll on the card for item *i* of the step's list, hidden ones included.
func _card_scrolls(node: Node) -> Array[CardScroll]:
	var found: Array[CardScroll] = []
	if node is CardScroll:
		found.append(node as CardScroll)
	for child in node.get_children():
		found.append_array(_card_scrolls(child))
	return found


func _tap(scroll: CardScroll, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	scroll._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	scroll._gui_input(release)


func _button_named(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _button_named(child, text)
		if found != null:
			return found
	return null


func _flag_thumbnails(node: Node) -> Array[FlagThumbnail]:
	var found: Array[FlagThumbnail] = []
	if node is FlagThumbnail:
		found.append(node as FlagThumbnail)
	for child in node.get_children():
		found.append_array(_flag_thumbnails(child))
	return found


func _first_color_picker(node: Node) -> ColorPicker:
	if node is ColorPicker:
		return node as ColorPicker
	for child in node.get_children():
		var found := _first_color_picker(child)
		if found != null:
			return found
	return null


func test_every_step_fits_the_width_it_is_designed_for() -> void:
	# Same guard as the settings page, and it caught the same thing here: a Godot container does not
	# clip, so a step whose *minimum* width exceeds the viewport runs off the right edge with no
	# scrollbar to reach it. The old Identity step wanted 1052 of 720 when its two columns were an
	# HBox — invisible on a desktop, and half the flag designer gone on a phone.
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
