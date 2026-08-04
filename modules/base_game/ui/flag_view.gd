class_name FlagView
extends ColorRect

## A reusable flag widget: give it a [FlagValue] and it renders the composited heraldic flag at
## whatever size the control is laid out to. One draw call, one [ShaderMaterial] (see flag.gdshader)
## — cheap to place many of, and it updates live when the value changes (so the future flag designer
## gets its preview for free). The cloth silhouette comes from the effect texture's alpha, so the
## control can be any rectangle; the flag draws within its own shape and the rest is transparent.

const SHADER := preload("res://modules/base_game/ui/flag.gdshader")
const BASE_TEX := preload("res://modules/base_game/assets/ui/flag_base.png")
const EFFECT_TEX := preload("res://modules/base_game/assets/ui/flag_effect.png")
## The same banner without its pole, and shorter for it — the legacy build's own second cut of the
## art. A flag hung in a strip of chrome is nearly all pole and nearly no cloth at the tall aspect;
## this one spends its height on the thing the player chose.
const BASE_TEX_SHORT := preload("res://modules/base_game/assets/ui/flag_base_short.png")
const EFFECT_TEX_SHORT := preload("res://modules/base_game/assets/ui/flag_effect_short.png")
const PATTERN_DIR := "res://modules/base_game/assets/flags/patterns/"
const EMBLEM_DIR := "res://modules/base_game/assets/flags/emblems/"

# Texture cache shared across every FlagView, keyed by resource path.
static var _tex_cache: Dictionary = {}
## Where the cloth sits inside each cut's quad, keyed by [member short]. Measured once per cut and
## kept, because it comes from reading an image back and every flag on screen wants the same answer.
static var _cloth_cache: Dictionary = {}

## Draw the poleless cut. Set before the view enters the tree: the textures are chosen once, when
## the material is built.
var short := false

var _value: FlagValue = FlagValue.new()
var _material: ShaderMaterial


## The flag art's height as a multiple of its width. Callers that want a flag at a given width size
## it as `Vector2(w, w * FlagView.aspect())`; the cloth is then never stretched, and no screen has
## to carry the art's pixel dimensions around as a literal.
##
## [param short] answers for the poleless cut, which is a different shape — 1.68 against 2.11 — so a
## caller that sets [member short] has to size itself from the same argument.
static func aspect(short: bool = false) -> float:
	var size := (EFFECT_TEX_SHORT if short else EFFECT_TEX).get_size()
	return size.y / maxf(size.x, 1.0)


## Where the cloth hangs inside the art's rectangle, in UV — `(min.x, min.y, width, height)`.
##
## **The quad is not the flag.** The art carries a pole, a crossbar and a finial, so the cloth is only
## part of the rectangle: on the poleless cut it runs from 0.21 to 1.0 down the quad, which puts its
## centre at 0.605 rather than 0.5. Anything heraldic laid out against the quad therefore sits about a
## tenth of the flag's height too high — which is exactly what a centred emblem did.
##
## Measured off the effect texture's own alpha, which is already the silhouette this shader clips the
## cloth to, so the two can never disagree. Cached per cut — reading an image back is not something to
## do once per flag on screen.
##
## **Not [method Image.get_used_rect], which counts any alpha above zero.** Two thousandths of this
## art is a near-invisible halo out at the quad's edges, and against that test the answer comes back
## as very nearly the whole rectangle — the exact wrong answer, arrived at silently. Any threshold
## between about 2% and 80% gives the same bounds to the pixel, so the number below is chosen from the
## middle of a wide flat band rather than tuned.
##
## The scan runs on a downscaled copy: the result is wanted as a fraction of the quad, where a
## hundred and twenty-eight columns already resolve finer than the eye, and it keeps a per-pixel
## GDScript loop off a half-million-pixel image.
const CLOTH_SCAN_WIDTH := 128
const CLOTH_SCAN_ALPHA := 0.25


static func cloth_rect(short: bool = false) -> Rect2:
	if _cloth_cache.has(short):
		return _cloth_cache[short] as Rect2
	var texture: Texture2D = EFFECT_TEX_SHORT if short else EFFECT_TEX
	var rect := Rect2(0.0, 0.0, 1.0, 1.0)
	var image := texture.get_image()
	if image != null and (not image.is_compressed() or image.decompress() == OK):
		var source := image.get_size()
		if source.x > 0 and source.y > 0:
			var scan := image.duplicate() as Image
			var height := maxi(1, int(round(float(source.y) * CLOTH_SCAN_WIDTH / float(source.x))))
			scan.resize(CLOTH_SCAN_WIDTH, height, Image.INTERPOLATE_BILINEAR)
			var min_x := CLOTH_SCAN_WIDTH
			var min_y := height
			var max_x := -1
			var max_y := -1
			for y in height:
				for x in CLOTH_SCAN_WIDTH:
					if scan.get_pixel(x, y).a < CLOTH_SCAN_ALPHA:
						continue
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
			if max_x >= min_x and max_y >= min_y:
				rect = Rect2(float(min_x) / CLOTH_SCAN_WIDTH, float(min_y) / height,
					float(max_x - min_x + 1) / CLOTH_SCAN_WIDTH,
					float(max_y - min_y + 1) / height)
	_cloth_cache[short] = rect
	return rect


func _init() -> void:
	# ColorRect paints a solid; the shader overrides the output, but keep the input opaque so the
	# shader's alpha is what shows.
	color = Color.WHITE


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("base_tex", BASE_TEX_SHORT if short else BASE_TEX)
	_material.set_shader_parameter("effect_tex", EFFECT_TEX_SHORT if short else EFFECT_TEX)
	# The emblem is kept square against the cloth's own proportion, so this has to follow the cut.
	_material.set_shader_parameter("flag_hw", aspect(short))
	# And the pattern and emblem are placed against the cloth rather than the rectangle it hangs in,
	# which is a different rect per cut for the same reason.
	var cloth := cloth_rect(short)
	_material.set_shader_parameter("cloth_rect",
		Vector4(cloth.position.x, cloth.position.y, cloth.size.x, cloth.size.y))
	material = _material
	# A sensible default footprint in the flag's own aspect; callers can override.
	if custom_minimum_size == Vector2.ZERO:
		var w := 120.0
		custom_minimum_size = Vector2(w, w * aspect(short))
	_apply()


## Show a flag. Accepts a [FlagValue]; live-updates the render.
func set_value(value: FlagValue) -> void:
	_value = value if value != null else FlagValue.new()
	_apply()


func get_value() -> FlagValue:
	return _value


func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("shape_color", _value.shape_color)
	_material.set_shader_parameter("texture_color", _value.texture_color)
	_material.set_shader_parameter("emblem_color", _value.emblem_color)
	_material.set_shader_parameter("has_pattern", _value.has_pattern())
	_material.set_shader_parameter("has_emblem", _value.has_emblem())
	if _value.has_pattern():
		_material.set_shader_parameter("pattern_tex", _load_tex(PATTERN_DIR + _value.texture + ".png"))
	if _value.has_emblem():
		_material.set_shader_parameter("emblem_tex", _load_tex(EMBLEM_DIR + _value.emblem + ".png"))


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex
