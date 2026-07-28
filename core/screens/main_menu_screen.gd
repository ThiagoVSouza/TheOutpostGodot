extends Control

## App-shell main menu (placeholder). Continue / New Game / Load are wired to the real session;
## Settings / Help / News are disabled stubs. The whole shell exists to reach a real game start.

const GAME_SCREEN := "base_game.chat"

## The plate's width: the viewport's, less this margin on each side, capped at [constant
## MENU_MAX_WIDTH]. A fixed width cannot serve both — the portrait viewport is 720 units across and a
## desktop window's is over 2000, so the 280 this used to be read as a cramped strip on a phone and a
## postage stamp on a monitor.
const MENU_MARGIN := 40.0
const MENU_MAX_WIDTH := 520.0

const TITLE_FONT_SIZE := 44

var _col: VBoxContainer = null
## The horizontal padding [method ShellPalette.plate_style] adds around the column, which the plate's
## total width has to stay inside.
var _plate_inset := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	# Normally already playing from the splash and so a no-op; this is what brings the theme back
	# when the menu is reached from a game, where the music was stopped.
	Kernel.audio.play_music(AppShell.SHELL_MUSIC)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The flat colour stays underneath: the art is cropped to cover, and on an aspect it cannot fill
	# this is what shows rather than nothing.
	ShellPalette.paint(self)
	ShellPalette.paint_art(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# The menu sits on its own frame rather than straight on the painting. Now that the art carries no
	# scrim, the frame is the only thing holding contrast where the art is busiest (the lit farmhouse,
	# the stonework): a *disabled* item is low-contrast by design, and over that midground it
	# disappears entirely without one.
	# Two containers, not one: the outer draws the frame's drop shadow (a StyleBoxTexture cannot), the
	# inner draws the frame itself over it.
	var shadow := PanelContainer.new()
	shadow.add_theme_stylebox_override("panel", UiSkin.frame_shadow_style())
	center.add_child(shadow)

	var plate := PanelContainer.new()
	var style := UiSkin.frame_style()
	_plate_inset = style.content_margin_left + style.content_margin_right
	plate.add_theme_stylebox_override("panel", style)
	shadow.add_child(plate)

	_col = VBoxContainer.new()
	var col := _col
	col.add_theme_constant_override("separation", 12)
	plate.add_child(col)
	_size_menu()
	# `size` is still zero here — the screen is built before layout runs — so the width is taken from
	# the viewport, and re-taken whenever the window changes.
	get_window().size_changed.connect(_size_menu)

	var title := Label.new()
	title.text = "THE OUTPOST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	# The frame's middle is pale parchment, so the shell's near-white title would be unreadable on it.
	title.add_theme_color_override("font_color", UiSkin.INK)
	col.add_child(title)

	col.add_child(_spacer(20))

	# Exactly one blue plate on the screen, and it is whichever button carries on playing: Continue
	# when there is a game to return to, New Game when there is not. Marking both would say "these two
	# matter equally", which is the opposite of what the colour is for.
	var can_continue := Kernel.session.workspace().exists() or not Kernel.saves.slots().is_empty()
	col.add_child(_menu_button("Continue", _on_continue, can_continue,
		UiSkin.BLUE if can_continue else UiSkin.BROWN))
	col.add_child(_menu_button("New Game", _on_new_game, true,
		UiSkin.BROWN if can_continue else UiSkin.BLUE))
	col.add_child(_menu_button("Load Game", _on_load, not Kernel.saves.slots().is_empty()))
	col.add_child(_menu_button("Settings", _on_settings, true))
	col.add_child(_menu_button("Help", Callable(), false))
	col.add_child(_menu_button("News", Callable(), false))
	col.add_child(_spacer(8))
	col.add_child(_menu_button("Exit Game", _on_exit, true))


## Widen the column to the viewport, up to [constant MENU_MAX_WIDTH]. The plate wraps whatever the
## column asks for, so this is the one number that decides how much of the screen the menu takes.
func _size_menu() -> void:
	if _col == null:
		return
	var available := get_viewport_rect().size.x - MENU_MARGIN * 2.0 - _plate_inset
	_col.custom_minimum_size.x = clampf(available, 0.0, MENU_MAX_WIDTH)


func _menu_button(text: String, on_press: Callable, enabled: bool,
		variant: UiSkin.Variant = UiSkin.BROWN) -> SkinnedButton:
	var b := SkinnedButton.create(text, variant, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	b.set_disabled(not enabled)
	if enabled and on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _on_continue() -> void:
	var resumed: Dictionary = Kernel.session.continue_or_start()
	if bool(resumed["ok"]) and bool(resumed["continued"]):
		Kernel.router.goto(GAME_SCREEN)
	else:
		Kernel.log.warn("MainMenu", "Continue found nothing to resume (%s)" % resumed.get("source", ""))


func _on_new_game() -> void:
	Kernel.router.goto("core.new_game")


func _on_load() -> void:
	Kernel.router.goto("core.load")


## Tell the settings screen where Back goes, rather than letting it assume: the same screen is meant
## to be reachable from inside a game later, and the router keeps no history to infer it from.
func _on_settings() -> void:
	Kernel.router.goto("core.settings", {"back": "core.main_menu"})


func _on_exit() -> void:
	Kernel.request_exit()
