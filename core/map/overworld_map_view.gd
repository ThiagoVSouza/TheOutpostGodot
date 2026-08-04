class_name OverworldMapView
extends Control

## Overworld renderer: draws only the visible tile range, with independently toggleable tile and
## 5x5 subgrids. Supports a close default frame, wheel/pinch/key zoom and drag-to-pan.
##
## Deferred to match the old renderer fully: corner-blend mask overlays between biomes, whole-tile
## ground decorations, and season tint. Those compose over this base layer.

## The player pressed on a subtile without panning the map — see [method subtile_at] for the
## coordinate space. What is *at* that subtile is the caller's question to answer: this view knows
## the geometry of the map and nothing about what has been built on it.
signal subtile_clicked(subtile: Vector2i)

## The outlined footprint changed, including to nothing at all — the map drops a selection that the
## player has zoomed away from ([constant MIN_SELECTABLE_PX]), so a caller showing details of the
## selected thing cannot learn about it by polling.
signal selection_changed(footprint: Array[Rect2i])

# Variation channel for the base biome texture is the biome's index in terrain-set order (matches
# `biomeChannel` in mapRenderer.ts).
var _map: TerrainMap
var _textures: Dictionary = {}      # biome -> Array[Texture2D], in variant order
var _channel: Dictionary = {}       # biome -> int (index in terrain order)
var _biome_colors: Dictionary = {}  # biome -> Color, averaged from its own art at setup
var _scatter: Dictionary = {}       # biome -> Array[Texture2D], things that stand on the ground
## Cells whose ground is not what their biome says — a ploughed field on grass. `Vector2i -> String`,
## where the string is a key into [member _textures] exactly as a biome name is, so an overridden cell
## picks up its art, its variants and its averaged colour through the paths a biome already uses.
##
## **Deliberately not a biome.** Adding one to [TerrainMap] would make this map multi-biome and cost
## the single-rectangle fast path a uniform world is drawn with — for a handful of cells.
var _ground: Dictionary = {}

var _zoom: float = 1.0
var _origin: Vector2 = Vector2.ZERO # world-pixel coordinate drawn at the view's top-left
var _dragging: bool = false
var _markers: Dictionary = {}       # id -> {cell: Vector2i, control: Control}
## **Both coordinate overlays start off.** They are a construction aid, not part of the world: the map
## a player opens into should be the terrain, and the grid is something they turn on when they want to
## reason about cells. The Map Layers control reads these rather than stating its own defaults, so the
## plates come up matching what the map is actually drawing.
var _tile_grid_visible := false
var _subgrid_visible := false

## **What the world is made of, above the ground it stands on.** Everything worked into the map or
## standing on it — a ploughed field, a tree, a rock, and eventually a building — is one layer, and
## the things that move over it are another. Neither is a rendering detail: they are what the Terrain
## plate turns off to leave bare ground, and what a selection is allowed to find.
##
## The ground itself has no flag. It is the surface the other two are drawn on, so "hide the terrain"
## would leave nothing for anything else to stand on.
var _construction_layer_visible := true
var _units_layer_visible := true

## The selected footprint, in **subtile** space — see [method subtile_at]. An [Array] of [Rect2i]
## rather than one, because a construction need not be a rectangle; empty when nothing is selected.
##
## The view is told what to outline and never works it out: which cells are one farm is the caller's
## knowledge, exactly as which cell an outpost stands on is ([method set_marker]).
var _selection: Array[Rect2i] = []

## Where the pointer went down, and how far it has travelled since. A press on this control is
## ambiguous until it is released — the same button both pans the map and picks something off it.
var _press_position := Vector2.ZERO
var _drag_distance := 0.0

const MIN_ZOOM := 0.05
const MAX_ZOOM := 4.0

## **How small a tile may get on screen before its art stops being drawn at all.**
##
## Terrain art costs one [method CanvasItem.draw_texture_rect] *and* a variant hash per visible cell,
## and the visible cell count is quadratic in how far out the player zooms: this map is 500x500 at
## 128px tiles, so a 1280x800 stage sees 160 tiles at the default frame and **25,000** at
## [constant MIN_ZOOM]. Nothing about that is texture memory — four 256px tiles are ~170 KB in VRAM —
## it is per-cell work in GDScript, and it lands as a stutter while dragging or zooming rather than
## as a steady frame cost, because [method CanvasItem._draw] only runs on [method queue_redraw].
##
## Below this size the art is downscaled past the point of being legible anyway, so the map falls
## back to flat biome colour and the cell loop stops doing the expensive half of its work. At 32px
## the ceiling is about a thousand cells, which is a comfortable one.
##
## The swap is not a visible flash because the flat colour is **averaged from the biome's own
## textures** ([method _derive_biome_colors]) rather than picked by hand: what is lost crossing the
## threshold is detail, not hue.
const MIN_TEXTURED_TILE_PX := 32.0

## **Things that stand on the ground, rather than being part of it.** Trees, and eventually whatever
## else has a footprint and a silhouette. They are not terrain and cannot be drawn as terrain for two
## reasons: a tree overhangs the cell it stands on, so the next cell's ground would paint over its
## canopy; and two trees that overlap have to be sorted, near in front of far.
##
## Both fall out of drawing them in a **second pass** over the same window. Rows run top to bottom, so
## a tree one row down is drawn after — and therefore in front of — the one above it, which is the
## sorting, free. Only the ones sharing a cell have to be ordered against each other.
##
## Placement is [MapVariation] again: the same hash the ground variants use, on its own channel. A
## cell's trees are therefore a pure function of the map seed and cost nothing to store, which is what
## lets a 500x500 map have them at all.
const SCATTER_CHANNEL := 64
const SCATTER_SLOTS_PER_CELL := 2
## Of 255. Deliberately sparse while this is one test sprite — the density is the dial to turn once
## there is a set of trees and a reason for a cell to be wooded.
const SCATTER_CHANCE := 26
## How tall a sprite is drawn, against the tile it stands on.
const SCATTER_TILE_FRACTION := 0.62
## Where in its own image the thing actually meets the ground: along the trunk, at its foot — not the
## middle of the picture, most of which is canopy above the ground and shadow beside it. Get this
## wrong and everything bobs against the terrain as the map pans.
const SCATTER_ANCHOR := Vector2(0.34, 0.91)
## Cells to reach past the visible window before drawing. A tree stands *up* from its footing, so one
## rooted just below the bottom edge still has canopy on screen; without this they pop in at the edge.
const SCATTER_OVERSCAN := Vector2i(1, 2)
## Below this the sprites are a few pixels of noise, and there are thousands of them: at
## [constant MIN_ZOOM] this map shows 25,000 cells at once. Higher than the ground's own threshold
## because a tree stops being a tree well before the ground stops being ground.
const MIN_SCATTER_TILE_PX := 40.0
## A desktop stage begins at roughly this many complete map tiles from top to bottom. Unlike the old
## fit-to-whole-map behavior, making the world larger no longer makes the starting view farther away.
##
## **Chosen against [constant MIN_SELECTABLE_PX], not by eye**, and measured at the *small* end of
## the window sizes this runs at, because that is where it binds. On a 1280x800 stage ten rows put a
## subtile at about 15 units, comfortably selectable; on a windowed 1000x565 stage the same ten rows
## put it at about 10 — exactly the size below which one stops being worth aiming at, so the finest
## thing a player can select would blink in and out with the smallest scroll, at the zoom the game
## opens at. Eight rows lifts that to about 13 on the small window and about 19 on the large one, and
## puts every stage size clear of the line rather than the roomy ones only.
const DEFAULT_VISIBLE_TILE_ROWS := 8.0
const SUBGRID_DIVISIONS := 5

## **How small a thing may get on screen before it stops being something you can point at.** The one
## number the whole selection ladder is built from: a thing is selectable while its own footprint is
## at least this many units across, so what a click can reach changes with the zoom without anyone
## assigning tiers by hand.
##
## A subtile at the default frame is 13 to 19 units depending on the window and passes; zoom out to
## where a tile is 20 and it is 4 units and does not, while a farm three tiles wide is still 60 by 40.
## Out at [constant MIN_ZOOM] a
## one-tile cottage is 6 units and has gone too, while the farm is 13 and remains. The same rule
## retires each thing at its own zoom, and a smaller building retires earlier than a larger one
## without either being assigned a tier.
##
## **Nothing built today is ever too small to click.** A farm plot bottoms out at 13 units because the
## map does not zoom out far enough to shrink one past this, so the rung above a construction is never
## reached in practice yet — which is just as well, because that rung is the settlement and it does not
## exist (see `map_content.gd`). Lower [constant MIN_ZOOM], or build something one tile across, and the
## walk starts mattering.
##
## Ten is the smaller of two limits: below about this a target is hard to hit with a mouse, and the
## outline drawn round it stops enclosing anything legible.
const MIN_SELECTABLE_PX := 10.0

## How far the pointer may travel between press and release and still count as a press *on* something
## rather than a drag of the map. One button does both, so the difference has to be measured.
##
## Accumulated distance, not press-to-release displacement: a pan that wanders off and comes back has
## moved the world under the player, and treating that as a click would select whatever the return
## journey happened to end on.
const CLICK_SLOP := 6.0

## The outline drawn round the selected footprint.
##
## **Blue, because everything the map is made of is not.** Grass is green and worked earth is brown,
## which between them cover the warm half of the wheel — a gold line was legible but sat *in* that
## range, reading as part of the ground rather than as a mark laid over it. Blue is the one strong
## hue nothing on the map competes with, and it is already the skin's colour for "this is the one
## selected" ([constant UiSkin.BLUE], the speed plates' latched art).
##
## It is not that art's colour, though. The painted blue is a muted slate (about `3d5d80`) built to
## sit behind a caption on a dark plate; laid on sunlit grass it is darker than the grass and reads as
## a shadow. This is the same hue lifted to something luminous — the family kept, the job changed.
const SELECTION_COLOR := Color(0.36, 0.72, 1.0, 1.0)
## A second, darker line laid just outside the first. The map is bright and varied, and a single line
## of any colour disappears somewhere; the pair reads as an edge on anything. Navy rather than the
## near-black it started as, so the two together read as one blue mark rather than as a coloured line
## with a soot outline.
const SELECTION_SHADOW_COLOR := Color(0.04, 0.11, 0.24, 0.7)
## In screen units, so the outline stays exactly as findable at every zoom — unlike the thing it
## encloses, which is the whole reason [constant MIN_SELECTABLE_PX] exists.
##
## Three, not the two it began at: at two the line was correct and easy to miss, which for the one
## mark on the map saying "this is what you are acting on" is the wrong way to be wrong.
const SELECTION_WIDTH := 3.0

