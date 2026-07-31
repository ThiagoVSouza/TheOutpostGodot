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

## One destination plate wide — the narrow column of icons the wireframe draws. It carried the names
## as lettering until there was art to carry them instead; those live on the hover label now.
const RAIL_WIDTH := UiSkin.SIDEMENU_WIDTH - UiSkin.SIDEMENU_PADDING * 2.0

## For a destination with no art yet, and for the mobile menu's list. Smaller than a page's buttons:
## these are destinations, not decisions, and at [constant UiSkin.CONTROL_FONT_SIZE] "Diplomacy"
## alone would set the column nearly 100 units wider than the map can spare.
const RAIL_BUTTON_FONT_SIZE := UiSkin.FONT_SMALL

## Between one destination plate and the next. Tighter than the old lettered buttons wanted: these
## are square and framed, and too much air between them stops reading as one column.
const RAIL_SEPARATION := 10

## The hover label: how far off the plate it comes to rest, and how long it takes to get there. It
## travels out from behind the rail rather than the legacy's fixed twelve units, so how far it goes
## is whatever the name's own width turns out to be; the timing is the legacy's (`0.16s ease`).
const RAIL_LABEL_GAP := 14.0
const RAIL_LABEL_TIME := 0.16

## How far the floating mobile menu button sits in from the stage's bottom-right corner.
const MENU_BUTTON_MARGIN := 16
const SPLIT_GUTTER_SIZE := 10.0
const MIN_PANEL_FRACTION := 0.15

## How far the conversation is held off the stage's edges. **On desktop only**: the board sits in
## from the rail on one side and the window on the other, so it reads as an object lying on the map
## rather than a bar bolted across the bottom of the window. On a phone there is no rail and no room
## to spare, so it runs the full width.
const CHAT_SIDE_INSET := 24.0
const CHAT_TOP_INSET := 16.0

## **Nothing under the board.** It sits on the bottom edge of the stage, not floating above it: a gap
## there left a strip of dark background below the conversation and made it read as a panel hovering
## over the screen rather than the bottom of the frame. The safe area and the on-screen keyboard
## still push it up — that is clearance, not decoration.
const CHAT_BOTTOM_INSET := 0.0

## How long the board takes to grow or shrink. Short on purpose — this happens every time the player
## says anything, so it has to feel like the board answering rather than an animation being played
## at them.
const CHAT_REVEAL_TIME := Motion.DURATION_NORMAL

## A page or the chat dock has opened/closed. Lets a caller update its own UI (a chevron's glyph)
## without polling — used by `game_screen.gd` to flip the dock's expand button between ^ and v.
signal chat_expanded_changed(expanded: bool)

## The breakpoint flipped. Nothing in Phase 1 needs this yet, but the world-gate/event-mode work
## (Phase 4) will want to know without re-deriving `size.x` itself.
signal breakpoint_changed(is_mobile: bool)

## Regions callers fill with content. [member base_layer] is always full-rect and always visible —
## the map goes here and is never hidden by anything this class does. [member top_bar] is a plain
## container a caller adds widgets to; [member chat_slot] holds the one [ChatDock], parented by
## [method set_chat_dock] and never swapped or hidden.
##
## There is no separate `dock` region any more. The input line used to be a row below the stage,
## spanning the whole window under the rail, while the conversation was a panel floating above it —
## two frames that never lined up and read as two pieces of UI. Both are one board inside the stage
## now; see [ChatDock].
var base_layer: Control
var top_bar: HBoxContainer
var chat_slot: Control

var _rail: VBoxContainer
var _rail_plate: PanelContainer
var _rail_label: PanelContainer
var _rail_label_text: Label
var _rail_label_home := Vector2.ZERO
var _rail_label_tucked := Vector2.ZERO
var _rail_label_tween: Tween = null
var _menu_button: SkinnedButton
var _map_layers_button: SkinnedButton
var _menu_list: HudPanel
var _menu_list_box: VBoxContainer
var _return_button: SkinnedButton
var _mobile_menu_open := false

