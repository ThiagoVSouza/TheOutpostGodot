extends GutTest


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	return screen


func test_map_layers_panel_controls_the_two_grid_overlays() -> void:
	var screen := _screen()
	screen.call("_open_destination", "map_layers")
	var panels: Dictionary = screen.get("_destination_panels")
	var panel := panels.get("map_layers") as HudPanel
	assert_not_null(panel)
	if panel == null:
		return
	var view := screen.get("_map_view") as OverworldMapView
	var tile_grid := panel.find_child(BaseGameMap.TILE_GRID_TOGGLE_NAME, true, false) as CheckButton
	var subgrid := panel.find_child(BaseGameMap.SUBGRID_TOGGLE_NAME, true, false) as CheckButton
	assert_not_null(tile_grid)
	assert_not_null(subgrid)
	if tile_grid == null or subgrid == null:
		return

	# Both overlays start off, so the page's job here is turning them on and back off again.
	assert_false(view.is_tile_grid_visible())
	tile_grid.toggled.emit(true)
	assert_true(view.is_tile_grid_visible())
	assert_false(view.is_subgrid_visible(), "each row answers only for its own overlay")
	subgrid.toggled.emit(true)
	assert_true(view.is_subgrid_visible())
	tile_grid.toggled.emit(false)
	assert_false(view.is_tile_grid_visible())
	assert_true(view.is_subgrid_visible())
