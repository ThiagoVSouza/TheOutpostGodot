class_name PickerModal
extends CanvasLayer

## A themed modal host for a focused set of choices: a title, scrollable caller-owned content, and
## one Done action. Unlike [ModalDialog], it is not a yes/no question and applies choices live while
## it is open.

signal closed

const LAYER := 100
const MARGIN := 40.0
const MAX_WIDTH := 820.0
const MAX_CONTENT_HEIGHT := 760.0
const COLUMN_SEPARATION := 18
const TOUCH_SCROLL_DEADZONE := 16

var _column: VBoxContainer = null
var _scroll: ScrollContainer = null
var _plate_inset := 0.0
var _preferred_content_height := MAX_CONTENT_HEIGHT


static func create(title: String, content: Control,
		preferred_content_height: float = MAX_CONTENT_HEIGHT) -> PickerModal:
	var modal := PickerModal.new()
	modal.layer = LAYER
	modal._preferred_content_height = preferred_content_height
	modal._build(title, content)
	return modal


func _build(title: String, content: Control) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var scrim := ColorRect.new()
	scrim.color = UiSkin.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var shadow := PanelContainer.new()
	shadow.add_theme_stylebox_override("panel", UiSkin.frame_shadow_style())
	center.add_child(shadow)

	var plate := PanelContainer.new()
	var style := UiSkin.frame_style()
	_plate_inset = style.content_margin_left + style.content_margin_right
	plate.add_theme_stylebox_override("panel", style)
	shadow.add_child(plate)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", COLUMN_SEPARATION)
	plate.add_child(_column)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", UiSkin.FONT_HEADING)
	heading.add_theme_color_override("font_color", UiSkin.INK)
	_column.add_child(heading)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A small deadzone keeps a finger wobble as a tap, while child controls with PASS can hand a
	# deliberate drag to this scroll container. This matches CardScroll's proven phone behavior.
	_scroll.scroll_deadzone = TOUCH_SCROLL_DEADZONE
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSkin.apply_scroll_container(_scroll)
	_column.add_child(_scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)

	var actions := HBoxContainer.new()
	_column.add_child(actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(spacer)
	var done := SkinnedButton.create("Done", UiSkin.BLUE, UiSkin.BUTTON_HEIGHT,
		UiSkin.BUTTON_FONT_SIZE)
	done.custom_minimum_size.x = ModalDialog.ANSWER_WIDTH
	done.pressed.connect(close)
	actions.add_child(done)

	hide()


func _ready() -> void:
	_size_to_viewport()
	get_tree().root.size_changed.connect(_size_to_viewport)


func _size_to_viewport() -> void:
	if _column == null or not is_inside_tree():
		return
	var viewport_size := get_tree().root.get_visible_rect().size
	_column.custom_minimum_size.x = clampf(
		viewport_size.x - MARGIN * 2.0 - _plate_inset, 0.0, MAX_WIDTH)
	_scroll.custom_minimum_size.y = minf(_preferred_content_height,
		maxf(180.0, viewport_size.y - MARGIN * 2.0 - 250.0))


func open() -> void:
	_size_to_viewport()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
