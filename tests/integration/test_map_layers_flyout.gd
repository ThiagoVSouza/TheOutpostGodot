extends GutTest

## The desktop map-layers shortcut opens its layers where it stands, over the map they change,
## rather than sending the player to a page that covers both. These assertions cover the three
## things that arrangement promises: the column arrives above the plate that opened it, a layer
## plate really reaches the map, and nothing of it survives a page taking the stage.


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	# Wide enough to be the desktop layout: below the breakpoint there is no shortcut to press.
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	return screen


func _open(shell: HudShell) -> void:
	var button := shell.get("_map_layers_button") as SkinnedButton
	button.button.button_pressed = true
	shell.call("_toggle_map_layers")
	await wait_seconds(HudShell.MAP_LAYERS_REVEAL_TIME + 0.05)


func test_the_column_unrolls_upward_from_the_shortcut_it_belongs_to() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var button := shell.get("_map_layers_button") as SkinnedButton
	var flyout := shell.get("_map_layers_flyout") as Control
	assert_false(flyout.visible, "the layers stay closed until the shortcut is pressed")

	await _open(shell)
	var plate_rect := button.get_global_rect()
	var column_rect := flyout.get_global_rect()
	assert_true(flyout.visible)
	assert_almost_eq(column_rect.end.y - plate_rect.end.y, UiSkin.MAP_LAYERS_COLUMN_PADDING, 0.5,
		"the column closes under the shortcut by the same moulding it carries on every other side")
	assert_almost_eq(column_rect.position.x, plate_rect.position.x
		- UiSkin.MAP_LAYERS_COLUMN_PADDING, 0.5,
		"and that moulding is the same on the sides — the plate is seated, not poking out")
	assert_lt(column_rect.position.y, plate_rect.position.y,
		"it opens upward, over the map, and never below the plate")
	assert_almost_eq(column_rect.get_center().x, plate_rect.get_center().x, 0.5,
		"the column is centred on the plate it grew out of")
	assert_gte(column_rect.size.x, plate_rect.size.x,
		"the shortcut sits inside the column rather than beside it")
	assert_true(button.button.button_pressed,
		"the shortcut holds its selected state while its layers are on screen")


func test_the_grid_plate_drives_both_coordinate_overlays_together() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var view := screen.get("_map_view") as OverworldMapView
	var grid := screen.get("_grid_layer_plate") as SkinnedButton
	assert_not_null(grid)
	if grid == null:
		return

	await _open(shell)
	# The overlays start off, so the plate opens unlatched — stating the map's real condition rather
	# than a default of its own.
	assert_false(grid.button.button_pressed, "the plate opens stating the map's real condition")
	assert_false(view.is_tile_grid_visible())
	grid.button.button_pressed = true
	assert_true(view.is_tile_grid_visible())
	assert_true(view.is_subgrid_visible(),
		"the subgrid is part of the same layer — one plate draws both or neither")
	grid.button.button_pressed = false
	assert_false(view.is_tile_grid_visible())
	assert_false(view.is_subgrid_visible(),
		"and it cannot be left drawn over a hidden grid")


## The Terrain plate strips the map back to bare ground: it does not hide the terrain — there would
## be nothing left to draw — it hides everything standing on it, constructions and units together.
func test_the_terrain_plate_strips_the_map_back_to_bare_ground() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var terrain := screen.get("_terrain_layer_plate") as SkinnedButton
	assert_not_null(terrain)
	if terrain == null:
		return
	assert_false(terrain.button.button_pressed,
		"the map opens as the world, with everything on it — stripping it back is what you ask for")
	assert_true(view.is_construction_layer_visible())
	assert_true(view.is_units_layer_visible())

	terrain.button.button_pressed = true
	assert_false(view.is_construction_layer_visible(),
		"the works come off: ploughed fields, trees, and whatever is built later")
	assert_false(view.is_units_layer_visible(),
		"and the things that move over them go at the same time")
	assert_false(view.is_scatter_visible(),
		"nothing standing on the ground is drawn while the layer it belongs to is off")
	assert_false(view.is_tile_grid_visible(),
		"the coordinate overlays are a separate plate and are not touched either way")

	terrain.button.button_pressed = false
	assert_true(view.is_construction_layer_visible(), "and the world comes back")
	assert_true(view.is_units_layer_visible())


## A name comes out from behind the plate it belongs to, not from behind the chrome: the column has
## to draw *under* the label and its plates *over* it, or a layer's name appears to emerge from the
## background instead of from the button.
func test_a_layer_names_itself_from_behind_its_own_plate() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var grid := screen.get("_grid_layer_plate") as SkinnedButton
	var label_clip := shell.get("_map_layers_label_clip") as Control
	var flyout := shell.get("_map_layers_flyout") as Control
	var box := shell.get("_map_layers_box") as Control

	assert_lt(flyout.z_index, label_clip.z_index, "the column's parchment draws under the label")
	assert_gt(flyout.z_index + box.z_index, label_clip.z_index,
		"its plates still cover the overlapping cap the label opens underneath")

	await _open(shell)
	shell.call("_show_map_layers_label", "Grid", grid)
	await wait_seconds(HudShell.RAIL_LABEL_TIME + 0.05)
	assert_true(label_clip.visible)
	assert_almost_eq(label_clip.get_global_rect().end.x,
		grid.get_global_rect().position.x + HudShell.RAIL_LABEL_OVERLAP, 0.1,
		"only the label's own cap is hidden, and it is the plate that hides it")


func test_a_page_takes_the_layers_off_the_screen_with_the_shortcut() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var flyout := shell.get("_map_layers_flyout") as Control
	var button := shell.get("_map_layers_button") as SkinnedButton

	await _open(shell)
	screen.call("_open_destination", "domain")
	assert_false(flyout.visible, "no tail of the column is left over a newly opened page")
	assert_false(button.button.button_pressed,
		"the shortcut cannot keep claiming to be open once its column has gone")
	assert_false(shell.is_map_layers_open())


func test_escape_closes_the_layers_before_anything_underneath_them() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell

	await _open(shell)
	assert_true(shell.close_topmost(), "the flyout is what one press of Esc reaches for")
	assert_false(shell.is_map_layers_open())
	assert_false(shell.is_chat_expanded(),
		"closing the layers must not have disturbed the conversation underneath them")
