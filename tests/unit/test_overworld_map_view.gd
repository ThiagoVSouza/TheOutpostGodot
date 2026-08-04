extends GutTest


func _view(view_size: Vector2 = Vector2(1280, 800)) -> OverworldMapView:
	var view := OverworldMapView.new()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = view_size
	add_child_autofree(view)
	view.setup(BaseGameMap.load_map(), {})
	return view


func test_the_construction_map_is_large_and_all_one_biome() -> void:
	var map := BaseGameMap.load_map()
	assert_eq(map.width, BaseGameMap.MAP_WIDTH)
	assert_eq(map.height, BaseGameMap.MAP_HEIGHT)
	assert_gte(map.width, 500)
	assert_eq(map.biome_names(), ["grass"])
	assert_eq(map.biome_at(0, 0), "grass")
	assert_eq(map.biome_at(map.width - 1, map.height - 1), "grass")


## The ground is four variants of one texture, and any of them can end up beside any other — the
## variant is chosen per cell, so every pairing occurs somewhere on a 500x500 map. They therefore
## have to tile against *each other*, not merely against themselves.
func test_the_ground_is_four_interchangeable_variants_of_one_atlas() -> void:
	var textures := BaseGameMap.load_textures(BaseGameMap.load_map())
	var variants: Array = textures["grass"]
	assert_eq(variants.size(), BaseGameMap.GRASS_ATLAS_COLUMNS * BaseGameMap.GRASS_ATLAS_ROWS)
	for variant: Texture2D in variants:
		assert_eq((variant as AtlasTexture).atlas, BaseGameMap.GRASS_ATLAS,
			"every cell on screen draws from one texture, so the canvas can batch them")
		assert_eq(variant.get_size(),
			Vector2(BaseGameMap.GRASS_ATLAS.get_width() / BaseGameMap.GRASS_ATLAS_COLUMNS,
				BaseGameMap.GRASS_ATLAS.get_height() / BaseGameMap.GRASS_ATLAS_ROWS))


## The opening frame is chosen against the selection ladder, not by eye: it has to put a subtile
## clear of [constant OverworldMapView.MIN_SELECTABLE_PX], or the finest thing a player can pick
## would blink in and out with the smallest scroll at the exact zoom the game opens at.
func test_the_opening_frame_leaves_a_subtile_worth_pointing_at() -> void:
	var view := _view()
	assert_almost_eq(view.visible_tile_rows(), OverworldMapView.DEFAULT_VISIBLE_TILE_ROWS, 0.01)

	var subtile := view.footprint_screen_size([Rect2i(0, 0, 1, 1)] as Array[Rect2i])
	assert_gt(subtile.x, OverworldMapView.MIN_SELECTABLE_PX * 1.2,
		"the opening view sits comfortably inside the finest tier, not on its edge")
	assert_true(view.is_footprint_selectable([Rect2i(0, 0, 1, 1)] as Array[Rect2i]))


## Both start off: they are a construction aid, not part of the world, so a player opens into the
## terrain and turns them on when they want to reason about cells.
func test_both_coordinate_layers_start_off_and_are_independently_toggleable() -> void:
	var view := _view()
	assert_false(view.is_tile_grid_visible())
	assert_false(view.is_subgrid_visible())
	assert_eq(OverworldMapView.SUBGRID_DIVISIONS, 5)

	view.set_tile_grid_visible(true)
	assert_true(view.is_tile_grid_visible())
	assert_false(view.is_subgrid_visible(), "each overlay answers only for itself")
	view.set_subgrid_visible(true)
	assert_true(view.is_subgrid_visible())
	view.set_tile_grid_visible(false)
	assert_false(view.is_tile_grid_visible())
	assert_true(view.is_subgrid_visible())


