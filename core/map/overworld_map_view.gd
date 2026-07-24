class_name OverworldMapView
extends Control

## First-pass overworld renderer: draws each cell's base biome texture, picking the variant with the
## ported [MapVariation] hash so the map looks identical to the legacy renderer's base layer. Only
## the visible tile range is drawn each frame (culled to the view rect), the same window logic as
## `mapRenderer.ts`. Supports fit-to-view, wheel zoom toward the cursor, and drag-to-pan.
##
## Deferred to match the old renderer fully: corner-blend mask overlays between biomes, whole-tile
## ground decorations, and season tint. Those compose over this base layer.

# Variation channel for the base biome texture is the biome's index in terrain-set order (matches
# `biomeChannel` in mapRenderer.ts).
var _map: TerrainMap
var _textures: Dictionary = {}      # biome -> Array[Texture2D], in variant order
var _channel: Dictionary = {}       # biome -> int (index in terrain order)

var _zoom: float = 1.0
var _origin: Vector2 = Vector2.ZERO # world-pixel coordinate drawn at the view's top-left
var _dragging: bool = false

const MIN_ZOOM := 0.05
const MAX_ZOOM := 4.0
const FALLBACK_COLORS := {
	"grass": Color(0.36, 0.55, 0.24), "savanah": Color(0.68, 0.6, 0.28),
	"swamp": Color(0.3, 0.38, 0.28), "tundra": Color(0.8, 0.84, 0.88),
	"desert": Color(0.82, 0.72, 0.42), "sand": Color(0.88, 0.82, 0.6),
	"ocean": Color(0.16, 0.32, 0.5),
}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Re-frame once the control gets its real size from layout (size is 0 during _ready).
	resized.connect(fit)


## Hand the view its decoded map and the loaded textures (biome -> Array[Texture2D]). Fits the whole
## map into the current rect and redraws.
func setup(map: TerrainMap, textures: Dictionary) -> void:
	_map = map
	_textures = textures
	_channel.clear()
	var names := map.biome_names()
	for i in names.size():
		_channel[String(names[i])] = i
	fit()


## Frame the whole map in the view, centred.
func fit() -> void:
	if _map == null:
		return
	var view := size
	var world := Vector2(_map.width, _map.height) * _map.tile_size_px
	if world.x <= 0.0 or world.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return
	_zoom = clampf(minf(view.x / world.x, view.y / world.y), MIN_ZOOM, MAX_ZOOM)
	# Centre: put the world's midpoint at the view's midpoint.
	_origin = world * 0.5 - (view * 0.5) / _zoom
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	var tile := float(_map.tile_size_px)
	# Visible tile window (same clamp as the TS renderer), plus a one-tile margin.
	var first_x := maxi(0, int(floor(_origin.x / tile)))
	var first_y := maxi(0, int(floor(_origin.y / tile)))
	var last_x := mini(_map.width - 1, int(floor((_origin.x + size.x / _zoom) / tile)))
	var last_y := mini(_map.height - 1, int(floor((_origin.y + size.y / _zoom) / tile)))

	for y in range(first_y, last_y + 1):
		for x in range(first_x, last_x + 1):
			var biome := _map.biome_at(x, y)
			# Snap corners to whole pixels so neighbouring tiles never leave a seam.
			var left := roundf((x * tile - _origin.x) * _zoom)
			var top := roundf((y * tile - _origin.y) * _zoom)
			var right := roundf(((x + 1) * tile - _origin.x) * _zoom)
			var bottom := roundf(((y + 1) * tile - _origin.y) * _zoom)
			var rect := Rect2(left, top, right - left, bottom - top)
			var tex := _texture_for(biome, x, y)
			if tex != null:
				draw_texture_rect(tex, rect, false)
			else:
				draw_rect(rect, FALLBACK_COLORS.get(biome, Color(0.5, 0.5, 0.5)))


func _texture_for(biome: String, x: int, y: int) -> Texture2D:
	var variants: Array = _textures.get(biome, [])
	if variants.is_empty():
		return null
	var channel := int(_channel.get(biome, 0))
	var index := MapVariation.pick_variant(_map.seed, x, y, channel, variants.size())
	return variants[index] as Texture2D


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.1)
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		# Drag moves the world under the cursor: shift the origin opposite to the motion.
		_origin -= (event as InputEventMouseMotion).relative / _zoom
		queue_redraw()


## Zoom toward a screen point so the world under the cursor stays put.
func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := _origin + screen_point / _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := _origin + screen_point / _zoom
	_origin += before - after
	queue_redraw()