## Light lines stay legible over dark terrain without turning the construction grid into a black
## cage over the map. The subgrid is deliberately softer so tile boundaries retain the hierarchy.
const TILE_GRID_COLOR := Color(1.0, 1.0, 1.0, 0.46)
const SUBGRID_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const TILE_GRID_WIDTH := 2.0
const SUBGRID_WIDTH := 1.0

## The ring drawn on a marked cell, so the marker's *cell* is unambiguous even though the marker
## itself is drawn at a fixed screen size and therefore does not cover the tile.
const MARKER_RING_COLOR := Color(1, 1, 1, 0.85)
const MARKER_RING_RADIUS := 5.0
const MARKER_RING_WIDTH := 2.0
const FALLBACK_COLORS := {
	"grass": Color(0.36, 0.55, 0.24), "savanah": Color(0.68, 0.6, 0.28),
	"swamp": Color(0.3, 0.38, 0.28), "tundra": Color(0.8, 0.84, 0.88),
	"desert": Color(0.82, 0.72, 0.42), "sand": Color(0.88, 0.82, 0.6),
	"ocean": Color(0.16, 0.32, 0.5),
}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# **Mipmaps in the import do nothing without this**, and nothing about the failure says so: the
	# project leaves `default_texture_filter` at Godot's own Linear, which never samples a mip level,
	# so a terrain texture imported with mipmaps would still be point-sampled from its full-size image
	# at every zoom — shimmering as the map moves and thrashing the texture cache for the privilege.
	# Set on this node alone; the UI wants the project default and has no mipmaps to sample.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Focusable, and focused on open: `_gui_input` only receives *key* events for the focused
	# control, so without this the zoom keys would go nowhere while the wheel still worked.
	focus_mode = Control.FOCUS_ALL
	grab_focus.call_deferred()
	# Re-frame once the control gets its real size from layout (size is 0 during _ready).
	resized.connect(fit)


## Hand the view its decoded map and loaded textures (biome -> Array[Texture2D]), then establish the
## close default frame.
func setup(map: TerrainMap, textures: Dictionary) -> void:
	_map = map
	_textures = textures
	_channel.clear()
	var names := map.biome_names()
	for i in names.size():
		_channel[String(names[i])] = i
	_derive_biome_colors()
	fit()


## Reset to the default close frame, centred on the world. The public name is retained because the
## existing Open Map action calls it as the map's reset-view operation.
func fit() -> void:
	if _map == null:
		return
	var view := size
	var world := Vector2(_map.width, _map.height) * _map.tile_size_px
	if world.x <= 0.0 or world.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return
	_zoom = clampf(view.y / (float(_map.tile_size_px) * DEFAULT_VISIBLE_TILE_ROWS),
		MIN_ZOOM, MAX_ZOOM)
	# Centre: put the world's midpoint at the view's midpoint.
	_origin = world * 0.5 - (view * 0.5) / _zoom
	_clamp_origin()
	_refresh()


func set_tile_grid_visible(visible: bool) -> void:
	if _tile_grid_visible == visible:
		return
	_tile_grid_visible = visible
	queue_redraw()


func is_tile_grid_visible() -> bool:
	return _tile_grid_visible


func set_subgrid_visible(visible: bool) -> void:
	if _subgrid_visible == visible:
		return
	_subgrid_visible = visible
	queue_redraw()


func is_subgrid_visible() -> bool:
	return _subgrid_visible


# --- layers ------------------------------------------------------------------------------------

## Show or hide everything worked into the ground or standing on it — the ploughed fields and the
## trees today, buildings and rocks when there are any. Turning it off leaves the bare biome, which is
## what the Terrain plate is for.
##
## **Dropping a selection that stood on this layer is the caller's to do**, not this method's. An
## outline round a farm that is no longer drawn points at empty grass — but whether the selected
## footprint *was* a farm or was the bare ground beside one is exactly the distinction this view does
## not keep, and bare ground is still there with the layer off.
func set_construction_layer_visible(visible: bool) -> void:
	if _construction_layer_visible == visible:
		return
	_construction_layer_visible = visible
	queue_redraw()


func is_construction_layer_visible() -> bool:
	return _construction_layer_visible


## Show or hide whatever moves over the map. **Nothing draws through this yet** — there are no units.
## It is a real flag rather than a stub because the Terrain plate turns it off together with the
## constructions, and a plate whose second half quietly did nothing would look like it worked.
func set_units_layer_visible(visible: bool) -> void:
	if _units_layer_visible == visible:
		return
	_units_layer_visible = visible
	queue_redraw()


func is_units_layer_visible() -> bool:
	return _units_layer_visible


# --- selection ---------------------------------------------------------------------------------

