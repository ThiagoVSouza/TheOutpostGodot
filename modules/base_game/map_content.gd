class_name BaseGameMap
extends RefCounted

## Where this module's overworld content lives, and how to load it.
##
## Two things need the map now — the overlay that draws it, and `seed_new_game`, which has to choose
## where the outpost stands — so the paths live here instead of in whichever screen happened to need
## them first. The seed loads the grid without the textures: placing a settlement is a question about
## the ground, and the pictures of it cost megabytes.

const MAP_JSON := "res://modules/base_game/assets/map/overworld_demo.json"
const TERRAIN_JSON := "res://modules/base_game/assets/map/overworld_terrain.json"

## The content base the terrain set's relative texture paths ("assets/map/…") resolve against.
const CONTENT_BASE := "res://modules/base_game/"

## Ground an outpost can be founded on — every biome in the set except open water. Content knowledge,
## which is why it lives here and is passed *into* [TerrainMap] rather than assumed by it.
const HABITABLE_BIOMES: PackedStringArray = ["grass", "savanah", "swamp", "tundra", "desert", "sand"]


## The decoded overworld grid, or null if the content will not load (logged by [TerrainMap]).
static func load_map() -> TerrainMap:
	return TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)


## biome -> Array[Texture2D] in variant order, resolving the terrain set's relative paths.
static func load_textures(map: TerrainMap) -> Dictionary:
	var textures: Dictionary = {}
	for biome: Variant in map.biome_names():
		var variants: Array = []
		for rel: String in map.textures_for(String(biome)):
			var tex: Variant = load(CONTENT_BASE + rel)
			if tex is Texture2D:
				variants.append(tex)
		textures[String(biome)] = variants
	return textures


## The cell a new outpost is founded on.
##
## **Placeholder rule, deliberately simple: the habitable cell nearest the map's middle.** It is
## deterministic, so the site survives a save and a reload, and it never lands in the sea. Two things
## it is *not* yet, both blocked rather than forgotten:
## - varied per game — that needs a per-world seed, and no such thing exists yet (the only seed here
##   belongs to the map content, which is the same for everyone);
## - matched to the wizard's `outpost_location` — the demo terrain set has no forest or mountain
##   biome to put a "Forest" or "Mountains" start on, so any mapping would be invented rather than
##   honoured.
static func outpost_site(map: TerrainMap) -> Vector2i:
	return map.find_cell_nearest_centre(HABITABLE_BIOMES)