func test_coordinate_layers_use_white_based_lines() -> void:
	for color: Color in [OverworldMapView.TILE_GRID_COLOR, OverworldMapView.SUBGRID_COLOR]:
		assert_eq(color.r, 1.0)
		assert_eq(color.g, 1.0)
		assert_eq(color.b, 1.0)
	assert_gt(OverworldMapView.TILE_GRID_COLOR.a, OverworldMapView.SUBGRID_COLOR.a,
		"tile boundaries remain stronger than the white subgrid")


## A stand-in for the terrain atlas the art will arrive as: four quadrants, four flat colours, so a
## slice's region and a biome's averaged colour are both checkable without shipping a PNG for it.
func _atlas(colors: Array) -> ImageTexture:
	var cell := 64
	var image := Image.create_empty(cell * 2, cell * 2, false, Image.FORMAT_RGBA8)
	for index in 4:
		var origin := Vector2i((index % 2) * cell, (index / 2) * cell)
		image.fill_rect(Rect2i(origin, Vector2i(cell, cell)), colors[index] as Color)
	return ImageTexture.create_from_image(image)


## The project leaves the canvas filter at Godot's own Linear, which never samples a mip level. A
## terrain texture imported *with* mipmaps would still be drawn from its full-size image at every
## zoom, and nothing about that failure announces itself — it just shimmers while the map moves.
func test_the_map_samples_mipmaps_rather_than_the_projects_default_filter() -> void:
	var view := _view()
	assert_eq(view.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)


func test_an_atlas_is_sliced_into_variants_in_reading_order_over_one_texture() -> void:
	var atlas := _atlas([Color.RED, Color.GREEN, Color.BLUE, Color.WHITE])
	var variants := OverworldMapView.slice_variants(atlas, 2, 2)
	assert_eq(variants.size(), 4)

	for variant: Texture2D in variants:
		# The whole point of an atlas here: every cell on screen draws from the same texture, so the
		# canvas can batch them instead of switching texture every few tiles.
		assert_eq((variant as AtlasTexture).atlas, atlas)
		assert_true((variant as AtlasTexture).filter_clip,
			"a variant may not bleed into its neighbour along a shared edge")
	assert_eq((variants[0] as AtlasTexture).region, Rect2(0, 0, 64, 64))
	assert_eq((variants[1] as AtlasTexture).region, Rect2(64, 0, 64, 64),
		"the second variant is the top-right quadrant — reading order, not column order")
	assert_eq((variants[3] as AtlasTexture).region, Rect2(64, 64, 64, 64))


func test_terrain_art_stops_being_drawn_once_a_tile_is_too_small_to_read() -> void:
	var view := _view()
	assert_false(view.is_terrain_textured(), "a map with no art is never textured, at any zoom")

	view.setup(BaseGameMap.load_map(),
		{"grass": OverworldMapView.slice_variants(_atlas(
			[Color.RED, Color.RED, Color.RED, Color.RED]), 2, 2)})
	assert_true(view.is_terrain_textured(), "the default frame is close enough to show the ground")

	# Out to where a tile is smaller than the threshold: the cell loop keeps culling, but it stops
	# doing the per-cell hash and texture lookup that make a redraw expensive.
	var below := OverworldMapView.MIN_TEXTURED_TILE_PX / float(BaseGameMap.TILE_SIZE_PX) * 0.5
	view.call("_zoom_at", Vector2.ZERO, below / view.get("_zoom"))
	assert_lt(float(BaseGameMap.TILE_SIZE_PX) * view.get("_zoom"),
		OverworldMapView.MIN_TEXTURED_TILE_PX)
	assert_false(view.is_terrain_textured())


# --- selection ----------------------------------------------------------------------------------

