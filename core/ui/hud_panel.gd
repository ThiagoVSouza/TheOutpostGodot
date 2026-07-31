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

	# **A page in here is the same object as a page in the wizard.** It was a flat blue-slate surface
	# from [ShellPalette] while every screen outside the game was painted parchment, which made the
	# game look like a different product from its own menus. The shadow is a sibling plate behind the
	# frame, exactly as the wizard's page builds it: a [StyleBoxTexture] cannot cast one.
	var shadow := PanelContainer.new()
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shadow.add_theme_stylebox_override("panel", UiSkin.frame_shadow_style())
	add_child(shadow)

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiSkin.frame_style())
	shadow.add_child(plate)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	plate.add_child(outer)

	# The frame's own texture carries the outer padding, so these are only the gaps *between* the
	# header, its rule and the body.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	outer.add_child(header)

	_title_label = Label.new()
	# Ink, not [method UiSkin.label_style]: that paints the cream caption a dark button plate needs,
	# and cream on parchment is barely there.
	_title_label.add_theme_font_size_override("font_size", UiSkin.FONT_HEADING)
	_title_label.add_theme_color_override("font_color", UiSkin.INK)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close"
	UiSkin.apply_input(close)
	close.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	close.custom_minimum_size = Vector2(UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_HEIGHT)
	close.pressed.connect(func() -> void: dismissed.emit())
	header.add_child(close)

	var rule_margin := MarginContainer.new()
	rule_margin.add_theme_constant_override("margin_top", 10)
	rule_margin.add_theme_constant_override("margin_bottom", 10)
	outer.add_child(rule_margin)
	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", UiSkin.separator_style())
	rule_margin.add_child(rule)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	outer.add_child(body)


func set_title(text: String) -> void:
	_title_label.text = text
