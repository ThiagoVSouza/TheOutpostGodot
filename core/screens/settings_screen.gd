extends Control

## The settings screen: every category the game will need, in one place.
##
## **Most of it does not work yet, and says so.** The screen is deliberately built out to its full
## shape now, because the shape is a design document — it is where you can see that key rebinding
## needs an `InputMap` that does not exist, that a resolution list needs a window-mode policy nobody
## has decided, and roughly how much is left. Every control that is not connected to anything is
## disabled and tagged, so no one can mistake a placeholder for a preference: a slider that moves and
## changes nothing is worse than an empty section, because it looks finished.
##
## What is real: the audio levels, and the narration length. Both persist — audio in [AppSettings],
## narration as the app-level default for new games *and*, when a game is open, in that game's own
## profile so it takes effect immediately (the two-layer arrangement `AppSettings.narration_level`
## explains).
##
## Reached from the main menu; `on_enter({"back": <screen id>})` says where Back returns to, so the
## same screen can later be opened from inside a game without knowing who called it.

const DEFAULT_BACK := "core.main_menu"

## The tag on anything not yet wired, and its colour. One phrase, used everywhere, so the state is
## recognisable at a glance rather than being read row by row.
const PLANNED_TAG := "planned"

## Marks a control as not-yet-built, so it can be told apart from one that is finished but simply
## does not apply in the current state. Both are greyed out; only this one is a promise.
const PLANNED_META := "outpost_planned"
## Both read against parchment now, not against a dark panel: the tab body is `frame_thin`, whose
## middle is transparent, so the page's own paper is what every row sits on.
const PLANNED_COLOR := Color(0.58, 0.34, 0.05)
const NOTE_COLOR := UiSkin.INK_MUTED

const LABEL_WIDTH := 260.0
const CONTROL_WIDTH := 320.0
## Back has one short word in it, so left to itself the plate would be far narrower than Reset's.
const BACK_WIDTH := 240.0
## The narrowest a row's explanatory hint may be before it takes a line of its own rather than a
## sliver beside the control. See [method _row].
const HINT_MIN_WIDTH := 220.0

## Room for the volume percentage beside its slider. Wide enough for "100%" at
## [constant UiSkin.FONT_BODY] — a right-aligned readout that has to widen for its own maximum value
## drags the slider a few pixels left every time the level passes 99%.
const READOUT_WIDTH := 84.0

## How much air sits between the end of a row and the scroll bar. Smaller than the margin on the
## other three sides, because the bar is already a wide object with its own moulding — the usual
## reading margin on top of it left the rows looking pushed away from the edge.
const ROW_TO_SCROLLBAR_GAP := 10

## Audio levels the player can set, in the order a mixer shows them.
const AUDIO_ROWS := [
	{"id": AudioManager.MASTER, "label": "Master volume"},
	{"id": AudioManager.MUSIC, "label": "Music"},
	{"id": AudioManager.SFX, "label": "Sound effects"},
	{"id": AudioManager.AMBIENCE, "label": "Ambience"},
]

## Narration lengths, matching the new-game wizard's Settings step. `topics` is included here but not
## there on purpose: it is a different output *form* (a terse list of what happened rather than
## prose), which is a reasonable standing preference but a strange thing to start a story on.
const NARRATION_ROWS := [
	{"id": NarrationSettings.LEVEL_TOPICS, "label": "Topics — a list of what happened"},
	{"id": NarrationSettings.LEVEL_SHORT, "label": "Short — terse, to the point"},
	{"id": NarrationSettings.LEVEL_NORMAL, "label": "Average — balanced narration"},
	{"id": NarrationSettings.LEVEL_LONG, "label": "Long — rich, descriptive prose"},
]

## Window modes the player can pick, matching `AppSettings.WINDOW_MODES`.
const WINDOW_MODE_ROWS := [
	{"id": AppSettings.WINDOW_MODE_WINDOWED, "label": "Windowed"},
	{"id": AppSettings.WINDOW_MODE_BORDERLESS, "label": "Borderless"},
	{"id": AppSettings.WINDOW_MODE_FULLSCREEN, "label": "Fullscreen"},
]

