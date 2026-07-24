extends Control

## App-shell loading screen (placeholder). Generic and reused: `on_enter({next, params})` says where
## to go once "loading" finishes. Today it is cosmetic — a short filling bar — but this is where real
## asset loading and AI-model warm-up (D8 prefix-cache ingest) will hook in. If no `next` is given it
## falls back to the main menu.

const FILL_SECONDS := 0.8

var _next: String = "core.main_menu"
var _params: Dictionary = {}
var _bar: ProgressBar = null


func on_enter(params: Dictionary) -> void:
	_next = String(params.get("next", _next))
	_params = params.get("params", {}) as Dictionary


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	var tween := create_tween()
	tween.tween_property(_bar, "value", 100.0, FILL_SECONDS)
	tween.tween_callback(func() -> void: Kernel.router.goto(_next, _params))


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(col)

	var label := Label.new()
	label.text = "Loading…"
	col.add_child(label)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 16)
	col.add_child(_bar)
