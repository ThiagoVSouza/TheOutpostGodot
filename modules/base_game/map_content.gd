class_name BaseGameMap
extends RefCounted

## The base game's deliberately simple construction map.
##
## Two systems need the same geometry: the game screen renders it, and new-game seeding chooses the
## outpost's permanent cell. Keeping the procedural definition here gives both one source of truth.

## Large enough that the close default camera can pan for hundreds of tiles in every direction,
## while procedural storage keeps it cheaper than the old 40x28 JSON demo.
const MAP_WIDTH := 500
const MAP_HEIGHT := 500
const TILE_SIZE_PX := 128
const MAP_SEED := 1311768467

## Stable node names shared by the module's Map Layers panel and its game screen wiring.
const TILE_GRID_TOGGLE_NAME := "TileGridToggle"
const SUBGRID_TOGGLE_NAME := "SubgridToggle"
const TERRAIN_ONLY_TOGGLE_NAME := "TerrainOnlyToggle"

## The map's finest addressable square, and the unit a click resolves to. Taken from the renderer's
## own subdivision rather than restated, so the squares the 5x5 overlay draws are exactly the ones a
## player can select.
const SUBTILES_PER_TILE := OverworldMapView.SUBGRID_DIVISIONS

## The construction map currently has one biome and therefore one habitable terrain.
const HABITABLE_BIOMES: PackedStringArray = ["grass"]


## A uniform grass world: one biome, drawn from four interchangeable variants of the same ground.
static func load_map() -> TerrainMap:
	return TerrainMap.create_flat("construction-overworld", MAP_WIDTH, MAP_HEIGHT, TILE_SIZE_PX,
		"grass", MAP_SEED)


## The one biome's ground, as four variants in a single 512x512 atlas.
##
## **One atlas rather than four files** so every cell on screen draws from the same texture and the
## canvas can batch them — with four separate textures picked pseudo-randomly per cell, the texture
## changes every few tiles and the batches break up constantly. Imported VRAM-compressed with
## mipmaps: the compression is 8:1 on a texture whose alpha channel was fully opaque anyway, and the
## mipmaps are what stop the ground shimmering as the map zooms.
##
## Variants are picked per cell by [method MapVariation.pick_variant], deterministically from
## [constant MAP_SEED], so a cell keeps its ground across a save and reload. Below
## [constant OverworldMapView.MIN_TEXTURED_TILE_PX] the renderer stops drawing them entirely and
## falls back to the average of these four — see that constant for why.
const GRASS_ATLAS := preload("res://core/assets/map/atlas_grass.png")
const GRASS_ATLAS_COLUMNS := 2
const GRASS_ATLAS_ROWS := 2


## Worked ground: a ploughed field, one whole cell of it. Unlike a tree this is not something standing
## *on* the ground, it is what the ground has become — so it is keyed alongside the biomes and drawn
## in the same pass, which gets it the same variants, the same zoom threshold and the same averaged
## colour when the map is too far out to draw art at all.
const FARM_TEXTURE := preload("res://core/assets/map/test_farm1.png")
const FARM_GROUND := "farm"


static func load_textures(_map: TerrainMap) -> Dictionary:
	return {
		"grass": OverworldMapView.slice_variants(GRASS_ATLAS, GRASS_ATLAS_COLUMNS,
			GRASS_ATLAS_ROWS),
		FARM_GROUND: [FARM_TEXTURE] as Array[Texture2D],
	}


## **A few plots by the settlement, for looking at.** Placed against the cell the outpost is founded
## on rather than against the map's own middle, so they stay with the settlement if the siting rule
## changes. Rectangles because a ploughed field is a rectangle; separated by a cell or two because
## what wants judging is whether they read as *fields* rather than as one brown region.
##
## Nothing decides these yet — there is no building or farming system to ask. When there is, it
## replaces this constant and the renderer does not change.
const FARM_PLOTS: Array[Rect2i] = [
	Rect2i(-4, -2, 3, 2),
	Rect2i(1, -3, 2, 3),
	Rect2i(-2, 2, 4, 2),
	Rect2i(3, 1, 2, 2),
]


## **The plots as things rather than as coloured cells.** The renderer only ever needed to know which
## ground was ploughed, so the farms were a flat cell-to-name dictionary and there was no such object
## as *a* farm — which is precisely what a player clicking one is asking for. Each plot is now
## identified, and [method load_ground_overrides] is derived from this list so the thing the player
## selects and the thing the map draws cannot describe different cells.
##
## `cells` is absolute, resolved against the outpost's site. Empty when the map has no habitable cell
## to found on, which is also when there is nothing to draw.
static func constructions(map: TerrainMap) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	var site := map.find_cell_nearest_centre(HABITABLE_BIOMES)
	if site.x < 0:
		return built
	for index in FARM_PLOTS.size():
		var plot := FARM_PLOTS[index]
		var cells := Rect2i(site + plot.position, plot.size)
		# A plot placed off the edge of the world is dropped whole rather than clipped: half a farm is
		# a thing nothing built, and the outpost is at the map's middle so this cannot happen today.
		if not Rect2i(0, 0, map.width, map.height).encloses(cells):
			continue
		built.append({
			"id": "farm_%d" % index,
			"kind": KIND_CONSTRUCTION,
			"title": "Ploughed field",
			"ground": FARM_GROUND,
			"cells": cells,
		})
	return built