## V-Sync modes the player can pick, matching `AppSettings.VSYNC_MODES`.
const VSYNC_ROWS := [
	{"id": AppSettings.VSYNC_OFF, "label": "Off"},
	{"id": AppSettings.VSYNC_ON, "label": "On"},
	{"id": AppSettings.VSYNC_ADAPTIVE, "label": "Adaptive"},
]

## Frame-rate caps. Ids are the stored integers as strings, since the option rows carry string ids;
## `0` is Godot's own "uncapped", which is the default so V-Sync stays what limits the rate.
const FPS_ROWS := [
	{"id": "0", "label": "Unlimited"},
	{"id": "30", "label": "30"},
	{"id": "60", "label": "60"},
	{"id": "120", "label": "120"},
]

## The actions the game intends to bind, with the keys they are expected to default to.
##
## **This list is the design, not a reflection of one:** the project has no `InputMap` actions at all
## yet, so nothing here is bound to anything. Writing it out is what makes the gap concrete — and
## rebinding is a promise the game has already made (`docs/Remember.md`: the player should be able to
## change *every* binding), so the set it covers had better be complete before any of it is coded.
const KEY_BINDINGS := [
	{"group": "Conversation", "actions": [
		["Send message", "Enter"],
		["Newline in message", "Shift + Enter"],
		["Open chat", "Enter"],
		["Focus the input", "T"],
		["Repeat last message", "Up"],
	]},
	{"group": "The world", "actions": [
		["Pause / resume time", "Space"],
		["Set speed 1", "1"],
		["Set speed 2", "2"],
		["Set speed 3", "3"],
		["Open the map", "M"],
		["Open the roster", "R"],
		["Open the chronicle", "L"],
	]},
	{"group": "Map", "actions": [
		["Pan", "Drag / W A S D"],
		["Zoom in", "Mouse wheel up / +"],
		["Zoom out", "Mouse wheel down / -"],
		["Centre on the outpost", "Home"],
	]},
	{"group": "System", "actions": [
		["Settings", "F1"],
		["Quick save", "F5"],
		["Quick load", "F9"],
		["Screenshot", "F12"],
		["Back / close", "Escape"],
	]},
]

var _back := DEFAULT_BACK
var _volume_readouts: Dictionary = {}  # category -> Label
var _binding_buttons: Dictionary = {}  # action id -> Button
## The one binding button waiting for a keypress, if any.
var _listening_button: Button = null


func on_enter(params: Dictionary) -> void:
	_back = String(params.get("back", DEFAULT_BACK))


## Hardware/gesture back goes wherever the on-screen Back button goes (Android UX pass) — the
## caller-supplied destination, same as a tap.
func on_hardware_back() -> bool:
	Kernel.router.goto(_back)
	return true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Every control these point at is about to be rebuilt, so the old entries are dangling
	# references — a rebuild (window mode, or a reset) would otherwise leave freed Buttons here.
	_volume_readouts.clear()
	_binding_buttons.clear()
	_listening_button = null
	ShellPalette.paint_shell(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 20)
	# The Reset/Back footer sits on this edge, so it has to clear the navigation bar.
	margin.add_theme_constant_override("margin_bottom", 20 + SafeArea.bottom(get_viewport()))
	add_child(margin)

	# The same frame the menu and the modal sit on, so Settings reads as part of the shell rather than
	# a bare page.
	var shadow := PanelContainer.new()
	shadow.add_theme_stylebox_override("panel", UiSkin.frame_shadow_style())
	margin.add_child(shadow)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiSkin.frame_style())
	shadow.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	frame.add_child(col)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiSkin.FONT_TITLE)
	# Ink: the frame's middle is pale parchment, where the shell's near-white text vanishes.
	title.add_theme_color_override("font_color", UiSkin.INK)
	col.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The body is the border-only frame, so the rows sit straight on the page's parchment rather than
	# on a dark slab laid over it. Everything inside is therefore written in ink.
	# Only the rail's own thickness, not the usual reading margin: the scroll bar is meant to run the
	# whole side of this frame, so what sits inside it has to reach the rail. `_add_tab` puts the
	# reading margin back around the rows, where it belongs.
	tabs.add_theme_stylebox_override("panel", UiSkin.thin_frame_style(UiSkin.FRAME_THIN_RAIL))
	tabs.add_theme_stylebox_override("tab_selected", UiSkin.tab_style(true))
	tabs.add_theme_stylebox_override("tab_unselected", UiSkin.tab_style(false))
	tabs.add_theme_stylebox_override("tab_hovered", UiSkin.tab_style(false))
	tabs.add_theme_stylebox_override("tab_disabled", UiSkin.tab_style(false))
	# The strip's own background and the little separators between tabs would draw the stock dark
	# theme behind the plates; there is nothing to show there but the page.
	tabs.add_theme_stylebox_override("tabbar_background", StyleBoxEmpty.new())
	tabs.add_theme_color_override("font_selected_color", UiSkin.INK)
	tabs.add_theme_color_override("font_unselected_color", UiSkin.LABEL)
	tabs.add_theme_color_override("font_hovered_color", UiSkin.LABEL)
	tabs.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	# The tabs are the one clickable thing here that no `apply_*` helper touches — the strip is the
	# TabContainer's own internal child, not something the screen built.
	UiSkin.apply_cursor(tabs.get_tab_bar())
	col.add_child(tabs)
	_add_tab(tabs, "Gameplay", _build_gameplay_tab())
	_add_tab(tabs, "Audio", _build_audio_tab())
	_add_tab(tabs, "Video", _build_video_tab())
	_add_tab(tabs, "Controls", _build_controls_tab())

	# Back on the left, Reset on the right, at opposite edges with the gap between them — the same
	# hands as the exit modal, where leaving is the left plate and the destructive answer is the right
	# one. Keeping the sides consistent is what stops a reflex tap from resetting the settings.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 0)
	col.add_child(footer)
	var back := SkinnedButton.create("Back", UiSkin.BROWN, UiSkin.BUTTON_HEIGHT,
		UiSkin.BUTTON_FONT_SIZE)
	back.custom_minimum_size.x = BACK_WIDTH
	back.pressed.connect(func() -> void: Kernel.router.goto(_back))
	footer.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	var reset := SkinnedButton.create("Reset all to defaults", UiSkin.BROWN, UiSkin.BUTTON_HEIGHT,
		UiSkin.BUTTON_FONT_SIZE)
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)


