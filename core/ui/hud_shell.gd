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

## Whether the rail draws its painted column behind the destination plates. **Off, to be looked at**
## — the plates carry their own frames, so the question is whether the column behind them is holding
## them together or just adding weight. The geometry does not move either way: the empty box keeps
## the same margins, so the rail measures the same and the conversation's insets do not shift.
const RAIL_BACKGROUND := false

## How far the rail sits in from the stage's top-left. Tighter than the conversation's inset: the
## plates carry their own frames and their own shadows, so they read as sitting *on* the map rather
## than needing air cut around them.
const RAIL_MARGIN := 8.0

## Between one destination plate and the next. Tighter than the old lettered buttons wanted: these
## are square and framed, and too much air between them stops reading as one column.
const RAIL_SEPARATION := 10

## How far the hover label starts inside the button it belongs to, and how long it takes to unroll.
## The overlap is what keeps its left-hand cap out of sight: the plate draws under the button, so
## anything within this distance of the button's edge is covered by the button itself.
const RAIL_LABEL_OVERLAP := 16.0
const RAIL_LABEL_TIME := 0.16
## The hover plate must clear every page/chat layer, while the destination icons still cover the
## overlapping cap where the label appears to slide out from underneath them.
const RAIL_LABEL_Z_INDEX := 10
const RAIL_BUTTON_Z_INDEX := RAIL_LABEL_Z_INDEX + 1

## How long the map-layers column takes to unroll out from under its shortcut. The same short beat as
## the hover labels: this is chrome answering a press, not a panel arriving.
const MAP_LAYERS_REVEAL_TIME := RAIL_LABEL_TIME

## How far the floating mobile menu button sits in from the stage's bottom-right corner.
const MENU_BUTTON_MARGIN := 16

## How far the map shortcut sits in from that same corner — on every side, because the column opens
## *around* this button rather than beside it and overhangs it by its own moulding in all directions.
## Inset only [constant MENU_BUTTON_MARGIN], the column's right-hand edge landed on the window's own
## and its ornament was cut off against it, while its foot landed on the conversation. The two plates
## are never on screen together — one is the desktop's, one the phone's — so nothing is left looking
## misaligned by the difference.
const MAP_LAYERS_BUTTON_MARGIN := MENU_BUTTON_MARGIN + int(UiSkin.MAP_LAYERS_COLUMN_PADDING)
const SPLIT_GUTTER_SIZE := 10.0
const MIN_PANEL_FRACTION := 0.15

## How far the conversation is held from the desktop chrome: after the rail on the left and from the
## window edge on the right. On a phone there is no rail and no room to spare, so it runs full width.
const CHAT_SIDE_INSET := 24.0
const CHAT_TOP_INSET := 16.0

## Breathing room between a destination page and the stage's top edge or the conversation below it.
## Pages and chat share their horizontal rect; this is the corresponding vertical inset for pages.
const PAGE_VERTICAL_INSET := 16.0

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

## The selection band was shown or hidden — including by Esc and by its own ✕, neither of which the
## caller that put something in it can otherwise see. `game_screen.gd` uses it to clear the map's
## outline, so closing the band and deselecting cannot come apart.
signal selection_visibility_changed(visible: bool)

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

## Holds the one [SelectionDock], parented by [method set_selection_dock]. It is a band **above** the
## conversation rather than a region of its own elsewhere on the stage: the two are cut from the same
## parchment and meet with no gap, so together they are one surface growing up from the bottom edge.
## See [SelectionDock] for why the gap has to be zero.
var selection_slot: Control

## Anything a caller wants drawn over the whole shell, laid out by hand. The outpost's banner hangs
## here: it is twice the height of the bar it flies from, and a control that size *inside* the bar
## would simply make the bar that tall. Added after everything else, so it clears the stage as well
## as the chrome; a plain [Control], so nothing here moves what a caller puts in it.
var overlay: Control

## The banner, once a caller has handed one over — see [method set_banner].
var _banner: Control = null
var _banner_top := 0.0

var _rail: VBoxContainer
var _rail_host: Control
var _rail_plate: PanelContainer
var _rail_label_clip: Control
var _rail_label: PanelContainer
var _rail_label_text: Label
var _rail_label_width := 0.0
var _rail_label_tween: Tween = null
var _menu_button: SkinnedButton
var _map_layers_button: SkinnedButton
var _map_layers_label_clip: Control
var _map_layers_label: PanelContainer
var _map_layers_label_text: Label
var _map_layers_label_width := 0.0
var _map_layers_label_source_x := 0.0
var _map_layers_label_tween: Tween = null
var _map_layers_flyout: Control
var _map_layers_column: PanelContainer
var _map_layers_box: VBoxContainer
var _map_layers_open := false
## 0 closed, 1 fully unrolled — the value the reveal drives, read by
## [method _layout_map_layers_flyout] so the animation and the resting geometry are one path.
var _map_layers_reveal := 0.0
var _map_layers_tween: Tween = null
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

## The band, and whether the player currently has something selected. **Kept while a page is open**
## even though the band is not drawn then: a page covers the selection, it does not cancel it, so
## closing the page brings the band back rather than making the player pick the thing again.
var _selection_dock: SelectionDock = null
var _selection_open := false

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
	var top_shadow := PanelContainer.new()
	top_shadow.name = "top_header_shadow"
	top_shadow.z_index = 1
	top_shadow.add_theme_stylebox_override("panel", UiSkin.header_shadow_style())
	top_shadow.custom_minimum_size.y = UiSkin.TOP_BAR_HEIGHT
	root.add_child(top_shadow)
	var top_plate := PanelContainer.new()
	# The legacy build's own painted bar rather than a strip cut from the page's frame: parchment in a
	# dark metal channel with a notched end, which is the shape the wireframe draws.
	top_plate.add_theme_stylebox_override("panel", UiSkin.top_bar_style())
	top_plate.custom_minimum_size.y = UiSkin.TOP_BAR_HEIGHT
	top_shadow.add_child(top_plate)
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	top_plate.add_child(top_bar)

	# The banner's home. Last child of the shell, so it draws over the bar *and* over the stage the
	# bar sits above — parented inside the bar it would have been covered by the map the moment it
	# hung past the bar's bottom edge.
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 2

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
	# **It has to draw between the column and the buttons**: over the rail's parchment and its
	# right-hand moulding, and under the plate it belongs to, so the end that meets the button is
	# genuinely hidden rather than trimmed to look hidden.
	#
	# That needs a plain [Control] in between, because a container lays every child out to fill it.
	# [member Control.top_level] looks like the way out — a container does skip a top-level child when
	# it sorts — but it is not: it reparents the canvas item to the viewport's own canvas, so the
	# label drew above the entire tree and sat on the button instead of under it.
	# **The reveal is a window, not a slide.** The plate keeps its own size and a clipping wrapper
	# widens over it, so the name unrolls out from under the column instead of arriving beside it.
	# It has to be done this way round: a [PanelContainer] cannot be tweened narrower than the text
	# inside it — [method Control.get_combined_minimum_size] clamps it straight back.
	_rail_label_clip = Control.new()
	_rail_label_clip.clip_contents = true
	_rail_label_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_label_clip.z_index = RAIL_LABEL_Z_INDEX
	_rail_label_clip.visible = false
	_rail_label = PanelContainer.new()
	_rail_label.add_theme_stylebox_override("panel", UiSkin.sidemenu_label_style())
	_rail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_label_text = Label.new()
	_rail_label_text.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_rail_label_text.add_theme_color_override("font_color", UiSkin.SIDEMENU_LABEL_INK)
	_rail_label_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_label.add_child(_rail_label_text)
	_rail_label_clip.add_child(_rail_label)

	_rail_plate = PanelContainer.new()
	_rail_plate.add_theme_stylebox_override("panel", UiSkin.sidemenu_style(RAIL_BACKGROUND))
	_stage.add_child(_rail_plate)
	_rail_plate.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(RAIL_MARGIN))
	_rail = VBoxContainer.new()
	_rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_rail.add_theme_constant_override("separation", RAIL_SEPARATION)
	_rail.z_index = RAIL_BUTTON_Z_INDEX
	# The host is what the plate sizes itself to, so it has to carry the column's own minimum — a
	# plain Control has none of its own. `add_rail_action` keeps it in step as plates arrive.
	_rail_host = Control.new()
	_rail_plate.add_child(_rail_host)
	_rail_plate.resized.connect(_place_banner)
	_rail_host.add_child(_rail_label_clip)
	_rail_host.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_page_slot = Control.new()
	_stage.add_child(_page_slot)

	# Before the conversation in the tree, so that where the two surfaces meet the board's own top
	# rule is what draws last and the join is a rule rather than a seam.
	selection_slot = Control.new()
	selection_slot.visible = false
	_stage.add_child(selection_slot)

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

	# The right-hand map shortcut is a destination plate too: same footprint, shadow and scale
	# response as the rail, but with its own authored parchment/selected states.
	_map_layers_button = UiSkin.map_layers_button()
	_stage.add_child(_map_layers_button)
	_map_layers_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MAP_LAYERS_BUTTON_MARGIN)
	# Its hover label is wired by `add_map_layers_action`, which is what knows the destination's name.
	_map_layers_button.pressed.connect(_toggle_map_layers)
	_map_layers_button.tooltip_text = "Map Layers"

	# **The layers open where the shortcut is, not where a page would be.** The column is pinned by
	# its bottom edge to the shortcut's own and grows upward from there, so the plate the player just
	# pressed stays put and the choices arrive above it — a page would have covered both the map they
	# are about to change and the button they opened it with.
	#
	# The reveal is the hover label's trick turned on its side: a clipping window whose bottom edge is
	# fixed while its height grows, with the column held against that bottom edge inside it. The
	# column unrolls out from under the shortcut instead of sliding in from somewhere off screen.
	# **The column straddles the hover label: parchment below it, plates above.** A name unrolls from
	# behind the plate it belongs to, not from behind the chrome — with the whole column over the
	# label, a layer's name appeared to come out of the background instead of out of the button, which
	# is a different (and wronger) thing for it to be doing.
	_map_layers_flyout = Control.new()
	_map_layers_flyout.clip_contents = true
	_map_layers_flyout.visible = false
	_map_layers_flyout.z_index = RAIL_LABEL_Z_INDEX - 1
	_map_layers_column = PanelContainer.new()
	_map_layers_column.add_theme_stylebox_override("panel", UiSkin.map_layers_flyout_style())
	_map_layers_box = VBoxContainer.new()
	_map_layers_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_map_layers_box.add_theme_constant_override("separation", int(UiSkin.MAP_LAYERS_SEPARATION))
	# Above the label, for the same reason the rail's own icons are: it opens a few units *inside* the
	# plate it names, and the plate has to be what hides that overlap. Relative to the column, which
	# is what a child's `z_index` means unless it is told otherwise.
	_map_layers_box.z_index = RAIL_BUTTON_Z_INDEX - _map_layers_flyout.z_index
	_map_layers_column.add_child(_map_layers_box)
	_map_layers_flyout.add_child(_map_layers_column)
	_stage.add_child(_map_layers_flyout)

	# A mirrored copy of the rail's hover label. This one is parented to the stage because its source
	# button floats at the opposite edge; its clipping window grows left while the plate stays fixed.
	_map_layers_label_clip = Control.new()
	_map_layers_label_clip.clip_contents = true
	_map_layers_label_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layers_label_clip.z_index = RAIL_LABEL_Z_INDEX
	_map_layers_label_clip.visible = false
	_map_layers_label = PanelContainer.new()
	_map_layers_label.add_theme_stylebox_override("panel", UiSkin.sidemenu_label_style())
	_map_layers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layers_label_text = Label.new()
	_map_layers_label_text.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_map_layers_label_text.add_theme_color_override("font_color", UiSkin.SIDEMENU_LABEL_INK)
	_map_layers_label_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layers_label.add_child(_map_layers_label_text)
	_map_layers_label_clip.add_child(_map_layers_label)
	_stage.add_child(_map_layers_label_clip)
	_map_layers_button.z_index = RAIL_BUTTON_Z_INDEX
	# It belongs to the map, not above a page or expanded conversation. Keep it over the base layer
	# but underneath the two overlay slots, so it returns when those panels close instead of covering
	# their content.
	_stage.move_child(_map_layers_label_clip, _stage.get_children().find(_page_slot))
	# The column belongs to the same group. Its own z-order decides what it draws over; this only
	# keeps it with the rest of the map's chrome, above the base layer and below the page slot.
	_stage.move_child(_map_layers_flyout, _stage.get_children().find(_page_slot))
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

	add_child(overlay)


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
	# Deferred: the column's minimum only counts the new plate once it has been laid out.
	_rail_host.call_deferred("set", "custom_minimum_size", _rail.get_combined_minimum_size())
	# The banner heads this column, so it moves when the column does.
	_place_banner.call_deferred()

	_add_mobile_menu_action(label, on_pressed)


## Name the floating map shortcut, and register the same destination in the mobile menu.
##
## [param on_pressed] is the *phone's* path only. A phone has no shortcut to press and no room beside
## it for a column of layers, so the entry in Menu opens the module's Map Layers page instead. The
## desktop plate is wired to its own flyout ([method add_map_layers_toggle]) rather than to a caller's
## action: what it opens is chrome this class owns and places.
func add_map_layers_action(label: String, on_pressed: Callable) -> void:
	_map_layers_button.tooltip_text = label
	_wire_map_layers_label(_map_layers_button, label)
	_add_mobile_menu_action(label, on_pressed)


## Add one layer to the shortcut's flyout: a plate that latches on and off, painted with
## [param texture] while the layer is off and [param selected] while it is drawn.
##
## The shell owns the column and the animation; the caller owns what a layer *is* — [param on_toggled]
## receives the new state and is the only thing that touches the map. Returns the plate so a caller
## can re-state it when the same layer is changed from somewhere else (the phone's page).
func add_map_layers_toggle(label: String, texture: Texture2D, selected: Texture2D,
		on_toggled: Callable, pressed: bool = true) -> SkinnedButton:
	var plate := UiSkin.map_layer_button(texture, selected)
	plate.button.set_pressed_no_signal(pressed)
	plate.button.toggled.connect(func(value: bool) -> void: on_toggled.call(value))
	plate.tooltip_text = label
	_wire_map_layers_label(plate, label)
	_map_layers_box.add_child(plate)
	# Deferred, like the rail's own: the column's minimum only counts the new plate once it has been
	# laid out, and the flyout's whole height is derived from that minimum.
	_layout_map_layers_flyout.call_deferred()
	return plate


## Both the shortcut and every plate inside its flyout name themselves the same way: on the one
## mirrored plate that unrolls toward the left edge.
func _wire_map_layers_label(plate: SkinnedButton, label: String) -> void:
	plate.button.mouse_entered.connect(func() -> void: _show_map_layers_label(label, plate))
	plate.button.mouse_exited.connect(_hide_map_layers_label)
	plate.button.focus_entered.connect(func() -> void: _show_map_layers_label(label, plate))
	plate.button.focus_exited.connect(_hide_map_layers_label)


func _toggle_map_layers() -> void:
	# The shortcut is a latch, so by the time this runs Godot has already flipped it — read the plate
	# rather than the shell, or the two disagree the first time the player presses it.
	_set_map_layers_open(_map_layers_button.button.button_pressed)


## [param animated] is false when the flyout is not being dismissed so much as overtaken: a page
## opening takes the shortcut off the screen with it, and the tail of an unroll playing over the
## newly opened page is the same flash [method _relayout_stage] already removes from the hover label.
func _set_map_layers_open(open: bool, animated: bool = true) -> void:
	if open == _map_layers_open:
		return
	_map_layers_open = open
	_map_layers_button.button.set_pressed_no_signal(open)
	if open:
		_map_layers_flyout.visible = true
	if not animated:
		if _map_layers_tween != null and _map_layers_tween.is_valid():
			_map_layers_tween.kill()
		_set_map_layers_reveal(1.0 if open else 0.0)
		_map_layers_flyout.visible = open
		return
	_reveal_map_layers(1.0 if open else 0.0)


func is_map_layers_open() -> bool:
	return _map_layers_open


func _reveal_map_layers(to: float) -> void:
	if _map_layers_tween != null and _map_layers_tween.is_valid():
		_map_layers_tween.kill()
	if not is_inside_tree():
		_set_map_layers_reveal(to)
		_map_layers_flyout.visible = to > 0.0
		return
	_map_layers_tween = create_tween().set_ease(Motion.EASE).set_trans(Motion.TRANS)
	_map_layers_tween.tween_method(_set_map_layers_reveal, _map_layers_reveal, to,
		MAP_LAYERS_REVEAL_TIME)
	if is_zero_approx(to):
		_map_layers_tween.tween_callback(func() -> void: _map_layers_flyout.visible = false)


func _set_map_layers_reveal(value: float) -> void:
	_map_layers_reveal = value
	_layout_map_layers_flyout()