## The map divided [constant SUBGRID_DIVISIONS] ways on each axis — the same squares the 5x5 overlay
## draws, so what a player can turn on and see is exactly what they can click. A whole map cell is
## therefore `subtile / SUBGRID_DIVISIONS`, and the two coordinate spaces never need converting
## anywhere else.
##
## Takes a point in this control's own coordinates. The answer is **not** clamped to the map: a click
## past the edge of the world is a click on nothing, and a caller has to be able to tell.
func subtile_at(point: Vector2) -> Vector2i:
	if _map == null or _zoom <= 0.0:
		return Vector2i(-1, -1)
	var world := _origin + point / _zoom
	var step := float(_map.tile_size_px) / float(SUBGRID_DIVISIONS)
	return Vector2i(int(floor(world.x / step)), int(floor(world.y / step)))


## Whether [param subtile] is on the map at all.
func has_subtile(subtile: Vector2i) -> bool:
	if _map == null:
		return false
	return (subtile.x >= 0 and subtile.y >= 0
		and subtile.x < _map.width * SUBGRID_DIVISIONS
		and subtile.y < _map.height * SUBGRID_DIVISIONS)


## The whole footprint as one rectangle of the current screen, which is what decides whether it is
## worth aiming at. Its *bounds*, deliberately: an L-shaped building is as easy to hit as the box
## around it, and the alternative is asking how big its smallest limb is.
func footprint_screen_size(footprint: Array[Rect2i]) -> Vector2:
	if _map == null or footprint.is_empty():
		return Vector2.ZERO
	var bounds := footprint[0]
	for rect in footprint:
		bounds = bounds.merge(rect)
	var step := float(_map.tile_size_px) / float(SUBGRID_DIVISIONS)
	return Vector2(bounds.size) * step * _zoom


## The one question the selection ladder asks. See [constant MIN_SELECTABLE_PX].
##
## The **smaller** dimension decides: a long thin wall one subtile deep is as hard to click as a
## subtile, however far it runs.
func is_footprint_selectable(footprint: Array[Rect2i]) -> bool:
	var on_screen := footprint_screen_size(footprint)
	if on_screen == Vector2.ZERO:
		return false
	return minf(on_screen.x, on_screen.y) >= MIN_SELECTABLE_PX


## Outline [param footprint] — subtile-space rectangles, which for bare ground is a single 1x1.
## Replaces whatever was selected; pass an empty array (or call [method clear_selection]) for nothing.
##
## **The caller has already decided this is selectable.** It is handed a footprint, not a point, so a
## farm arrives as the whole farm — which is what makes "click any part of a construction, get the
## construction" a property of the content rather than of the renderer.
func set_selection(footprint: Array[Rect2i]) -> void:
	if footprint == _selection:
		return
	_selection = footprint.duplicate()
	queue_redraw()
	selection_changed.emit(_selection.duplicate())


func clear_selection() -> void:
	set_selection([] as Array[Rect2i])


func selection() -> Array[Rect2i]:
	return _selection.duplicate()


func has_selection() -> bool:
	return not _selection.is_empty()


## Drop a selection the player has zoomed away from. The outline is the only thing keeping a
## shrinking farm findable, and past its threshold it stops enclosing anything a player could act on
## — so the honest thing is to let it go rather than leave a mark on the map that can no longer be
## read.
func _drop_unselectable() -> void:
	if has_selection() and not is_footprint_selectable(_selection):
		clear_selection()


## Useful to accessibility/debug UI and to lock the initial framing contract in tests.
func visible_tile_rows() -> float:
	if _map == null or _zoom <= 0.0:
		return 0.0
	return size.y / (float(_map.tile_size_px) * _zoom)


## Pin [param control] to map cell [param cell], replacing any marker already under [param id]. The
## marker is the **caller's own node**, which is what keeps this view free of anything
## content-specific: `base_game` pins a `FlagView` for the outpost, and core never learns that flags
## exist. The node is reparented here and positioned with its bottom edge on the cell's centre, the
## way a pin sits on the spot it marks.
##
## Markers keep a fixed screen size: a settlement that shrank with the zoom would vanish exactly
## when the player zooms out to find it.
func set_marker(id: String, cell: Vector2i, control: Control) -> void:
	remove_marker(id)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat a pan/zoom aimed at the map
	if control.size == Vector2.ZERO:
		control.size = control.custom_minimum_size
	if control.get_parent() != self:
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		add_child(control)
	_markers[id] = {"cell": cell, "control": control}
	_refresh()


func remove_marker(id: String) -> void:
	var existing: Dictionary = _markers.get(id, {}) as Dictionary
	if existing.is_empty():
		return
	var control: Control = existing["control"]
	if is_instance_valid(control):
		control.queue_free()
	_markers.erase(id)


func clear_markers() -> void:
	for id in _markers.keys():
		remove_marker(String(id))


## Redraw the tiles *and* reposition the markers. Every pan, zoom and re-fit has to do both, so they
## go through one call — a marker left behind by a pan is the bug this prevents.
func _refresh() -> void:
	queue_redraw()
	_place_markers()


