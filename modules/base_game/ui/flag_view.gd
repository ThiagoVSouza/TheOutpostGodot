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
