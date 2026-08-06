extends GutTest

## The map's content as *things* rather than as coloured cells — which is what a player clicking one
## is asking for, and what the renderer never needed.


func _map() -> TerrainMap:
	return BaseGameMap.load_map()


func _view() -> OverworldMapView:
	var view := OverworldMapView.new()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 800)
	add_child_autofree(view)
	view.setup(BaseGameMap.load_map(), {})
	return view


func test_every_plot_is_an_identified_construction_sited_on_the_outpost() -> void:
	var map := _map()
	var built := BaseGameMap.constructions(map)
	assert_eq(built.size(), BaseGameMap.FARM_CELLS.size())

	var site := BaseGameMap.outpost_site(map)
	var ids: Array = []
	for construction: Dictionary in built:
		assert_false(String(construction["id"]).is_empty())
		assert_false(ids.has(construction["id"]), "an id nothing else answers to")
		ids.append(construction["id"])
		assert_eq(String(construction["kind"]), BaseGameMap.KIND_CONSTRUCTION)
		assert_eq(String(construction["ground"]), BaseGameMap.FARM_GROUND)
		# **A field is one cell and complete in itself.** Tiling one across several cells would show
		# its ragged edge through the middle of what is meant to be a single field.
		var cells := construction["cells"] as Rect2i
		assert_eq(cells.size, Vector2i.ONE, "a field is one cell")
		# Placed against the settlement, so they stay with it if the siting rule changes.
		assert_lt((Vector2(cells.get_center()) - Vector2(site)).length(), 10.0)


## No two fields may claim the same cell — two sprites drawn exactly on top of each other look like
## one field, so the duplicate is invisible rather than obviously wrong.
func test_no_two_fields_stand_on_the_same_cell() -> void:
	var seen: Dictionary = {}
	for cell: Vector2i in BaseGameMap.FARM_CELLS:
		assert_false(seen.has(cell), "cell %s is claimed twice" % cell)
		seen[cell] = true


# --- the crop cycle -----------------------------------------------------------------------------

## The sheet holds one frame per stage, and the enum is what indexes it — so a stage added to one and
## not the other is caught here rather than by a field going invisible on the map.
func test_the_sheet_holds_one_frame_for_every_crop_stage() -> void:
	var frames := BaseGameMap.farm_frames()
	assert_eq(frames.size(), BaseGameMap.CropStage.size())
	assert_eq(BaseGameMap.CROP_STAGE_TITLES.size(), BaseGameMap.CropStage.size())
	for frame: Texture2D in frames:
		assert_not_null(frame)
		assert_eq(frame.get_size(), Vector2(BaseGameMap.FARM_ATLAS_CELL,
			BaseGameMap.FARM_ATLAS_CELL), "every cell is the whole square, overhang included")


## **The frames must not move against each other.** They are the same field at four moments, drawn one
## after another in the same place, so a frame cut from a different position would make the field jump
## sideways as the crop advances — which reads as a bug in the map rather than in the sheet.
func test_the_frames_are_cut_on_one_pitch() -> void:
	var frames := BaseGameMap.farm_frames()
	for index in frames.size():
		var region := (frames[index] as AtlasTexture).region
		assert_eq(region.position, Vector2(BaseGameMap.FARM_ATLAS_ORIGIN)
			+ Vector2(float(index * BaseGameMap.FARM_ATLAS_CELL), 0.0),
			"frame %d is on the pitch" % index)


## The stage the fields are at changes what they are called and what is drawn, and nothing else.
func test_the_crop_stage_changes_the_art_and_the_name_of_every_field() -> void:
	var map := _map()
	var was := BaseGameMap.crop_stage
	var seen: Array = []
	for stage: int in [BaseGameMap.CropStage.PLOUGHED, BaseGameMap.CropStage.RIPE]:
		BaseGameMap.crop_stage = stage as BaseGameMap.CropStage
		assert_eq(String(BaseGameMap.constructions(map)[0]["title"]),
			String(BaseGameMap.CROP_STAGE_TITLES[stage]))
		var texture := BaseGameMap.farm_texture()
		assert_false(seen.has(texture), "a different stage is a different frame")
		seen.append(texture)
		# The ground entry under the field is the same frame, so the flat colour the map falls back to
		# when it is zoomed out is the average of the crop actually standing there.
		assert_eq((BaseGameMap.load_textures(map)[BaseGameMap.FARM_GROUND] as Array)[0], texture)
	BaseGameMap.crop_stage = was


# --- houses ---------------------------------------------------------------------------------------

## A house stands on **one subtile** and is drawn much larger than one. Both halves matter: the first
## is what it occupies, the second is what you see.
func test_a_house_occupies_one_subtile_and_is_drawn_wider_than_it() -> void:
	var map := _map()
	var built := BaseGameMap.houses(map)
	assert_eq(built.size(), BaseGameMap.HOUSE_SUBTILES.size())

	var ids: Array = []
	for house: Dictionary in built:
		assert_false(ids.has(house["id"]), "an id nothing else answers to")
		ids.append(house["id"])
		assert_eq(String(house["kind"]), BaseGameMap.KIND_CONSTRUCTION)
		assert_true(house.has("subtile"), "founded on a subtile, not on a cell")

	# **The building itself is exactly one subtile**, and only its overhang reaches past that.
	var subtile := 1.0 / float(BaseGameMap.SUBTILES_PER_TILE)
	var building := BaseGameMap.HOUSE_TILE_WIDTH * float(Buildings.NOMINAL_PX) \
		/ float(Buildings.ATLAS_CELL)
	assert_almost_eq(building, subtile, 0.0001,
		"the house is drawn the size of the square it stands on")
	assert_gt(BaseGameMap.HOUSE_TILE_WIDTH, subtile,
		"and its art reaches past that — eaves and rubble are not contained by a doorstep")
	# A field is a whole cell, so it is five houses across and twenty-five in area.
	assert_almost_eq(BaseGameMap.FARM_TILE_WIDTH * float(BaseGameMap.FARM_TILE_PX)
		/ float(BaseGameMap.FARM_ATLAS_CELL), 1.0, 0.0001, "a field is one whole tile")


## Two houses on one subtile would be two paintings exactly on top of each other, which looks like one
## house rather than like an obvious mistake.
func test_no_two_houses_stand_on_the_same_subtile() -> void:
	var seen: Dictionary = {}
	for subtile: Vector2i in BaseGameMap.HOUSE_SUBTILES:
		assert_false(seen.has(subtile), "subtile %s is claimed twice" % subtile)
		seen[subtile] = true


## The hamlet has to stand clear of the fields and of the demonstration road figure — a house dropped
## on top of either would hide the thing it landed on and read as a rendering fault.
func test_the_hamlet_stands_clear_of_the_fields_and_the_roads() -> void:
	var map := _map()
	var paved: Dictionary = {}
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		paved[at] = true
	for house: Dictionary in BaseGameMap.houses(map):
		var subtile := house["subtile"] as Vector2i
		assert_false(paved.has(subtile), "house at %s stands on a road" % subtile)
		assert_true(BaseGameMap.construction_at(map, subtile / BaseGameMap.SUBTILES_PER_TILE).is_empty(),
			"house at %s stands in a field" % subtile)