func _place_markers() -> void:
	for id in _markers:
		var marker: Dictionary = _markers[id] as Dictionary
		var control: Control = marker["control"]
		if not is_instance_valid(control):
			continue
		var centre := _cell_centre_on_screen(marker["cell"] as Vector2i)
		# Bottom-centre on the cell, then hide it once the cell itself leaves the view: a pin
		# clamped to the edge of a map claims a position the settlement does not have.
		control.position = centre - Vector2(control.size.x * 0.5, control.size.y)
		control.visible = Rect2(Vector2.ZERO, size).has_point(centre)


## Where a cell's centre falls in this control's coordinates.
func _cell_centre_on_screen(cell: Vector2i) -> Vector2:
	var tile := float(_map.tile_size_px) if _map != null else 0.0
	return ((Vector2(cell) + Vector2(0.5, 0.5)) * tile - _origin) * _zoom


func _draw() -> void:
	if _map == null:
		return
	var tile := float(_map.tile_size_px)
	var textured := is_terrain_textured()
	if not textured and _map.biome_names().size() == 1:
		# A uniform map is one rectangle, not one draw call per visible cell. At minimum zoom that
		# avoids tens of thousands of identical green rectangles per frame. Keep multi-biome maps on
		# the per-cell path so distance never erases their terrain differences — they pay per cell,
		# but only for a `draw_rect`, with no texture and no variant hash.
		var map_rect := Rect2(-_origin * _zoom,
			Vector2(_map.width, _map.height) * tile * _zoom)
		var visible_map := map_rect.intersection(Rect2(Vector2.ZERO, size))
		if visible_map.has_area():
			draw_rect(visible_map, _biome_color(_map.biome_at(0, 0)))
		# The one rectangle is the *biome*; anything worked into it is still its own cell.
		_draw_ground_overrides(tile, textured)
	else:
		# Authored textured maps still cull to the visible tile window.
		var first_x := maxi(0, int(floor(_origin.x / tile)))
		var first_y := maxi(0, int(floor(_origin.y / tile)))
		var last_x := mini(_map.width - 1, int(floor((_origin.x + size.x / _zoom) / tile)))
		var last_y := mini(_map.height - 1, int(floor((_origin.y + size.y / _zoom) / tile)))
		for y in range(first_y, last_y + 1):
			for x in range(first_x, last_x + 1):
				var biome := _ground_key(x, y)
				# Snap corners to whole pixels so neighbouring tiles never leave a seam.
				var left := roundf((x * tile - _origin.x) * _zoom)
				var top := roundf((y * tile - _origin.y) * _zoom)
				var right := roundf(((x + 1) * tile - _origin.x) * _zoom)
				var bottom := roundf(((y + 1) * tile - _origin.y) * _zoom)
				var rect := Rect2(left, top, right - left, bottom - top)
				# `_texture_for` is the expensive half — a dictionary lookup and a three-round 32-bit
				# hash, in GDScript, per cell. Below the threshold it is not called at all.
				var tex := _texture_for(biome, x, y) if textured else null
				if tex != null:
					draw_texture_rect(tex, rect, false)
				else:
					draw_rect(rect, _biome_color(biome))

	_draw_scatter(tile)
	_draw_map_grids()
	# Last, and over the grids: the outline says what the player has picked, and a coordinate overlay
	# drawn on top of it would break the one continuous line that makes it read as an enclosure.
	_draw_selection(tile)

	for id in _markers:
		var cell := (_markers[id] as Dictionary)["cell"] as Vector2i
		draw_arc(_cell_centre_on_screen(cell), MARKER_RING_RADIUS, 0.0, TAU, 24,
			MARKER_RING_COLOR, MARKER_RING_WIDTH, true)


## Hand the view the things that stand on a biome's ground — trees today. Keyed the same way the
## terrain textures are, so a biome with none simply has no entry.
func set_scatter(scatter: Dictionary) -> void:
	_scatter = scatter
	queue_redraw()


## Hand the view the cells whose ground has been worked into something else — `Vector2i -> String`,
## the string keyed into the same texture table biome names are. See [member _ground].
func set_ground_overrides(overrides: Dictionary) -> void:
	_ground = overrides
	queue_redraw()


## What a cell's ground *is*, which is its biome unless something has been made of it — and its biome
## again with the construction layer off, because a ploughed field is something that was *done* to
## grass and hiding the works leaves the grass.
func _ground_key(x: int, y: int) -> String:
	if not _construction_layer_visible:
		return _map.biome_at(x, y)
	var key: Variant = _ground.get(Vector2i(x, y))
	return String(key) if key != null else _map.biome_at(x, y)


