class_name FlagThumbnail
extends Button

## One square pattern/emblem choice. It renders the source PNG as an alpha mask through
## [constant SHADER], rather than modulating its RGB, and leaves the flagpole/effect art out so the
## option itself fills the cell. The special `none` option is a labelled empty cell.

const SHADER := preload("res://modules/base_game/ui/flag_thumbnail.gdshader")
const PATTERN_DIR := "res://modules/base_game/assets/flags/patterns/"
const EMBLEM_DIR := "res://modules/base_game/assets/flags/emblems/"
const CELL_SIZE := 72.0
const SAMPLE_INSET := 7.0

var option_id := FlagValue.NONE
var kind := "pattern"
var base_color := Color.WHITE
var fill_color := Color.BLACK

var _sample: ColorRect = null


func setup(option_kind: String, id: String, background: Color, foreground: Color,
		group: ButtonGroup, selected: bool) -> void:
	kind = option_kind
	option_id = id
	base_color = background
	fill_color = foreground
	toggle_mode = true
	button_group = group
	custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	tooltip_text = "None" if id == FlagValue.NONE else _display_name(id)
	UiSkin.apply_thumbnail(self, selected)
	button_pressed = selected
	toggled.connect(func(on: bool) -> void: UiSkin.apply_thumbnail(self, on))
	if id == FlagValue.NONE:
		_add_none_label()
	else:
		_add_sample()


func set_colors(background: Color, foreground: Color) -> void:
	base_color = background
	fill_color = foreground
	if _sample == null:
		return
	var shader_material := _sample.material as ShaderMaterial
	shader_material.set_shader_parameter("base_color", base_color)
	shader_material.set_shader_parameter("fill_color", fill_color)


func _add_sample() -> void:
	_sample = ColorRect.new()
	_sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sample.offset_left = SAMPLE_INSET
	_sample.offset_top = SAMPLE_INSET
	_sample.offset_right = -SAMPLE_INSET
	_sample.offset_bottom = -SAMPLE_INSET
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter("mask_tex", load(_asset_path()))
	shader_material.set_shader_parameter("base_color", base_color)
	shader_material.set_shader_parameter("fill_color", fill_color)
	_sample.material = shader_material
	add_child(_sample)


func _add_none_label() -> void:
	var label := Label.new()
	label.text = "None"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	label.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	add_child(label)


func _asset_path() -> String:
	var directory := PATTERN_DIR if kind == "pattern" else EMBLEM_DIR
	return directory + option_id + ".png"


func _display_name(id: String) -> String:
	return ("Pattern " if kind == "pattern" else "Emblem ") + id.right(2)