## Click a house and get the house, at the granularity it occupies — one subtile, the same as a road,
## and unlike a field which is a whole cell.
func test_clicking_a_house_selects_the_subtile_it_stands_on() -> void:
	var map := _map()
	var view := _view()
	var subtile := (BaseGameMap.houses(map)[0]["subtile"]) as Vector2i

	var picked := BaseGameMap.selection_at(map, view, subtile)
	assert_eq(String(picked["kind"]), BaseGameMap.KIND_CONSTRUCTION)
	assert_eq(String(picked["title"]), Buildings.title())
	assert_eq((picked["footprint"] as Array[Rect2i]), [Rect2i(subtile, Vector2i.ONE)] as Array[Rect2i],
		"the subtile it is founded on, not the extent of its painting")
	assert_true(bool(picked["owned"]))

	# One subtile over is open ground, however much roof is drawn above it.
	assert_eq(String(BaseGameMap.selection_at(map, view, subtile + Vector2i(1, 0))["kind"]),
		BaseGameMap.KIND_TERRAIN)

	# With the works hidden, the house goes and the ground it stands on is what is left.
	assert_eq(String(BaseGameMap.selection_at(map, view, subtile, false)["kind"]),
		BaseGameMap.KIND_TERRAIN)


## A house refuses the subtile it stands on and nothing more — a road running up to a door is a road
## running up to a door.
func test_a_road_may_not_be_laid_through_a_house_but_may_run_up_to_it() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	var subtile := (BaseGameMap.houses(map)[0]["subtile"]) as Vector2i

	assert_false(BaseGameMap.can_build_road(map, subtile, roads))
	assert_eq(BaseGameMap.plan_state(map, subtile, roads, BaseGameMap.TOOL_ROAD), "invalid",
		"and it shows red rather than being quietly skipped")
	assert_true(BaseGameMap.can_build_road(map, subtile + Vector2i(1, 0), roads),
		"the next subtile along is open ground, whatever is drawn over it")


func test_each_house_is_handed_to_the_map_as_one_standing_item_over_its_subtile() -> void:
	var map := _map()
	var items := BaseGameMap.house_standing(map)
	var built := BaseGameMap.houses(map)
	assert_eq(items.size(), built.size())

	for index in items.size():
		var item: Dictionary = items[index]
		var subtile := built[index]["subtile"] as Vector2i
		var expected := (Vector2(subtile) + Vector2(0.5, 0.5)) / float(BaseGameMap.SUBTILES_PER_TILE)
		assert_almost_eq((item["at"] as Vector2).x, expected.x, 0.0001, "centred on its subtile")
		assert_almost_eq((item["at"] as Vector2).y, expected.y, 0.0001)
		assert_eq(item["anchor"] as Vector2, Vector2(0.5, 0.5),
			"painted looking down on the roof, so it sits centred in its own cell")
		assert_eq(item["texture"] as Texture2D, Buildings.texture())
		assert_eq(item["cells"] as Array, [subtile / BaseGameMap.SUBTILES_PER_TILE],
			"it shades its whole cell, so nothing scatters through it")


## Fields and houses reach the map as one list, because they have to sort against each other and
## against the trees — two lists could only ever put every house in front of every field.
func test_everything_standing_on_the_ground_is_handed_over_together() -> void:
	var map := _map()
	assert_eq(BaseGameMap.standing(map).size(),
		BaseGameMap.farm_standing(map).size() + BaseGameMap.house_standing(map).size())


## What the map is handed to draw: one item per field, anchored on the cell's centre because a field
## lies flat and has no front edge, and wider than its cell because its edge spills past it.
## A farm is one cell and one selectable thing, but it is *drawn* as a grid of smaller plots — so a
## field is not five times a cottage across.
func test_a_field_is_drawn_as_a_grid_of_plots_that_exactly_covers_its_cell() -> void:
	var map := _map()
	var items := BaseGameMap.farm_standing(map)
	var built := BaseGameMap.constructions(map)
	var per_cell := BaseGameMap.FARM_SPRITES_PER_CELL
	assert_eq(items.size(), built.size() * per_cell * per_cell)

	# Every plot of the first farm, against the cell it has to cover between them.
	var cell := (built[0]["cells"] as Rect2i).position
	var plots: Array = []
	for item: Dictionary in items:
		if (item["cells"] as Array)[0] == cell:
			plots.append(item)
	assert_eq(plots.size(), per_cell * per_cell)

	var step := 1.0 / float(per_cell)
	for plot: Dictionary in plots:
		assert_eq(plot["anchor"] as Vector2, Vector2(0.5, 0.5), "flat on the ground, so no front edge")
		# **The nominal art is exactly one plot wide**, so the grid tiles the cell with no gap and no
		# double coverage — that is what keeps the ground override underneath from ever showing.
		var nominal := float(plot["tile_width"]) * float(BaseGameMap.FARM_TILE_PX) \
			/ float(BaseGameMap.FARM_ATLAS_CELL)
		assert_almost_eq(nominal, step, 0.0001, "a plot is one over %d of a tile" % per_cell)
		assert_gt(float(plot["tile_width"]), nominal, "and its ragged edge reaches past that")
		# Anchored on a plot's own centre, so the whole grid sits inside the cell.
		var offset := (plot["at"] as Vector2) - Vector2(cell)
		assert_gt(offset.x, 0.0)
		assert_lt(offset.x, 1.0)
		assert_gt(offset.y, 0.0)
		assert_lt(offset.y, 1.0)

	# Between them the plots cover the cell exactly: the first is half a step in from the corner and
	# the last half a step in from the far side.
	var corners: Array = []
	for plot: Dictionary in plots:
		corners.append((plot["at"] as Vector2) - Vector2(cell))
	corners.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y * 10.0 + a.x < b.y * 10.0 + b.x)
	assert_almost_eq((corners[0] as Vector2).x, step * 0.5, 0.0001)
	assert_almost_eq((corners[corners.size() - 1] as Vector2).y, 1.0 - step * 0.5, 0.0001)


## The one guarantee the renderer depends on: what the player can select and what the map draws are
## derived from the same list, so they cannot describe different cells.
func test_the_drawn_ground_is_derived_from_the_same_constructions_the_player_selects() -> void:
	var map := _map()
	var overrides := BaseGameMap.load_ground_overrides(map)
	assert_false(overrides.is_empty())

	var counted := 0
	for construction: Dictionary in BaseGameMap.constructions(map):
		var cells := construction["cells"] as Rect2i
		counted += cells.size.x * cells.size.y
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				assert_eq(String(overrides.get(Vector2i(x, y), "")), BaseGameMap.FARM_GROUND,
					"every cell of a construction is ploughed ground on the map")
	assert_eq(overrides.size(), counted, "and nothing is ploughed that no construction stands on")


## Point 4 of the selection brief: click any part of a thing and get the whole of it.
func test_any_cell_of_a_plot_answers_with_the_whole_plot() -> void:
	var map := _map()
	var first := BaseGameMap.constructions(map)[0]
	var cells := first["cells"] as Rect2i

	for y in range(cells.position.y, cells.end.y):
		for x in range(cells.position.x, cells.end.x):
			var found := BaseGameMap.construction_at(map, Vector2i(x, y))
			assert_eq(String(found.get("id", "")), String(first["id"]),
				"the corner and the middle are the same farm")

	# A cell just outside it belongs to nothing.
	assert_true(BaseGameMap.construction_at(map,
		cells.position - Vector2i(1, 1)).is_empty())


func test_a_constructions_footprint_is_its_cells_in_subtiles() -> void:
	var built := {"cells": Rect2i(10, 20, 3, 2)}
	var footprint := BaseGameMap.construction_footprint(built)
	assert_eq(footprint.size(), 1)
	assert_eq(footprint[0], Rect2i(50, 100, 15, 10),
		"five subtiles to the tile, on both axes")
	# Bare ground takes the same shape, so nothing downstream treats it as a special case.
	assert_eq(BaseGameMap.subtile_footprint(Vector2i(7, 9)), [Rect2i(7, 9, 1, 1)] as Array[Rect2i])


# --- the ladder ---------------------------------------------------------------------------------

func test_clicking_a_plot_selects_the_whole_plot_and_clicking_beside_it_selects_the_ground() -> void:
	var map := _map()
	var view := _view()
	var plot := (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i
	# A subtile in the middle of the plot's first cell.
	var inside := plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)

	var picked := BaseGameMap.selection_at(map, view, inside)
	assert_eq(String(picked["kind"]), BaseGameMap.KIND_CONSTRUCTION)
	assert_eq(String(picked["title"]), String(BaseGameMap.CROP_STAGE_TITLES[int(BaseGameMap.crop_stage)]),
		"a field is named for the crop standing in it")
	assert_true(bool(picked["owned"]), "a field is something the settlement holds")
	assert_eq((picked["footprint"] as Array[Rect2i])[0],
		Rect2i(plot.position * 5, plot.size * 5), "the whole plot, from one subtile of it")

	# Well clear of every plot.
	var wild := (plot.position - Vector2i(30, 30)) * BaseGameMap.SUBTILES_PER_TILE
	var ground := BaseGameMap.selection_at(map, view, wild)
	assert_eq(String(ground["kind"]), BaseGameMap.KIND_TERRAIN)
	assert_eq(String(ground["title"]), "Grassland", "the word for the biome, not its texture key")
	assert_false(bool(ground["owned"]), "nobody holds wild ground")
	assert_eq((ground["footprint"] as Array[Rect2i])[0], Rect2i(wild, Vector2i.ONE),
		"one subtile, and only the one that was clicked")


## The Terrain plate takes the works away; a click then lands on the ground they were built on.
func test_with_the_constructions_hidden_a_plot_is_the_ground_it_was_made_from() -> void:
	var map := _map()
	var view := _view()
	var plot := (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i
	var inside := plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)

	var picked := BaseGameMap.selection_at(map, view, inside, false)
	assert_eq(String(picked["kind"]), BaseGameMap.KIND_TERRAIN)
	assert_eq((picked["footprint"] as Array[Rect2i])[0], Rect2i(inside, Vector2i.ONE))


## The ladder's whole point: what a click can reach changes with the zoom, and this method never
## learns what zoom is — it asks the view whether each candidate is worth aiming at.
func test_zooming_out_takes_bare_ground_off_the_ladder_before_the_plot() -> void:
	var map := _map()
	var view := _view()
	var plot := (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i
	var inside := plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)
	var wild := (plot.position - Vector2i(30, 30)) * BaseGameMap.SUBTILES_PER_TILE

	# Out to where a subtile is a few units across and a whole cell is tens of them. Stated as a size
	# rather than as a zoom factor, because the ladder is a rule about sizes and the opening frame is a
	# dial that moves — see `_zoom_to_subtile` in `test_overworld_map_view.gd`.
	var step := float(BaseGameMap.TILE_SIZE_PX) / float(BaseGameMap.SUBTILES_PER_TILE)
	view.call("_zoom_at", Vector2.ZERO, (5.0 / step) / (view.get("_zoom") as float))
	assert_true(BaseGameMap.selection_at(map, view, wild).is_empty(),
		"bare ground is too small to point at, so a click on it means nothing")
	assert_eq(String(BaseGameMap.selection_at(map, view, inside)["kind"]),
		BaseGameMap.KIND_CONSTRUCTION, "the plot is still worth aiming at")


# --- building -----------------------------------------------------------------------------------

## The one rule the brief asked for: open ground only. A construction owns whole cells, so a road may
## not cross a ploughed field.
func test_a_road_may_not_be_laid_across_a_field() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	var plot := (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i
	var on_field := plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)
	var open := (plot.position - Vector2i(8, 8)) * BaseGameMap.SUBTILES_PER_TILE

	assert_false(BaseGameMap.can_build_road(map, on_field, roads))
	assert_true(BaseGameMap.can_build_road(map, open, roads))
	assert_eq(BaseGameMap.plan_state(map, on_field, roads, BaseGameMap.TOOL_ROAD), "invalid",
		"and it shows red rather than being quietly skipped — the gap needs explaining")
	assert_eq(BaseGameMap.plan_state(map, open, roads, BaseGameMap.TOOL_ROAD), "valid")