## The perimeter of the selected footprint, traced rather than drawn rectangle by rectangle: an edge
## between two selected subtiles is interior and is skipped, so two plots that happen to abut are
## outlined as the one shape they now look like, and a footprint that is not a rectangle at all still
## comes out right.
##
## Cost is four neighbour lookups per subtile in the footprint — 600 for a three-by-two-tile farm, per
## redraw. That is comfortable for a building and would not be for a province; the day something
## selects a region, this wants the bounds instead.
func _draw_selection(tile: float) -> void:
	if _selection.is_empty() or _map == null:
		return
	var step := tile / float(SUBGRID_DIVISIONS)
	# The set is what makes an edge test a lookup rather than a search through the rectangles.
	var filled: Dictionary = {}
	for rect in _selection:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				filled[Vector2i(x, y)] = true

	var segments: Array[PackedVector2Array] = []
	for subtile: Vector2i in filled:
		var left := (float(subtile.x) * step - _origin.x) * _zoom
		var top := (float(subtile.y) * step - _origin.y) * _zoom
		var right := (float(subtile.x + 1) * step - _origin.x) * _zoom
		var bottom := (float(subtile.y + 1) * step - _origin.y) * _zoom
		if not filled.has(subtile + Vector2i(0, -1)):
			segments.append(PackedVector2Array([Vector2(left, top), Vector2(right, top)]))
		if not filled.has(subtile + Vector2i(0, 1)):
			segments.append(PackedVector2Array([Vector2(left, bottom), Vector2(right, bottom)]))
		if not filled.has(subtile + Vector2i(-1, 0)):
			segments.append(PackedVector2Array([Vector2(left, top), Vector2(left, bottom)]))
		if not filled.has(subtile + Vector2i(1, 0)):
			segments.append(PackedVector2Array([Vector2(right, top), Vector2(right, bottom)]))

	# The dark line first and wider, so what shows either side of the pale one is a rim rather than a
	# second outline — the same trick the top bar's lettering uses to stay readable on parchment.
	for segment in segments:
		draw_line(segment[0], segment[1], SELECTION_SHADOW_COLOR, SELECTION_WIDTH * 2.0, true)
	for segment in segments:
		draw_line(segment[0], segment[1], SELECTION_COLOR, SELECTION_WIDTH, true)


## The overridden cells, drawn over a uniform map's single rectangle.
##
## Walks the overrides and culls each, rather than walking the visible window and asking about every
## cell in it: the set is a handful of worked cells against a quarter of a million wild ones. That
## trade reverses if a map is ever mostly built on, and this is where it would be noticed.
func _draw_ground_overrides(tile: float, textured: bool) -> void:
	if _ground.is_empty() or not _construction_layer_visible:
		return
	var view := Rect2(Vector2.ZERO, size)
	for cell: Vector2i in _ground:
		var left := roundf((float(cell.x) * tile - _origin.x) * _zoom)
		var top := roundf((float(cell.y) * tile - _origin.y) * _zoom)
		var right := roundf((float(cell.x + 1) * tile - _origin.x) * _zoom)
		var bottom := roundf((float(cell.y + 1) * tile - _origin.y) * _zoom)
		var rect := Rect2(left, top, right - left, bottom - top)
		if not rect.intersects(view):
			continue
		var key := String(_ground[cell])
		var texture := _texture_for(key, cell.x, cell.y) if textured else null
		if texture != null:
			draw_texture_rect(texture, rect, false)
		else:
			draw_rect(rect, _biome_color(key))


## Whether anything standing on the ground is currently being drawn — false with nothing to draw,
## false with the layer it belongs to turned off, and false once zoomed out past
## [constant MIN_SCATTER_TILE_PX].
func is_scatter_visible() -> bool:
	if _map == null or _scatter.is_empty() or not _construction_layer_visible:
		return false
	return float(_map.tile_size_px) * _zoom >= MIN_SCATTER_TILE_PX


## What stands on one cell's ground — see the note in [method _draw_scatter] for why this is asked of
## the ground rather than of the biome under it. Its own method so the rule is checkable without
## driving a redraw and reading pixels back.
func _scatter_variants(x: int, y: int) -> Array:
	return _scatter.get(_ground_key(x, y), [])


## The second pass. See [constant SCATTER_CHANNEL] for why it is a pass of its own.
func _draw_scatter(tile: float) -> void:
	if not is_scatter_visible():
		return
	var first_x := maxi(0, int(floor(_origin.x / tile)) - SCATTER_OVERSCAN.x)
	var first_y := maxi(0, int(floor(_origin.y / tile)) - SCATTER_OVERSCAN.y)
	var last_x := mini(_map.width - 1,
		int(floor((_origin.x + size.x / _zoom) / tile)) + SCATTER_OVERSCAN.x)
	var last_y := mini(_map.height - 1,
		int(floor((_origin.y + size.y / _zoom) / tile)) + SCATTER_OVERSCAN.y)
	var height := tile * _zoom * SCATTER_TILE_FRACTION
	for y in range(first_y, last_y + 1):
		for x in range(first_x, last_x + 1):
			# **Keyed on what the ground *is*, not on what the biome says it was.** Nobody leaves a
			# pine standing in the middle of a ploughed field: working the ground clears what stood on
			# it. Because the lookup goes through [method _ground_key], that falls out of the farm
			# simply having no scatter of its own rather than from a rule about farms — and a worked
			# ground that *should* carry something (an orchard's trees, a quarry's rubble) gets it by
			# being given one.
			#
			# Only the cell a thing is **footed** in is tested. A tree rooted on the grass beside a
			# field still leans its canopy over the furrows, which is what a hedgerow looks like.
			var variants := _scatter_variants(x, y)
			if variants.is_empty():
				continue
			# Collected before drawing so the ones sharing a cell can be ordered among themselves;
			# between cells the row order has already done it.
			var placed: Array = []
			for slot in SCATTER_SLOTS_PER_CELL:
				var hash := MapVariation.hash32(_map.seed, x, y, SCATTER_CHANNEL + slot)
				if (hash & 0xFF) >= SCATTER_CHANCE:
					continue
				placed.append([
					float((hash >> 8) & 0xFF) / 255.0,   # where in the cell, across
					float((hash >> 16) & 0xFF) / 255.0,  # and down — which is also the sort key
					int((hash >> 24) % variants.size()),
				])
			if placed.is_empty():
				continue
			placed.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
			for spot: Array in placed:
				var texture := variants[int(spot[2])] as Texture2D
				if texture == null:
					continue
				var art := texture.get_size()
				var wide := height * art.x / maxf(art.y, 1.0)
				# The cell's top-left on screen, plus where in the cell this one is footed.
				var foot := Vector2(
					(float(x) + float(spot[0])) * tile - _origin.x,
					(float(y) + float(spot[1])) * tile - _origin.y) * _zoom
				draw_texture_rect(texture, Rect2(
					foot - Vector2(wide, height) * SCATTER_ANCHOR, Vector2(wide, height)), false)