## The unit a click resolves to is the square the 5x5 overlay draws, so what a player can turn on and
## see is exactly what they can pick.
func test_a_point_resolves_to_the_subtile_the_overlay_draws() -> void:
	var view := _view()
	var step := float(BaseGameMap.TILE_SIZE_PX) / float(OverworldMapView.SUBGRID_DIVISIONS)
	# The map opens centred, so work from wherever the view's own origin landed rather than assuming.
	var origin := view.get("_origin") as Vector2
	var zoom := view.get("_zoom") as float

	# Sampled from the middle of a subtile rather than its corner. On an edge the answer is decided by
	# the last bit of a float, and which side it lands on is not what this is testing.
	var middle := Vector2(step, step) * zoom * 0.5
	var first := view.subtile_at(middle)
	assert_eq(first, Vector2i(int(floor(origin.x / step)), int(floor(origin.y / step))))
	# One subtile to the right on screen is one subtile to the right in the world.
	assert_eq(view.subtile_at(middle + Vector2(step * zoom, 0.0)), first + Vector2i(1, 0))
	assert_eq(view.subtile_at(middle + Vector2(0.0, step * zoom)), first + Vector2i(0, 1))
	# And five of them make a whole map cell.
	assert_eq(view.subtile_at(middle + Vector2(step * zoom * 5.0, 0.0)),
		first + Vector2i(OverworldMapView.SUBGRID_DIVISIONS, 0))


## Off the map is a real answer, not a clamped one: a caller has to be able to tell that a click
## landed on nothing rather than on the edge cell.
func test_a_click_past_the_edge_of_the_world_is_not_clamped_onto_it() -> void:
	var view := _view()
	assert_true(view.has_subtile(Vector2i(0, 0)))
	assert_true(view.has_subtile(
		Vector2i(BaseGameMap.MAP_WIDTH * OverworldMapView.SUBGRID_DIVISIONS - 1, 0)))
	assert_false(view.has_subtile(Vector2i(-1, 0)))
	assert_false(view.has_subtile(
		Vector2i(BaseGameMap.MAP_WIDTH * OverworldMapView.SUBGRID_DIVISIONS, 0)))


## One button pans the map and picks things off it, so the difference is measured rather than
## declared — and it is measured as distance *travelled*, because a pan that wanders back to where it
## started has still moved the world under the player.
func test_a_press_is_a_click_only_if_the_map_did_not_move_under_it() -> void:
	var view := _view()
	var clicked: Array[Vector2i] = []
	view.subtile_clicked.connect(func(subtile: Vector2i) -> void: clicked.append(subtile))

	_press(view, Vector2(400, 300))
	_release(view, Vector2(400, 300))
	assert_eq(clicked.size(), 1, "a press that did not move is a press on something")
	assert_eq(clicked[0], view.subtile_at(Vector2(400, 300)))

	# A drag well past the slop, ending back where it began.
	_press(view, Vector2(400, 300))
	_drag(view, Vector2(60, 0))
	_drag(view, Vector2(-60, 0))
	_release(view, Vector2(400, 300))
	assert_eq(clicked.size(), 1, "the map was panned and put back — that is not a click")

	# A wobble inside the slop still counts: a mouse is never perfectly still.
	_press(view, Vector2(400, 300))
	_drag(view, Vector2(2, 0))
	_release(view, Vector2(402, 300))
	assert_eq(clicked.size(), 2, "a hand is not a vice — a couple of units is still a press")


