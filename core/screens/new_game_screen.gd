extends Control

## App-shell new-game screen (placeholder wizard). One field — the hero's name — then Start seeds a
## fresh game and enters it. The module-pick screen and the full module-declared multi-step wizard
## are future; this is the minimum to reach a real, seeded game start.

const GAME_SCREEN := "base_game.chat"
const DEFAULT_HERO := "Marcus"

var _name_field: LineEdit = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(320, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "New Game"
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	var prompt := Label.new()
	prompt.text = "Name your hero:"
	col.add_child(prompt)

	_name_field = LineEdit.new()
	_name_field.text = DEFAULT_HERO
	_name_field.placeholder_text = DEFAULT_HERO
	_name_field.custom_minimum_size = Vector2(0, 36)
	_name_field.text_submitted.connect(func(_t: String) -> void: _on_start())
	col.add_child(_name_field)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 40)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: Kernel.router.goto("core.main_menu"))
	row.add_child(back)

	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(0, 40)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_on_start)
	row.add_child(start)


func _on_start() -> void:
	var hero_name := _name_field.text.strip_edges()
	if hero_name.is_empty():
		hero_name = DEFAULT_HERO
	Kernel.session.begin_new_game({"hero_name": hero_name})
	Kernel.router.goto("core.loading", {"next": GAME_SCREEN})