var _last_keyboard_height := 0
## Clearance the on-screen keyboard (or the navigation bar) needs under the conversation.
var _keyboard_inset := 0.0

## The conversation itself, parented into [member chat_slot] by [method set_chat_dock]. The shell
## reads only its collapsed height and tells it when to show its expanded parts.
var _chat_dock: ChatDock = null

## 0 collapsed, 1 expanded — the value the open/close animation drives. Every chat geometry decision
## reads it, so one tween moves the board and nothing else has to know it is moving.
var _chat_reveal := 0.0
var _chat_tween: Tween = null

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
	# The conversation is inside the stage now rather than in a row below it, so the keyboard's
	# clearance is part of its own geometry — see `_layout_chat`.
	# The keyboard's height is in *physical* pixels; this margin is in the stretched logical units
	# `display/window/stretch/mode` puts the UI in (project.godot). Adding the raw number reserves
	# far too much room — measured on an S26 Ultra, ~1.5x — leaving a dead band above the keyboard.
	var window_height := float(DisplayServer.window_get_size().y)
	var scale := get_viewport().get_visible_rect().size.y / window_height if window_height > 0.0 else 1.0
	# The keyboard covers the navigation bar while it is up, so the two insets never add.
	_keyboard_inset = float(maxi(int(height * scale), SafeArea.bottom(get_viewport())))
	_relayout_stage()


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

	# **The chrome is painted parchment, like every screen outside the game.** The same material a
	# page is cut from, held closer to its moulding ([method UiSkin.chrome_style]) so a bar across the
	# whole window costs the map as little height as it can. Anything less than the real parchment —
	# the border-only thin frame was tried first — leaves the dark background showing through and the
	# strip reads as a dark panel with a gold edge, which is the look this replaces.
	var top_plate := PanelContainer.new()
	# The legacy build's own painted bar rather than a strip cut from the page's frame: parchment in a
	# dark metal channel with a notched end, which is the shape the wireframe draws.
	top_plate.add_theme_stylebox_override("panel", UiSkin.top_bar_style())
	top_plate.custom_minimum_size.y = UiSkin.TOP_BAR_HEIGHT
	root.add_child(top_plate)
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	top_plate.add_child(top_bar)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.clip_contents = true
	body.add_child(_stage)

	base_layer = Control.new()
	base_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(base_layer)

	# **The rail floats over the map; it is not a column beside it.** As a child of an HBox it took
	# its full width out of the stage for the stage's whole height — and since the plate itself stops
	# under its last destination, everything below that was a dead strip of background the map was
	# not allowed to draw in. It is parented into the stage now, over the base layer, and only the
	# things that are *not* the map are held clear of it (see `_content_left`).
	# **Built and parented before the rail, so the rail draws over it.** The label comes out from
	# *behind* the column: at rest it is tucked entirely underneath, which is why it needs no fade.
	_rail_label = PanelContainer.new()
	_rail_label.add_theme_stylebox_override("panel", UiSkin.sidemenu_label_style())
	_rail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_label.visible = false
	_rail_label_text = Label.new()
	_rail_label_text.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_rail_label_text.add_theme_color_override("font_color", UiSkin.SIDEMENU_LABEL_INK)
	_rail_label_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_label.add_child(_rail_label_text)
	_stage.add_child(_rail_label)

	_rail_plate = PanelContainer.new()
	_rail_plate.add_theme_stylebox_override("panel", UiSkin.sidemenu_style())
	_stage.add_child(_rail_plate)
	_rail_plate.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(CHAT_SIDE_INSET))
	_rail = VBoxContainer.new()
	_rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_rail.add_theme_constant_override("separation", RAIL_SEPARATION)
	_rail_plate.add_child(_rail)

	_page_slot = Control.new()
	_stage.add_child(_page_slot)

	chat_slot = Control.new()
	_stage.add_child(chat_slot)

	_gutter = Control.new()
	_gutter.mouse_filter = Control.MOUSE_FILTER_STOP
	_gutter.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_gutter.gui_input.connect(_on_gutter_gui_input)
	_stage.add_child(_gutter)

	# The mobile menu button floats over the stage, bottom-right (ux_plan.md §1.1's mobile re-flow).
	# Parented to `_stage` and anchored, NOT to the shell: anchored to the shell it sits at the
	# window's bottom-right corner, which is the *dock's* row — on a real phone it landed squarely
	# on top of the Send button and hid it. The stage stops above the dock, so this floats over the
	# map exactly as drawn. Anchors rather than a computed position so it needs no resize handling.
	_menu_button = SkinnedButton.create("Menu", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		RAIL_BUTTON_FONT_SIZE)
	_menu_button.visible = false
	_menu_button.pressed.connect(_toggle_mobile_menu)
	_stage.add_child(_menu_button)
	_menu_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MENU_BUTTON_MARGIN)

	_map_layers_button = SkinnedButton.create("Map Layers", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		RAIL_BUTTON_FONT_SIZE)
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
	_menu_list_box.add_theme_constant_override("separation", 8)
	_menu_list.body.add_child(_menu_list_box)
	_return_button = SkinnedButton.create("Return", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		RAIL_BUTTON_FONT_SIZE)
	_return_button.pressed.connect(_close_mobile_menu)
	_menu_list_box.add_child(_return_button)


