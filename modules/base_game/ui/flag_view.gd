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
const PATTERN_DIR := "res://modules/base_game/assets/flags/patterns/"
const EMBLEM_DIR := "res://modules/base_game/assets/flags/emblems/"

# Texture cache shared across every FlagView, keyed by resource path.
static var _tex_cache: Dictionary = {}

var _value: FlagValue = FlagValue.new()
var _material: ShaderMaterial


func _init() -> void:
	# ColorRect paints a solid; the shader overrides the output, but keep the input opaque so the
	# shader's alpha is what shows.
	color = Color.WHITE


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("base_tex", BASE_TEX)
	_material.set_shader_parameter("effect_tex", EFFECT_TEX)
	var tex_size := EFFECT_TEX.get_size()
	if tex_size.x > 0.0:
		_material.set_shader_parameter("flag_hw", tex_size.y / tex_size.x)
	material = _material
	# A sensible default footprint in the flag's own aspect; callers can override.
	if custom_minimum_size == Vector2.ZERO:
		var w := 120.0
		custom_minimum_size = Vector2(w, w * (tex_size.y / maxf(tex_size.x, 1.0)))
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
