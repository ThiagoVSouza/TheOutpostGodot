class_name TerrainMap
extends RefCounted

## A decoded overworld map: the terrain set (biomes → texture variants, priorities, tile size) and
## the map layer (a palette + an ASCII-grid of cells) from the legacy content JSON, ported from
## `mapData.ts`. Pure data — no rendering, no file IO of its own beyond the `from_files` helper — so
## it is testable without a SceneTree. Code here assumes the JSON is well-formed content; it raises a
## clear error on the shape mistakes the old parser caught (row width, unknown palette char).
##
## Only the first layer is read (the legacy maps are single-layer). Corner-blend masks, decorations
## and seasons from the terrain set are not decoded yet — the first-pass renderer draws base biomes.

var id: String
var width: int
var height: int
var seed: int
var tile_size_px: int
var tile_world_meters: float

# biome name -> { "priority": int, "textures": PackedStringArray }
var _biomes: Dictionary = {}
# the decoded layer: a palette char -> biome name, plus the raw rows
var _palette: Dictionary = {}
var _rows: PackedStringArray = PackedStringArray()


## Build from already-parsed JSON dictionaries (the map and its terrain set). Kept separate from file
## loading so tests can hand it literals.
static func from_data(map_data: Dictionary, terrain_data: Dictionary) -> TerrainMap:
	var m := TerrainMap.new()
	m._decode(map_data, terrain_data)
	return m


## Load and parse the two JSON files (res:// paths). Returns null and logs on any IO/parse failure so
## a caller can fall back rather than crash the screen.
static func from_files(map_path: String, terrain_path: String) -> TerrainMap:
	var map_data: Variant = _read_json(map_path)
	var terrain_data: Variant = _read_json(terrain_path)
	if not (map_data is Dictionary) or not (terrain_data is Dictionary):
		return null
	return TerrainMap.from_data(map_data as Dictionary, terrain_data as Dictionary)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("TerrainMap: no such file '%s'" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("TerrainMap: could not parse JSON '%s'" % path)
	return parsed


func _decode(map_data: Dictionary, terrain_data: Dictionary) -> void:
	id = String(map_data.get("id", ""))
	width = int(map_data.get("width", 0))
	height = int(map_data.get("height", 0))
	# JSON numbers may parse as float; seed is an integer channel input.
	seed = int(map_data.get("seed", 0))
	tile_size_px = int(terrain_data.get("tileSizePx", 128))
	tile_world_meters = float(map_data.get("tileWorldMeters", 0.0))

	for biome: Variant in terrain_data.get("biomes", []):
		var b := biome as Dictionary
		var textures := PackedStringArray()
		for t: Variant in b.get("textures", []):
			textures.append(String(t))
		_biomes[String(b.get("name", ""))] = {
			"priority": int(b.get("priority", 0)),
			"textures": textures,
		}

	var layers: Array = map_data.get("layers", [])
	assert(not layers.is_empty(), "map '%s' has no terrain layer" % id)
	var layer := layers[0] as Dictionary
	var palette: Dictionary = layer.get("palette", {})
	for char_key: Variant in palette:
		_palette[String(char_key)] = String(palette[char_key])
	for row: Variant in layer.get("cells", []):
		_rows.append(String(row))

	_validate()


func _validate() -> void:
	assert(_rows.size() == height,
		"map '%s' has %d rows but height %d" % [id, _rows.size(), height])
	for y in _rows.size():
		var row := _rows[y]
		assert(row.length() == width,
			"map '%s' row %d width %d != map width %d" % [id, y, row.length(), width])
		for x in row.length():
			assert(_palette.has(row[x]),
				"map '%s' cell (%d,%d) uses '%s', missing from the palette" % [id, x, y, row[x]])


## The biome name at a cell. Out-of-range raises — a renderer clamps to the visible range first.
func biome_at(x: int, y: int) -> String:
	assert(x >= 0 and x < width and y >= 0 and y < height,
		"cell (%d,%d) is outside the %dx%d grid" % [x, y, width, height])
	return String(_palette[_rows[y][x]])


func biome_names() -> Array:
	return _biomes.keys()


func priority_of(biome: String) -> int:
	return int((_biomes.get(biome, {}) as Dictionary).get("priority", 0))


## The texture variant paths for a biome (relative to the content base dir), in author order — index
## order is what [MapVariation.pick_variant] selects into.
func textures_for(biome: String) -> PackedStringArray:
	return (_biomes.get(biome, {}) as Dictionary).get("textures", PackedStringArray())


func variant_count(biome: String) -> int:
	return textures_for(biome).size()
