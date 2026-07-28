class_name ModalDialog
extends CanvasLayer

## A modal question built from the shell's own furniture: [UiSkin]'s parchment frame over a dark
## scrim, answered with [SkinnedButton] plates.
##
## Replaces [ConfirmationDialog] rather than restyling one. An [AcceptDialog] is a [Window] — it
## brings its own panel, its own internal buttons and, when the platform embeds it, its own idea of
## what a modal looks like. Reaching every one of those through theme overrides to arrive at *this*
## picture is more work than drawing it, and it would leave the frame and the plates as something
## only the dialog knows how to build. Here they are the same [method UiSkin.frame_style] and
## [SkinnedButton] the main menu uses, so a second dialog costs one [method create] call.
##
## A [CanvasLayer] at [constant LAYER], not a [Control]: it has to cover whatever is on screen no
## matter which node it was added to, and layer order settles that without depending on the tree.

signal confirmed
signal cancelled

## Well above anything a screen builds, so nothing can be laid over the modal.
const LAYER := 100

## The frame tracks the viewport like the main menu's does, between these bounds.
const MARGIN := 40.0
const MAX_WIDTH := 620.0
const MESSAGE_FONT_SIZE := 28

## The question is given room to sit in rather than being packed against the buttons — a modal that
## hugs its own text reads as a tooltip.
const MESSAGE_MIN_HEIGHT := 120.0
const COLUMN_SEPARATION := 28

## The answers are pushed to opposite edges with the gap between them, so neither is the one your
## thumb lands on by accident. Narrower than the frame on purpose: a full-width pair reads as a
## single bar split in two.
const ANSWER_WIDTH := 200.0

## What the dialog asks. Assigning after construction re-labels it.
var message: String = "":
	set(value):
		message = value
		if _message_label != null:
			_message_label.text = value

var _message_label: Label = null
var _column: VBoxContainer = null
var _plate_inset := 0.0


## Build a dialog. [param confirm_variant] and [param cancel_variant] default to the app's colour
## roles — green answers, red backs out — and are arguments rather than constants so a dialog whose
## confirm *is* the destructive choice can say so.
static func create(text: String, confirm_text: String = "Yes", cancel_text: String = "No",
		confirm_variant: UiSkin.Variant = UiSkin.GREEN,
		cancel_variant: UiSkin.Variant = UiSkin.RED) -> ModalDialog:
	var dialog := ModalDialog.new()
	dialog.layer = LAYER
	dialog._build(text, confirm_text, cancel_text, confirm_variant, cancel_variant)
	dialog.message = text
	return dialog


func _build(text: String, confirm_text: String, cancel_text: String,
		confirm_variant: UiSkin.Variant, cancel_variant: UiSkin.Variant) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# The scrim both dims and *blocks*: a modal whose backdrop lets clicks reach the screen behind is
	# not modal. STOP rather than IGNORE is the whole difference.
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

	_message_label = Label.new()
	_message_label.text = text
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(0, MESSAGE_MIN_HEIGHT)
	_message_label.add_theme_font_size_override("font_size", MESSAGE_FONT_SIZE)
	# Ink, not the shell's near-white: the frame's middle is pale parchment.
	_message_label.add_theme_color_override("font_color", UiSkin.INK)
	_column.add_child(_message_label)

	# No separation constant here — the spacer between the two answers *is* the gap, and it expands so
	# the pair sits against the frame's edges however wide the dialog ends up.
	var answers := HBoxContainer.new()
	answers.add_theme_constant_override("separation", 0)
	_column.add_child(answers)

	var cancel := _answer(cancel_text, cancel_variant, _on_cancel)
	answers.add_child(cancel)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	answers.add_child(gap)

	answers.add_child(_answer(confirm_text, confirm_variant, _on_confirm))

	hide()


## One answer plate, fixed width rather than expanding, so the gap between the pair is what grows.
func _answer(text: String, variant: UiSkin.Variant, on_press: Callable) -> SkinnedButton:
	var button := SkinnedButton.create(text, variant, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	button.custom_minimum_size.x = ANSWER_WIDTH
	button.pressed.connect(on_press)
	return button


## The viewport is only reachable once this is in the tree, and [method create] runs before that —
## so the sizing and the resize hook wait for here rather than being done at build time.
func _ready() -> void:
	_size_to_viewport()
	get_tree().root.size_changed.connect(_size_to_viewport)


func _size_to_viewport() -> void:
	if _column == null or not is_inside_tree():
		return
	var available := get_tree().root.get_visible_rect().size.x - MARGIN * 2.0 - _plate_inset
	_column.custom_minimum_size.x = clampf(available, 0.0, MAX_WIDTH)


func open() -> void:
	_size_to_viewport()
	show()


func close() -> void:
	hide()


func _on_confirm() -> void:
	close()
	confirmed.emit()


func _on_cancel() -> void:
	close()
	cancelled.emit()
