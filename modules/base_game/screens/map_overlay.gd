extends Control

## A full-screen overlay that renders the overworld map in-game (M7 first pass). Toggled from the
## chat screen rather than routed to, because the [ScreenRouter] is stateless — leaving the chat
## screen would discard its conversation log. As a child overlay the map opens over the running game
## and closes back to it untouched.
##
## Loads this module's map content ([BaseGameMap]) and hands it to the reusable [OverworldMapView],
## then pins the outpost's own flag to the cell the seed founded it on — the map shows a settlement,
## not just terrain.

## The banner pinned to the outpost's cell. A fixed screen size, so it stays findable at any zoom.
const MARKER_FLAG_WIDTH := 30.0


func _ready() -> void:
	# `set_anchors_and_offsets_preset`, not `set_anchors_preset`: the latter recomputes the offsets to
	# *preserve the current rect*, and this overlay is built in code, so at `_ready` it is 0×0 inside
	# a parent that already has a size. That bakes in offsets of -width,-height and pins the overlay
	# to nothing — which is why the Map button used to open an invisible overlay. Screens loaded from
	# a `.tscn` get away with the other call only because their scene already stores a full rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	var map := BaseGameMap.load_map()
	if map == null:
		title.text = "Overworld — map failed to load (see log)"
		return
	view.setup(map, BaseGameMap.load_textures(map))

	var outpost_name := _pin_outpost(view)
	if not outpost_name.is_empty():
		title.text = "Overworld — %s" % outpost_name


## Pin the outpost's banner to its cell. Returns the settlement's name, or "" when this world has no
## site — a game seeded before the outpost had a place on the map still opens, just without a pin.
func _pin_outpost(view: OverworldMapView) -> String:
	var site: Dictionary = Kernel.state.get_value(GameSession.OUTPOST_SITE_STATE_KEY, {})
	if site.is_empty():
		return ""
	var flag := FlagView.new()
	flag.custom_minimum_size = Vector2(MARKER_FLAG_WIDTH, MARKER_FLAG_WIDTH * FlagView.aspect())
	flag.set_value(FlagValue.from_dict(
		Kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {}) as Dictionary))
	view.set_marker("outpost", Vector2i(int(site["x"]), int(site["y"])), flag)
	return String(Entities.get_entity(Kernel.state, "outpost").get("name", ""))