## The column keeps its own size while the window over it opens upward — the same arrangement the
## hover labels use, and for the same reason: a [PanelContainer] cannot be tweened smaller than the
## plates inside it, so the thing that moves has to be the window rather than the panel.
##
## Placed from the shortcut's live offsets rather than from a constant, so the column follows it up
## and down as the conversation grows underneath them both.
func _layout_map_layers_flyout() -> void:
	if _map_layers_flyout == null:
		return
	var wanted := _map_layers_column.get_combined_minimum_size()
	wanted.x = maxf(wanted.x, UiSkin.MAP_LAYERS_COLUMN_WIDTH)
	_map_layers_column.size = wanted
	var height := wanted.y * _map_layers_reveal
	var centre := (_map_layers_button.offset_left + _map_layers_button.offset_right) * 0.5
	_map_layers_flyout.anchor_left = 1.0
	_map_layers_flyout.anchor_right = 1.0
	_map_layers_flyout.anchor_top = 1.0
	_map_layers_flyout.anchor_bottom = 1.0
	_map_layers_flyout.offset_left = centre - wanted.x * 0.5
	_map_layers_flyout.offset_right = centre + wanted.x * 0.5
	# The column runs down *past* the shortcut and closes under it, by the same moulding it carries on
	# every other side — which is what its style reserves room at the foot for
	# ([method UiSkin.map_layers_flyout_style]).
	_map_layers_flyout.offset_bottom = (_map_layers_button.offset_bottom
		+ UiSkin.MAP_LAYERS_COLUMN_PADDING)
	_map_layers_flyout.offset_top = _map_layers_flyout.offset_bottom - height
	# Held against the window's bottom edge, so what shows first is the foot of the column and the
	# rest arrives from above.
	_map_layers_column.position.y = height - wanted.y


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


## Hang a caller's banner over the chrome. The caller owns what it is; the shell owns where it goes,
## which is **centred on the rail's column** — the banner and the destinations below it are one strip
## of chrome down the left, and lining the banner up with the bar's own padding instead left the two
## a few units apart and looking like an accident.
##
## [param top] is how far down the banner starts, and is normally negative: the art carries a finial
## and a crossbar the caller wants lifted off the screen.
func set_banner(banner: Control, top: float) -> void:
	_banner = banner
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_top = top
	overlay.add_child(_banner)
	_place_banner()


## **Centred on the first destination plate**, not on the column around it: the column is wider than
## a plate by its own moulding, so centring on it left the banner off to one side of the icons it is
## supposed to head. Falls back to the column only while the rail is still empty.
##
## Re-run whenever the rail's size settles as well as on a resize. The first call lands before the
## rail has been laid out — every rect is still zero then, which put the banner hard against the left
## edge of the screen and left it there on any window that never resized afterwards.
func _place_banner() -> void:
	if _banner == null:
		return
	var wanted := _banner.get_combined_minimum_size()
	_banner.size = wanted
	var target: Control = _rail_plate
	if _rail != null and _rail.get_child_count() > 0:
		target = _rail.get_child(0) as Control
	var rect := target.get_global_rect()
	var origin := overlay.get_global_rect().position
	_banner.position = Vector2(
		rect.position.x - origin.x + (rect.size.x - wanted.x) * 0.5, _banner_top)
	# **The column starts under the banner it is headed by.** Derived rather than a constant: the
	# banner's own height decides it, so shortening the bar — which lifts the stage, and with it the
	# rail — cannot leave the two overlapping again. The banner is placed in the overlay's space and
	# the rail in the stage's, which is what the one subtraction is for.
	var stage_top := _stage.get_global_rect().position.y - origin.y
	_rail_plate.position.y = maxf(RAIL_MARGIN, _banner_top + wanted.y + RAIL_MARGIN - stage_top)


## Parent the conversation into the stage. It stays there for the shell's whole life — collapsed and
## expanded are the same board at two heights, so there is nothing to swap in or out.
func set_chat_dock(dock: ChatDock) -> void:
	_chat_dock = dock
	chat_slot.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# **The collapsed board is only as tall as the dock says, so it has to be re-asked.** Its height was
	# taken once, during the first layout, when the input row had not settled to its final metrics —
	# so the strip on a freshly loaded game was a couple of units out and stayed that way until the
	# first expand happened to run the layout again. This also covers the pending-question row: it
	# appears inside the board, and the strip has to grow to keep it answerable.
	dock.minimum_size_changed.connect(_relayout_stage)
	dock.engaged.connect(func() -> void: set_chat_expanded(true))
	dock.dismissed.connect(func() -> void: set_chat_expanded(false))
	_relayout_stage()


func is_chat_expanded() -> bool:
	return _chat_open


# --- selection band ---------------------------------------------------------------------------

## Parent the band into the stage, where it stays for the shell's whole life — like the conversation,
## it is shown and hidden rather than swapped, so nothing in it has to be rebuilt per selection.
func set_selection_dock(dock: SelectionDock) -> void:
	_selection_dock = dock
	selection_slot.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.dismissed.connect(func() -> void: set_selection_visible(false))
	_relayout_stage()


