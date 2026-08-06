class_name SelectionDock
extends PanelContainer

## What the player has picked off the map, as a band across the bottom of the stage: a picture of the
## thing, its name and who holds it, and — later — the actions that can be taken on it.
##
## **It is cut from the conversation's own parchment** ([method UiSkin.chat_frame_style]) and sits
## flush on top of the board, with no gap between them. That is not only a matter of matching: the
## chat texture deliberately has no bottom edge (see [constant UiSkin.CHAT_FRAME_SLICE_BOTTOM] — it is
## drawn to run off the bottom of the screen), so a band floating clear of the board would show its
## own unfinished foot. Resting on the conversation, the two read as one continuous surface and the
## missing rail is never anywhere the player can see it.
##
## **[HudShell] owns where it goes, this owns what is on it** — the same division [ChatDock]
## documents, and for the same reason: the shell has to fit this band, the conversation and a page
## into one stage, and it cannot do that if each of them also has an opinion about it.

## The ✕ was pressed. Named to match [ChatDock] and [HudPanel], so a caller wires all three up alike.
signal dismissed

## Where the interactive menu goes — the actions available on whatever is selected. **Deliberately
## empty**: what a player can do to a farm is a system that does not exist yet, and a band of
## invented buttons would claim otherwise. The region is real so that arriving content has somewhere
## to go without the band's geometry changing under it.
var actions: HBoxContainer

## How much of the band the picture and its captions take, leaving the rest to [member actions]. The
## picture is square and the band is short, so this follows from the height rather than being chosen.
const PORTRAIT_SIZE := 74.0

## The band's height, and why it is fixed rather than derived from its contents: it is a strip the
## conversation and the page above it both have to make room for, and one that changed height with the
## length of a name would move the whole stage every time the player clicked something else.
const BAND_HEIGHT := 116.0

## Between the picture's column and the actions, and how far the rule sits from each.
const COLUMN_SEPARATION := 18

var _portrait: TextureRect
var _title_label: Label
var _owner_label: Label
var _close: Button


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_theme_stylebox_override("panel", UiSkin.chat_frame_style())
	custom_minimum_size.y = BAND_HEIGHT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COLUMN_SEPARATION)
	add_child(row)

	# The picture and its captions are one column: the art, the thing's name under it, and who holds
	# it under that. Mounted in the same thin frame the conversation's event artwork uses, so a slot
	# with nothing in it yet reads as a mount rather than as a hole.
	var portrait_frame := PanelContainer.new()
	portrait_frame.add_theme_stylebox_override("panel", UiSkin.thin_frame_style(4.0))
	portrait_frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# The art is a terrain tile or a building sprite drawn for the map, not for a frame — without this
	# a wide field would paint over its own moulding.
	_portrait.clip_contents = true
	portrait_frame.add_child(_portrait)

	var captions := VBoxContainer.new()
	captions.add_theme_constant_override("separation", 2)
	captions.alignment = BoxContainer.ALIGNMENT_CENTER
	captions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(captions)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	_title_label.add_theme_color_override("font_color", UiSkin.INK)
	captions.add_child(_title_label)
	_owner_label = Label.new()
	_owner_label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_owner_label.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	captions.add_child(_owner_label)

	var rule := VSeparator.new()
	rule.add_theme_stylebox_override("separator", UiSkin.separator_style())
	row.add_child(rule)

	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	# Top-aligned rather than centred on the band: it closes the band, it is not one of the actions
	# inside it, and the conversation below puts its own ✕ in the same corner.
	_close = Button.new()
	_close.text = "✕"
	_close.tooltip_text = "Close"
	UiSkin.apply_input(_close)
	_close.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	_close.custom_minimum_size = Vector2(UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_HEIGHT)
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.pressed.connect(func() -> void: dismissed.emit())
	row.add_child(_close)


## Show what has been selected. [param owner] is empty for anything nobody holds — bare ground — and
## the line is left blank rather than filled with a word standing in for "no one".
func show_selection(title: String, owner: String, art: Texture2D) -> void:
	_title_label.text = title
	_owner_label.text = owner
	_owner_label.visible = not owner.is_empty()
	_portrait.texture = art


## Empty the action area. Every route into the band fills it from scratch — a selection puts Build
## there, choosing a tool puts Confirm and Cancel there — so nothing is ever left over from the last
## thing the player had selected.
func clear_actions() -> void:
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()


## Hide the ✕ while the band is a build bar. Cancel is the way out of building, and two controls that
## both abandon the plan — one of them the same glyph that means "deselect" everywhere else — is one
## more than the bar can explain.
func set_closable(closable: bool) -> void:
	_close.visible = closable
