class_name HudShell
extends Control

## The persistent chrome the wireframes specify (ux_plan.md §1.1, §3): a top bar, a left rail
## (desktop) or a bottom-right menu button (mobile), a chat dock, and a panel host — around one
## stage where the base layer (the overworld map) always shows. Mechanism only: this file knows
## nothing about domains, coins or chat messages. `modules/base_game/screens/game_screen.gd` fills
## every region and this class only decides where things go and how they move.
##
## **One shell, not two scenes** (ux_plan.md §3): desktop and mobile share every region and differ
## only below [constant MOBILE_BREAKPOINT_WIDTH] — the rail swaps for the menu button, and the split
## (rule 1) becomes mutually-exclusive (rule 5). [method add_rail_action] registers a destination on
## both at once so nothing can be added to one and forgotten on the other.
##
## Pages ([method show_page]/[method hide_page]) and the chat dock's expanded state
## ([method set_chat_expanded]) are two independent regions that can be open at once on desktop —
## rule 1's draggable split (rule 2) — or mutually exclusive on mobile (rule 5). A page is swapped in
## by the caller each time (Phase 5's registry will rebuild one per destination); the panel is
## reparented, never freed, so a caller may show the same instance again later. The chat dock is not
## swappable content, so it gets its own boolean toggle instead of the page API.

## A screen narrower than this re-flows to the mobile layout. Chosen to sit cleanly between this
## project's own two capture widths — 720 (the default portrait viewport, project.godot) and 1280
## (desktop capture, tools/capture_screens.gd) — so neither breakpoint's own screenshot sits on the
## line between the two layouts.
const MOBILE_BREAKPOINT_WIDTH := 900.0

const RAIL_WIDTH := 72.0

## How far the floating mobile menu button sits in from the stage's bottom-right corner.
const MENU_BUTTON_MARGIN := 16
const SPLIT_GUTTER_SIZE := 10.0
const MIN_PANEL_FRACTION := 0.15
const DOCK_BASE_MARGIN := 16

## A page or the chat dock has opened/closed. Lets a caller update its own UI (a chevron's glyph)
## without polling — used by `game_screen.gd` to flip the dock's expand button between ^ and v.
signal chat_expanded_changed(expanded: bool)

## The breakpoint flipped. Nothing in Phase 1 needs this yet, but the world-gate/event-mode work
## (Phase 4) will want to know without re-deriving `size.x` itself.
signal breakpoint_changed(is_mobile: bool)

## Regions callers fill with content. [member base_layer] is always full-rect and always visible —
## the map goes here and is never hidden by anything this class does. [member top_bar] and
## [member dock] are plain containers a caller adds widgets to; [member chat_slot] is where a
## caller permanently parents its one persistent expanded-chat [HudPanel] (see class doc above).
var base_layer: Control
var top_bar: HBoxContainer
var dock: VBoxContainer
var chat_slot: Control

var _rail: VBoxContainer
var _menu_button: Button
var _map_layers_button: Button
var _menu_list: HudPanel
var _menu_list_box: VBoxContainer
var _return_button: Button
var _mobile_menu_open := false

var _dock_margin: MarginContainer
var _last_keyboard_height := 0

var _stage: Control
var _page_slot: Control
var _gutter: Control

var _page_panel: HudPanel = null
var _chat_open := false
var _event_active := false
var _split_fraction := 0.5
var _dragging_split := false
var _open_order: Array = []  ## "page"/"chat", most-recently-opened last — what Esc closes first

var _is_mobile := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_on_resized)
	_on_resized()


func _process(_delta: float) -> void:
	# The on-screen-keyboard handling that used to live in `chat_screen._process` (ux_plan.md
	# Phase 1: "the keyboard handling moves to the dock — it is the fix for a real device bug, not
	# decoration"). Polled rather than event-driven: whether Android resizes the viewport when the
	# keyboard shows or just overlays it is a manifest-level setting this project's non-Gradle
	# export does not expose, so `DisplayServer.virtual_keyboard_get_height()` is the one signal
	# that works either way.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var height := DisplayServer.virtual_keyboard_get_height()
	if height == _last_keyboard_height:
		return
	_last_keyboard_height = height
	# The keyboard's height is in *physical* pixels; this margin is in the stretched logical units
	# `display/window/stretch/mode` puts the UI in (project.godot). Adding the raw number reserves
	# far too much room — measured on an S26 Ultra, ~1.5x — leaving a dead band above the keyboard.
	var window_height := float(DisplayServer.window_get_size().y)
	var scale := get_viewport().get_visible_rect().size.y / window_height if window_height > 0.0 else 1.0
	# The keyboard covers the navigation bar while it is up, so the two insets never add.
	var below := maxi(int(height * scale), SafeArea.bottom(get_viewport()))
	_dock_margin.add_theme_constant_override("margin_bottom", DOCK_BASE_MARGIN + below)


