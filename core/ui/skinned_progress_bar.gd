class_name SkinnedProgressBar
extends Control

## The painted progress bar: [UiSkin]'s well with its blue fill revealed left to right.
##
## **The fill is uncovered, not stretched.** It is drawn at the bar's *full* width at every value and
## clipped to the current fraction, so the texture inside it — the crackle, the bevel along the top —
## sits at one fixed scale from 0% to 100%, and progress shows more of that same picture rather than
## a squeezed copy of it growing. Scaling one copy to fit is what a plain [ProgressBar] or a
## stretch-filled [TextureProgressBar] does, and on this art it reads as the pattern sliding and
## smearing as the bar advances.
##
## Both halves are nine-sliced, which is a different question from the one above: slicing is how the
## bar covers a width the art was not drawn at (916px) without distorting its end caps. The middle
## tiles rather than stretches so the crackle keeps its density.

## 0.0 to 1.0. Assigning re-clips; this is what a [Tween] should drive.
var ratio: float = 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		_reveal()

var _background: NinePatchRect = null
var _clip: Control = null
var _fill: NinePatchRect = null


func _init() -> void:
	custom_minimum_size = Vector2(0, UiSkin.PROGRESS_HEIGHT)
	_background = _patch(UiSkin.PROGRESS_BACKGROUND_TEXTURE)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	# The clip is the only thing that changes size with progress. Its child is always the whole bar.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	_fill = _patch(UiSkin.PROGRESS_FILL_TEXTURE)
	_clip.add_child(_fill)


func _ready() -> void:
	_reveal()
	resized.connect(_reveal)


func _patch(texture: Texture2D) -> NinePatchRect:
	var patch := NinePatchRect.new()
	patch.texture = texture
	patch.patch_margin_left = int(UiSkin.PROGRESS_SLICE_H)
	patch.patch_margin_right = int(UiSkin.PROGRESS_SLICE_H)
	patch.patch_margin_top = int(UiSkin.PROGRESS_SLICE_V)
	patch.patch_margin_bottom = int(UiSkin.PROGRESS_SLICE_V)
	patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return patch


## Re-clip to [member ratio]. The fill keeps the bar's full size throughout — only the window onto it
## moves — which is what stops the texture from scaling as the value changes.
func _reveal() -> void:
	if _clip == null or _fill == null:
		return
	_fill.position = Vector2.ZERO
	_fill.size = size
	_clip.position = Vector2.ZERO
	_clip.size = Vector2(size.x * ratio, size.y)