## Whether the map is currently drawing its terrain art rather than flat biome colour — false when
## there is no art at all, and false once the player has zoomed out past
## [constant MIN_TEXTURED_TILE_PX]. Public because it is the one thing about the renderer a caller
## (or a test) can meaningfully ask: it decides both what the map looks like and what a redraw costs.
func is_terrain_textured() -> bool:
	if _map == null or _textures.is_empty():
		return false
	return float(_map.tile_size_px) * _zoom >= MIN_TEXTURED_TILE_PX


## What one cell of [param biome] is worth as a single colour: the average of its own art, so
## crossing [constant MIN_TEXTURED_TILE_PX] loses detail without shifting hue. Falls back to the
## hand-picked table for a biome with no art — which is every biome on the construction map today.
func _biome_color(biome: String) -> Color:
	if _biome_colors.has(biome):
		return _biome_colors[biome] as Color
	return FALLBACK_COLORS.get(biome, Color(0.5, 0.5, 0.5))


## Averaged once, at [method setup], because it reads pixels back off the GPU — per redraw it would
## cost more than the textures it is standing in for.
func _derive_biome_colors() -> void:
	_biome_colors.clear()
	for biome: String in _textures:
		var variants: Array = _textures[biome]
		var total := Color(0.0, 0.0, 0.0)
		var counted := 0
		for variant: Variant in variants:
			var average := _average_color(variant as Texture2D)
			if average.a <= 0.0:
				continue
			total += Color(average.r, average.g, average.b)
			counted += 1
		if counted > 0:
			_biome_colors[biome] = total / float(counted)


## One texture reduced to its mean colour. Returns a fully transparent colour when the image cannot
## be read at all, which the caller takes as "no answer" and skips, leaving the hand-picked fallback
## in place rather than painting the map black.
##
## **An [AtlasTexture] has to be taken apart in the right order.** Its own `get_image` slices the base
## before anything has a chance to decompress it, and [method Image.get_region] refuses to operate on
## a block-compressed image — which a VRAM-compressed import always is. So: base first, decompress,
## and only then take the region.
static func _average_color(texture: Texture2D) -> Color:
	var unreadable := Color(0.0, 0.0, 0.0, 0.0)
	if texture == null:
		return unreadable
	var atlas := texture as AtlasTexture
	var source: Texture2D = atlas.atlas if atlas != null else texture
	if source == null:
		return unreadable
	var image := source.get_image()
	if image == null:
		return unreadable
	# `get_image` hands back whatever the import produced, which for a VRAM-compressed texture is a
	# block format `get_pixel` cannot read either.
	if image.is_compressed() and image.decompress() != OK:
		return unreadable
	if atlas != null:
		var region := Rect2i(atlas.region)
		if region.size.x <= 0 or region.size.y <= 0:
			return unreadable
		image = image.get_region(region)
	if image.is_empty():
		return unreadable
	# Lanczos, not bilinear: a bilinear downscale straight to 1x1 samples four texels and calls that
	# the average, which for grass is whichever four blades it happened to land on.
	image.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return image.get_pixel(0, 0)


## Cut a variant atlas into the per-variant textures [method setup] expects, in reading order —
## left to right, then top to bottom. One atlas rather than one file per variant so that every cell
## on screen draws from the *same* texture: with four separate textures picked pseudo-randomly per
## cell, the texture changes every few tiles and the canvas batches break up constantly.
##
## [member AtlasTexture.filter_clip] keeps each tile's sampling inside its own region, so a variant
## cannot bleed into its neighbour along a shared edge. It does not fix the deeper mip levels, where
## the base texture genuinely mixes neighbouring cells together — [constant MIN_TEXTURED_TILE_PX] is
## what keeps the map away from those.
static func slice_variants(atlas: Texture2D, columns: int, rows: int) -> Array[Texture2D]:
	var variants: Array[Texture2D] = []
	if atlas == null or columns <= 0 or rows <= 0:
		return variants
	var cell := Vector2(float(atlas.get_width()) / float(columns),
		float(atlas.get_height()) / float(rows))
	for row in rows:
		for column in columns:
			var slice := AtlasTexture.new()
			slice.atlas = atlas
			slice.region = Rect2(Vector2(float(column), float(row)) * cell, cell)
			slice.filter_clip = true
			variants.append(slice)
	return variants


