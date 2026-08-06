class_name ChatCharacter
extends Control

## **One layered figure standing in a [ChatScene]**, carrying one shadow for the composite.
##
## A node per character rather than a pass of the scene's own `_draw`, and that is the whole reason
## this class exists: a material belongs to a [CanvasItem], so a shadow shader set on the scene would
## run for the painted background as well. Given each figure a node of its own, the shader applies to
## exactly the thing it is a shadow of. Its visual children sit in a [CanvasGroup], so body, hair and
## later clothing are flattened before the shadow material samples their combined alpha.
##
## It also costs one draw call where sampling the silhouette by hand cost twenty-four.

const SHADOW_SHADER := preload("res://core/ui/theme/character_shadow.gdshader")
## Given to a layer that carries a `tone` — see `core/ui/theme/skin_tone.gdshader` for why skin is
## remapped rather than multiplied.
const TONE_SHADER := preload("res://core/ui/theme/skin_tone.gdshader")

## **How the tone shader is told where a body's skin actually sits**, measured from the file rather
## than written down.
##
## The remap normalises a painting's luminance before recolouring it, so it has to know which part of
## the range the skin occupies. Hard-coding that silently ties the shader to one set of exports: the
## lighter bodies sit around 0.90 where the first ones sat at 0.58, and against the old fixed numbers
## most of a light figure clamped past the top of the ramp and flattened to a single colour. Measuring
## instead means a body may be exported at any exposure and simply works.
##
## Sampled from a small copy — a few thousand pixels is plenty for a percentile, and reading a
## quarter of a million off the GPU per figure is not something to do at all, let alone per redraw.
const LEVELS_SAMPLE := 96
## Percentiles rather than the true extremes, so one stray bright pixel cannot decide the white point.
const LEVELS_LOW := 0.02
const LEVELS_HIGH := 0.98

## Measured once per texture. Reading pixels back is the expensive part and a body's levels never
## change, so the answer is kept for the life of the process.
static var _levels: Dictionary = {}


## Where [param texture]'s figure sits in luminance, as `(black, white)` — see [constant LEVELS_SAMPLE].
static func skin_levels(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2(0.0, 1.0)
	if _levels.has(texture):
		return _levels[texture] as Vector2
	var image := texture.get_image()
	var measured := Vector2(0.0, 1.0)
	if image != null:
		if image.is_compressed():
			image.decompress()
		image.resize(LEVELS_SAMPLE, LEVELS_SAMPLE, Image.INTERPOLATE_BILINEAR)
		var lit: Array[float] = []
		for y in LEVELS_SAMPLE:
			for x in LEVELS_SAMPLE:
				var pixel := image.get_pixel(x, y)
				# Only the figure. Its transparent margin is not skin and would drag the black point
				# down to nothing.
				if pixel.a > 0.9:
					lit.append(pixel.get_luminance())
		if lit.size() > 16:
			lit.sort()
			measured = Vector2(lit[int(float(lit.size() - 1) * LEVELS_LOW)],
				lit[int(float(lit.size() - 1) * LEVELS_HIGH)])
			# A flat or near-flat image would divide by nothing in the shader.
			if measured.y - measured.x < 0.05:
				measured = Vector2(0.0, 1.0)
	_levels[texture] = measured
	return measured

## One full alignment canvas in the character stack.
class CharacterLayer:
	extends Control

	var texture: Texture2D = null
	var tint := Color.WHITE
	## **The mirror lives on the layer, not on the shadow.** It was a uniform on the composite's shader
	## and stopped taking effect once the layers moved into a [CanvasGroup] — both figures ended up
	## facing the same way. Flipping where the picture is actually drawn cannot come adrift from it.
	var flip := false
	## `{shadow, highlight}` for a layer whose colour is remapped rather than multiplied — skin. Empty
	## for everything else, which a plain tint suits: greyscale hair multiplies perfectly well.
	var tone: Dictionary = {}

	func _init(source: Texture2D, color: Color, tone_colors: Dictionary = {},
			mirrored: bool = false) -> void:
		texture = source
		tint = color
		tone = tone_colors
		flip = mirrored
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not tone.is_empty():
			var shaded := ShaderMaterial.new()
			shaded.shader = TONE_SHADER
			shaded.set_shader_parameter("shadow_color", tone.get("shadow", Color.BLACK))
			shaded.set_shader_parameter("highlight_color", tone.get("highlight", Color.WHITE))
			# Measured off this particular body, not assumed — see [method skin_levels]. Qualified by
			# class: an inner class does not inherit the enclosing one's statics.
			var levels := ChatCharacter.skin_levels(source)
			shaded.set_shader_parameter("input_black", levels.x)
			shaded.set_shader_parameter("input_white", levels.y)
			material = shaded

	func _draw() -> void:
		if texture == null:
			return
		# Mirrored about this layer's own middle. Every layer shares one canvas, so flipping them all
		# the same way keeps hair on the head it belongs to.
		if flip:
			draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, tint)
		if flip:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _composite: CanvasGroup = null
