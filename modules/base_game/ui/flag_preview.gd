extends Control

## Dev preview for the reusable [FlagView]: a large live flag plus controls to randomise it and to
## cycle patterns/emblems, so the compositing can be eyeballed in the running engine. Not part of the
## game flow — run it directly:
##   Godot --path . res://modules/base_game/ui/flag_preview.tscn

const PALETTE := ["#b62a2a", "#2f5fc0", "#2fa354", "#f3c43f", "#000000", "#f7f7f2", "#8b5a2b", "#a03291"]
const PATTERN_COUNT := 14
const EMBLEM_COUNT := 13

var _flag: FlagView
var _value := FlagValue.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.12, 0.14)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	add_child(row)

	var frame := CenterContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(frame)
	_flag = FlagView.new()
	_flag.custom_minimum_size = Vector2(320, 320 * 1007.0 / 478.0)
	frame.add_child(_flag)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.custom_minimum_size = Vector2(220, 0)
	row.add_child(controls)
	_add_button(controls, "Randomize", _randomize)
	_add_button(controls, "Next pattern", func() -> void: _cycle_pattern(1))
	_add_button(controls, "Next emblem", func() -> void: _cycle_emblem(1))

	_value.texture = "pattern03"
	_value.emblem = "emblem01"
	_flag.set_value(_value)


func _add_button(parent: Node, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)


func _randomize() -> void:
	_value.shape_color = Color.html(PALETTE[randi() % PALETTE.size()])
	_value.texture_color = Color.html(PALETTE[randi() % PALETTE.size()])
	_value.emblem_color = Color.html(PALETTE[randi() % PALETTE.size()])
	_value.texture = "pattern%02d" % (1 + randi() % PATTERN_COUNT)
	_value.emblem = "emblem%02d" % (1 + randi() % EMBLEM_COUNT)
	_flag.set_value(_value)


func _cycle_pattern(step: int) -> void:
	var n := int(_value.texture.substr(7)) if _value.has_pattern() else 0
	n = wrapi(n + step, 0, PATTERN_COUNT + 1)
	_value.texture = FlagValue.NONE if n == 0 else "pattern%02d" % n
	_flag.set_value(_value)


func _cycle_emblem(step: int) -> void:
	var n := int(_value.emblem.substr(6)) if _value.has_emblem() else 0
	n = wrapi(n + step, 0, EMBLEM_COUNT + 1)
	_value.emblem = FlagValue.NONE if n == 0 else "emblem%02d" % n
	_flag.set_value(_value)