# --- rail / mobile menu ------------------------------------------------------------------------

## Register a destination reachable from both the desktop rail and the mobile menu list, so nothing
## can be added to one and forgotten on the other. Only "Main Menu" is wired in Phase 1 — the other
## six wireframed destinations are Phase 5's panel registry (ux_plan.md §Phase 5).
func add_rail_action(label: String, on_pressed: Callable, icon: Texture2D = null) -> void:
	# **A destination with art is the art.** The plate carries its own border and its own picture, so
	# there is nothing for a caption to sit on and none is drawn — the name is the tooltip and, on a
	# phone, the mobile list's own row. A destination that has not been given art yet falls back to a
	# lettered plate rather than to a blank square.
	var rail_button: Control
	if icon != null:
		var plate := UiSkin.destination_button(icon)
		plate.pressed.connect(on_pressed)
		plate.button.mouse_entered.connect(func() -> void: _show_rail_label(label, plate))
		plate.button.mouse_exited.connect(_hide_rail_label)
		plate.button.focus_entered.connect(func() -> void: _show_rail_label(label, plate))
		plate.button.focus_exited.connect(_hide_rail_label)
		rail_button = plate
	else:
		var lettered := SkinnedButton.create(label, UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
			RAIL_BUTTON_FONT_SIZE)
		lettered.pressed.connect(on_pressed)
		rail_button = lettered
	rail_button.tooltip_text = label
	_rail.add_child(rail_button)

	_add_mobile_menu_action(label, on_pressed)


func add_map_layers_action(label: String, on_pressed: Callable) -> void:
	_map_layers_button.label.text = label
	_map_layers_button.pressed.connect(on_pressed)
	_add_mobile_menu_action(label, on_pressed)


func _add_mobile_menu_action(label: String, on_pressed: Callable) -> void:
	var menu_button := SkinnedButton.create(label, UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		RAIL_BUTTON_FONT_SIZE)
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
	if _chat_dock != null:
		_chat_dock.set_expanded(expanded)
	_reveal_chat(1.0 if expanded else 0.0)
	_relayout_stage()
	chat_expanded_changed.emit(_chat_open)


## Grow or shrink the board. The tween drives [member _chat_reveal] and re-runs the layout on each
## step, so the animation and the resting geometry are the same code — there is no second path that
## could put the board somewhere the layout would not.
func _reveal_chat(to: float) -> void:
	if _chat_tween != null and _chat_tween.is_valid():
		_chat_tween.kill()
	if not is_inside_tree():
		_chat_reveal = to
		return
	_chat_tween = create_tween().set_ease(Motion.EASE).set_trans(Motion.TRANS)
	_chat_tween.tween_method(_set_chat_reveal, _chat_reveal, to, CHAT_REVEAL_TIME)