# --- building --------------------------------------------------------------------------------

func _build() -> void:
	# The map only ever *contains*-fits the stage (`OverworldMapView.fit()` never crops), so on an
	# aspect ratio far from the map's own — a tall phone especially — real letterbox bands show on
	# one axis. Without this they fell through to Godot's default gray instead of the shell's dark
	# background; every other screen already paints itself this way (`ShellPalette.paint`).
	ShellPalette.paint(self)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	var top_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		top_margin.add_theme_constant_override("margin_" + side, 12)
	top_margin.add_child(top_bar)
	root.add_child(top_margin)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	_rail = VBoxContainer.new()
	_rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	_rail.add_theme_constant_override("separation", 8)
	body.add_child(_rail)

	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	body.add_child(_stage)

	base_layer = Control.new()
	base_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(base_layer)

	_page_slot = Control.new()
	_stage.add_child(_page_slot)

	chat_slot = Control.new()
	_stage.add_child(chat_slot)

	_gutter = Control.new()
	_gutter.mouse_filter = Control.MOUSE_FILTER_STOP
	_gutter.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_gutter.gui_input.connect(_on_gutter_gui_input)
	_stage.add_child(_gutter)

	_dock_margin = MarginContainer.new()
	for side in ["left", "top", "right"]:
		_dock_margin.add_theme_constant_override("margin_" + side, DOCK_BASE_MARGIN)
	_dock_margin.add_theme_constant_override("margin_bottom",
		DOCK_BASE_MARGIN + SafeArea.bottom(get_viewport()))
	root.add_child(_dock_margin)
	dock = VBoxContainer.new()
	dock.add_theme_constant_override("separation", 6)
	_dock_margin.add_child(dock)

	# The mobile menu button floats over the stage, bottom-right (ux_plan.md §1.1's mobile re-flow).
	# Parented to `_stage` and anchored, NOT to the shell: anchored to the shell it sits at the
	# window's bottom-right corner, which is the *dock's* row — on a real phone it landed squarely
	# on top of the Send button and hid it. The stage stops above the dock, so this floats over the
	# map exactly as drawn. Anchors rather than a computed position so it needs no resize handling.
	_menu_button = Button.new()
	_menu_button.text = "Menu"
	_menu_button.visible = false
	_menu_button.pressed.connect(_toggle_mobile_menu)
	_stage.add_child(_menu_button)
	_menu_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MENU_BUTTON_MARGIN)

	_map_layers_button = Button.new()
	_map_layers_button.text = "Map Layers"
	_stage.add_child(_map_layers_button)
	_map_layers_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MENU_BUTTON_MARGIN)
	# It belongs to the map, not above a page or expanded conversation. Keep it over the base layer
	# but underneath the two overlay slots, so it returns when those panels close instead of covering
	# their content.
	_stage.move_child(_map_layers_button, _stage.get_children().find(_page_slot))

	# Also in the stage, so opening the menu leaves the persistent chrome (top bar, dock) visible —
	# §1.1: "Nothing here is ever replaced — only what sits *inside* it changes."
	_menu_list = HudPanel.new()
	_menu_list.visible = false
	_stage.add_child(_menu_list)
	_menu_list.set_title("Menu")
	_menu_list.dismissed.connect(_close_mobile_menu)
	_menu_list_box = VBoxContainer.new()
	_menu_list_box.add_theme_constant_override("separation", 4)
	_menu_list.body.add_child(_menu_list_box)
	_return_button = Button.new()
	_return_button.text = "Return"
	_return_button.pressed.connect(_close_mobile_menu)
	_menu_list_box.add_child(_return_button)


# --- rail / mobile menu ------------------------------------------------------------------------

## Register a destination reachable from both the desktop rail and the mobile menu list, so nothing
## can be added to one and forgotten on the other. Only "Main Menu" is wired in Phase 1 — the other
## six wireframed destinations are Phase 5's panel registry (ux_plan.md §Phase 5).
func add_rail_action(label: String, on_pressed: Callable) -> void:
	var rail_button := Button.new()
	rail_button.text = label
	rail_button.tooltip_text = label
	rail_button.custom_minimum_size = Vector2(0, 48)
	rail_button.pressed.connect(on_pressed)
	_rail.add_child(rail_button)

	_add_mobile_menu_action(label, on_pressed)