func _press(view: OverworldMapView, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	view.call("_gui_input", event)


func _release(view: OverworldMapView, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	view.call("_gui_input", event)


func _drag(view: OverworldMapView, by: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = by
	view.call("_gui_input", event)


## The whole selection ladder rests on this one question, so it is asked of the footprint's own size
## on screen rather than of the zoom — which is what lets a farm outlive a subtile without either
## being assigned a tier.
func test_what_is_worth_pointing_at_is_decided_by_its_own_size_on_screen() -> void:
	var view := _view()
	var subtile: Array[Rect2i] = [Rect2i(0, 0, 1, 1)]
	# One tile square, in subtiles — a cottage, the smallest thing anyone would build.
	var cottage: Array[Rect2i] = [Rect2i(0, 0, 5, 5)]
	# Three tiles by two — the shape of a farm plot.
	var farm: Array[Rect2i] = [Rect2i(0, 0, 15, 10)]
	for footprint: Array[Rect2i] in [subtile, cottage, farm]:
		assert_true(view.is_footprint_selectable(footprint),
			"at the opening frame every tier is on")

	# Out far enough that a subtile is a pixel or two and the built things are still tens of them.
	view.call("_zoom_at", Vector2.ZERO, 0.25)
	assert_false(view.is_footprint_selectable(subtile),
		"bare ground retires first, and does it without being told to")
	assert_true(view.is_footprint_selectable(cottage))
	assert_true(view.is_footprint_selectable(farm))

	# And out to the far limit, where the cottage goes the same way in its turn — while the farm,
	# which is six times its area, is still there. Nothing assigned either of them a tier.
	view.call("_zoom_at", Vector2.ZERO, 0.01)
	assert_false(view.is_footprint_selectable(cottage),
		"a smaller building retires earlier than a larger one, by the one rule")
	assert_true(view.is_footprint_selectable(farm),
		"the map does not zoom out far enough to shrink a farm plot past being clickable")
	assert_eq(view.footprint_screen_size([] as Array[Rect2i]), Vector2.ZERO,
		"nothing has no size, and is never selectable")


## The smaller dimension decides: a wall one subtile deep is as hard to click as a subtile, however
## far it runs.
func test_a_long_thin_footprint_is_judged_by_its_narrow_side() -> void:
	var view := _view()
	view.call("_zoom_at", Vector2.ZERO, 0.25)
	assert_false(view.is_footprint_selectable([Rect2i(0, 0, 200, 1)] as Array[Rect2i]))
	assert_true(view.is_footprint_selectable([Rect2i(0, 0, 200, 40)] as Array[Rect2i]))


## Zooming away from the selected thing lets it go. The outline is the only thing keeping it findable,
## and past the threshold it stops enclosing anything a player could act on.
func test_zooming_out_past_a_selection_drops_it_and_says_so() -> void:
	var view := _view()
	var reported: Array = []
	view.selection_changed.connect(func(footprint: Array[Rect2i]) -> void:
		reported.append(footprint))

	view.set_selection([Rect2i(0, 0, 1, 1)] as Array[Rect2i])
	assert_true(view.has_selection())
	assert_eq(reported.size(), 1)

	view.call("_zoom_at", Vector2.ZERO, 0.25)
	assert_false(view.has_selection(), "the player zoomed away from it")
	assert_eq(reported.size(), 2)
	assert_true((reported[1] as Array).is_empty(), "and the caller is told, rather than polling")

	# A farm survives the same zoom, because it is still big enough on screen.
	view.set_selection([Rect2i(0, 0, 15, 10)] as Array[Rect2i])
	view.call("_zoom_at", Vector2.ZERO, 0.9)
	assert_true(view.has_selection())


## The view is handed a footprint and never works one out — which is what keeps it free of anything
## content-specific, exactly as markers are.
func test_the_selection_is_reported_only_when_it_actually_changes() -> void:
	var view := _view()
	# An array, not an int: a GDScript lambda captures a local by *value*, so a plain counter would be
	# incremented on a copy and read back as zero.
	var changes := [0]
	view.selection_changed.connect(func(_f: Array[Rect2i]) -> void: changes[0] += 1)

	view.set_selection([Rect2i(3, 4, 1, 1)] as Array[Rect2i])
	assert_eq(changes[0], 1)
	view.set_selection([Rect2i(3, 4, 1, 1)] as Array[Rect2i])
	assert_eq(changes[0], 1, "selecting what is already selected is not a change")
	assert_eq(view.selection(), [Rect2i(3, 4, 1, 1)] as Array[Rect2i])
	view.clear_selection()
	assert_eq(changes[0], 2)
	assert_false(view.has_selection())
	view.clear_selection()
	assert_eq(changes[0], 2)


# --- layers -------------------------------------------------------------------------------------

## The ground has no flag of its own — it is the surface the others stand on. What "terrain only"
## means is that the two layers above it come off.
func test_the_layers_above_the_ground_are_independently_switchable() -> void:
	var view := _view()
	view.set_scatter({"grass": [_atlas([Color.RED, Color.RED, Color.RED, Color.RED])]})
	assert_true(view.is_construction_layer_visible())
	assert_true(view.is_units_layer_visible())
	assert_true(view.is_scatter_visible())

	view.set_construction_layer_visible(false)
	assert_false(view.is_construction_layer_visible())
	assert_false(view.is_scatter_visible(),
		"a tree is something standing on the ground, so it belongs to that layer")
	assert_true(view.is_units_layer_visible(), "each layer answers only for itself")

	view.set_units_layer_visible(false)
	assert_false(view.is_units_layer_visible())
	view.set_construction_layer_visible(true)
	assert_true(view.is_scatter_visible())


## Working the ground clears what stood on it. The scatter pass keys on what a cell's ground *is*, so
## a field carries nothing simply by having no scatter of its own — no rule about farms anywhere.
func test_nothing_is_left_standing_on_ground_that_has_been_worked() -> void:
	var view := _view()
	var tree := _atlas([Color.GREEN, Color.GREEN, Color.GREEN, Color.GREEN])
	view.set_scatter({"grass": [tree]})
	var ploughed := Vector2i(10, 10)
	view.set_ground_overrides({ploughed: BaseGameMap.FARM_GROUND})

	assert_eq(view.call("_scatter_variants", ploughed.x, ploughed.y), [],
		"a pine does not stand in the middle of a ploughed field")
	assert_eq((view.call("_scatter_variants", 11, 10) as Array).size(), 1,
		"and the grass beside it is unaffected — its canopy may still lean over the furrows")

	# Give the worked ground something of its own and it carries it, by the same lookup.
	view.set_scatter({"grass": [tree], BaseGameMap.FARM_GROUND: [tree]})
	assert_eq((view.call("_scatter_variants", ploughed.x, ploughed.y) as Array).size(), 1,
		"an orchard's trees or a quarry's rubble arrive by being given one, not by a new rule")


## A ploughed field is something done *to* grass. Hide the works and the grass is what is left — not
## a hole, and not the field still drawn under a flag saying it is hidden.
func test_hiding_the_constructions_leaves_the_ground_they_were_made_from() -> void:
	var view := _view()
	var cell := Vector2i(10, 10)
	view.set_ground_overrides({cell: BaseGameMap.FARM_GROUND})
	assert_eq(view.call("_ground_key", cell.x, cell.y), BaseGameMap.FARM_GROUND)

	view.set_construction_layer_visible(false)
	assert_eq(view.call("_ground_key", cell.x, cell.y), "grass",
		"the field comes off and the grass it was ploughed from is underneath")

	view.set_construction_layer_visible(true)
	assert_eq(view.call("_ground_key", cell.x, cell.y), BaseGameMap.FARM_GROUND)


func test_the_flat_colour_a_zoomed_out_map_falls_back_to_is_averaged_from_its_own_art() -> void:
	var view := _view()
	assert_eq(view.call("_biome_color", "grass"), OverworldMapView.FALLBACK_COLORS["grass"],
		"with no art there is nothing to average, so the hand-picked table stands")

	var blue := Color(0.0, 0.0, 1.0)
	view.setup(BaseGameMap.load_map(),
		{"grass": OverworldMapView.slice_variants(_atlas([blue, blue, blue, blue]), 2, 2)})
	var averaged := view.call("_biome_color", "grass") as Color
	assert_gt(averaged.b, averaged.r + averaged.g,
		"crossing the threshold loses detail, not hue — the flat colour comes from the art itself")