func _set_chat_reveal(value: float) -> void:
	_chat_reveal = value
	_relayout_stage()


## Parent the conversation into the stage. It stays there for the shell's whole life — collapsed and
## expanded are the same board at two heights, so there is nothing to swap in or out.
func set_chat_dock(dock: ChatDock) -> void:
	_chat_dock = dock
	chat_slot.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.engaged.connect(func() -> void: set_chat_expanded(true))
	dock.dismissed.connect(func() -> void: set_chat_expanded(false))
	_relayout_stage()


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
		# The plate, not the column inside it: hiding only the column would leave an empty painted
		# strip down the side of a phone screen.
		_rail_plate.visible = not mobile
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
	# **The conversation is never hidden any more.** Collapsed it is the same board showing only its
	# bottom section, which is what makes opening it look like one piece growing rather than a second
	# panel arriving. Only the page still comes and goes.
	_gutter.visible = not _is_mobile and page_open and _chat_open and not _event_active
	if page_open and not (_is_mobile or _event_active):
		_layout_page_above_split(_split_fraction if _chat_open else 1.0)
	else:
		_fill(_page_slot)
	_layout_chat(page_open)
	_page_slot.visible = page_open


## Where the board's top edge sits, measured up from the stage's bottom, at each end of the reveal —
## and wherever the tween currently has it in between. Both ends are expressed the same way, against
## the same edge, which is what makes one `lerp` enough to animate the whole thing.
func _layout_chat(page_open: bool) -> void:
	var bottom := CHAT_BOTTOM_INSET + _keyboard_inset
	chat_slot.anchor_left = 0.0
	chat_slot.anchor_right = 1.0
	chat_slot.anchor_top = 1.0
	chat_slot.anchor_bottom = 1.0
	# **The same gap either side, measured from the window.** Not from the rail: the rail floats
	# inside the left-hand gap, so matching the *rail's* edge on the right left about 24 units there
	# against ten times that on the left, and the board read as shoved up against the window. The
	# board is centred on the stage and the rail is a thing standing in the space beside it.
	chat_slot.offset_left = _content_left()
	chat_slot.offset_right = -_content_left()
	chat_slot.offset_bottom = -bottom

	var collapsed := _collapsed_chat_height() + bottom
	var stage_height := _stage.size.y
	var expanded := stage_height - CHAT_TOP_INSET
	# Sharing the stage with a page (desktop rule 1): the board's ceiling is the split instead of the
	# top of the stage. Event mode ignores the split — an unresolved decision owns the screen.
	if page_open and not _is_mobile and not _event_active:
		expanded = stage_height * (1.0 - _split_fraction) - SPLIT_GUTTER_SIZE * 0.5
	chat_slot.offset_top = -maxf(collapsed, lerpf(collapsed, expanded, _chat_reveal))

	# **The two floating plates ride on top of the board.** They are anchored to the stage's
	# bottom-right corner, which used to be free map and is now where the conversation lives — the
	# mobile Menu plate landed squarely on the send button, which is the same collision ux_plan.md
	# already recorded once when the dock was a row of its own. Riding the board's edge also means
	# they move with the reveal instead of being covered halfway through it.
	_float_above_chat(_menu_button)
	_float_above_chat(_map_layers_button)


func _float_above_chat(button: Control) -> void:
	var height := button.get_combined_minimum_size().y
	button.offset_bottom = chat_slot.offset_top - MENU_BUTTON_MARGIN
	button.offset_top = button.offset_bottom - height


