class_name OutpostTheme
extends RefCounted

## The real [Theme] `ShellPalette`'s own docstring named as its replacement (M8 Phase 2,
## ux_plan.md §2.4/§Phase2): every default Godot control — buttons, labels, line edits, dialogs —
## picks this up automatically once it is set as the root viewport's theme, so a screen that adds
## a plain `Button.new()` gets the game's palette for free instead of stock light-on-gray Godot
## chrome. This is what "the app stops being two visual languages" means, and it is what themes
## the exit-confirm dialog (`GameKernel._ensure_exit_confirm`) — a bare `ConfirmationDialog.new()`
## with no per-node styling, so it only looks right if the *default* theme already does.
##
## `ShellPalette` is not replaced outright: its background colors, the art-crop math and
## `plate_style()` are still what a handful of screens reach for directly. This governs the
## controls Godot itself draws (buttons, fields, dialogs); Phase 2 layers it in alongside
## `ShellPalette` rather than unwinding every call site in one pass.

const BACKGROUND := ShellPalette.BACKGROUND
const SURFACE := Color(0.15, 0.18, 0.25)
const SURFACE_HOVER := Color(0.23, 0.29, 0.39)
const SURFACE_PRESSED := Color(0.34, 0.27, 0.15)
const SURFACE_DISABLED := Color(0.10, 0.12, 0.17)
const FIELD := Color(0.07, 0.09, 0.14)
const BORDER := Color(0.48, 0.59, 0.78, 0.36)

const TEXT := Color(0.93, 0.93, 0.95)
const TEXT_MUTED := Color(1, 1, 1, 0.55)
const TEXT_DISABLED := Color(1, 1, 1, 0.35)

## The one warm accent, already in use for narrated prose (`chat_screen`/`game_screen`'s
## `[color=wheat]`) and the settings screen's `planned` rows — reused here rather than a second
## accent the palette never agreed to.
const ACCENT := Color(0.95, 0.75, 0.35)

const CORNER_RADIUS := 4
const BUTTON_MARGIN_H := 14
const BUTTON_MARGIN_V := 8


static func build() -> Theme:
	var theme := Theme.new()

	theme.set_color("font_color", "Label", TEXT)

	_style_button(theme, "Button")
	_style_button(theme, "CheckButton")
	_style_button(theme, "OptionButton")

	_style_field(theme, "LineEdit")
	_style_field(theme, "TextEdit")

	theme.set_stylebox("panel", "Panel", _box(SURFACE, BORDER, CORNER_RADIUS * 2))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, CORNER_RADIUS * 2))
	# AcceptDialog/ConfirmationDialog draw their own body through this type — this is the line
	# that themes the exit-confirm dialog (Phase 2's "done when").
	theme.set_stylebox("panel", "AcceptDialog", _box(SURFACE, BORDER, CORNER_RADIUS * 2))
	theme.set_color("font_color", "AcceptDialog", TEXT)

	var tab_panel := _box(SURFACE, BORDER)
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_stylebox("tab_selected", "TabContainer", _box(SURFACE_HOVER, BORDER))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(BACKGROUND, Color(0, 0, 0, 0)))
	theme.set_color("font_selected_color", "TabContainer", TEXT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)

	theme.set_stylebox("separator", "HSeparator", _separator())
	theme.set_stylebox("separator", "VSeparator", _separator())

	return theme


static func _style_button(theme: Theme, type_name: String) -> void:
	theme.set_stylebox("normal", type_name, _box(SURFACE, BORDER))
	theme.set_stylebox("hover", type_name, _box(SURFACE_HOVER, BORDER))
	theme.set_stylebox("pressed", type_name, _box(SURFACE_PRESSED, ACCENT))
	theme.set_stylebox("disabled", type_name, _box(SURFACE_DISABLED, Color(0, 0, 0, 0)))
	theme.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), ACCENT))
	theme.set_color("font_color", type_name, TEXT)
	theme.set_color("font_hover_color", type_name, TEXT)
	theme.set_color("font_pressed_color", type_name, ACCENT)
	theme.set_color("font_disabled_color", type_name, TEXT_DISABLED)
	theme.set_color("font_focus_color", type_name, TEXT)


static func _style_field(theme: Theme, type_name: String) -> void:
	theme.set_stylebox("normal", type_name, _box(FIELD, BORDER))
	theme.set_stylebox("focus", type_name, _box(FIELD, ACCENT))
	theme.set_stylebox("read_only", type_name, _box(SURFACE_DISABLED, Color(0, 0, 0, 0)))
	theme.set_color("font_color", type_name, TEXT)
	theme.set_color("font_placeholder_color", type_name, TEXT_MUTED)
	theme.set_color("font_selected_color", type_name, BACKGROUND)
	theme.set_color("selection_color", type_name, ACCENT)


static func _box(bg: Color, border: Color, radius: int = CORNER_RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = BUTTON_MARGIN_H
	style.content_margin_right = BUTTON_MARGIN_H
	style.content_margin_top = BUTTON_MARGIN_V
	style.content_margin_bottom = BUTTON_MARGIN_V
	return style


static func _separator() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BORDER
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style