## Painting back over a road you have just drawn is how anyone draws. Flashing it red would be
## telling the player off for the ordinary way of holding the tool.
func test_drawing_over_a_road_already_there_is_nothing_to_do_rather_than_an_error() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	var open := Vector2i(60, 60)
	roads.add(open)
	assert_eq(BaseGameMap.plan_state(map, open, roads, BaseGameMap.TOOL_ROAD), "skip")
	assert_false(BaseGameMap.can_build_road(map, open, roads))


func test_demolishing_finds_roads_and_ignores_everything_else() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	var paved := Vector2i(60, 60)
	roads.add(paved)
	assert_eq(BaseGameMap.plan_state(map, paved, roads, BaseGameMap.TOOL_DEMOLISH), "valid")
	assert_eq(BaseGameMap.plan_state(map, paved + Vector2i(1, 0), roads,
		BaseGameMap.TOOL_DEMOLISH), "skip",
		"dragging across bare ground on the way to a road is not an error")


## A road is one subtile and selecting one selects only that — unlike a farm, whose cells are one
## thing built at one moment.
func test_clicking_a_road_selects_that_one_piece_of_it() -> void:
	var map := _map()
	var view := _view()
	var roads := RoadNetwork.new()
	var here := Vector2i(60, 60)
	for x in range(60, 70):
		roads.add(Vector2i(x, 60))

	var picked := BaseGameMap.selection_at(map, view, here, true, roads)
	assert_eq(String(picked["kind"]), BaseGameMap.KIND_ROAD)
	assert_eq(String(picked["title"]), "Road")
	assert_eq((picked["footprint"] as Array[Rect2i]), [Rect2i(here, Vector2i.ONE)] as Array[Rect2i],
		"one square, not the whole run it belongs to")

	# With the works hidden, the road is hidden too, and the click lands on the ground beneath it.
	var under := BaseGameMap.selection_at(map, view, here, false, roads)
	assert_eq(String(under["kind"]), BaseGameMap.KIND_TERRAIN)


# --- the demonstration network ---------------------------------------------------------------

## The whole reason the figure exists: a wrong atlas should be obvious the moment the map opens,
## rather than after somebody happens to draw the one junction that is broken. That only holds if
## every piece is actually on screen, which is a property of the shape and is therefore checkable.
func test_the_demonstration_figure_puts_all_sixteen_pieces_on_the_map() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		roads.add(at)
	assert_gt(roads.count(), 0)

	var seen: Dictionary = {}
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		seen[roads.mask_at(at)] = true
	var missing: Array = []
	for mask in 16:
		if not seen.has(mask):
			missing.append(mask)
	assert_eq(missing, [], "every piece of the sheet is demonstrated; masks missing: %s" % [missing])


## The figure stands on open ground. A stretch of it buried under a ploughed field would be a piece
## the player cannot see, which is the one thing it is for.
func test_the_demonstration_figure_avoids_the_fields() -> void:
	var map := _map()
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		var cell := at / BaseGameMap.SUBTILES_PER_TILE
		assert_true(BaseGameMap.construction_at(map, cell).is_empty(),
			"subtile %s sits on a construction" % at)


## The four dead-ends and the lone stub only read as themselves while nothing touches them. Two marks
## drifting into contact would quietly turn a pair of dead-ends into a straight.
func test_the_stubs_stay_clear_of_everything_else() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		roads.add(at)
	var origin := BaseGameMap.outpost_site(map) * BaseGameMap.SUBTILES_PER_TILE
	var stubs := origin + BaseGameMap.DEMO_ROAD_STUBS_ORIGIN

	assert_eq(roads.mask_at(stubs), 0, "the lone stub is attached to nothing")
	assert_eq(roads.mask_at(stubs + Vector2i(3, 0)), RoadNetwork.EAST)
	assert_eq(roads.mask_at(stubs + Vector2i(4, 0)), RoadNetwork.WEST)
	assert_eq(roads.mask_at(stubs + Vector2i(7, 0)), RoadNetwork.SOUTH)
	assert_eq(roads.mask_at(stubs + Vector2i(7, 1)), RoadNetwork.NORTH)


