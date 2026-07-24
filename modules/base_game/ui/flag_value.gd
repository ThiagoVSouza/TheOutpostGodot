class_name FlagValue
extends RefCounted

## A heraldic flag's design: a cloth colour, a tinted pattern, and a tinted emblem — the reusable
## identity shown wherever a house/outpost appears (character cards, the map, the roster). Mirrors
## the legacy flag-designer value so a flag authored in the old system round-trips: [method to_dict]
## / [method from_dict] use the same keys (`shapeColor`, `texture`, `textureColor`, `emblem`,
## `emblemColor`) and hex colour strings, and [method serialize] matches its JSON.
##
## Pure data — no textures, no rendering. [FlagView] turns one of these into pixels.

const NONE := "none"

var shape_color: Color = Color.html("#b62a2a")
var texture: String = NONE          # pattern id, e.g. "pattern03", or "none"
var texture_color: Color = Color.html("#f3c43f")
var emblem: String = "emblem01"     # emblem id, or "none"
var emblem_color: Color = Color.html("#000000")


static func from_dict(data: Dictionary) -> FlagValue:
	var v := FlagValue.new()
	v.shape_color = _color(data.get("shapeColor", "#b62a2a"))
	v.texture = String(data.get("texture", NONE))
	v.texture_color = _color(data.get("textureColor", "#f3c43f"))
	v.emblem = String(data.get("emblem", "emblem01"))
	v.emblem_color = _color(data.get("emblemColor", "#000000"))
	return v


## Parse the serialized string the old designer stored (a JSON object); falls back to the default
## flag on anything malformed, so a bad save never hard-fails a screen. Uses the instance parser
## (not `JSON.parse_string`) so malformed input returns an error code rather than logging one.
static func deserialize(text: String) -> FlagValue:
	var parser := JSON.new()
	if parser.parse(text) == OK and parser.data is Dictionary:
		return from_dict(parser.data as Dictionary)
	return FlagValue.new()


func to_dict() -> Dictionary:
	return {
		"shapeColor": _hex(shape_color),
		"texture": texture,
		"textureColor": _hex(texture_color),
		"emblem": emblem,
		"emblemColor": _hex(emblem_color),
	}


func serialize() -> String:
	return JSON.stringify(to_dict())


func has_pattern() -> bool:
	return texture != NONE and not texture.is_empty()


func has_emblem() -> bool:
	return emblem != NONE and not emblem.is_empty()


static func _color(value: Variant) -> Color:
	return Color.html(String(value)) if String(value).is_valid_html_color() else Color.WHITE


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)
