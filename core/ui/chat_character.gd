class_name ChatCharacter
extends Control

## **One figure standing in a [ChatScene]**, carrying its own drop shadow in a [ShaderMaterial].
##
## A node per character rather than a pass of the scene's own `_draw`, and that is the whole reason
## this class exists: a material belongs to a [CanvasItem], so a shadow shader set on the scene would
## run for the painted background as well. Given each figure a node of its own, the shader applies to
## exactly the thing it is a shadow of — and the same arrangement is what a stack of layers will want
## later, flattened by a [CanvasGroup] so the shadow is cast by the composite silhouette rather than
## by each garment separately.
##
## It also costs one draw call where sampling the silhouette by hand cost twenty-four.

const SHADOW_SHADER := preload("res://core/ui/theme/character_shadow.gdshader")

var _texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shaded := ShaderMaterial.new()
	shaded.shader = SHADOW_SHADER
	material = shaded


## **Place the figure and hand the shader everything it needs.**
##
## [param canvas] is where the texture's *whole* canvas lands on screen — padding included, since that
## is the alignment grid layers share. [param spread] is how far the shadow may reach beyond it, and
## this control is grown by exactly that much: a canvas shader cannot paint outside its own primitive,
## so the room has to exist in the rect before the shader can use it.
##
## [param bounds] is the scene's picture. Anything of this figure or its shadow outside it is cut,
## because the band is a window onto a painting and the parchment below it is not part of the scene.
func place(texture: Texture2D, canvas: Rect2, spread: float, drop: Vector2, radius: float,
		bounds: Rect2, flip: bool) -> void:
	_texture = texture
	var rect := canvas.grow(spread)
	position = rect.position
	size = rect.size
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var shaded := material as ShaderMaterial
	# Everything the shader takes is in this rect's own UV, so a circle in units stays a circle
	# whatever shape the rect turns out to be.
	shaded.set_shader_parameter("pad", Vector2(spread, spread) / rect.size)
	shaded.set_shader_parameter("shadow_offset", drop / rect.size)
	shaded.set_shader_parameter("shadow_radius", Vector2(radius, radius) / rect.size)
	shaded.set_shader_parameter("flip", flip)
	# The window, in the same UV. Expressed as a fraction rather than a rectangle in units so the
	# shader needs to know nothing about where on the board any of this is.
	var visible := rect.intersection(bounds)
	if visible.has_area():
		shaded.set_shader_parameter("clip_uv", Vector4(
			(visible.position.x - rect.position.x) / rect.size.x,
			(visible.position.y - rect.position.y) / rect.size.y,
			(visible.end.x - rect.position.x) / rect.size.x,
			(visible.end.y - rect.position.y) / rect.size.y))
	else:
		shaded.set_shader_parameter("clip_uv", Vector4.ZERO)
	queue_redraw()


func set_shadow(color: Color, gain: float) -> void:
	var shaded := material as ShaderMaterial
	shaded.set_shader_parameter("shadow_color", color)
	shaded.set_shader_parameter("shadow_gain", gain)


## **Drawn over the whole control, padding and all.** The shader is what puts the figure in the middle
## of it — stretching the texture here and un-stretching it there is what buys the shadow room to
## spread into without the artist having to leave a transparent margin in every layer.
func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
