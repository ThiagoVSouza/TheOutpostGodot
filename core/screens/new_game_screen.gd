extends Control

## App-shell new-game wizard: Background -> Location -> Identity -> Settings, then Start seeds a
## fresh game and enters it. Mirrors the legacy Tauri wizard's four steps (the flow captured in
## docs/plan.md / PR #47's description); the module-pick screen and a module-config-driven wizard
## remain deferred — there is nothing yet for a module to configure.

const GAME_SCREEN := "base_game.chat"
const DEFAULT_HERO := "Marcus"
const DEFAULT_OUTPOST := "Ravenwatch"

const STEP_TITLES := ["Background", "Location", "Identity", "Settings"]

## Cards per row on the pick-one steps. Five backgrounds over three columns reads as a deliberate
## 3 + 2 rather than the ragged single row a wider grid would give.
const CARD_COLUMNS := 3

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
var _back_btn: Button = null
var _next_btn: Button = null

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
	ShellPalette.paint(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "New Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_step_label)

	var pages_host := Control.new()
	pages_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(pages_host)

	_step_pages = [
		_build_background_step(),
		_build_location_step(),
		_build_identity_step(),
		_build_settings_step(),
	]
	for page: Control in _step_pages:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		pages_host.add_child(page)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	col.add_child(nav)

	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(0, 40)
	_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_btn.pressed.connect(_on_back)
	nav.add_child(_back_btn)

	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(0, 40)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(_on_next)
	nav.add_child(_next_btn)

	_goto_step(0)


func _goto_step(step: int) -> void:
	_current_step = step
	for i in _step_pages.size():
		(_step_pages[i] as Control).visible = i == step
	_step_label.text = "Step %d of %d — %s" % [step + 1, STEP_TITLES.size(), STEP_TITLES[step]]
	_back_btn.text = "Back" if step > 0 else "Cancel"
	_next_btn.text = "Start" if step == _step_pages.size() - 1 else "Next"


func _on_back() -> void:
	if _current_step == 0:
		Kernel.router.goto("core.main_menu")
	else:
		_goto_step(_current_step - 1)


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
	var grid := GridContainer.new()
	grid.columns = CARD_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var group := ButtonGroup.new()
	for item: Dictionary in items:
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = group
		card.custom_minimum_size = Vector2(0, 90)
		# The cards share the row evenly and wrap their own text. Sizing them to a fixed width
		# instead lets a long description push the grid wider than the window — the last column
		# then sits off-screen, unreachable, with no scrollbar to reveal it.
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.text = "%s\n%s" % [String(item["title"]), String(item["desc"])]
		card.button_pressed = String(item["id"]) == default_id
		card.pressed.connect(func() -> void: on_select.call(String(item["id"])))
		grid.add_child(card)
	return col


# --- Step 3: Identity ---------------------------------------------------------------------

func _build_identity_step() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	left.add_child(_field_label("Hero name"))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = DEFAULT_HERO
	left.add_child(_name_field)

	left.add_child(_field_label("Sex"))
	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	left.add_child(sex_row)
	var sex_group := ButtonGroup.new()
	var male := Button.new()
	male.text = "Male"
	male.toggle_mode = true
	male.button_group = sex_group
	male.button_pressed = true
	male.pressed.connect(func() -> void: _sex = "male")
	sex_row.add_child(male)
	var female := Button.new()
	female.text = "Female"
	female.toggle_mode = true
	female.button_group = sex_group
	female.pressed.connect(func() -> void: _sex = "female")
	sex_row.add_child(female)

	left.add_child(_field_label("Outpost name"))
	var outpost_row := HBoxContainer.new()
	outpost_row.add_theme_constant_override("separation", 8)
	left.add_child(outpost_row)
	_outpost_name_field = LineEdit.new()
	_outpost_name_field.text = DEFAULT_OUTPOST
	_outpost_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outpost_row.add_child(_outpost_name_field)
	var reroll := Button.new()
	reroll.text = "Randomize"
	reroll.pressed.connect(_randomize_outpost_name)
	outpost_row.add_child(reroll)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
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

	var randomize_flag := Button.new()
	randomize_flag.text = "Randomize flag"
	randomize_flag.pressed.connect(_randomize_flag)
	flag_controls.add_child(randomize_flag)

	_flag_view.set_value(_flag_value)
	return col


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _flag_color_picker(parent: Node, label_text: String, initial: Color,
		on_pick: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(60, 24)
	picker.color = initial
	picker.color_changed.connect(on_pick)
	row.add_child(picker)
	return picker


func _flag_cycle_row(label_text: String, on_step: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func() -> void: on_step.call(-1))
	row.add_child(prev)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func() -> void: on_step.call(1))
	row.add_child(next)
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
		b.text = "%s — %s" % [String(item["title"]), String(item["desc"])]
		b.button_pressed = String(item["id"]) == _selected_verbosity
		b.pressed.connect(func() -> void: _selected_verbosity = String(item["id"]))
		col.add_child(b)
	return col
