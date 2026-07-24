extends Control

## A full-screen overlay that renders the overworld map in-game (M7 first pass). Toggled from the
## chat screen rather than routed to, because the [ScreenRouter] is stateless — leaving the chat
## screen would discard its conversation log. As a child overlay the map opens over the running game
## and closes back to it untouched.
##
## Owns the content paths (the map lives in base_game): it loads the decoded [TerrainMap] and the
## biome textures, then hands both to the reusable [OverworldMapView].

const MAP_JSON := "res://modules/base_game/assets/map/overworld_demo.json"
const TERRAIN_JSON := "res://modules/base_game/assets/map/overworld_terrain.json"
# The content base the terrain set's relative texture paths ("assets/map/…") resolve against.
const CONTENT_BASE := "res://modules/base_game/"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Dim the game behind the map and swallow clicks so they do not fall through to the chat UI.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Overworld"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		title.add_theme_constant_override("margin_" + side, 8)
	header.add_child(title)
	var hint := Label.new()
	hint.text = "drag to pan · scroll to zoom"
	hint.modulate = Color(1, 1, 1, 0.6)
	header.add_child(hint)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	header.add_child(close)

	var view := OverworldMapView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(view)

	var map := TerrainMap.from_files(MAP_JSON, TERRAIN_JSON)
	if map == null:
		title.text = "Overworld — map failed to load (see log)"
		return
	view.setup(map, _load_textures(map))


## biome -> Array[Texture2D] in variant order, resolving the terrain set's relative paths.
func _load_textures(map: TerrainMap) -> Dictionary:
	var textures: Dictionary = {}
	for biome: Variant in map.biome_names():
		var variants: Array = []
		for rel: String in map.textures_for(String(biome)):
			var tex: Variant = load(CONTENT_BASE + rel)
			if tex is Texture2D:
				variants.append(tex)
		textures[String(biome)] = variants
	return textures
