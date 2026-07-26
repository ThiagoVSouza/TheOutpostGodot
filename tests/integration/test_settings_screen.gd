extends GutTest

## The settings screen, driven as the real screen through the autoload Kernel (the same arrangement
## `test_new_game_wizard.gd` uses).
##
## The screen is mostly placeholders on purpose, so what is worth asserting is the boundary: the
## controls that claim to work do work and persist, the ones marked `planned` cannot be operated, and
## the two are told apart by something better than eyesight.

## The screen's script, for its constants: it is a `.tscn`-rooted screen with no `class_name`, so a
## preload is how the tag string is shared rather than duplicated as a literal here.
const SettingsScreen := preload("res://core/screens/settings_screen.gd")

var _restore_volumes: Dictionary = {}
var _restore_narration := ""
var _restore_window_mode := ""
var _restore_vsync := ""


func before_each() -> void:
	# The real app sets this once from the boot scene; nothing plays that role headless, so
	# router.goto would otherwise be a no-op with a push_error.
	var host := Control.new()
	add_child_autofree(host)
	Kernel.router.set_host(host)
	# The autoload kernel is shared across the whole suite, and this screen writes to its settings.
	for category in AudioManager.MIXER_LEVELS:
		_restore_volumes[category] = Kernel.settings.audio_volume(category)
	_restore_narration = Kernel.settings.narration_level()
	_restore_window_mode = Kernel.settings.window_mode()
	_restore_vsync = Kernel.settings.vsync_mode()


func after_each() -> void:
	for category in _restore_volumes:
		Kernel.settings.set_audio_volume(String(category), float(_restore_volumes[category]))
	Kernel.settings.set_narration_level(_restore_narration)
	Kernel.settings.set_window_mode(_restore_window_mode)
	Kernel.settings.set_vsync_mode(_restore_vsync)
	Kernel.settings.apply_audio(Kernel.audio)
	Kernel.settings.apply_video()
	# The rebinding tests write real overrides into the shared settings and the process-wide
	# InputMap; put both back so the rest of the suite (and a dev running this) keeps its keys.
	Kernel.settings.clear_all_key_bindings()
	InputActions.install(Kernel.settings)


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("core.settings")
	add_child_autofree(screen)
	return screen


## Every descendant of [param node], so a row's control can be found without knowing the container
## nesting the screen happens to use.
func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


func test_it_is_a_registered_screen_reachable_from_the_shell() -> void:
	assert_true(Kernel.screens.has("core.settings"))


func test_back_returns_to_wherever_it_was_opened_from() -> void:
	# The router keeps no history, so the caller says where Back goes. A screen that assumed the main
	# menu would strand the player when this is opened from a game.
	var screen: Control = Kernel.screens.instantiate("core.settings")
	screen.call("on_enter", {"back": "base_game.chat"})
	add_child_autofree(screen)
	assert_eq(String(screen.get("_back")), "base_game.chat")

	var default_screen := _screen()
	assert_eq(String(default_screen.get("_back")), "core.main_menu",
		"and falls back to the menu when nobody said")


func test_moving_the_music_slider_changes_the_mixer_and_persists() -> void:
	var screen := _screen()
	var sliders: Array[Node] = []
	for node in _descendants(screen):
		if node is HSlider and (node as HSlider).editable:
			sliders.append(node)
	assert_gt(sliders.size(), 0, "the audio tab has working sliders")

	# The first working slider is Master (AUDIO_ROWS order); drive it and check both effects.
	var slider := sliders[0] as HSlider
	slider.value = 0.35

	assert_almost_eq(Kernel.settings.audio_volume(AudioManager.MASTER), 0.35, 0.001,
		"the preference was stored")
	assert_almost_eq(Kernel.audio.category_volume(AudioManager.MASTER), 0.35, 0.02,
		"and the bus actually moved")


func test_choosing_a_narration_length_sets_the_default_for_new_games() -> void:
	var screen := _screen()
	var narration: OptionButton = null
	for node in _descendants(screen):
		if node is OptionButton and not (node as OptionButton).disabled:
			narration = node
			break
	assert_not_null(narration, "the gameplay tab has a working narration control")

	# Pick whichever entry is not currently selected, so the test does not depend on the default.
	var target := 0 if narration.selected != 0 else 1
	narration.item_selected.emit(target)

	assert_eq(Kernel.settings.narration_level(), String(narration.get_item_metadata(target)))


## An enabled `OptionButton` whose first entry reads [param first_item_text] — how the window-mode
## and V-Sync controls are told apart from each other and from the (disabled) mock dropdowns
## elsewhere on the tab, without the test knowing the tab's internal layout.
func _find_option(root: Node, first_item_text: String) -> OptionButton:
	for node in _descendants(root):
		if node is OptionButton and not (node as OptionButton).disabled \
				and (node as OptionButton).item_count > 0 \
				and (node as OptionButton).get_item_text(0) == first_item_text:
			return node
	return null


func test_changing_the_window_mode_persists() -> void:
	var screen := _screen()
	var window_mode := _find_option(screen, "Windowed")
	assert_not_null(window_mode, "the video tab has a working window-mode control")

	var target := 2 if window_mode.selected != 2 else 0
	window_mode.item_selected.emit(target)

	assert_eq(Kernel.settings.window_mode(), String(window_mode.get_item_metadata(target)))


func test_changing_vsync_persists() -> void:
	var screen := _screen()
	var vsync := _find_option(screen, "Off")
	assert_not_null(vsync, "the video tab has a working V-Sync control")

	var target := 0 if vsync.selected != 0 else 1
	vsync.item_selected.emit(target)

	assert_eq(Kernel.settings.vsync_mode(), String(vsync.get_item_metadata(target)))


func test_a_planned_control_cannot_be_operated() -> void:
	# The screen's whole premise is that unfinished settings are visible without being usable. A
	# placeholder the player can move — that then does nothing — is worse than an empty section.
	var screen := _screen()
	var inert := 0
	for node in _descendants(screen):
		if node is Range and not (node as Range).editable:
			inert += 1
		elif node is BaseButton and (node as BaseButton).disabled:
			inert += 1
	assert_gt(inert, 20, "the planned settings are present and every one of them is inert")


func test_every_planned_row_is_labelled_as_such() -> void:
	# Disabled is not enough on its own: a greyed control reads as "unavailable right now", not as
	# "not built yet". The tag is what makes the difference legible.
	#
	# Counted against controls *marked* planned rather than against every disabled control, because
	# the screen now has both kinds: Resolution outside Windowed mode, and Monitor with one display,
	# are finished settings that simply do not apply — greyed, explained by a note, and correctly
	# untagged. Counting all disabled controls would demand a "not built yet" tag on those two.
	var screen := _screen()
	var tags := 0
	var planned_controls := 0
	for node in _descendants(screen):
		if node is Label and (node as Label).text == SettingsScreen.PLANNED_TAG:
			tags += 1
		elif node is Control and (node as Control).has_meta(SettingsScreen.PLANNED_META):
			planned_controls += 1
	assert_gt(planned_controls, 20, "the planned settings are present")
	assert_eq(tags, planned_controls, "one 'planned' tag per planned control, no more and no fewer")


# --- key rebinding -------------------------------------------------------------------------

func _binding_button(screen: Control, action_id: String) -> Button:
	var buttons: Dictionary = screen.get("_binding_buttons")
	return buttons.get(action_id)


