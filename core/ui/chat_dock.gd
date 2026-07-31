class_name ChatDock
extends PanelContainer

## The conversation, as **one object** — a board carrying the chronicle sheet and the line the player
## writes on, whether it is showing a single row or the whole exchange.
##
## It replaces two controls that only looked like one thing by accident: a panel floating over the
## map and, below it, an input bar spanning the window under the rail. Two frames, two materials, two
## edges that never lined up. Everything here lives in a single [StyleBoxTexture]
## ([method UiSkin.chat_frame_style]) and the collapsed state is that same board with only its bottom
## section on show, so opening the conversation grows the board rather than putting a second one on
## screen.
##
## **[HudShell] owns the geometry, this owns the contents.** The shell decides where the board sits
## and how tall it is at each state (that is where the animation and the desktop insets live); this
## says what is inside it and which parts belong to the collapsed strip. [member collapsed_height] is
## the one number that crosses between them.
##
## The material is deliberately not the parchment the rest of the game's chrome wears. The chrome
## frames the window; this is an object lying on the map.

## The header's close control was pressed — the same signal [HudPanel] emits, so a caller wires the
## conversation up exactly as it wires up a page.
signal dismissed

## The player wants to write: a press anywhere on the collapsed board that was not a control.
signal engaged

## Filled by the caller (`game_screen.gd`): the chronicle, and the row of controls under it.
var body: VBoxContainer
var input_row: HBoxContainer

## How tall the board is with only its bottom section showing — the input row, plus the board's own
## edge and padding. Read by [HudShell] to lay the collapsed state out. Measured from the real
## controls rather than guessed at, so a taller field or a bigger send plate cannot leave the strip
## clipping its own contents.
var collapsed_height: float:
	get:
		var content: float = maxf(input_row.get_combined_minimum_size().y, UiSkin.CHAT_SEND_SIZE)
		return content + _frame_padding * 2.0 + _pending_height()

var _header: Control
var _title_label: Label
var _sheet: PanelContainer
var _frame_padding := 0.0
var _pending: Control = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var style := UiSkin.chat_frame_style()
	_frame_padding = style.content_margin_top
	add_theme_stylebox_override("panel", style)
	# A press on the board itself — the dark surround, not a control on it — is a press on the
	# conversation. It is the largest target the collapsed strip has, and on a phone it is the one a
	# thumb finds without aiming.
	gui_input.connect(_on_board_input)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiSkin.CHAT_FRAME_PADDING)
	add_child(column)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 12)
	column.add_child(_header)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UiSkin.FONT_HEADING)
	# On the board, not on parchment: this is the one caption in the conversation that wants the
	# light ink the dark plates use.
	_title_label.add_theme_color_override("font_color", UiSkin.LABEL)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close"
	UiSkin.apply_input(close)
	close.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	close.custom_minimum_size = Vector2(UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_HEIGHT)
	close.pressed.connect(func() -> void: dismissed.emit())
	_header.add_child(close)

	# The chronicle sheet. It expands into whatever the board is given, so the board's height is the
	# only thing that decides how much of the conversation is on show.
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", UiSkin.chat_text_area_style())
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_sheet)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_sheet.add_child(body)

	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", UiSkin.CHAT_FRAME_PADDING)
	column.add_child(input_row)

	set_expanded(false)


func set_title(text: String) -> void:
	_title_label.text = text


## Everything above the input row belongs to the expanded board. Hidden rather than faded, so a
## collapsed strip reports the height of its own contents and nothing more.
func set_expanded(expanded: bool) -> void:
	_header.visible = expanded
	_sheet.visible = expanded


## A row the caller wants kept on the collapsed strip — the pending question, which must stay
## answerable whether or not the conversation is open (ux_plan.md's reason for putting it in the dock
## in the first place). It is counted into [member collapsed_height] while it is visible.
func set_pending_row(row: Control) -> void:
	_pending = row
	input_row.get_parent().add_child(row)
	input_row.get_parent().move_child(row, input_row.get_index())


func _pending_height() -> float:
	if _pending == null or not _pending.visible:
		return 0.0
	return _pending.get_combined_minimum_size().y + UiSkin.CHAT_FRAME_PADDING


func _on_board_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		engaged.emit()