## Show or hide the band. It **takes its height out of the conversation's ceiling** rather than
## floating over it: an expanded chat with a band above it is shorter by exactly the band, so nothing
## on either is ever covered by the other.
func set_selection_visible(visible: bool) -> void:
	if visible == _selection_open:
		return
	_selection_open = visible
	if visible and _selection_dock != null:
		_selection_dock.modulate.a = 0.0
		Motion.fade(_selection_dock, 1.0, Motion.DURATION_FAST)
	_relayout_stage()
	selection_visibility_changed.emit(_selection_open)


func is_selection_visible() -> bool:
	return _selection_open


## Whether the band is actually on the stage, as opposed to selected-but-covered: a page takes the
## stage and the band waits for it to close.
func is_selection_showing() -> bool:
	return _selection_open and _page_panel == null


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

## Close whatever is "on top" — the map-layers flyout, then the mobile menu list, else the most
## recently opened of {page, chat} — and report whether anything was closed. `game_screen.gd`'s own
## `on_hardware_back` just forwards to this (ux_plan.md §1.3 rule 6: "Esc closes the topmost thing").
func close_topmost() -> bool:
	if _event_active:
		return true
	# Shallowest thing on the screen, and the only one that opens *over* the map rather than instead
	# of it — so it is what one press of Esc is reaching for while it is up.
	if _map_layers_open:
		_set_map_layers_open(false)
		return true
	if _mobile_menu_open:
		_close_mobile_menu()
		return true
	if not _open_order.is_empty():
		var top := String(_open_order[-1])
		if top == "chat":
			set_chat_expanded(false)
		else:
			hide_page()
		return true
	# **The selection is the last thing Esc reaches**, under the page and the conversation both. It is
	# the quietest thing on the screen — a band and an outline on the map — and closing it first would
	# make one press of Esc do the least visible of the available jobs. With a page open the band is
	# not even drawn, so Esc closes the page, the band comes back, and the next press lets it go.
	if _selection_open:
		set_selection_visible(false)
		return true
	return false


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
	_place_banner()
	_relayout_stage()


func _relayout_stage() -> void:
	var page_open := _page_panel != null
	# The desktop shortcut belongs to the unobscured map. When a page or the expanded conversation
	# occupies the stage, leave its content clean; on mobile the same action is in Menu, and on
	# desktop it returns as soon as the player closes the overlay.
	_map_layers_button.visible = not _is_mobile and not page_open and not _chat_open
	if not _map_layers_button.visible:
		# Its z-order deliberately clears the page so the label can overlap the icon cleanly. Remove
		# the transient label immediately when the shortcut itself leaves, rather than letting the
		# tail of its hide animation flash over the newly opened page.
		_map_layers_label_clip.visible = false
		# The layers belong to the shortcut, so they leave with it — and they leave *now*, for the
		# same reason.
		_set_map_layers_open(false, false)
	# **The conversation is never hidden any more.** Collapsed it is the same board showing only its
	# bottom section, which is what makes opening it look like one piece growing rather than a second
	# panel arriving. Only the page still comes and goes.
	_gutter.visible = not _is_mobile and page_open and _chat_open and not _event_active
	# Lay the chat out first: a page with a collapsed conversation uses the board's live top edge as
	# its bottom boundary, so it can never extend underneath the input strip.
	_layout_chat(page_open)
	if page_open:
		var split := _chat_open and not (_is_mobile or _event_active)
		_layout_page_above_split(_split_fraction if split else 1.0)
	else:
		_fill(_page_slot)
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
	# The board is centred in the stage: the stable rail clearance used on the left is mirrored on the
	# right. This keeps both resting and expanded states on one fixed horizontal rect.
	chat_slot.offset_left = _content_left()
	chat_slot.offset_right = -_content_right()
	chat_slot.offset_bottom = -bottom

	var band := _selection_band_height()
	var collapsed := _collapsed_chat_height() + bottom
	var stage_height := _stage.size.y
	# **The band comes out of the conversation's ceiling.** It sits above the board and both have to
	# fit the stage, so an expanded chat under a band is shorter by exactly the band's height.
	var expanded := stage_height - CHAT_TOP_INSET - band
	# Sharing the stage with a page (desktop rule 1): the board's ceiling is the split instead of the
	# top of the stage. Event mode ignores the split — an unresolved decision owns the screen.
	if page_open and not _is_mobile and not _event_active:
		expanded = stage_height * (1.0 - _split_fraction) - SPLIT_GUTTER_SIZE * 0.5
	chat_slot.offset_top = -maxf(collapsed, lerpf(collapsed, expanded, _chat_reveal))

	# Flush on the board's top edge — no gap, deliberately. [SelectionDock] documents why.
	selection_slot.visible = band > 0.0
	if selection_slot.visible:
		selection_slot.anchor_left = 0.0
		selection_slot.anchor_right = 1.0
		selection_slot.anchor_top = 1.0
		selection_slot.anchor_bottom = 1.0
		selection_slot.offset_left = chat_slot.offset_left
		selection_slot.offset_right = chat_slot.offset_right
		selection_slot.offset_bottom = chat_slot.offset_top
		selection_slot.offset_top = chat_slot.offset_top - band

	# **The two floating plates ride on top of the board.** They are anchored to the stage's
	# bottom-right corner, which used to be free map and is now where the conversation lives — the
	# mobile Menu plate landed squarely on the send button, which is the same collision ux_plan.md
	# already recorded once when the dock was a row of its own. Riding the board's edge also means
	# they move with the reveal instead of being covered halfway through it.
	_float_above_chat(_menu_button, MENU_BUTTON_MARGIN)
	# The shortcut clears the board by its own deeper margin, so that the column closing underneath it
	# has somewhere to close rather than landing on the conversation.
	_float_above_chat(_map_layers_button, MAP_LAYERS_BUTTON_MARGIN)
	# After the shortcut, never before: the column is placed from the offsets that call has just set.
	_layout_map_layers_flyout()


