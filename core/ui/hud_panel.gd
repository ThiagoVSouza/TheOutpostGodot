class_name HudPanel
extends Control

## The "Page Title + close" shape (ux_plan.md §1.2): states 2 (expanded chat) and 3 (a page) share
## this geometry exactly, which the wireframes' own repetition calls out as their strongest
## structural hint (§1.2's closing note). One control, not two near-duplicates — a page sets
## [method set_title]; the chat dock leaves it empty. [member body] is where a caller adds its own
## content; everything else here is the shared chrome around it.
##
## Mechanism only, like [HudShell] beside it: this file does not know what a page or a conversation
## is, only how one is framed.

signal dismissed  ## the header's close button was pressed

var body: VBoxContainer

var _title_label: Label


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Code-built, so at `_ready` this has whatever rect its not-yet-parented state left it with —
	# `_and_offsets_` fills continuously as the parent resizes rather than baking in that rect
	# (the trap `map_overlay.gd` documented and ux_plan.md §7 carries forward).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ShellPalette.paint(self)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	var header_margin := MarginContainer.new()
	for side in ["left", "top", "right"]:
		header_margin.add_theme_constant_override("margin_" + side, 16)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	outer.add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close := Button.new()
	close.text = "✕"  # ✕
	close.tooltip_text = "Close"
	close.pressed.connect(func() -> void: dismissed.emit())
	header.add_child(close)

	outer.add_child(HSeparator.new())

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 16)
	body_margin.add_theme_constant_override("margin_top", 12)
	outer.add_child(body_margin)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body_margin.add_child(body)


func set_title(text: String) -> void:
	_title_label.text = text