## The construction covering [param cell], or an empty dictionary. Point 4 of the selection brief —
## "click any part of it, get the whole of it" — is this method: the caller never sees the cell it
## asked about, only the thing that occupies it.
static func construction_at(map: TerrainMap, cell: Vector2i) -> Dictionary:
	for built: Dictionary in constructions(map):
		if (built["cells"] as Rect2i).has_point(cell):
			return built
	return {}


static func load_ground_overrides(map: TerrainMap) -> Dictionary:
	var overrides: Dictionary = {}
	for built: Dictionary in constructions(map):
		var cells := built["cells"] as Rect2i
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				overrides[Vector2i(x, y)] = String(built["ground"])
	return overrides


## **One tree, on purpose.** It is here to prove the parts that are easy to get wrong and impossible
## to see in a test — the ground anchor, the near-in-front-of-far sorting, and the second pass that
## stops the next cell's ground painting over a canopy. Density and variety are dials to turn once
## there is a set of trees and a reason for a particular cell to be wooded; today every grass cell is
## a candidate and [constant OverworldMapView.SCATTER_CHANCE] keeps it sparse.
const TEST_TREE := preload("res://core/assets/map/test_tree.png")


static func load_scatter(_map: TerrainMap) -> Dictionary:
	return {"grass": [TEST_TREE] as Array[Texture2D]}


# --- selection ----------------------------------------------------------------------------------

## What kind of thing a selection is. The band shows a construction and bare ground differently, and
## the Terrain plate hides one of them and not the other.
const KIND_CONSTRUCTION := "construction"
const KIND_TERRAIN := "terrain"

## How a biome reads to a player. The renderer's key is a texture name; this is the word for it.
const BIOME_TITLES := {
	"grass": "Grassland",
}

## **The rungs above a construction are not built yet.** The selection ladder walks from the smallest
## occupant of a clicked subtile up through its containers until one is big enough on screen to be
## worth aiming at ([constant OverworldMapView.MIN_SELECTABLE_PX]); today that walk has two rungs,
## bare ground and a construction, and stops.
##
## The two rungs above it — **settlement** and **region** — have no data behind them. The outpost is a
## single cell in state (`GameSession.OUTPOST_SITE_STATE_KEY`) with no footprint, and there is no
## notion of a region anywhere in the project. Inventing either here would mean a shape a real
## settlement system throws away.
##
## When they exist, they slot in at [method selection_at]: give a construction a `settlement` id,
## return the settlement's own footprint as the next candidate when the construction fails the
## threshold, and the far-zoom behaviour — click anywhere in a town and get the town — follows without
## touching the renderer. See `docs/ux_plan.md`, "the selection ladder".
##
## Note also that at that point [method OverworldMapView._draw_selection] wants the footprint's bounds
## rather than a traced perimeter: it is four neighbour lookups per subtile, which is right for a
## building and wrong for a province.

## What a click on [param subtile] has picked, or an empty dictionary for nothing selectable there.
##
## [param view] is asked whether each candidate is large enough on screen, so the answer changes with
## the zoom without this method knowing anything about zoom. [param constructions_visible] is the
## Terrain plate: with the works hidden, a click lands on the ground they were built on.
##
## Returns `{kind, title, footprint, art, owned}` — `owned` because who holds a thing is game state,
## which map content has no business reading.
static func selection_at(map: TerrainMap, view: OverworldMapView, subtile: Vector2i,
		constructions_visible: bool = true) -> Dictionary:
	if map == null or view == null or not view.has_subtile(subtile):
		return {}
	var cell := subtile / SUBTILES_PER_TILE
	if constructions_visible:
		var built := construction_at(map, cell)
		if not built.is_empty():
			var footprint := construction_footprint(built)
			# Too small to aim at. The rung above is the settlement, which does not exist yet — so
			# this is where the walk stops and the click means nothing. See the note above.
			if not view.is_footprint_selectable(footprint):
				return {}
			return {
				"kind": KIND_CONSTRUCTION,
				"title": String(built["title"]),
				"footprint": footprint,
				"art": FARM_TEXTURE,
				"owned": true,
			}
	var ground := subtile_footprint(subtile)
	if not view.is_footprint_selectable(ground):
		return {}
	var biome := map.biome_at(cell.x, cell.y)
	return {
		"kind": KIND_TERRAIN,
		"title": String(BIOME_TITLES.get(biome, biome.capitalize())),
		"footprint": ground,
		"art": GRASS_ATLAS,
		"owned": false,
	}


## A construction's cells as the subtile rectangle the map outlines.
static func construction_footprint(built: Dictionary) -> Array[Rect2i]:
	var cells := built["cells"] as Rect2i
	return [Rect2i(cells.position * SUBTILES_PER_TILE, cells.size * SUBTILES_PER_TILE)] as Array[Rect2i]


## One subtile, as the same shape a construction's footprint has — so the map outlines both by one
## path and bare ground is not a special case anywhere downstream.
static func subtile_footprint(subtile: Vector2i) -> Array[Rect2i]:
	return [Rect2i(subtile, Vector2i.ONE)] as Array[Rect2i]


## The cell a new outpost is founded on.
##
## **Placeholder rule, deliberately simple: the cell nearest the map's middle.** It is deterministic,
## so the site survives a save and reload. It is not yet varied per game (there is no per-world map
## seed), or matched to the wizard's location (this construction map has only grass).
static func outpost_site(map: TerrainMap) -> Vector2i:
	return map.find_cell_nearest_centre(HABITABLE_BIOMES)