## Wrap a tab's content in a scroll container: several of these sections are already taller than a
## phone screen, and a settings row the player cannot reach is the same as one that does not exist.
##
## The bar is the painted one. That matters more here than it would elsewhere: this is the screen
## where scrolling is not optional, so the stock thin blue-grey bar was the one piece of Godot's own
## chrome left sitting on the parchment, and it was on every tab. Its plate buttons also make the
## page usable with taps alone, which a 12px drag handle on a phone is not.
func _add_tab(tabs: TabContainer, title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiSkin.apply_scroll_container(scroll)

	# The reading margin lives here rather than on the frame, and that is what puts the bar against
	# the rail. Godot gives a ScrollContainer's bar the container's full height at its right edge, so
	# the bar is flush with the frame exactly when the *container* is — pad the frame instead and the
	# bar floats in the middle of the page with a strip of parchment either side of it. The right
	# margin is the gap between the rows and the bar, not between the rows and the frame.
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_bottom"]:
		padding.add_theme_constant_override(side, int(UiSkin.FRAME_THIN_PADDING))
	padding.add_theme_constant_override("margin_right", ROW_TO_SCROLLBAR_GAP)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_child(content)

	scroll.add_child(padding)
	tabs.add_child(scroll)


# --- Gameplay ------------------------------------------------------------------------------

func _build_gameplay_tab() -> Control:
	var col := _tab_column()

	_section(col, "Narration")
	var narration := _options(NARRATION_ROWS, Kernel.settings.narration_level(), _on_narration_changed)
	_row(col, "Narration length", narration,
		"Applies to the game you are in, and becomes the default for new ones.")

	_section(col, "Difficulty")
	_planned_row(col, "Difficulty", _options_mock(["Story", "Normal", "Hard", "Unforgiving"], 1),
		"No difficulty model exists yet — the balance tables are per-workflow.")
	_planned_row(col, "Permadeath", _check_mock(false), "")
	_planned_row(col, "Barbarian aggression", _options_mock(["Low", "Normal", "High"], 1), "")

	_section(col, "Saving")
	_planned_row(col, "Autosave every", _options_mock(["Turn", "Day", "Month"], 0),
		"A checkpoint is already written every turn; this would make the cadence a choice.")
	_planned_row(col, "Named-save slots", _options_mock(["3", "10", "Unlimited"], 1), "")

	_section(col, "Guidance")
	_planned_row(col, "Tutorials", _check_mock(true),
		"Tutorials, tips and tooltips are all still to be written.")
	_planned_row(col, "Tooltips", _check_mock(true), "")
	_planned_row(col, "Show dice rolls", _check_mock(false),
		"The die is traced but deliberately never narrated; this would surface it in the log.")

	# Language and Accessibility live here rather than in tabs of their own. Between them they hold
	# one real setting and a dozen placeholders, and a tab the player opens to find nothing they can
	# change is worse than a section they scroll past — the sections still name them, so nothing is
	# hidden. When either grows something wired, it earns its tab back.
	_add_language_sections(col)
	_add_accessibility_sections(col)
	return col


func _on_narration_changed(level: String) -> void:
	# The app-level default for the next new game.
	Kernel.settings.set_narration_level(level)
	Kernel.settings.save()
	# And the current game's own choice, when there is one — the per-game value is what governs play,
	# so changing it only in the app-level store would look like nothing happened.
	var profile: Dictionary = Kernel.state.get_value(GameSession.PROFILE_STATE_KEY, {})
	if not profile.is_empty():
		profile[GameSession.PROFILE_VERBOSITY] = level
		Kernel.state.set_value(GameSession.PROFILE_STATE_KEY, profile)
		Kernel.apply_player_preferences()


# --- Audio ---------------------------------------------------------------------------------

func _build_audio_tab() -> Control:
	var col := _tab_column()

	_section(col, "Levels")
	for entry: Dictionary in AUDIO_ROWS:
		var category := String(entry["id"])
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Kernel.settings.audio_volume(category)
		UiSkin.apply_slider(slider)
		slider.custom_minimum_size = Vector2(CONTROL_WIDTH - 60.0, UiSkin.CONTROL_HEIGHT)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var readout := Label.new()
		readout.custom_minimum_size = Vector2(READOUT_WIDTH, 0)
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.add_theme_color_override("font_color", UiSkin.INK)
		readout.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
		_volume_readouts[category] = readout
		_set_readout(category, slider.value)
		slider.value_changed.connect(func(value: float) -> void: _on_volume_changed(category, value))

		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		pair.add_child(slider)
		pair.add_child(readout)
		_row(col, String(entry["label"]), pair, "")

	var test := SkinnedButton.create("Play a test sound", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	test.pressed.connect(func() -> void: Kernel.audio.play_sfx("ui_click"))
	_row(col, "", test, "Plays the UI click at the current effects level.")

	_section(col, "Output")
	_planned_row(col, "Output device", _options_mock(["System default"], 0), "")
	_planned_row(col, "Mute when unfocused", _check_mock(true), "")
	_planned_row(col, "Mono downmix", _check_mock(false), "")

	_section(col, "Voice")
	_planned_row(col, "Spoken narration", _check_mock(false),
		"Text-to-speech over the narrator's prose.")
	_planned_row(col, "Voice input", _check_mock(false),
		"The input-source seam already accepts a voice source; the recogniser is M6 work.")
	return col


func _on_volume_changed(category: String, value: float) -> void:
	Kernel.settings.set_audio_volume(category, value)
	Kernel.audio.set_category_volume(category, value)
	Kernel.settings.save()
	_set_readout(category, value)


func _set_readout(category: String, value: float) -> void:
	var readout: Label = _volume_readouts.get(category)
	if readout != null:
		readout.text = "%d%%" % roundi(value * 100.0)


# --- Video ---------------------------------------------------------------------------------

func _build_video_tab() -> Control:
	var col := _tab_column()

	_section(col, "Display")
	var window_mode := _options(WINDOW_MODE_ROWS, Kernel.settings.window_mode(), _on_window_mode_changed)
	_row(col, "Window mode", window_mode, "Borderless keeps the current window size without decorations.")

	# Resolution is a *windowed desktop* setting: fullscreen and borderless take their size from the
	# screen, and on a phone the OS owns the window outright. Rather than let it sit there doing
	# nothing, it is disabled with the reason showing — the same honesty the `planned` tag buys, for
	# a control that is finished but not applicable right now.
	var windowed := Kernel.settings.window_mode() == AppSettings.WINDOW_MODE_WINDOWED
	var resizable := AppSettings.can_resize_window()
	var resolution_rows := _resolution_rows()
	var resolution := _options(resolution_rows,
		AppSettings.effective_windowed_resolution(Kernel.settings.resolution(), _windowed_usable_rect()),
		_on_resolution_changed)
	resolution.disabled = not (windowed and resizable) or resolution_rows.is_empty()
	# Disabled but still hovered — unlike a `planned` row, which the pointer passes straight through.
	UiSkin.apply_cursor(resolution, not resolution.disabled)
	var resolution_note := ""
	if not resizable:
		resolution_note = "The window is the operating system's to size on this device."
	elif not windowed:
		resolution_note = "Choose Windowed first; fullscreen and borderless use the screen's size."
	elif resolution_rows.is_empty():
		resolution_note = "No supported window size fits this display."
	_row(col, "Windowed resolution", resolution, resolution_note)

	# One monitor means no choice to make, and a dropdown with a single entry is furniture.
	var screens := DisplayServer.get_screen_count()
	var monitor := _options(_monitor_rows(screens), str(Kernel.settings.monitor()), _on_monitor_changed)
	monitor.disabled = screens < 2
	UiSkin.apply_cursor(monitor, not monitor.disabled)
	_row(col, "Monitor", monitor, "" if screens >= 2 else "Only one display is attached.")

	_section(col, "Performance")
	var vsync := _options(VSYNC_ROWS, Kernel.settings.vsync_mode(), _on_vsync_changed)
	_row(col, "V-Sync", vsync, "")
	var fps := _options(FPS_ROWS, str(Kernel.settings.max_fps()), _on_max_fps_changed)
	_row(col, "Frame rate cap", fps,
		"Matters most on a phone, where it is a battery setting more than a smoothness one.")
	_planned_row(col, "Render scale", _options_mock(["75%", "100%", "125%"], 1),
		"A 3D setting (the viewport's 3D scale). This is a 2D game, so there is nothing for it to "
		+ "scale — it stays here as a reminder to remove it, not to build it.")

	_section(col, "Presentation")
	_planned_row(col, "UI scale", _options_mock(["Small", "Normal", "Large"], 1),
		"Every screen is built in code with no theme yet, so there is nothing to scale.")
	_planned_row(col, "Brightness", _slider_mock(0.5), "")
	_planned_row(col, "Map season tint", _check_mock(true),
		"The map's season tint is one of the deferred pieces of the legacy renderer.")
	_planned_row(col, "Screen shake", _check_mock(true), "")
	return col


## Whether a Controls-tab label names an action that actually exists (and so gets a live rebind
## button instead of a `planned` placeholder). Matched on the *label*, because `KEY_BINDINGS` is
## written in display terms — the two lists agree on wording, and a test asserts they still do.
func _is_bindable(label: String) -> bool:
	for action: Dictionary in InputActions.ACTIONS:
		if String(action["label"]) == label:
			return true
	return false


## One rebindable action: a button showing its current key, which listens for the next keypress
## when clicked.
func _binding_row(parent: Node, action_id: String, label: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	UiSkin.apply_input(button)
	button.set_meta("action_id", action_id)
	button.text = InputActions.key_name(InputActions.keycode_for(action_id, Kernel.settings))
	button.toggle_mode = true
	button.toggled.connect(func(on: bool) -> void: _listen_for_key(button, on))
	_binding_buttons[action_id] = button
	var default_name := InputActions.key_name(InputActions.default_keycode(action_id))
	_row(parent, label, button, "Default: %s" % default_name)


## Put a binding button into "press a key" mode. Only one listens at a time — two buttons waiting
## for the same keypress would both claim it.
func _listen_for_key(button: Button, listening: bool) -> void:
	if listening and _listening_button != null and _listening_button != button:
		_listening_button.set_pressed_no_signal(false)
		_refresh_binding_button(_listening_button)
	_listening_button = button if listening else null
	if listening:
		button.text = "Press a key…"
	else:
		_refresh_binding_button(button)


## While a binding button is listening, the next keypress belongs to it rather than to the game —
## including keys that are themselves bound to something, which is the whole point. Handled in
## `_input` (not `_unhandled_input`) so it is seen *before* the action it would otherwise trigger.
func _input(event: InputEvent) -> void:
	if _listening_button == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var button := _listening_button
	var action_id := String(button.get_meta("action_id"))
	# Escape cancels rather than binds: it is the one key a player will reflexively press to back
	# out of a mode, and losing "Back / close" to a mis-click would be hard to undo.
	if key.keycode != KEY_ESCAPE:
		_rebind(action_id, key.keycode)
	button.set_pressed_no_signal(false)
	_listening_button = null
	_refresh_binding_button(button)


## Apply a new key, taking it from whatever held it. A key may drive only one action: leaving both
## bound means one silently wins, which the player cannot see or diagnose.
func _rebind(action_id: String, keycode: int) -> void:
	var conflict := InputActions.action_using(keycode, Kernel.settings, action_id)
	if not conflict.is_empty():
		# Explicitly UNBOUND, not "no override": the latter falls back to a default that is this
		# very key, and the clash would survive the fix.
		Kernel.settings.set_key_binding(conflict, AppSettings.UNBOUND)
	Kernel.settings.set_key_binding(action_id, keycode)
	Kernel.settings.save()
	InputActions.install(Kernel.settings)
	if not conflict.is_empty() and _binding_buttons.has(conflict):
		_refresh_binding_button(_binding_buttons[conflict])


func _refresh_binding_button(button: Button) -> void:
	var action_id := String(button.get_meta("action_id"))
	button.text = InputActions.key_name(InputActions.keycode_for(action_id, Kernel.settings))


func _on_reset_bindings() -> void:
	Kernel.settings.clear_all_key_bindings()
	Kernel.settings.save()
	InputActions.install(Kernel.settings)
	for action_id in _binding_buttons:
		_refresh_binding_button(_binding_buttons[action_id])


## `{id, label}` rows for the resolution picker, led by "Default" — the honest name for
## [constant AppSettings.UNSET], which leaves whatever size the window already had.
func _resolution_rows() -> Array:
	var rows: Array = []
	for size: String in AppSettings.suitable_resolutions(_windowed_usable_rect()):
		var parts := size.split("x")
		rows.append({"id": size, "label": "%s × %s" % [parts[0], parts[1]]})
	return rows


func _windowed_usable_rect() -> Rect2i:
	var screen := Kernel.settings.monitor()
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = DisplayServer.window_get_current_screen()
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = 0
	return DisplayServer.screen_get_usable_rect(screen)


func _monitor_rows(screens: int) -> Array:
	var rows: Array = [{"id": str(AppSettings.MONITOR_UNSET), "label": "Default"}]
	for i in screens:
		rows.append({"id": str(i), "label": "Monitor %d" % (i + 1)})
	return rows


func _on_window_mode_changed(mode: String) -> void:
	Kernel.settings.set_window_mode(mode)
	Kernel.settings.save()
	Kernel.settings.apply_video()
	# Resolution's availability depends on this, so the tab has to be rebuilt to show it.
	_rebuild()


func _on_resolution_changed(value: String) -> void:
	Kernel.settings.set_resolution(value)
	Kernel.settings.save()
	Kernel.settings.apply_video()


func _on_monitor_changed(value: String) -> void:
	Kernel.settings.set_monitor(int(value))
	Kernel.settings.save()
	Kernel.settings.apply_video()
	_rebuild()


func _on_max_fps_changed(value: String) -> void:
	Kernel.settings.set_max_fps(int(value))
	Kernel.settings.save()
	Kernel.settings.apply_video()


func _on_vsync_changed(mode: String) -> void:
	Kernel.settings.set_vsync_mode(mode)
	Kernel.settings.save()
	Kernel.settings.apply_video()


# --- Controls ------------------------------------------------------------------------------

func _build_controls_tab() -> Control:
	var col := _tab_column()
	_note(col, ("Click a key to change it, then press the new one. Escape cancels the change. "
		+ "Actions still marked “%s” have no feature behind them yet — a binding you could change "
		+ "and then watch do nothing would be worse than one that is honestly not ready.")
		% PLANNED_TAG)

	var reset := SkinnedButton.create("Reset all bindings", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	reset.pressed.connect(_on_reset_bindings)
	_row(col, "", reset, "Leaves audio, video and gameplay settings alone.")

	# Built from the same list the actions are declared in (grouped by their own `group`), so the
	# tab cannot drift from what is actually bindable. Anything in KEY_BINDINGS that has no action
	# behind it keeps its `planned` tag.
	for group: Dictionary in KEY_BINDINGS:
		var group_name := String(group["group"])
		_section(col, group_name)
		for action: Dictionary in InputActions.ACTIONS:
			if String(action["group"]) == group_name:
				_binding_row(col, String(action["id"]), String(action["label"]))
		for action: Array in group["actions"]:
			if _is_bindable(String(action[0])):
				continue  # already shown above, as a live control
			var binding := Button.new()
			binding.text = String(action[1])
			binding.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
			_planned_row(col, String(action[0]), binding, "")

	_section(col, "Mouse and touch")
	_planned_row(col, "Map drag sensitivity", _slider_mock(0.5), "")
	_planned_row(col, "Invert map drag", _check_mock(false), "")
	_planned_row(col, "Edge panning", _check_mock(false), "")
	_planned_row(col, "Long-press delay", _options_mock(["Short", "Normal", "Long"], 1), "")
	return col


# --- Language ------------------------------------------------------------------------------

func _add_language_sections(col: VBoxContainer) -> void:
	_note(col, "Interface strings are still English literals in code, and the narrator is told which "
		+ "language to write in per beat. Internals stay English on purpose (D35) — a switch here "
		+ "would change what the player reads, never what is stored.")

	_section(col, "Language")
	_planned_row(col, "Interface", _options_mock(["English", "Português", "Español"], 0), "")
	_planned_row(col, "Narration", _options_mock(["Same as interface", "English", "Português",
		"Español"], 0), "Classification stability across these three is measured and holds (D17).")
	_planned_row(col, "Translate what I type", _check_mock(true),
		"Non-English input is translated at the boundary before anything is stored (D35).")


# --- Accessibility -------------------------------------------------------------------------

func _add_accessibility_sections(col: VBoxContainer) -> void:
	_note(col, "None of this is built. It is listed so it is budgeted for rather than discovered "
		+ "late — a text-heavy game has more of an obligation here than most.")

	_section(col, "Reading")
	_planned_row(col, "Text size", _options_mock(["Normal", "Large", "Larger"], 0), "")
	_planned_row(col, "Dyslexia-friendly font", _check_mock(false), "")
	_planned_row(col, "Line spacing", _options_mock(["Normal", "Relaxed"], 0), "")
	_planned_row(col, "Narration speed", _options_mock(["Instant", "Typed out"], 0), "")

	_section(col, "Visual")
	_planned_row(col, "Colour-blind palette", _options_mock(["Off", "Deuteranopia", "Protanopia",
		"Tritanopia"], 0), "The map's biome colours are the first thing this has to answer for.")
	_planned_row(col, "High contrast", _check_mock(false), "")
	_planned_row(col, "Reduce motion", _check_mock(false), "")

	_section(col, "Input")
	_planned_row(col, "Hold instead of press", _check_mock(false), "")
	_planned_row(col, "Screen-reader hints", _check_mock(false), "")


# --- Row-building helpers ------------------------------------------------------------------

func _tab_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	return col


func _section(parent: Node, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(spacer)
	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	label.add_theme_color_override("font_color", NOTE_COLOR)
	label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	parent.add_child(label)
	var rule := HSeparator.new()
	# Brown, so the rule belongs to the parchment. `OutpostTheme` draws separators in the shell's cool
	# blue-grey, which is right on a dark panel and was the last thing on this page still tinted from
	# the other palette.
	rule.add_theme_stylebox_override("separator", UiSkin.separator_style())
	parent.add_child(rule)


## One setting: its name, its control, the `planned` tag when it is not wired, and an optional line of
## explanation. Added in that order, so the eye meets the state before the reason.
##
## An [HFlowContainer], not an [HBoxContainer]: name + control + hint is about 640px of fixed columns,
## which fits a desktop window and does not fit the 720-wide portrait viewport a phone renders at —
## an [HBoxContainer] answers that by running the hint off the right edge, where it cannot be read or
## scrolled to (the tab's [ScrollContainer] is deliberately vertical-only). Flowing puts the hint on
## its own line exactly when it stops fitting, and leaves the desktop row a single line as before.
func _row(parent: Node, label_text: String, control: Control, note: String,
		planned: bool = false) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", UiSkin.INK)
	label.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	row.add_child(label)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

	if planned:
		var tag := Label.new()
		tag.text = PLANNED_TAG
		tag.add_theme_color_override("font_color", PLANNED_COLOR)
		tag.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)

	if not note.is_empty():
		var hint := Label.new()
		hint.text = note
		hint.add_theme_color_override("font_color", NOTE_COLOR)
		hint.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A wrapping label's own minimum width is its longest word, which would let the flow squeeze the
		# hint into a sliver beside the control rather than moving it down. This is the width below
		# which sharing the line is not worth it.
		hint.custom_minimum_size = Vector2(HINT_MIN_WIDTH, 0)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hint)
	return row


## A setting that does not work yet: the control is inert and the row carries the tag. Shown and
## *labelled*, not hidden — the point is to make what is coming visible without implying it is here.
##
## Distinct from a control that is *built but not applicable right now* (Resolution outside Windowed
## mode, Monitor with one display): those are disabled too, and carry a note saying why, but they
## are emphatically not `planned`. [constant PLANNED_META] is what tells the two apart — greying
## alone cannot, which is the whole reason the tag exists.
func _planned_row(parent: Node, label_text: String, control: Control, note: String) -> void:
	if control is BaseButton:
		(control as BaseButton).disabled = true
	elif control is Range:
		(control as Range).editable = false
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.modulate = Color(1, 1, 1, 0.5)
	control.set_meta(PLANNED_META, true)
	_row(parent, label_text, control, note, true)


func _note(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", NOTE_COLOR)
	parent.add_child(label)


## A working dropdown over `{id, label}` entries.
func _options(entries: Array, selected_id: String, on_change: Callable) -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	UiSkin.apply_input(options)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		options.add_item(String(entry["label"]))
		options.set_item_metadata(i, String(entry["id"]))
		if String(entry["id"]) == selected_id:
			options.select(i)
	options.item_selected.connect(func(index: int) -> void:
		on_change.call(String(options.get_item_metadata(index))))
	return options


func _options_mock(labels: Array, selected: int) -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	UiSkin.apply_input(options)
	for label: String in labels:
		options.add_item(label)
	if selected >= 0 and selected < labels.size():
		options.select(selected)
	return options


func _check_mock(pressed: bool) -> CheckButton:
	var check := CheckButton.new()
	check.button_pressed = pressed
	UiSkin.apply_toggle(check)
	return check


func _slider_mock(value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	UiSkin.apply_slider(slider)
	slider.custom_minimum_size = Vector2(CONTROL_WIDTH, UiSkin.CONTROL_HEIGHT)
	return slider


func _on_reset() -> void:
	Kernel.settings.reset_to_defaults()
	Kernel.settings.save()
	Kernel.settings.apply_audio(Kernel.audio)
	Kernel.settings.apply_video()
	_rebuild()


## Rebuild every control from the store, rather than resetting each in place: there is one place
## that reads stored values into controls, and reusing it cannot drift from what the store holds.
## Also how a setting that changes *another* control's availability (window mode → resolution)
## refreshes it.
func _rebuild() -> void:
	var tab := _current_tab()
	for child in get_children():
		child.queue_free()
	_build_ui()
	# Rebuilding drops the player back on the first tab otherwise, which — for a control that
	# rebuilds on change, like window mode — throws them out of the tab they were working in.
	_select_tab(tab)


func _current_tab() -> int:
	var tabs := _find_tabs()
	return tabs.current_tab if tabs != null else 0


func _select_tab(index: int) -> void:
	var tabs := _find_tabs()
	if tabs != null and index >= 0 and index < tabs.get_tab_count():
		tabs.current_tab = index


func _find_tabs() -> TabContainer:
	for node in _descendants(self):
		if node is TabContainer:
			return node
	return null


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