## How tall the band is right now, and zero when it is not on the stage — which is both "nothing is
## selected" and "a page has taken the stage". Everything that has to clear the bottom of the screen
## measures against this rather than asking the two questions separately.
func _selection_band_height() -> float:
	if not is_selection_showing() or _selection_dock == null:
		return 0.0
	return maxf(_selection_dock.get_combined_minimum_size().y, SelectionDock.BAND_HEIGHT)


## The top of everything stacked on the stage's bottom edge: the band when it is up, the conversation
## otherwise. **The one edge anything above the stack may occupy down to** — a page's foot, and the
## two floating plates.
func _stack_top() -> float:
	return chat_slot.offset_top - _selection_band_height()


func _float_above_chat(button: Control, margin: float) -> void:
	var height := button.get_combined_minimum_size().y
	button.offset_bottom = _stack_top() - margin
	button.offset_top = button.offset_bottom - height


## The page's half of a split. [param bottom_frac] of 1.0 is "the page has the stage to itself",
## which is what it gets while the conversation is only a strip along the bottom.
func _layout_page_above_split(bottom_frac: float) -> void:
	_page_slot.anchor_left = 0.0
	_page_slot.anchor_right = 1.0
	_page_slot.anchor_top = 0.0
	_page_slot.anchor_bottom = bottom_frac
	_page_slot.offset_left = _content_left()
	_page_slot.offset_right = -_content_right()
	_page_slot.offset_top = PAGE_VERTICAL_INSET
	if is_equal_approx(bottom_frac, 1.0):
		# The page owns the area above the collapsed input strip, not the full stage behind it.
		_page_slot.offset_bottom = _stack_top() - PAGE_VERTICAL_INSET
	else:
		_page_slot.offset_bottom = -SPLIT_GUTTER_SIZE * 0.5 - PAGE_VERTICAL_INSET

	_gutter.anchor_left = 0.0
	_gutter.anchor_right = 1.0
	_gutter.anchor_top = bottom_frac
	_gutter.anchor_bottom = bottom_frac
	_gutter.offset_left = _content_left()
	_gutter.offset_right = -_content_right()
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
	# Sized from the font rather than from the panel's cached minimum: the text was set a moment ago
	# and the container has not laid out since, so asking it now answers for the *previous* name.
	_rail_label.reset_size()
	var wanted := _rail_label.get_combined_minimum_size()
	_rail_label.size = wanted
	# The window opens [constant RAIL_LABEL_OVERLAP] *inside* the button, so the plate's left-hand cap
	# — and every seam with it — stays under the button for as long as the label exists, rather than
	# being trimmed at the join and still showing a sliver of its own moulding.
	_rail_label.position = Vector2.ZERO
	_rail_label_width = wanted.x + RAIL_LABEL_OVERLAP
	var origin := _rail_host.get_global_rect().position
	_rail_label_clip.position = Vector2(rect.end.x - origin.x - RAIL_LABEL_OVERLAP,
		rect.position.y - origin.y + (rect.size.y - wanted.y) * 0.5)
	_rail_label_clip.size.y = wanted.y
	if not _rail_label_clip.visible:
		_rail_label_clip.size.x = 0.0
		_rail_label_clip.visible = true
	_tween_rail_label(_rail_label_width, false)


