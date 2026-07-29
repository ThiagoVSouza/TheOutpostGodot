extends Control

## App-shell new-game wizard: Background -> Location -> Identity -> Settings, then Start seeds a
## fresh game and enters it. Mirrors the legacy Tauri wizard's four steps (the flow captured in
## docs/plan.md / PR #47's description); the module-pick screen and a module-config-driven wizard
## remain deferred — there is nothing yet for a module to configure.

const GAME_SCREEN := "base_game.chat"
const DEFAULT_HERO := "Marcus"
const DEFAULT_OUTPOST := "Ravenwatch"

const STEP_TITLES := ["Background", "Location", "Identity", "Settings"]

## How small a card may get before it stops being readable. The cards flow rather than sitting in a
## fixed number of columns, so this — not a column count — is what decides how many fit on a line.
## It is a *minimum*: the card grows to whatever its text needs.
const CARD_MIN_WIDTH := 240.0
const CARD_MIN_HEIGHT := 130.0

## Wide enough that "Female" is not a tighter plate than "Male" — a pick-one pair whose halves are
## different sizes reads as one of them mattering more.
const SEX_BUTTON_WIDTH := 150.0

## The column the flag designer's layer names sit in, so its rows line up down the left.
const FLAG_LABEL_WIDTH := 120.0

## How narrow either half of the Identity step may get. Both halves declare the same one so that when
## they do share a line neither is squeezed to make room for the other.
const IDENTITY_COLUMN_WIDTH := 420.0

## Room for the longest name either field ships with, so a default value is never shown clipped.
const FIELD_MIN_WIDTH := 300.0

## The colour swatch on a flag layer. Still Godot's stock ColorPickerButton — the painted swatch
## palette is the flag designer's own step of this work — but at least sized to the row it sits in.
const SWATCH_WIDTH := 90.0

const BACKGROUNDS := [
	{"id": "wealthy_merchant", "title": "Merchant",
	 "desc": "Economic start — 5,000 coins and a trade network."},
	{"id": "knight", "title": "Knight",
	 "desc": "Military start — 10 soldiers, plate armor, a warhorse."},
	{"id": "unlanded_noble", "title": "Noble",
	 "desc": "Political start — a royal order and standing to call on."},
	{"id": "mercenary_captain", "title": "Mercenary",
	 "desc": "Frontier start — 10 adventurers and wildlands knowledge."},
	{"id": "scholar", "title": "Scholar",
	 "desc": "Knowledge start — a retinue of specialists."},
]

const LOCATIONS := [
	{"id": "coast", "title": "Coast",
	 "desc": "Difficulty: Easy · Fertility: Average · Barbarians: Friendly"},
	{"id": "valley", "title": "Valley",
	 "desc": "Difficulty: Average · Fertility: High · Barbarians: Mixed"},
	{"id": "forest", "title": "Forest",
	 "desc": "Difficulty: Hard · Fertility: Average · Barbarians: Mixed"},
	{"id": "mountains", "title": "Mountains",
	 "desc": "Difficulty: Very Hard · Fertility: Poor · Barbarians: Hostile"},
]

const OUTPOST_NAMES := ["Ravenwatch", "Stonegate", "Ironward", "Dawnrest", "Northpass",
	"Amberhold", "Greyhaven", "Frostmere", "Redcliff", "Oakmarch"]

## The Settings step speaks [NarrationSettings]' own vocabulary rather than a display vocabulary of
## its own, so the stored answer *is* the level and nothing has to translate between the two. Only
## the titles are dressed up: "Average" reads better on a card than "Normal".
const VERBOSITIES := [
	{"id": NarrationSettings.LEVEL_SHORT, "title": "Short", "desc": "Terse, to the point."},
	{"id": NarrationSettings.LEVEL_NORMAL, "title": "Average", "desc": "Balanced narration."},
	{"id": NarrationSettings.LEVEL_LONG, "title": "Long", "desc": "Rich, descriptive prose."},
]

const FLAG_PALETTE := ["#b62a2a", "#2f5fc0", "#2fa354", "#f3c43f", "#000000", "#f7f7f2",
	"#8b5a2b", "#a03291"]
const FLAG_PATTERN_COUNT := 14
const FLAG_EMBLEM_COUNT := 13

var _current_step := 0
var _step_pages: Array = []
var _step_label: Label = null
var _back: SkinnedButton = null
var _next: SkinnedButton = null