func add_map_layers_action(label: String, on_pressed: Callable) -> void:
	_map_layers_button.text = label
	_map_layers_button.pressed.connect(on_pressed)
	_add_mobile_menu_action(label, on_pressed)


func _add_mobile_menu_action(label: String, on_pressed: Callable) -> void:
	var menu_button := Button.new()
	menu_button.text = label
	menu_button.custom_minimum_size = Vector2(0, 40)
	menu_button.pressed.connect(func() -> void:
		_close_mobile_menu()
		on_pressed.call())
	_menu_list_box.add_child(menu_button)
	_menu_list_box.move_child(_return_button, _menu_list_box.get_child_count() - 1)


func _toggle_mobile_menu() -> void:
	if _mobile_menu_open:
		_close_mobile_menu()
	else:
		_mobile_menu_open = true
		_menu_list.visible = true
		_menu_list.modulate.a = 0.0
		Motion.fade(_menu_list, 1.0, Motion.DURATION_FAST)


func _close_mobile_menu() -> void:
	if not _mobile_menu_open:
		return
	_mobile_menu_open = false
	_menu_list.visible = false


# --- pages ---------------------------------------------------------------------------------

## Show [param panel] in the page region. A caller is expected to have already parented [param panel]
## somewhere in the tree (so its own `_ready` has already built it — see `game_screen.gd`'s
## `_build_menu_panel`, which parents under the screen itself before configuring it, the same trap
## `map_overlay.gd` hit the other way around). Once shown, the panel stays parented under the page
## slot permanently — hiding only toggles visibility — so re-opening it (or a caller's own field
## content, like a trace label's last text) survives between opens. Showing a *different* panel
## while one is already parented in the slot hides the old one rather than leaving both visible.
func show_page(panel: HudPanel) -> void:
	if _event_active:
		return
	if _page_panel == panel:
		return
	if _page_panel != null and _page_panel.get_parent() == _page_slot:
		_page_panel.visible = false
	_page_panel = panel
	if not panel.dismissed.is_connected(hide_page):
		panel.dismissed.connect(hide_page)
	if panel.get_parent() != _page_slot:
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		_page_slot.add_child(panel)
	panel.visible = true
	panel.modulate.a = 0.0
	Motion.fade(panel, 1.0, Motion.DURATION_FAST)
	_touch_order("page")
	if _is_mobile:
		set_chat_expanded(false)
	_relayout_stage()


func hide_page() -> void:
	if _page_panel == null:
		return
	_page_panel = null
	_open_order.erase("page")
	_relayout_stage()


func is_page_open() -> bool:
	return _page_panel != null


# --- chat dock -------------------------------------------------------------------------------

## Expand or collapse the chat dock's message area (state 1 <-> state 2, ux_plan.md §1.2). The
## panel itself is the caller's own persistent [HudPanel], permanently parented under
## [member chat_slot] — this only toggles whether that region is part of the stage's layout.
func set_chat_expanded(expanded: bool) -> void:
	if _event_active and not expanded:
		return
	if expanded == _chat_open:
		return
	_chat_open = expanded
	if expanded:
		_touch_order("chat")
		if _is_mobile:
			hide_page()
	else:
		_open_order.erase("chat")
	_relayout_stage()
	chat_expanded_changed.emit(_chat_open)


func is_chat_expanded() -> bool:
	return _chat_open


## Event mode is the UI's view of the kernel world gate. It forces the conversation to own the
## stage and prevents an unresolved decision from being collapsed, split, or covered by a page.
func set_event_active(active: bool) -> void:
	if active == _event_active:
		return
	_event_active = active
	if active:
		if _page_panel != null:
			hide_page()
		_chat_open = true
		_touch_order("chat")
	_relayout_stage()
	chat_expanded_changed.emit(_chat_open)


func is_event_active() -> bool:
	return _event_active


# --- Esc / hardware back ----------------------------------------------------------------------