## Drive the screen's own capture path with a synthetic keypress, exactly as a real one arrives.
func _press(screen: Control, keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	screen.call("_input", event)


func test_the_controls_tab_offers_a_live_button_per_bindable_action() -> void:
	var screen := _screen()
	for id: String in InputActions.ids():
		var button := _binding_button(screen, id)
		assert_not_null(button, "'%s' has a binding button" % id)
		assert_false(button.disabled, "and it is operable")
		assert_false(button.has_meta(SettingsScreen.PLANNED_META),
			"a bindable action is not marked planned")


func test_a_binding_button_shows_the_key_currently_in_force() -> void:
	var screen := _screen()
	var button := _binding_button(screen, InputActions.PASS_DAY)
	assert_eq(button.text, InputActions.key_name(
		InputActions.keycode_for(InputActions.PASS_DAY, Kernel.settings)))


func test_pressing_a_key_while_listening_rebinds_the_action() -> void:
	var screen := _screen()
	var button := _binding_button(screen, InputActions.PASS_DAY)
	button.button_pressed = true  # enters "press a key…"

	_press(screen, KEY_J)

	assert_eq(Kernel.settings.key_binding(InputActions.PASS_DAY), KEY_J, "the override was stored")
	assert_eq(button.text, "J", "and the button shows it")
	var event := InputEventKey.new()
	event.keycode = KEY_J
	assert_true(InputMap.event_is_action(event, InputActions.PASS_DAY), "and the InputMap agrees")


func test_escape_cancels_a_rebind_rather_than_binding_itself() -> void:
	# Escape is what a player reflexively presses to back out of a mode, and losing "Back / close"
	# to a mis-click would be awkward to undo.
	var screen := _screen()
	var button := _binding_button(screen, InputActions.PASS_DAY)
	var before := InputActions.keycode_for(InputActions.PASS_DAY, Kernel.settings)
	button.button_pressed = true

	_press(screen, KEY_ESCAPE)

	assert_eq(InputActions.keycode_for(InputActions.PASS_DAY, Kernel.settings), before,
		"the binding is unchanged")
	assert_false(button.button_pressed, "and the button stopped listening")


func test_taking_a_key_from_another_action_leaves_that_one_unbound() -> void:
	# The rule the UNBOUND constant exists for: a key drives exactly one action, and the loser must
	# not silently fall back to the default it just lost.
	var screen := _screen()
	var map_key := InputActions.keycode_for(InputActions.OPEN_MAP, Kernel.settings)
	var button := _binding_button(screen, InputActions.PASS_DAY)
	button.button_pressed = true

	_press(screen, map_key)

	assert_eq(InputActions.keycode_for(InputActions.PASS_DAY, Kernel.settings), map_key,
		"the winner took the key")
	assert_eq(InputActions.keycode_for(InputActions.OPEN_MAP, Kernel.settings), KEY_NONE,
		"and the loser holds no key at all")
	assert_eq(_binding_button(screen, InputActions.OPEN_MAP).text, "Unbound",
		"which the loser's own button says")


func test_resetting_bindings_restores_every_default() -> void:
	var screen := _screen()
	var button := _binding_button(screen, InputActions.PASS_DAY)
	button.button_pressed = true
	_press(screen, KEY_J)

	screen.call("_on_reset_bindings")

	for id: String in InputActions.ids():
		assert_eq(InputActions.keycode_for(id, Kernel.settings), InputActions.default_keycode(id),
			"'%s' is back on its default" % id)


func test_resetting_bindings_leaves_the_other_settings_alone() -> void:
	# "Reset all bindings" sits in the Controls tab and must not behave like the footer's
	# "Reset all to defaults" — a player clearing their keys should not lose their volumes.
	var screen := _screen()
	Kernel.settings.set_audio_volume(AudioManager.MUSIC, 0.33)

	screen.call("_on_reset_bindings")

	assert_almost_eq(Kernel.settings.audio_volume(AudioManager.MUSIC), 0.33, 0.001)


func test_the_controls_list_and_the_action_set_agree_on_wording() -> void:
	# The tab decides which rows are live by matching KEY_BINDINGS labels against action labels, so
	# a reworded label in one list would silently turn a live binding back into a placeholder.
	var labels: Array = []
	for group: Dictionary in SettingsScreen.KEY_BINDINGS:
		for action: Array in group["actions"]:
			labels.append(String(action[0]))
	for action: Dictionary in InputActions.ACTIONS:
		assert_true(labels.has(String(action["label"])),
			"'%s' is named in the Controls tab's own list" % action["label"])


func test_every_planned_control_is_actually_inert() -> void:
	# The other half of the promise: a control tagged "planned" must not be operable. (Its
	# counterpart — that untagged controls work — is what the audio/vsync/window-mode tests cover.)
	var screen := _screen()
	for node in _descendants(screen):
		if not (node is Control and (node as Control).has_meta(SettingsScreen.PLANNED_META)):
			continue
		if node is Range:
			assert_false((node as Range).editable, "a planned Range is not editable")
		elif node is BaseButton:
			assert_true((node as BaseButton).disabled, "a planned button is disabled")
