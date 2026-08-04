extends GutTest

## Decoding the overworld content JSON (ported from mapData.ts): the terrain set's biomes and the
## map layer's palette + ASCII cell grid.

const MAP_JSON := "res://modules/base_game/assets/map/overworld_demo.json"
const TERRAIN_JSON := "res://modules/base_game/assets/map/overworld_terrain.json"


func test_it_decodes_the_demo_map_dimensions_and_seed() -> void:
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	assert_not_null(map, "the demo files load")
	assert_eq(map.width, 40)
	assert_eq(map.height, 28)
	assert_eq(map.seed, 1311768467)
	assert_eq(map.tile_size_px, 128)


func test_biome_at_resolves_the_palette() -> void:
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	# Row 0 is all ocean; row 3 opens with ocean then grass (see overworld_demo.json).
	assert_eq(map.biome_at(0, 0), "ocean")
	assert_eq(map.biome_at(3, 3), "grass")


func test_it_reads_biome_priorities_and_variants() -> void:
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	assert_eq(map.priority_of("grass"), 1)
	assert_eq(map.priority_of("ocean"), 7)
	assert_eq(map.variant_count("grass"), 4, "four grass textures")
	assert_true(String(map.textures_for("grass")[0]).ends_with("grass_01.png"))


func test_biome_channel_order_matches_terrain_order() -> void:
	# The base variation channel is the biome's index in terrain-set order; grass is first.
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	assert_eq(String(map.biome_names()[0]), "grass")


func test_from_data_decodes_literals_and_maps_cells() -> void:
	var map := TerrainMap.from_data(
		{
			"id": "tiny", "width": 2, "height": 2, "seed": 7, "tileWorldMeters": 20,
			"layers": [{"palette": {"g": "grass", "o": "ocean"}, "cells": ["go", "og"]}],
		},
		{"tileSizePx": 64, "biomes": [
			{"name": "grass", "priority": 1, "textures": ["a.png", "b.png"]},
			{"name": "ocean", "priority": 7, "textures": ["c.png"]},
		]})
	assert_eq(map.tile_size_px, 64)
	assert_eq(map.biome_at(0, 0), "grass")
	assert_eq(map.biome_at(1, 0), "ocean")
	assert_eq(map.biome_at(0, 1), "ocean")
	assert_eq(map.variant_count("grass"), 2)
	assert_eq(map.variant_count("ocean"), 1)


func test_it_finds_the_habitable_cell_nearest_the_middle() -> void:
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	var cell := map.find_cell_nearest_centre(BaseGameMap.HABITABLE_BIOMES)

	assert_true(cell.x >= 0, "the demo map has somewhere to stand")
	assert_false(BaseGameMap.HABITABLE_BIOMES.has("ocean"), "open water is not habitable")
	assert_true(BaseGameMap.HABITABLE_BIOMES.has(map.biome_at(cell.x, cell.y)),
		"the chosen cell is habitable ground, not sea")
	# Nearest the middle, so it must beat the map's own centre if that cell is habitable at all.
	var centre := Vector2(map.width - 1, map.height - 1) * 0.5
	assert_true((Vector2(cell) - centre).length() < float(mini(map.width, map.height)) * 0.5,
		"the site sits near the middle rather than out at an edge")


func test_the_site_is_the_same_on_every_run() -> void:
	# A settlement has to be in the same place after a save and a reload, so the rule that picks it
	# must not depend on iteration luck or a clock.
	var first := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	var second := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	assert_eq(first.find_cell_nearest_centre(BaseGameMap.HABITABLE_BIOMES),
		second.find_cell_nearest_centre(BaseGameMap.HABITABLE_BIOMES))


func test_a_biome_the_map_lacks_yields_no_cell() -> void:
	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	assert_eq(map.find_cell_nearest_centre(PackedStringArray(["glacier"])), Vector2i(-1, -1),
		"asking for ground the map has none of is answered, not guessed at")


func test_a_large_flat_map_needs_no_authored_cell_rows() -> void:
	var map := TerrainMap.create_flat("large-green", 500, 500, 128, "grass", 19)
	assert_eq(map.width, 500)
	assert_eq(map.height, 500)
	assert_eq(map.biome_at(0, 0), "grass")
	assert_eq(map.biome_at(499, 499), "grass")
	assert_eq(map.find_cell_nearest_centre(PackedStringArray(["grass"])), Vector2i(249, 249))
	assert_eq(map.find_cell_nearest_centre(PackedStringArray(["ocean"])), Vector2i(-1, -1))