var _layer_nodes: Array[CharacterLayer] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shaded := ShaderMaterial.new()
	shaded.shader = SHADOW_SHADER
	material = shaded
	_composite = CanvasGroup.new()
	# The children already occupy the padded primitive. CanvasGroup's default margin would alter the
	# UV grid the existing shadow shader receives.
	_composite.fit_margin = 0.0
	_composite.clear_margin = 0.0
	_composite.use_parent_material = true
	add_child(_composite)


## **Place the figure and hand the shader everything it needs.**
##
## [param canvas] is where the texture's *whole* canvas lands on screen — padding included, since that
## is the alignment grid layers share. [param spread] is how far the shadow may reach beyond it, and
## this control is grown by exactly that much: a canvas shader cannot paint outside its own primitive,
## so the room has to exist in the rect before the shader can use it.
##
## **Nothing here keeps the figure inside the band.** Its parent stage does, by clipping — see
## [method ChatScene._place_characters] for why that is not this node's business.
func place(layers: Array, canvas: Rect2, spread: float, drop: Vector2, radius: float,
		flip: bool) -> void:
	var rect := canvas.grow(spread)
	position = rect.position
	size = rect.size
	_sync_layers(layers, flip)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var shaded := material as ShaderMaterial
	# Everything the shader takes is in this rect's own UV, so a circle in units stays a circle
	# whatever shape the rect turns out to be.
	shaded.set_shader_parameter("pad", Vector2(spread, spread) / rect.size)
	shaded.set_shader_parameter("shadow_offset", drop / rect.size)
	shaded.set_shader_parameter("shadow_radius", Vector2(radius, radius) / rect.size)
	queue_redraw()


## Replace the visual stack while keeping every layer on the same padded rectangle. `tint` is
## multiplicative: white in grayscale hair becomes the chosen colour while darker values retain the
## authored shading.
func _sync_layers(layers: Array, flip: bool) -> void:
	var wanted: Array[Dictionary] = []
	for entry: Dictionary in layers:
		var texture := entry.get("texture") as Texture2D
		if texture != null:
			wanted.append(entry)
	var unchanged := wanted.size() == _layer_nodes.size()
	if unchanged:
		for index in wanted.size():
			var expected: Dictionary = wanted[index]
			var node := _layer_nodes[index]
			if node.texture != expected.get("texture") \
					or node.tint != expected.get("tint", Color.WHITE) \
					or node.tone != expected.get("tone", {}) or node.flip != flip:
				unchanged = false
				break
	if not unchanged:
		for node: CharacterLayer in _layer_nodes:
			node.queue_free()
		_layer_nodes.clear()
		for entry: Dictionary in wanted:
			var node := CharacterLayer.new(entry["texture"] as Texture2D,
				entry.get("tint", Color.WHITE) as Color, entry.get("tone", {}) as Dictionary, flip)
			_composite.add_child(node)
			_layer_nodes.append(node)
	for node: CharacterLayer in _layer_nodes:
		node.size = size


func set_shadow(color: Color, gain: float) -> void:
	var shaded := material as ShaderMaterial
	shaded.set_shader_parameter("shadow_color", color)
	shaded.set_shader_parameter("shadow_gain", gain)