## Close whatever is "on top" — the mobile menu list if it is open, else the most recently opened
## of {page, chat} — and report whether anything was closed. `game_screen.gd`'s own
## `on_hardware_back` just forwards to this (ux_plan.md §1.3 rule 6: "Esc closes the topmost thing").
func close_topmost() -> bool:
	if _event_active:
		return true
	if _mobile_menu_open:
		_close_mobile_menu()
		return true
	if _open_order.is_empty():
		return false
	var top := String(_open_order[-1])
	if top == "chat":
		set_chat_expanded(false)
	else:
		hide_page()
	return true


func _touch_order(name: String) -> void:
	_open_order.erase(name)
	_open_order.append(name)


# --- breakpoint + layout -----------------------------------------------------------------------

func _on_resized() -> void:
	var mobile := size.x < MOBILE_BREAKPOINT_WIDTH
	if mobile != _is_mobile:
		_is_mobile = mobile
		_rail.visible = not mobile
		_menu_button.visible = mobile
		_map_layers_button.visible = not mobile
		if not mobile:
			_close_mobile_menu()
		elif _page_panel != null and _chat_open:
			# Crossing into mobile with both open (dragged in from a wide window) — enforce
			# exclusivity (rule 5), keeping whichever was opened more recently.
			if not _open_order.is_empty() and String(_open_order[-1]) == "chat":
				hide_page()
			else:
				set_chat_expanded(false)
		breakpoint_changed.emit(mobile)
	_relayout_stage()


func _relayout_stage() -> void:
	var page_open := _page_panel != null
	# The desktop shortcut belongs to the unobscured map. When a page or the expanded conversation
	# occupies the stage, leave its content clean; on mobile the same action is in Menu, and on
	# desktop it returns as soon as the player closes the overlay.
	_map_layers_button.visible = not _is_mobile and not page_open and not _chat_open
	_gutter.visible = false
	if _event_active:
		_fill(chat_slot)
	elif _is_mobile:
		if page_open:
			_fill(_page_slot)
		if _chat_open:
			_fill(chat_slot)
	elif page_open and _chat_open:
		_gutter.visible = true
		_layout_split(_split_fraction)
	elif page_open:
		_fill(_page_slot)
	elif _chat_open:
		_fill(chat_slot)
	_page_slot.visible = page_open
	chat_slot.visible = _chat_open


func _fill(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = 0.0
	control.offset_bottom = 0.0


## Rule 1 (desktop, both open -> half height each) + rule 2 (draggable to any position): page takes
## the top [param top_frac] of the stage, chat the rest, with a fixed-thickness gutter between them
## regardless of the stage's own height.
func _layout_split(top_frac: float) -> void:
	_page_slot.anchor_left = 0.0
	_page_slot.anchor_right = 1.0
	_page_slot.anchor_top = 0.0
	_page_slot.anchor_bottom = top_frac
	_page_slot.offset_left = 0.0
	_page_slot.offset_right = 0.0
	_page_slot.offset_top = 0.0
	_page_slot.offset_bottom = -SPLIT_GUTTER_SIZE * 0.5

	_gutter.anchor_left = 0.0
	_gutter.anchor_right = 1.0
	_gutter.anchor_top = top_frac
	_gutter.anchor_bottom = top_frac
	_gutter.offset_left = 0.0
	_gutter.offset_right = 0.0
	_gutter.offset_top = -SPLIT_GUTTER_SIZE * 0.5
	_gutter.offset_bottom = SPLIT_GUTTER_SIZE * 0.5

	chat_slot.anchor_left = 0.0
	chat_slot.anchor_right = 1.0
	chat_slot.anchor_top = top_frac
	chat_slot.anchor_bottom = 1.0
	chat_slot.offset_left = 0.0
	chat_slot.offset_right = 0.0
	chat_slot.offset_top = SPLIT_GUTTER_SIZE * 0.5
	chat_slot.offset_bottom = 0.0


func _on_gutter_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging_split = (event as InputEventMouseButton).pressed


## Tracked at the shell level, not the gutter's own `_gui_input` (rule 2: "draggable to any
## position") — the gutter is a thin strip, and a real drag's pointer routinely outruns it between
## frames. `_stage.get_local_mouse_position()` stays correct regardless of where the pointer is.
func _input(event: InputEvent) -> void:
	if not _dragging_split:
		return
	if event is InputEventMouseMotion:
		if _stage.size.y > 0.0:
			var local_y := _stage.get_local_mouse_position().y
			_split_fraction = clampf(local_y / _stage.size.y, MIN_PANEL_FRACTION,
				1.0 - MIN_PANEL_FRACTION)
			_relayout_stage()
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_dragging_split = false