func _hide_rail_label() -> void:
	_tween_rail_label(0.0, true)


## Name a plate on the right-hand side — the shortcut itself, or one of the layers inside its flyout
## — on a matching plate that unrolls toward the left edge. The inner panel stays at its final
## position; only the clipping window opens, so it appears to emerge from beneath the plate instead
## of sliding in from elsewhere.
##
## **One plate for all of them**, exactly as the rail has one for its seven destinations: only one
## can be under the pointer at a time.
func _show_map_layers_label(text: String, plate: Control) -> void:
	if not plate.is_visible_in_tree():
		return
	_map_layers_label_text.text = text.to_upper()
	# Sized from the font rather than the container's cached minimum, which still answers for the
	# previous name — the trap `_show_rail_label` documents.
	_map_layers_label.reset_size()
	var wanted := _map_layers_label.get_combined_minimum_size()
	_map_layers_label.size = wanted
	_map_layers_label_width = wanted.x
	var rect := plate.get_global_rect()
	var origin := _stage.get_global_rect().position
	_map_layers_label_source_x = rect.position.x - origin.x + RAIL_LABEL_OVERLAP
	_map_layers_label_clip.position.y = rect.position.y - origin.y + (rect.size.y - wanted.y) * 0.5
	_map_layers_label_clip.size.y = wanted.y
	if not _map_layers_label_clip.visible:
		_set_map_layers_label_width(0.0)
		_map_layers_label_clip.visible = true
	_tween_map_layers_label(_map_layers_label_width, false)


func _hide_map_layers_label() -> void:
	_tween_map_layers_label(0.0, true)


## Keep the label itself fixed while the clipping window's left edge travels away from the button.
func _set_map_layers_label_width(width: float) -> void:
	_map_layers_label_clip.position.x = _map_layers_label_source_x - width
	_map_layers_label_clip.size.x = width
	_map_layers_label.position.x = width - _map_layers_label_width


func _tween_map_layers_label(to_width: float, hide_after: bool) -> void:
	if _map_layers_label_tween != null and _map_layers_label_tween.is_valid():
		_map_layers_label_tween.kill()
	if not is_inside_tree():
		return
	_map_layers_label_tween = create_tween()
	_map_layers_label_tween.set_ease(Motion.EASE).set_trans(Motion.TRANS)
	_map_layers_label_tween.tween_method(_set_map_layers_label_width,
		_map_layers_label_clip.size.x, to_width, RAIL_LABEL_TIME)
	if hide_after:
		_map_layers_label_tween.tween_callback(
			func() -> void: _map_layers_label_clip.visible = false)


## No fade either way: the window is what hides the plate, and the rail is what hides the window's
## first few units.
func _tween_rail_label(to_width: float, hide_after: bool) -> void:
	if _rail_label_tween != null and _rail_label_tween.is_valid():
		_rail_label_tween.kill()
	if not is_inside_tree():
		return
	_rail_label_tween = create_tween()
	_rail_label_tween.set_ease(Motion.EASE).set_trans(Motion.TRANS)
	_rail_label_tween.tween_property(_rail_label_clip, "size:x", to_width, RAIL_LABEL_TIME)
	if hide_after:
		_rail_label_tween.tween_callback(func() -> void: _rail_label_clip.visible = false)


func _collapsed_chat_height() -> float:
	return _chat_dock.collapsed_height if _chat_dock != null else UiSkin.CONTROL_HEIGHT


## How far in from the stage's left edge anything that is **not** the map begins: past the floating
## rail on desktop, flush on a phone where there is no rail. The map itself ignores this and runs the
## full width, which is the point of the rail floating.
func _content_left() -> float:
	if _is_mobile:
		return 0.0
	# Use the declared width, not the live minimum. On the first layout the latter only includes the
	# style padding; it grows after the destination buttons settle and used to resize the chat then.
	return RAIL_MARGIN + UiSkin.SIDEMENU_WIDTH + CHAT_SIDE_INSET


func _content_right() -> float:
	# Mirror the complete left clearance so chat and pages remain centred in the stage.
	return _content_left()


## A page fills the stage, minus whatever the floating rail is standing in front of.
func _fill(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 1.0
	control.offset_left = _content_left()
	control.offset_right = -_content_right()
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