var _selected_background := ""
var _selected_location := ""
## Starts at the player's app-level preference rather than a hardcoded default, so someone who always
## wants long prose is not re-choosing it at every new game. Read in `_build_settings_step`, since
## `Kernel` is not available at property-initialisation time.
var _selected_verbosity := NarrationSettings.LEVEL_NORMAL
var _sex := "male"

var _name_field: LineEdit = null
var _outpost_name_field: LineEdit = null

var _flag_value := FlagValue.new()
var _flag_view: FlagView = null
var _flag_shape_picker: ColorPickerButton = null
var _flag_pattern_picker: ColorPickerButton = null
var _flag_emblem_picker: ColorPickerButton = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ShellPalette.paint_shell(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	# The Back/Next row sits on this edge, so it has to clear the navigation bar.
	margin.add_theme_constant_override("margin_bottom", 20 + SafeArea.bottom(get_viewport()))
	add_child(margin)

	# The same parchment the menu and the settings page sit on. This screen wore `plate_style`'s dark
	# glass while it was unskinned — the honest placeholder for lettering that had to stay light — and
	# the frame is what replaces it now that everything on it is written in ink.
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
	title.text = "New Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiSkin.FONT_TITLE)
	title.add_theme_color_override("font_color", UiSkin.INK)
	col.add_child(title)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_step_label.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	col.add_child(_step_label)

	# **The steps scroll.** They did not before, and on a phone that was the same trap the settings
	# page had: the Identity step alone is taller than the viewport, so its lower fields simply had
	# nowhere to be. A VBox, not the old absolutely-positioned host — a hidden child contributes
	# nothing to a container's minimum size, so the scroll region is always exactly the step on show.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSkin.apply_scroll_container(scroll)
	col.add_child(scroll)

	var pages_host := VBoxContainer.new()
	pages_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_host)

	_step_pages = [
		_build_background_step(),
		_build_location_step(),
		_build_identity_step(),
		_build_settings_step(),
	]
	for page: Control in _step_pages:
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages_host.add_child(page)

	# Cancel/Back on the left and Next/Start on the right, the same hands as the settings footer and
	# the exit modal: leaving is always the left plate.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	col.add_child(nav)

	_back = SkinnedButton.create("Back", UiSkin.BROWN, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back.pressed.connect(_on_back)
	nav.add_child(_back)

	# Blue: on every step the one thing the screen wants is to carry on.
	_next = SkinnedButton.create("Next", UiSkin.BLUE, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.pressed.connect(_on_next)
	nav.add_child(_next)

	_goto_step(0)


func _goto_step(step: int) -> void:
	_current_step = step
	for i in _step_pages.size():
		(_step_pages[i] as Control).visible = i == step
	_step_label.text = "Step %d of %d — %s" % [step + 1, STEP_TITLES.size(), STEP_TITLES[step]]
	_back.label.text = "Back" if step > 0 else "Cancel"
	_next.label.text = "Start" if step == _step_pages.size() - 1 else "Next"


func _on_back() -> void:
	if _current_step == 0:
		Kernel.router.goto("core.main_menu")
	else:
		_goto_step(_current_step - 1)


## Hardware/gesture back does exactly what the on-screen Back/Cancel button does (Android UX
## pass) — never a surprise exit mid-wizard.
func on_hardware_back() -> bool:
	_on_back()
	return true


func _on_next() -> void:
	if _current_step == _step_pages.size() - 1:
		_finish()
	else:
		_goto_step(_current_step + 1)


func _finish() -> void:
	var hero_name := _name_field.text.strip_edges()
	if hero_name.is_empty():
		hero_name = DEFAULT_HERO
	var outpost_name := _outpost_name_field.text.strip_edges()
	if outpost_name.is_empty():
		outpost_name = DEFAULT_OUTPOST
	var fields := {
		"hero_name": hero_name,
		"sex": _sex,
		"outpost_name": outpost_name,
		"background": _selected_background,
		"outpost_location": _selected_location,
		"outpost_flag": _flag_value.to_dict(),
		"verbosity": _selected_verbosity,
	}
	Kernel.session.begin_new_game(fields)
	Kernel.router.goto("core.loading", {"next": GAME_SCREEN})


# --- Step 1: Background -----------------------------------------------------------------

func _build_background_step() -> Control:
	_selected_background = String(BACKGROUNDS[0]["id"])
	return _card_select_column(BACKGROUNDS, _selected_background,
		func(id: String) -> void: _selected_background = id)


# --- Step 2: Location --------------------------------------------------------------------

func _build_location_step() -> Control:
	_selected_location = String(LOCATIONS[0]["id"])
	return _card_select_column(LOCATIONS, _selected_location,
		func(id: String) -> void: _selected_location = id)


func _card_select_column(items: Array, default_id: String, on_select: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	# An [HFlowContainer], not the fixed-column grid this used to be. A grid divides whatever width it
	# is given by a number decided here, so at the phone's width three columns made each card a
	# sliver; flowing lets a card keep a width it can be read at and take as many lines as that needs
	# — three across on a desktop, two on a phone, without this screen knowing which it is on.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	col.add_child(flow)
	var group := ButtonGroup.new()
	for item: Dictionary in items:
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = group
		card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
		UiSkin.apply_card(card)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.text = "%s\n%s" % [String(item["title"]), String(item["desc"])]
		card.button_pressed = String(item["id"]) == default_id
		card.pressed.connect(func() -> void: on_select.call(String(item["id"])))
		flow.add_child(card)
	return col


# --- Step 3: Identity ---------------------------------------------------------------------

func _build_identity_step() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)

	# The fields and the flag designer are two columns on a desktop and two *rows* on a phone. An
	# HFlowContainer is what makes that one layout rather than two: side by side they need about 840,
	# which is more than a 720-wide phone has, and an HBox answers that by running the flag off the
	# right edge where it cannot be reached. Each column keeps a minimum width it stays usable at, and
	# the flow decides how many fit.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 30)
	row.add_theme_constant_override("v_separation", 16)
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = IDENTITY_COLUMN_WIDTH
	row.add_child(left)

	left.add_child(_field_label("Hero name"))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = DEFAULT_HERO
	UiSkin.apply_line_edit(_name_field)
	_name_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	left.add_child(_name_field)

	left.add_child(_field_label("Sex"))
	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	left.add_child(sex_row)
	var sex_group := ButtonGroup.new()
	sex_row.add_child(_sex_button("Male", "male", sex_group, true))
	sex_row.add_child(_sex_button("Female", "female", sex_group, false))

	left.add_child(_field_label("Outpost name"))
	# Flows, so the Randomize plate drops below the field rather than squeezing it. It squeezed it:
	# with both on one line at this type scale the field had about 200 units left, and "Ravenwatch"
	# — the default it ships with — showed as "Ravenwatc".
	var outpost_row := HFlowContainer.new()
	outpost_row.add_theme_constant_override("h_separation", 8)
	outpost_row.add_theme_constant_override("v_separation", 8)
	left.add_child(outpost_row)
	_outpost_name_field = LineEdit.new()
	_outpost_name_field.text = DEFAULT_OUTPOST
	UiSkin.apply_line_edit(_outpost_name_field)
	_outpost_name_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	outpost_row.add_child(_outpost_name_field)
	var reroll := SkinnedButton.create("Randomize", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	reroll.pressed.connect(_randomize_outpost_name)
	outpost_row.add_child(reroll)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = IDENTITY_COLUMN_WIDTH
	row.add_child(right)
	right.add_child(_field_label("Flag"))

	var flag_row := HBoxContainer.new()
	flag_row.add_theme_constant_override("separation", 16)
	right.add_child(flag_row)

	_flag_value.texture = "pattern03"
	_flag_value.emblem = "emblem01"
	_flag_view = FlagView.new()
	_flag_view.custom_minimum_size = Vector2(140, 140 * FlagView.aspect())
	flag_row.add_child(_flag_view)

	var flag_controls := VBoxContainer.new()
	flag_controls.add_theme_constant_override("separation", 6)
	flag_row.add_child(flag_controls)

	_flag_shape_picker = _flag_color_picker(flag_controls, "Cloth", _flag_value.shape_color,
		func(c: Color) -> void:
			_flag_value.shape_color = c
			_flag_view.set_value(_flag_value))
	_flag_pattern_picker = _flag_color_picker(flag_controls, "Pattern", _flag_value.texture_color,
		func(c: Color) -> void:
			_flag_value.texture_color = c
			_flag_view.set_value(_flag_value))
	_flag_emblem_picker = _flag_color_picker(flag_controls, "Emblem", _flag_value.emblem_color,
		func(c: Color) -> void:
			_flag_value.emblem_color = c
			_flag_view.set_value(_flag_value))

	flag_controls.add_child(_flag_cycle_row("Pattern shape",
		func(step: int) -> void: _cycle_flag_pattern(step)))
	flag_controls.add_child(_flag_cycle_row("Emblem shape",
		func(step: int) -> void: _cycle_flag_emblem(step)))

	var randomize_flag := SkinnedButton.create("Randomize flag", UiSkin.BROWN,
		UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_FONT_SIZE)
	randomize_flag.pressed.connect(_randomize_flag)
	flag_controls.add_child(randomize_flag)

	_flag_view.set_value(_flag_value)
	return col


## One of the two sex choices. A card rather than a plate: it is a pick-one, the same kind of answer
## the Background and Location steps take, and it should look like one.
func _sex_button(text: String, id: String, group: ButtonGroup, selected: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	UiSkin.apply_card(button)
	button.custom_minimum_size = Vector2(SEX_BUTTON_WIDTH, UiSkin.CONTROL_HEIGHT)
	button.pressed.connect(func() -> void: _sex = id)
	return button


## The `<` / `>` beside a flag layer. Painted as a field rather than a plate, because it belongs to
## the row of controls it steps through rather than being an action of its own.
func _stepper(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	UiSkin.apply_input(button)
	button.custom_minimum_size = Vector2(UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_HEIGHT)
	button.pressed.connect(on_press)
	return button


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	l.add_theme_color_override("font_color", UiSkin.INK)
	# **Wrapping, so a label cannot set the width of the page.** A Label's minimum width is its whole
	# line unless it may wrap, and "How should the game master narrate?" is 556 units of it at this
	# type scale — enough on its own to push the Settings step 20 past a 720-wide phone. Wrapping
	# drops that minimum to the longest single word. The flag designer's layer names are unaffected:
	# they are short and carry their own column width.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _flag_color_picker(parent: Node, label_text: String, initial: Color,
		on_pick: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := _field_label(label_text)
	l.custom_minimum_size = Vector2(FLAG_LABEL_WIDTH, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(SWATCH_WIDTH, UiSkin.CONTROL_HEIGHT)
	picker.color = initial
	picker.color_changed.connect(on_pick)
	row.add_child(picker)
	return picker


func _flag_cycle_row(label_text: String, on_step: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _field_label(label_text)
	l.custom_minimum_size = Vector2(FLAG_LABEL_WIDTH, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	row.add_child(_stepper("<", func() -> void: on_step.call(-1)))
	row.add_child(_stepper(">", func() -> void: on_step.call(1)))
	return row


func _randomize_outpost_name() -> void:
	_outpost_name_field.text = OUTPOST_NAMES[randi() % OUTPOST_NAMES.size()]


func _cycle_flag_pattern(step: int) -> void:
	var n := int(_flag_value.texture.substr(7)) if _flag_value.has_pattern() else 0
	n = wrapi(n + step, 0, FLAG_PATTERN_COUNT + 1)
	_flag_value.texture = FlagValue.NONE if n == 0 else "pattern%02d" % n
	_flag_view.set_value(_flag_value)


func _cycle_flag_emblem(step: int) -> void:
	var n := int(_flag_value.emblem.substr(6)) if _flag_value.has_emblem() else 0
	n = wrapi(n + step, 0, FLAG_EMBLEM_COUNT + 1)
	_flag_value.emblem = FlagValue.NONE if n == 0 else "emblem%02d" % n
	_flag_view.set_value(_flag_value)


func _randomize_flag() -> void:
	_flag_value.shape_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.texture_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.emblem_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.texture = "pattern%02d" % (1 + randi() % FLAG_PATTERN_COUNT)
	_flag_value.emblem = "emblem%02d" % (1 + randi() % FLAG_EMBLEM_COUNT)
	_flag_shape_picker.color = _flag_value.shape_color
	_flag_pattern_picker.color = _flag_value.texture_color
	_flag_emblem_picker.color = _flag_value.emblem_color
	_flag_view.set_value(_flag_value)


# --- Step 4: Settings ----------------------------------------------------------------------

func _build_settings_step() -> Control:
	_selected_verbosity = Kernel.settings.narration_level()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.add_child(_field_label("How should the game master narrate?"))
	var group := ButtonGroup.new()
	for item: Dictionary in VERBOSITIES:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		UiSkin.apply_card(b)
		b.custom_minimum_size.y = UiSkin.CONTROL_HEIGHT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s — %s" % [String(item["title"]), String(item["desc"])]
		b.button_pressed = String(item["id"]) == _selected_verbosity
		b.pressed.connect(func() -> void: _selected_verbosity = String(item["id"]))
		col.add_child(b)
	return col
