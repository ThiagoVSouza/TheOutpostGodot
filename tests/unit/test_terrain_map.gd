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
