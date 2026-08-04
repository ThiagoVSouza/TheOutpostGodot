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
	assert_eq(built.size(), BaseGameMap.FARM_PLOTS.size())

	var site := BaseGameMap.outpost_site(map)
	var ids: Array = []
	for construction: Dictionary in built:
		assert_false(String(construction["id"]).is_empty())
		assert_false(ids.has(construction["id"]), "an id nothing else answers to")
		ids.append(construction["id"])
		assert_eq(String(construction["kind"]), BaseGameMap.KIND_CONSTRUCTION)
		assert_eq(String(construction["ground"]), BaseGameMap.FARM_GROUND)
		# Placed against the settlement, so they stay with it if the siting rule changes.
		var cells := construction["cells"] as Rect2i
		assert_lt((Vector2(cells.get_center()) - Vector2(site)).length(), 10.0)


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
	assert_eq(String(picked["title"]), "Ploughed field")
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

	view.call("_zoom_at", Vector2.ZERO, 0.25)
	assert_true(BaseGameMap.selection_at(map, view, wild).is_empty(),
		"bare ground is too small to point at, so a click on it means nothing")
	assert_eq(String(BaseGameMap.selection_at(map, view, inside)["kind"]),
		BaseGameMap.KIND_CONSTRUCTION, "the plot is still worth aiming at")


func test_a_click_off_the_edge_of_the_world_selects_nothing() -> void:
	var map := _map()
	var view := _view()
	assert_true(BaseGameMap.selection_at(map, view, Vector2i(-1, -1)).is_empty())
	assert_true(BaseGameMap.selection_at(map, view,
		Vector2i(map.width * BaseGameMap.SUBTILES_PER_TILE, 0)).is_empty())
	assert_true(BaseGameMap.selection_at(null, view, Vector2i(0, 0)).is_empty())
