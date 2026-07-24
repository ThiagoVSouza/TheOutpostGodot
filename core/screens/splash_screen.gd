extends Control

## App-shell splash (placeholder). Shows the company logo for a beat, then advances to the loading
## screen. Any key or click skips ahead. Pure placeholder UI — a real logo/animation lands later.

const HOLD_SECONDS := 1.5

var _advanced := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_advance)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_input)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var label := Label.new()
	label.text = "PANGEA GAMES"
	label.add_theme_font_size_override("font_size", 48)
	center.add_child(label)


func _on_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_advance()


func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	Kernel.router.goto("core.loading", {"next": "core.main_menu"})
