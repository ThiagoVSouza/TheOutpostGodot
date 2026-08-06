extends GutTest

## The roads and their autotiling. The mask table is read off the art sheet and is the one thing here
## that cannot be derived, so it is checked piece by piece: a wrong entry draws a plausible-looking
## road with its junctions facing the wrong way, which is exactly the kind of wrong that survives a
## glance at a screenshot.


func _network() -> RoadNetwork:
	return RoadNetwork.new()


func test_the_sheet_holds_the_sixteen_pieces_a_four_way_join_needs() -> void:
	var roads := _network()
	assert_eq(roads.pieces().size(), RoadNetwork.ATLAS_COLUMNS * RoadNetwork.ATLAS_ROWS,
		"the sheet is cut whole; nine of its cells are simply empty")
	assert_eq(RoadNetwork.MASK_TO_INDEX.size(), 16, "four neighbours, two states each")
	# Every mask points at its own piece: two masks sharing one would silently draw the wrong join.
	var seen: Dictionary = {}
	for mask in 16:
		var index := RoadNetwork.MASK_TO_INDEX[mask]
		assert_false(seen.has(index), "mask %d reuses the piece mask %s already claimed"
			% [mask, seen.get(index, -1)])
		seen[index] = mask


## The table, spelled out against the sheet's own layout. Index is `row * 5 + column`.
func test_each_mask_takes_the_piece_drawn_for_it() -> void:
	var N := RoadNetwork.NORTH
	var E := RoadNetwork.EAST
	var S := RoadNetwork.SOUTH
	var W := RoadNetwork.WEST
	var expected := {
		0: 15,          # the lone stub, on its own in the fourth row
		N: 14, E: 3, S: 9, W: 4,                    # the four dead ends
		N | S: 8, E | W: 13,                        # the two straights
		S | E: 0, S | W: 2, N | E: 10, N | W: 12,   # the four corners
		E | S | W: 1, N | E | S: 5, N | S | W: 7, N | E | W: 11,  # the four T-junctions
		N | E | S | W: 6,                           # the cross
	}
	for mask: int in expected:
		assert_eq(RoadNetwork.MASK_TO_INDEX[mask], int(expected[mask]),
			"mask %d should take piece %d" % [mask, int(expected[mask])])


func test_a_piece_reads_its_shape_from_the_roads_around_it() -> void:
	var roads := _network()
	var here := Vector2i(50, 50)
	roads.add(here)
	assert_eq(roads.mask_at(here), 0, "one road alone is attached to nothing")

	roads.add(here + Vector2i(0, -1))
	assert_eq(roads.mask_at(here), RoadNetwork.NORTH)
	roads.add(here + Vector2i(1, 0))
	assert_eq(roads.mask_at(here), RoadNetwork.NORTH | RoadNetwork.EAST)
	roads.add(here + Vector2i(0, 1))
	roads.add(here + Vector2i(-1, 0))
	assert_eq(roads.mask_at(here),
		RoadNetwork.NORTH | RoadNetwork.EAST | RoadNetwork.SOUTH | RoadNetwork.WEST,
		"a crossroads")
	# Diagonals are not neighbours: a road is a four-way join, not an eight-way one.
	var lone := Vector2i(80, 80)
	roads.add(lone)
	roads.add(lone + Vector2i(1, 1))
	assert_eq(roads.mask_at(lone), 0)


## A ghost has to join the network it is about to become part of, or a run drawn up to an existing
## road shows two dead ends meeting instead of the junction it will be.
func test_a_planned_piece_is_shaped_as_though_it_were_already_built() -> void:
	var roads := _network()
	var built := Vector2i(10, 10)
	roads.add(built)
	var planned := built + Vector2i(1, 0)

	assert_eq(roads.mask_at(planned), RoadNetwork.WEST,
		"the plan sees the road it is being drawn towards")
	assert_eq(roads.mask_at(built), 0, "and the built road, asked plainly, does not see the plan")
	assert_eq(roads.mask_at(built, {planned: true}), RoadNetwork.EAST,
		"but asked *with* the plan, it takes the shape it is about to have")


func test_the_whole_network_renders_as_a_piece_per_subtile() -> void:
	var roads := _network()
	for x in range(5, 9):
		roads.add(Vector2i(x, 3))
	var textures := roads.textures()
	assert_eq(textures.size(), 4)
	# A straight run: two ends and two middles.
	assert_eq(textures[Vector2i(5, 3)], roads.piece_for_mask(RoadNetwork.EAST))
	assert_eq(textures[Vector2i(6, 3)], roads.piece_for_mask(RoadNetwork.EAST | RoadNetwork.WEST))
	assert_eq(textures[Vector2i(8, 3)], roads.piece_for_mask(RoadNetwork.WEST))


## The renderer clears a cell's scatter when a road runs through it, so it has to know which cells
## those are without asking twenty-five questions per cell per frame.
func test_the_network_reports_which_map_cells_it_runs_through() -> void:
	var roads := _network()
	roads.add(Vector2i(7, 3))    # cell (1, 0) at five subtiles to the tile
	roads.add(Vector2i(9, 4))    # same cell
	roads.add(Vector2i(10, 4))   # cell (2, 0)
	var cells := roads.cells(5)
	assert_eq(cells.size(), 2, "two roads in one cell name that cell once")
	assert_true(cells.has(Vector2i(1, 0)))
	assert_true(cells.has(Vector2i(2, 0)))


# --- persistence --------------------------------------------------------------------------------

func test_roads_survive_the_round_trip_through_a_save() -> void:
	var roads := _network()
	for at: Vector2i in [Vector2i(3, 4), Vector2i(3, 5), Vector2i(900, 1200)]:
		roads.add(at)

	var stored := roads.to_state()
	assert_eq(stored.size(), 6, "a flat list of pairs — JSON has no vector to store")
	# JSON is what a save really is, so the shape has to survive being one.
	var reloaded := _network()
	reloaded.from_state(JSON.parse_string(JSON.stringify(stored)))
	assert_eq(reloaded.count(), 3)
	for at: Vector2i in [Vector2i(3, 4), Vector2i(3, 5), Vector2i(900, 1200)]:
		assert_true(reloaded.has_road(at), "%s came back" % at)


## Sorted output, so a world that has not changed saves as the same bytes rather than as whatever
## order the dictionary happened to be in.
func test_the_saved_order_does_not_depend_on_the_order_they_were_built() -> void:
	var one := _network()
	for at: Vector2i in [Vector2i(9, 9), Vector2i(1, 2), Vector2i(4, 2)]:
		one.add(at)
	var two := _network()
	for at: Vector2i in [Vector2i(4, 2), Vector2i(9, 9), Vector2i(1, 2)]:
		two.add(at)
	assert_eq(one.to_state(), two.to_state())


## A save written before roads existed simply has no key. That is not an error, and neither is a
## truncated one.
func test_a_world_with_no_roads_in_it_loads_as_a_world_with_no_roads() -> void:
	var roads := _network()
	roads.add(Vector2i(1, 1))
	roads.from_state(null)
	assert_eq(roads.count(), 0)
	roads.from_state([])
	assert_eq(roads.count(), 0)
	roads.from_state("not a list")
	assert_eq(roads.count(), 0)
	# An odd tail is half a pair; dropping it beats reading a road onto the top edge of the world.
	roads.from_state([4, 5, 6])
	assert_eq(roads.count(), 1)
	assert_true(roads.has_road(Vector2i(4, 5)))