## The page's half of a split. [param bottom_frac] of 1.0 is "the page has the stage to itself",
## which is what it gets while the conversation is only a strip along the bottom.
func _layout_page_above_split(bottom_frac: float) -> void:
	_page_slot.anchor_left = 0.0
	_page_slot.anchor_right = 1.0
	_page_slot.anchor_top = 0.0
	_page_slot.anchor_bottom = bottom_frac
	_page_slot.offset_left = _content_left()
	_page_slot.offset_right = 0.0
	_page_slot.offset_top = 0.0
	_page_slot.offset_bottom = 0.0 if is_equal_approx(bottom_frac, 1.0) else -SPLIT_GUTTER_SIZE * 0.5

	_gutter.anchor_left = 0.0
	_gutter.anchor_right = 1.0
	_gutter.anchor_top = bottom_frac
	_gutter.anchor_bottom = bottom_frac
	_gutter.offset_left = _content_left()
	_gutter.offset_right = 0.0
	_gutter.offset_top = -SPLIT_GUTTER_SIZE * 0.5
	_gutter.offset_bottom = SPLIT_GUTTER_SIZE * 0.5


## Name the destination under the pointer, on a plate that slides out beside it — the legacy build's
## own behaviour, and the reason the rail can carry no captions and still be readable.
##
## **One plate, not seven.** Only one destination can be under the pointer at a time, so the label is
## built once and moved; a panel per button would be seven controls the layout has to keep in step
## with plates it does not own. It is parented to the stage rather than to the button, because a
## button here is a [PanelContainer] and a container lays its children out to fill it — a label
## positioned by hand inside one would be dragged back over the plate every frame.
func _show_rail_label(text: String, plate: Control) -> void:
	_rail_label_text.text = text.to_upper()
	# Placed from the plate's live rect at the moment it is shown, so nothing has to watch the rail
	# for movement: it is only ever wrong while it is invisible.
	var rect := plate.get_global_rect()
	var origin := _stage.get_global_rect().position
	# Sized from the font rather than from the panel's cached minimum: the text was set a moment ago
	# and the container has not laid out since, so asking it now answers for the *previous* name.
	_rail_label.reset_size()
	var wanted := _rail_label.get_combined_minimum_size()
	_rail_label.size = wanted
	_rail_label_home = Vector2(rect.end.x - origin.x + RAIL_LABEL_GAP,
		rect.position.y - origin.y + (rect.size.y - wanted.y) * 0.5)
	# Tucked is far enough left that the whole plate is behind the column — its right edge level with
	# the rail's — so what slides out has been out of sight rather than faded up over the parchment.
	# Measured off the rail rather than a fixed distance: a longer name has further to travel.
	_rail_label_tucked = Vector2(
		_rail_plate.get_global_rect().end.x - origin.x - wanted.x, _rail_label_home.y)
	if not _rail_label.visible:
		_rail_label.position = _rail_label_tucked
		_rail_label.visible = true
	_tween_rail_label(_rail_label_home, false)


func _hide_rail_label() -> void:
	_tween_rail_label(_rail_label_tucked, true)


## No fade either way: the label is hidden by the rail itself, so it has nothing to fade out of.
func _tween_rail_label(to: Vector2, hide_after: bool) -> void:
	if _rail_label_tween != null and _rail_label_tween.is_valid():
		_rail_label_tween.kill()
	if not is_inside_tree():
		return
	_rail_label_tween = create_tween()
	_rail_label_tween.set_ease(Motion.EASE).set_trans(Motion.TRANS)
	_rail_label_tween.tween_property(_rail_label, "position", to, RAIL_LABEL_TIME)
	if hide_after:
		_rail_label_tween.tween_callback(func() -> void: _rail_label.visible = false)


func _collapsed_chat_height() -> float:
	return _chat_dock.collapsed_height if _chat_dock != null else UiSkin.CONTROL_HEIGHT


## How far in from the stage's left edge anything that is **not** the map begins: past the floating
## rail on desktop, flush on a phone where there is no rail. The map itself ignores this and runs the
## full width, which is the point of the rail floating.
func _content_left() -> float:
	if _is_mobile:
		return 0.0
	return CHAT_SIDE_INSET + _rail_plate.get_combined_minimum_size().x + CHAT_SIDE_INSET


## A page fills the stage, minus whatever the floating rail is standing in front of.
func _fill(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 1.0
	control.offset_left = _content_left()
	control.offset_right = 0.0
	control.offset_top = 0.0
	control.offset_bottom = 0.0


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
