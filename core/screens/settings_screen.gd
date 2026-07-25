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
const PLANNED_COLOR := Color(0.95, 0.75, 0.35)
const NOTE_COLOR := Color(1, 1, 1, 0.55)

const LABEL_WIDTH := 260.0
const CONTROL_WIDTH := 320.0

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
		["Focus the input", "T"],
		["Repeat last message", "Up"],
	]},
	{"group": "The world", "actions": [
		["Let a day pass", "Space"],
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


func on_enter(params: Dictionary) -> void:
	_back = String(params.get("back", DEFAULT_BACK))


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ShellPalette.paint(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	var legend := Label.new()
	legend.text = "Items marked “%s” are not implemented yet — they show what is coming." % PLANNED_TAG
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.modulate = NOTE_COLOR
	col.add_child(legend)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	_add_tab(tabs, "Gameplay", _build_gameplay_tab())
	_add_tab(tabs, "Audio", _build_audio_tab())
	_add_tab(tabs, "Video", _build_video_tab())
	_add_tab(tabs, "Controls", _build_controls_tab())
	_add_tab(tabs, "Language", _build_language_tab())
	_add_tab(tabs, "Accessibility", _build_accessibility_tab())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	col.add_child(footer)
	var reset := Button.new()
	reset.text = "Reset all to defaults"
	reset.custom_minimum_size = Vector2(0, 40)
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(func() -> void: Kernel.router.goto(_back))
	footer.add_child(back)


## Wrap a tab's content in a scroll container: several of these sections are already taller than a
## phone screen, and a settings row the player cannot reach is the same as one that does not exist.
func _add_tab(tabs: TabContainer, title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
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
		slider.custom_minimum_size = Vector2(CONTROL_WIDTH - 60.0, 0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var readout := Label.new()
		readout.custom_minimum_size = Vector2(50, 0)
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_volume_readouts[category] = readout
		_set_readout(category, slider.value)
		slider.value_changed.connect(func(value: float) -> void: _on_volume_changed(category, value))

		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		pair.add_child(slider)
		pair.add_child(readout)
		_row(col, String(entry["label"]), pair, "")

	var test := Button.new()
	test.text = "Play a test sound"
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
	_note(col, "Nothing here is wired. The project has no display settings at all yet — it runs at "
		+ "the project default in a window, and a resolution list needs a window-mode policy first.")

	_section(col, "Display")
	_planned_row(col, "Window mode", _options_mock(["Windowed", "Borderless", "Fullscreen"], 0), "")
	_planned_row(col, "Resolution", _options_mock(["1280 × 720", "1920 × 1080", "2560 × 1440"], 1), "")
	_planned_row(col, "Monitor", _options_mock(["Primary"], 0), "")

	_section(col, "Performance")
	_planned_row(col, "V-Sync", _options_mock(["Off", "On", "Adaptive"], 1), "")
	_planned_row(col, "Frame rate cap", _options_mock(["30", "60", "120", "Unlimited"], 1),
		"Matters most on a phone, where it is a battery setting more than a smoothness one.")
	_planned_row(col, "Render scale", _options_mock(["75%", "100%", "125%"], 1), "")

	_section(col, "Presentation")
	_planned_row(col, "UI scale", _options_mock(["Small", "Normal", "Large"], 1),
		"Every screen is built in code with no theme yet, so there is nothing to scale.")
	_planned_row(col, "Brightness", _slider_mock(0.5), "")
	_planned_row(col, "Map season tint", _check_mock(true),
		"The map's season tint is one of the deferred pieces of the legacy renderer.")
	_planned_row(col, "Screen shake", _check_mock(true), "")
	return col


# --- Controls ------------------------------------------------------------------------------

func _build_controls_tab() -> Control:
	var col := _tab_column()
	_note(col, "The game has no input actions defined yet, so none of these are bound and none can "
		+ "be rebound. The list is the intended set — rebinding every one of them is already a "
		+ "promise, so the set has to be complete before any of it is built.")

	for group: Dictionary in KEY_BINDINGS:
		_section(col, String(group["group"]))
		for action: Array in group["actions"]:
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

func _build_language_tab() -> Control:
	var col := _tab_column()
	_note(col, "Interface strings are still English literals in code, and the narrator is told which "
		+ "language to write in per beat. Internals stay English on purpose (D35) — a switch here "
		+ "would change what the player reads, never what is stored.")

	_section(col, "Language")
	_planned_row(col, "Interface", _options_mock(["English", "Português", "Español"], 0), "")
	_planned_row(col, "Narration", _options_mock(["Same as interface", "English", "Português",
		"Español"], 0), "Classification stability across these three is measured and holds (D17).")
	_planned_row(col, "Translate what I type", _check_mock(true),
		"Non-English input is translated at the boundary before anything is stored (D35).")
	return col


# --- Accessibility -------------------------------------------------------------------------

func _build_accessibility_tab() -> Control:
	var col := _tab_column()
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
	return col


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
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = NOTE_COLOR
	parent.add_child(label)
	var rule := HSeparator.new()
	parent.add_child(rule)


## One setting: its name, its control, the `planned` tag when it is not wired, and an optional line of
## explanation. Added in that order, so the eye meets the state before the reason.
func _row(parent: Node, label_text: String, control: Control, note: String,
		planned: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

	if planned:
		var tag := Label.new()
		tag.text = PLANNED_TAG
		tag.modulate = PLANNED_COLOR
		tag.add_theme_font_size_override("font_size", 11)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)

	if not note.is_empty():
		var hint := Label.new()
		hint.text = note
		hint.modulate = NOTE_COLOR
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hint)
	return row


## A setting that does not work yet: the control is inert and the row carries the tag. Shown and
## *labelled*, not hidden — the point is to make what is coming visible without implying it is here.
func _planned_row(parent: Node, label_text: String, control: Control, note: String) -> void:
	if control is BaseButton:
		(control as BaseButton).disabled = true
	elif control is Range:
		(control as Range).editable = false
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.modulate = Color(1, 1, 1, 0.5)
	_row(parent, label_text, control, note, true)


func _note(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = NOTE_COLOR
	parent.add_child(label)


## A working dropdown over `{id, label}` entries.
func _options(entries: Array, selected_id: String, on_change: Callable) -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
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
	for label: String in labels:
		options.add_item(label)
	if selected >= 0 and selected < labels.size():
		options.select(selected)
	return options


func _check_mock(pressed: bool) -> CheckButton:
	var check := CheckButton.new()
	check.button_pressed = pressed
	return check


func _slider_mock(value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	return slider


func _on_reset() -> void:
	Kernel.settings.reset_to_defaults()
	Kernel.settings.save()
	Kernel.settings.apply_audio(Kernel.audio)
	# Rebuilt rather than each control being reset in place: there is one place that reads the stored
	# values into controls, and reusing it cannot drift from what the store actually holds.
	for child in get_children():
		child.queue_free()
	_build_ui()