## The second row is about arrangements rather than pieces, so what is worth asserting is that each
## figure really is the shape it is meant to be — and above all that none of them has joined onto its
## neighbour, which would silently turn the whole row into one blob and lose every case in it.
func test_the_awkward_figures_are_the_shapes_they_are_meant_to_be() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	for at: Vector2i in BaseGameMap.demonstration_roads(map):
		roads.add(at)
	var origin := (BaseGameMap.outpost_site(map) * BaseGameMap.SUBTILES_PER_TILE
		+ BaseGameMap.DEMO_ROAD_FIGURES_ORIGIN)
	var all := RoadNetwork.NORTH | RoadNetwork.EAST | RoadNetwork.SOUTH | RoadNetwork.WEST

	# The solid block: a crossroads in the middle, hemmed in on all four sides.
	assert_eq(roads.mask_at(origin + Vector2i(55, 1)), all, "the block's centre is a crossroads")
	# The tight ring: its corners are corners, one subtile of straight apart.
	assert_eq(roads.mask_at(origin + Vector2i(48, 0)),
		RoadNetwork.EAST | RoadNetwork.SOUTH, "the ring's top-left is a corner")
	assert_eq(roads.mask_at(origin + Vector2i(50, 2)),
		RoadNetwork.NORTH | RoadNetwork.WEST, "and its bottom-right is the opposite corner")
	# The comb: the same T-junction repeated along one spine.
	for tooth: int in [1, 3, 5]:
		assert_eq(roads.mask_at(origin + Vector2i(tooth, 0)),
			RoadNetwork.EAST | RoadNetwork.SOUTH | RoadNetwork.WEST,
			"the spine carries a T over tooth %d" % tooth)
		assert_eq(roads.mask_at(origin + Vector2i(tooth, 2)), RoadNetwork.NORTH,
			"and each tooth ends in a dead end")

	# **The two parallel runs must stay two runs.** If they ever touched, every piece in them would
	# gain a north or south link and the case would be gone without anything failing.
	for i in 5:
		for row: int in [0, 2]:
			var mask := roads.mask_at(origin + Vector2i(10 + i, row))
			assert_eq(mask & (RoadNetwork.NORTH | RoadNetwork.SOUTH), 0,
				"the runs are one subtile apart and must not join")
	assert_false(roads.has_road(origin + Vector2i(12, 1)), "the gap between them stays empty")


## Each figure has to stand clear of the next, or two of them become one shape and the arrangement
## being demonstrated is lost.
func test_no_two_demonstration_figures_touch_each_other() -> void:
	var map := _map()
	var roads := RoadNetwork.new()
	var placed: Array[Vector2i] = BaseGameMap.demonstration_roads(map)
	for at: Vector2i in placed:
		roads.add(at)
	# Every road is reachable from some other road, or is one of the deliberate lone stubs. What must
	# not happen is a *diagonal* touch between figures, which no mask would ever reveal.
	var occupied: Dictionary = {}
	for at: Vector2i in placed:
		occupied[at] = true
	var lone := 0
	for at: Vector2i in placed:
		var neighbours := 0
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if occupied.has(at + step):
				neighbours += 1
		if neighbours == 0:
			lone += 1
	assert_eq(lone, 1, "exactly one piece stands alone: the isolated stub, on purpose")


func test_a_click_off_the_edge_of_the_world_selects_nothing() -> void:
	var map := _map()
	var view := _view()
	assert_true(BaseGameMap.selection_at(map, view, Vector2i(-1, -1)).is_empty())
	assert_true(BaseGameMap.selection_at(map, view,
		Vector2i(map.width * BaseGameMap.SUBTILES_PER_TILE, 0)).is_empty())
	assert_true(BaseGameMap.selection_at(null, view, Vector2i(0, 0)).is_empty())