func _texture_for(biome: String, x: int, y: int) -> Texture2D:
	var variants: Array = _textures.get(biome, [])
	if variants.is_empty():
		return null
	var channel := int(_channel.get(biome, 0))
	var index := MapVariation.pick_variant(_map.seed, x, y, channel, variants.size())
	return variants[index] as Texture2D


func _draw_map_grids() -> void:
	if not _tile_grid_visible and not _subgrid_visible:
		return
	var tile := float(_map.tile_size_px)
	var world_width := float(_map.width) * tile
	var world_height := float(_map.height) * tile
	var visible_left := maxf(0.0, _origin.x)
	var visible_top := maxf(0.0, _origin.y)
	var visible_right := minf(world_width, _origin.x + size.x / _zoom)
	var visible_bottom := minf(world_height, _origin.y + size.y / _zoom)

	if _subgrid_visible:
		var step := tile / float(SUBGRID_DIVISIONS)
		_draw_grid_lines(step, SUBGRID_DIVISIONS, visible_left, visible_top, visible_right,
			visible_bottom, SUBGRID_COLOR, SUBGRID_WIDTH)
	if _tile_grid_visible:
		_draw_grid_lines(tile, 1, visible_left, visible_top, visible_right, visible_bottom,
			TILE_GRID_COLOR, TILE_GRID_WIDTH)


## Draw a world-aligned grid through the visible map rectangle. [param major_every] skips tile
## boundaries in the subgrid pass so the stronger tile grid can own those pixels.
func _draw_grid_lines(step: float, major_every: int, left: float, top: float, right: float,
		bottom: float, color: Color, line_width: float) -> void:
	var first_x := int(ceil(left / step))
	var last_x := int(floor(right / step))
	for i in range(first_x, last_x + 1):
		if major_every > 1 and i % major_every == 0:
			continue
		var screen_x := (float(i) * step - _origin.x) * _zoom
		draw_line(Vector2(screen_x, (top - _origin.y) * _zoom),
			Vector2(screen_x, (bottom - _origin.y) * _zoom), color, line_width, true)
	var first_y := int(ceil(top / step))
	var last_y := int(floor(bottom / step))
	for i in range(first_y, last_y + 1):
		if major_every > 1 and i % major_every == 0:
			continue
		var screen_y := (float(i) * step - _origin.y) * _zoom
		draw_line(Vector2((left - _origin.x) * _zoom, screen_y),
			Vector2((right - _origin.x) * _zoom, screen_y), color, line_width, true)


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
				# **The same button pans the map and picks things off it**, so which one this is cannot
				# be known until the button comes back up — see [constant CLICK_SLOP].
				_dragging = mb.pressed
				if mb.pressed:
					_press_position = mb.position
					_drag_distance = 0.0
				elif _drag_distance <= CLICK_SLOP:
					subtile_clicked.emit(subtile_at(_press_position))
	elif event is InputEventMouseMotion and _dragging:
		var motion := (event as InputEventMouseMotion).relative
		_drag_distance += motion.length()
		# Drag moves the world under the cursor: shift the origin opposite to the motion.
		_origin -= motion / _zoom
		_clamp_origin()
		_refresh()
	elif event is InputEventMagnifyGesture:
		# Touch pinch-zoom (needs `input_devices/pointing/android/enable_pan_and_scale_gestures`,
		# project.godot — off by default, so Android delivers raw multi-touch instead of this
		# without it). `factor` is already a relative scale — >1 spreading apart, <1 pinching in —
		# the same shape `_zoom_at` takes from the wheel.
		var magnify := event as InputEventMagnifyGesture
		_zoom_at(magnify.position, magnify.factor)
	elif event.is_pressed() and not event.is_echo():
		# The keyboard equivalents of the wheel. They zoom on the view's *middle* rather than the
		# cursor: there is no cursor to zoom toward on a touchscreen, and on a desktop the pointer
		# may be nowhere near the map when the key is pressed.
		var centre := size * 0.5
		if event.is_action(InputActions.MAP_ZOOM_IN):
			_zoom_at(centre, 1.1)
			accept_event()
		elif event.is_action(InputActions.MAP_ZOOM_OUT):
			_zoom_at(centre, 1.0 / 1.1)
			accept_event()


## Zoom toward a screen point so the world under the cursor stays put.
func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := _origin + screen_point / _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := _origin + screen_point / _zoom
	_origin += before - after
	_clamp_origin()
	# Zooming out is the one thing that can make the selected footprint too small to be worth
	# outlining, so it is where the ladder is re-checked.
	_drop_unselectable()
	_refresh()


func _clamp_origin() -> void:
	if _map == null or _zoom <= 0.0:
		return
	var world := Vector2(_map.width, _map.height) * _map.tile_size_px
	var visible_world := size / _zoom
	if visible_world.x >= world.x:
		_origin.x = (world.x - visible_world.x) * 0.5
	else:
		_origin.x = clampf(_origin.x, 0.0, world.x - visible_world.x)
	if visible_world.y >= world.y:
		_origin.y = (world.y - visible_world.y) * 0.5
	else:
		_origin.y = clampf(_origin.y, 0.0, world.y - visible_world.y)
