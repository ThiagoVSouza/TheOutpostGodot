extends GutTest

## Picking something off the map, end to end: the click resolves through the content, the map draws
## an outline round the whole of it, and the band across the bottom of the stage says what it is.
##
## The routes *out* of a selection matter as much as the route in — Esc, the band's own ✕, pressing
## the same thing again, hiding the layer it stands on, and zooming away from it — because each is a
## separate path and each has to leave the map and the band agreeing with each other.


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	# The desktop layout: below the breakpoint there is no rail, and the insets differ.
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	return screen


## Where on screen a given map subtile currently is — the middle of it, so nothing depends on which
## side of a boundary a float lands.
func _point_at(view: OverworldMapView, subtile: Vector2i) -> Vector2:
	var step := float(BaseGameMap.TILE_SIZE_PX) / float(OverworldMapView.SUBGRID_DIVISIONS)
	var origin := view.get("_origin") as Vector2
	var zoom := view.get("_zoom") as float
	return ((Vector2(subtile) + Vector2(0.5, 0.5)) * step - origin) * zoom


## Drive the real input path rather than calling the handler: what separates a click from a pan is
## the press/release pair, and that is the part worth exercising.
func _click(view: OverworldMapView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view.call("_gui_input", down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	view.call("_gui_input", up)


func _plot(screen: Control) -> Rect2i:
	var map := screen.get("_terrain_map") as TerrainMap
	return (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i


## A subtile inside the first farm, and one well clear of every farm.
func _inside(screen: Control) -> Vector2i:
	return _plot(screen).position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)


func _wild(screen: Control) -> Vector2i:
	return (_plot(screen).position - Vector2i(20, 20)) * BaseGameMap.SUBTILES_PER_TILE


func test_clicking_a_field_outlines_all_of_it_and_names_it_on_the_band() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell
	assert_false(shell.is_selection_visible(), "the band is not on screen until something is picked")
	assert_false(view.has_selection())

	var plot := _plot(screen)
	_click(view, _point_at(view, _inside(screen)))

	assert_true(view.has_selection())
	assert_eq(view.selection()[0], Rect2i(plot.position * 5, plot.size * 5),
		"one subtile of it selects the whole field")
	assert_true(shell.is_selection_visible())
	assert_true(shell.is_selection_showing(), "and the band is actually on the stage")

	var dock := shell.get("_selection_dock") as SelectionDock
	assert_eq((dock.get("_title_label") as Label).text, "Ploughed field")
	var owner := dock.get("_owner_label") as Label
	assert_true(owner.visible, "a field is held by the settlement, and the band says which")
	assert_false(owner.text.is_empty())


func test_clicking_bare_ground_selects_the_one_subtile_and_names_the_terrain() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell

	var wild := _wild(screen)
	_click(view, _point_at(view, wild))

	assert_true(shell.is_selection_visible())
	assert_eq(view.selection(), [Rect2i(wild, Vector2i.ONE)] as Array[Rect2i],
		"exactly the square that was clicked, no more")
	var dock := shell.get("_selection_dock") as SelectionDock
	assert_eq((dock.get("_title_label") as Label).text, "Grassland")
	assert_false((dock.get("_owner_label") as Label).visible,
		"nobody holds wild ground, and the line is left blank rather than filled with a word for it")


func test_pressing_the_same_thing_again_puts_it_away() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell
	var at := _point_at(view, _inside(screen))

	_click(view, at)
	assert_true(shell.is_selection_visible())
	_click(view, at)
	assert_false(shell.is_selection_visible(), "the band goes")
	assert_false(view.has_selection(), "and so does the outline — the two cannot come apart")


func test_moving_to_another_thing_replaces_the_selection_rather_than_adding_to_it() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView

	_click(view, _point_at(view, _inside(screen)))
	assert_eq(view.selection().size(), 1)
	var field := view.selection()[0]

	var wild := _wild(screen)
	_click(view, _point_at(view, wild))
	assert_eq(view.selection(), [Rect2i(wild, Vector2i.ONE)] as Array[Rect2i])
	assert_ne(view.selection()[0], field, "one selection at a time")


## Rule 6 of the shell's Esc contract, extended: the selection is the last thing Esc reaches, under
## the page and the conversation both. It is the quietest thing on screen.
func test_escape_clears_the_selection_after_everything_louder_than_it() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell

	_click(view, _point_at(view, _inside(screen)))
	shell.set_chat_expanded(true)

	assert_true(shell.close_topmost(), "the conversation is louder, so it goes first")
	assert_false(shell.is_chat_expanded())
	assert_true(shell.is_selection_visible(), "and the selection is still there")

	assert_true(shell.close_topmost())
	assert_false(shell.is_selection_visible())
	assert_false(view.has_selection())
	assert_false(shell.close_topmost(), "with nothing left, Esc falls through to the caller")


func test_the_bands_own_close_lets_the_selection_go() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell

	_click(view, _point_at(view, _inside(screen)))
	var dock := shell.get("_selection_dock") as SelectionDock
	(dock.get("_close") as Button).pressed.emit()

	assert_false(shell.is_selection_visible())
	assert_false(view.has_selection())


## A page covers the selection; it does not cancel it. Making the player find the thing again after
## closing a menu would be the shell forgetting something it was told.
func test_a_page_hides_the_band_and_gives_it_back() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell

	_click(view, _point_at(view, _inside(screen)))
	screen.call("_open_main_menu")
	await wait_process_frames(2)
	assert_true(shell.is_selection_visible(), "the player's selection survives")
	assert_false(shell.is_selection_showing(), "but the band is not on the stage while a page is")
	assert_true(view.has_selection(), "and the map still marks it")

	shell.hide_page()
	await wait_process_frames(2)
	assert_true(shell.is_selection_showing(), "closing the page brings the band back")


## A selected field that is no longer drawn would leave an outline round what now looks like plain
## grass. Bare ground is not affected — it is still there with the works off.
func test_stripping_the_map_back_drops_a_selected_field_but_not_selected_ground() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell
	var terrain := screen.get("_terrain_layer_plate") as SkinnedButton

	_click(view, _point_at(view, _inside(screen)))
	terrain.button.button_pressed = true
	assert_false(shell.is_selection_visible(), "the field is not drawn, so it is not selected")
	assert_false(view.has_selection())

	terrain.button.button_pressed = false
	_click(view, _point_at(view, _wild(screen)))
	assert_true(shell.is_selection_visible())
	terrain.button.button_pressed = true
	assert_true(shell.is_selection_visible(),
		"the ground is still there with the works off, so a selection of it stands")


## The band takes its height out of the conversation's ceiling rather than floating over it, so
## nothing on either is ever covered by the other.
func test_the_band_rests_on_the_conversation_and_shortens_it() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var shell := screen.get("_shell") as HudShell
	shell.set_chat_expanded(true)
	await wait_seconds(HudShell.CHAT_REVEAL_TIME + 0.05)
	var chat_top_alone := (shell.chat_slot as Control).offset_top

	_click(view, _point_at(view, _inside(screen)))
	await wait_process_frames(2)
	var chat := shell.chat_slot as Control
	var band := shell.selection_slot as Control
	assert_true(band.visible)
	assert_almost_eq(band.offset_bottom, chat.offset_top, 0.5,
		"flush on the board's top edge — the chat art has no bottom rule to show")
	assert_almost_eq(band.offset_top, chat.offset_top - SelectionDock.BAND_HEIGHT, 0.5)
	assert_gt(chat.offset_top, chat_top_alone,
		"the conversation's ceiling came down by the band, rather than being covered by it")
	assert_eq(chat.offset_left, band.offset_left, "the two are one surface, so they share a width")
	assert_eq(chat.offset_right, band.offset_right)
