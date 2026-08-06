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

## The pointer was dragged across a subtile while [method set_paint_mode] was on. Emitted once per
## subtile, including the ones a fast drag skipped over between two motion events, and including the
## one the press started on — so a single click paints exactly one.
signal subtile_painted(subtile: Vector2i)

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
## Things placed on the map by something that decided where they go, rather than hashed out of the
## seed — see [method set_standing]. Bucketed by the map row their anchor falls in, because the draw
## walks rows top to bottom anyway and that walk is what sorts them against the trees for free.
var _standing: Dictionary = {}      # int row -> Array of prepared items
## The cells those things occupy, so nothing scatters up through one. The same job
## [member _road_cells] does for roads.
var _standing_cells: Dictionary = {}
## How far past the visible window the standing pass reaches, derived from the widest and tallest
## thing actually in it. [constant SCATTER_OVERSCAN] is sized for a tree; a building three tiles tall
## rooted below the bottom edge still has a roof on screen, and a constant cannot know that.
var _standing_overscan := SCATTER_OVERSCAN
## How far through the cross-dissolve the standing things are: 0 the instant one becomes something
## else, 1 once it has settled. **One number for the whole map** rather than one per thing — what
## changes a crop or a building's state changes all of them at once, and a per-item clock would be
## bookkeeping in aid of a case that does not arise.
var _standing_fade := 1.0
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

## The roads, as `{Vector2i subtile -> Texture2D}` — the caller has already worked out which piece
## each one is, so this draws them and never learns how a road decides its own shape.
var _roads: Dictionary = {}
## The map cells any road runs through, derived once whenever the roads change. Read by
## [method _scatter_variants], which would otherwise ask twenty-five questions per cell per frame.
var _road_cells: Dictionary = {}
## A road being drawn but not yet built: the same `{subtile -> Texture2D}`, plus the subtiles within
## it that may not be built on. Drawn over everything, tinted, and owned entirely by the caller — the
## view has no idea what makes a plan valid.
var _road_plan: Dictionary = {}
var _road_plan_invalid: Dictionary = {}

## While painting, the left button draws on the map instead of moving it — so the map has to be moved
## some other way, which is what [constant EDGE_SCROLL_MARGIN] and the pan actions are for.
var _paint_mode := false
var _painting := false
## The last subtile the pointer was over during a paint drag. A drag reports motion in jumps of
## whatever the frame rate allows, so the subtiles *between* two reports have to be filled in.
var _paint_last := Vector2i(-1, -1)

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

## **How far in the player may go, measured against the finest art on the map.**
##
## The smallest thing built is one subtile, and it is painted at 128px
## ([constant Buildings.NOMINAL_PX]). A subtile is a fifth of a 128px tile, so the art is drawn 1:1
## when a tile is 640 units — a zoom of exactly 5. Past that a building is being upscaled and starts
## to go soft.
##
## Six rather than five, so there is a little room beyond 1:1 to lean in and look at something; 1.2x
## on a painted texture is comfortable, and the ceiling wants to be past the sweet spot rather than
## exactly on it. Raise this further only alongside art painted at more than 128px to the subtile.
const MAX_ZOOM := 6.0

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
## **How tall a scattered sprite is drawn, in subtiles** — the finest square the map addresses, and
## therefore the size of the smallest thing that can be built on it.
##
## Measured against the subtile rather than the tile because that is what a tree is actually judged
## beside. It was 0.62 of a *tile* while nothing else stood on the ground to compare it with — three
## subtiles tall, which turned out to be roughly three times the height of a cottage once there were
## cottages. A pine is taller than a house, not a landmark visible from the next valley.
##
## Half again the height of a one-subtile building is about right: unmistakably a tree, clearly not
## architecture, and it still overhangs its own square by enough for the second pass to be worth
## having.
const SCATTER_SUBTILE_HEIGHT := 1.5
const SCATTER_TILE_FRACTION := SCATTER_SUBTILE_HEIGHT / float(SUBGRID_DIVISIONS)
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

## The same question for the things that were *placed* rather than scattered — see
## [method set_standing]. It is the **ground's** threshold, not the scatter's, and that is deliberate
## for a reason that has nothing to do with legibility.
##
## This art overhangs the cell it belongs to: a field's edge is ragged and spills a few percent of a
## tile past its own square, which is what stops a row of them reading as tiles. Anything drawn into
## the cell rect instead — the ground pass, which clips — would cut that overhang off with a dead
## straight edge. Tying the two thresholds together means **there is no zoom at which the clipped
## version is on screen**: past this point the whole map is flat colour and the question of where a
## field's edge falls does not arise. Raise this above [constant MIN_TEXTURED_TILE_PX] and a band of
## zooms opens up in which every field is a hard-edged square.
const MIN_STANDING_TILE_PX := MIN_TEXTURED_TILE_PX

## **How long a standing thing takes to become the thing it has just been replaced by.**
##
## A crop advancing a stage or a house being finished is a change to the *world*, and the world does
## not cut. Swapped outright it reads as a glitch — the eye catches the substitution rather than the
## difference, which is the opposite of what a stage change is for: you want to see *what* changed,
## and a hard cut is exactly when you cannot.
##
## Long enough to register as a change rather than a flicker, short enough that a player pressing
## through the stages is never waiting for the map. It is a dissolve, not a growth animation — a crop
## really becoming the next crop wants art that grows, and this is the honest cheap version of it.
const STANDING_FADE_SECONDS := 0.35
## A desktop stage begins at roughly this many complete map tiles from top to bottom. Unlike the old
## fit-to-whole-map behavior, making the world larger no longer makes the starting view farther away.
##
## **What binds this is the smallest thing on the map being legible, not merely clickable.** It was
## eight rows while the smallest thing was a subtile of bare ground, and eight was reasoned from
## [constant MIN_SELECTABLE_PX]: on a windowed 1000x565 stage a subtile came out at about 13 units,
## clear of the line below which a target is not worth aiming at.
##
## That is no longer the binding case. A **house is one subtile**, and a house is a painting with a
## roof, windows and a doorstep on it — a thing you have to be able to *read*, not just hit. Ten units
## is enough to click and nowhere near enough to see, so the number the frame is now measured against
## is how big the smallest *building* is, and it is several times larger.
##
## Four rows puts a subtile at 40 units on a 1280x800 stage and 28 on the small windowed one, which
## are respectively a legible cottage and a recognisable one. It also still frames the settlement:
## four tiles down and about six across is the hamlet and the fields around it, which is what the game
## should open looking at.
##
## **This is the dial.** Everything else on the map is measured in tiles or subtiles and follows from
## it, so changing this one number rescales the opening view and nothing else.
const DEFAULT_VISIBLE_TILE_ROWS := 4.0
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

## How close to the edge of the view the pointer has to be, while painting, before the map starts
## moving under it — and how fast it then travels, in screen units a second. Both picked to be tuned
## rather than derived: the only test of an edge scroll is whether it feels like it is following you
## or running away, and neither number can be argued from anything.
const EDGE_SCROLL_MARGIN := 48.0
const EDGE_SCROLL_SPEED := 620.0

## A road being planned, before it is built. Blue for what will be laid, red for what may not be.
##
## **Translucent, but not by much.** The ground being committed to should stay readable underneath, so
## the first attempt washed both at around a third — and while red survives that over grass, blue does
## not: a light blue at 0.62 composites against green to a muted teal, which reads as a *colour of
## road* rather than as a mark meaning "not yet". Blue and green are close enough on the wheel that
## the ground has to be mostly covered before the hue is unambiguous. Red keeps the same weight only
## so the two behave alike.
const ROAD_PLAN_COLOR := Color(0.24, 0.55, 1.0, 0.85)
const ROAD_PLAN_INVALID_COLOR := Color(1.0, 0.22, 0.18, 0.85)

## What a road fades to once a subtile is too small to draw art in — the same fallback the ground
## makes at [constant MIN_TEXTURED_TILE_PX], for the same reason, averaged off the atlas at setup.
var _road_color := Color(0.72, 0.6, 0.24)

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
	# Godot turns per-frame processing on for any node whose script defines `_process`. This map is
	# redraw-driven and idle the rest of the time, so it starts off and is switched on only for the two
	# things that genuinely need frames — see [method _update_processing].
	_update_processing()
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


# --- roads -------------------------------------------------------------------------------------

## Lay the roads, as `{Vector2i subtile -> Texture2D}`. The caller has already decided which piece
## goes where; this only paints them and works out which cells they run through, for the scatter.
func set_roads(pieces: Dictionary) -> void:
	_roads = pieces.duplicate()
	_road_cells.clear()
	for subtile: Vector2i in _roads:
		_road_cells[Vector2i(subtile.x / SUBGRID_DIVISIONS, subtile.y / SUBGRID_DIVISIONS)] = true
	# Averaged from the art the caller is actually using, exactly as the biomes are, so crossing the
	# zoom threshold loses the road's shape without shifting its colour. Taken from any one piece:
	# they are all cut from one sheet and all the same material.
	for subtile: Vector2i in _roads:
		_road_color = _average_color(_roads[subtile] as Texture2D)
		break
	queue_redraw()


## Show a road that is being drawn but has not been built. [param invalid] is the subset that may not
## be built on, which draws in the refusal colour instead — the view is told which those are and
## never decides it.
func set_road_plan(pieces: Dictionary, invalid: Dictionary = {}) -> void:
	_road_plan = pieces.duplicate()
	_road_plan_invalid = invalid.duplicate()
	queue_redraw()


func clear_road_plan() -> void:
	set_road_plan({}, {})


func has_road_plan() -> bool:
	return not _road_plan.is_empty()


# --- painting ----------------------------------------------------------------------------------

## Turn the left button from a way of moving the map into a way of drawing on it.
##
## **The map still has to move while you draw**, so with this on the camera answers to the pan
## actions and to the pointer resting against the edge of the view instead ([method _process]).
func set_paint_mode(painting: bool) -> void:
	if _paint_mode == painting:
		return
	_paint_mode = painting
	_painting = false
	_paint_last = Vector2i(-1, -1)
	# A press that began as a drag must not go on panning once the mode changes underneath it.
	_dragging = false
	_update_processing()
	mouse_default_cursor_shape = Control.CURSOR_CROSS if painting else Control.CURSOR_ARROW


func is_paint_mode() -> bool:
	return _paint_mode


## Report every subtile between the last one and this, so a drag faster than the frame rate leaves a
## continuous road rather than a dotted line. A plain Bresenham walk on the subtile grid, which is
## also why a road drawn quickly across the screen comes out connected: the pieces it reports are
## always cardinal neighbours or a diagonal step, never a jump.
func _paint_to(subtile: Vector2i) -> void:
	if subtile == _paint_last:
		return
	if _paint_last == Vector2i(-1, -1):
		_paint_last = subtile
		if has_subtile(subtile):
			subtile_painted.emit(subtile)
		return
	var delta := subtile - _paint_last
	var steps := maxi(absi(delta.x), absi(delta.y))
	for step in range(1, steps + 1):
		var at := _paint_last + Vector2i(
			int(round(float(delta.x) * float(step) / float(steps))),
			int(round(float(delta.y) * float(step) / float(steps))))
		if has_subtile(at):
			subtile_painted.emit(at)
	_paint_last = subtile


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _standing_fade < 1.0:
		_standing_fade = minf(_standing_fade + delta / STANDING_FADE_SECONDS, 1.0)
		if is_equal_approx(_standing_fade, 1.0):
			_standing_fade = 1.0
			_update_processing()
		queue_redraw()
	if _paint_mode:
		_edge_scroll(delta)


## Edge scrolling, and only while painting. The pointer is busy drawing, so the map is moved by
## pushing it against the side of the view — the one gesture left that costs no button.
func _edge_scroll(delta: float) -> void:
	var pointer := get_local_mouse_position()
	var push := Vector2.ZERO
	if pointer.x < EDGE_SCROLL_MARGIN:
		push.x = -1.0
	elif pointer.x > size.x - EDGE_SCROLL_MARGIN:
		push.x = 1.0
	if pointer.y < EDGE_SCROLL_MARGIN:
		push.y = -1.0
	elif pointer.y > size.y - EDGE_SCROLL_MARGIN:
		push.y = 1.0
	push += _pan_from_keys()
	if push == Vector2.ZERO:
		return
	# In screen units per second, converted to world units, so the map travels at the same apparent
	# speed however far in or out the player is.
	_origin += push.normalized() * EDGE_SCROLL_SPEED * delta / _zoom
	_clamp_origin()
	# The pointer has not moved but the world under it has, so the piece being drawn follows the map.
	if _painting:
		_paint_to(subtile_at(pointer))
	_refresh()


func _pan_from_keys() -> Vector2:
	var push := Vector2.ZERO
	if Input.is_action_pressed(InputActions.MAP_PAN_LEFT):
		push.x -= 1.0
	if Input.is_action_pressed(InputActions.MAP_PAN_RIGHT):
		push.x += 1.0
	if Input.is_action_pressed(InputActions.MAP_PAN_UP):
		push.y -= 1.0
	if Input.is_action_pressed(InputActions.MAP_PAN_DOWN):
		push.y += 1.0
	return push


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

	# Roads go on the ground and under what stands on it, so they are drawn between the two — after
	# the fields, before the trees. Nothing is left standing on a road anyway
	# ([method _scatter_variants]), but a road passing beside a tree still wants the tree in front.
	_draw_roads(tile, textured)
	_draw_standing(tile)
	_draw_map_grids()
	# Last, and over the grids: the outline says what the player has picked, and a coordinate overlay
	# drawn on top of it would break the one continuous line that makes it read as an enclosure.
	_draw_selection(tile)
	# Over even that. A plan is the thing the player is doing right now; everything else on the map is
	# context for it, including a selection they made a moment ago.
	_draw_road_plan(tile, textured)

	for id in _markers:
		var cell := (_markers[id] as Dictionary)["cell"] as Vector2i
		draw_arc(_cell_centre_on_screen(cell), MARKER_RING_RADIUS, 0.0, TAU, 24,
			MARKER_RING_COLOR, MARKER_RING_WIDTH, true)


## Hand the view the things that stand on a biome's ground — trees today. Keyed the same way the
## terrain textures are, so a biome with none simply has no entry.
func set_scatter(scatter: Dictionary) -> void:
	_scatter = scatter
	queue_redraw()


## Replace the terrain texture tables after [method setup] — a crop advancing a stage today, a season
## turning later. Re-derives the averaged biome colours, which reads pixels back off the GPU and is
## therefore something to do when the world changes and never per frame.
func set_textures(textures: Dictionary) -> void:
	_textures = textures
	_derive_biome_colors()
	queue_redraw()


## **Hand the view the things something decided the position of** — a farm's crop today, a building
## when there is one. The counterpart to [method set_scatter]: a tree is a hash of the map seed and
## costs nothing to store, while these are placed, and the view is told rather than working them out.
##
## Each entry is `{texture, at, tile_width, anchor, cells}`:
##
## - `at` — where the thing sits, in **tiles** and fractional. The one point its art is pinned to, and
##   the key it sorts on.
## - `tile_width` — how many map tiles wide the *image* is. For art that overhangs its cell this is
##   more than the footprint: a field painted 320px into a 256px tile is 1.25. Height is never given;
##   it follows from the image's own aspect, so nothing here can squash a picture.
## - `anchor` — where in the image `at` falls, normalised. `(0.5, 0.5)` for something lying flat on a
##   cell, `(0.5, 1.0)` for something standing up from its front edge.
## - `cells` — an [Array] of [Vector2i] it occupies. Used **only** to keep the scatter from growing up
##   through it; the drawing pays no attention to it, because the art is free to overhang.
##
## Sorted against the trees by `at.y`, so near draws over far without anyone declaring a layer.
func set_standing(items: Array) -> void:
	# **What was standing where, before this call.** A thing is "the same thing" if it is at the same
	# place — so a field whose crop advanced has a predecessor to dissolve out of, while a field that
	# was not there a moment ago simply appears. Keyed on position because that is the only identity a
	# standing thing has here; the view is never told what anything *is*.
	var was: Dictionary = {}
	for row: int in _standing:
		for entry: Dictionary in (_standing[row] as Array):
			was[entry["at"]] = entry["texture"]

	_standing.clear()
	_standing_cells.clear()
	var overscan := SCATTER_OVERSCAN
	var replaced := false
	for item: Dictionary in items:
		var texture := item.get("texture") as Texture2D
		if texture == null:
			continue
		var at := item.get("at", Vector2.ZERO) as Vector2
		var tile_width := float(item.get("tile_width", 1.0))
		var anchor := item.get("anchor", Vector2(0.5, 0.5)) as Vector2
		var art := texture.get_size()
		var tile_height := tile_width * art.y / maxf(art.x, 1.0)
		var row := int(floor(at.y))
		if not _standing.has(row):
			_standing[row] = []
		# What this position held before, when that was something else. Interrupting a dissolve takes
		# the incoming picture as the new outgoing one — which snaps, but only ever by the part of a
		# fade already run, and only when someone is pressing through the stages faster than they play.
		var earlier := was.get(at) as Texture2D
		var previous: Texture2D = null
		if earlier != null and earlier != texture:
			previous = earlier
			replaced = true
		(_standing[row] as Array).append({
			"texture": texture, "at": at, "tile_width": tile_width, "anchor": anchor, "art": art,
			"previous": previous,
		})
		for cell: Vector2i in (item.get("cells", []) as Array):
			_standing_cells[cell] = true
		# How far this one reaches past the row it is bucketed in, in whichever direction its anchor
		# puts the art. Taken as the worst case over the whole set rather than per item: the pass has
		# one window, so one number decides it.
		overscan.x = maxi(overscan.x, int(ceil(tile_width * maxf(anchor.x, 1.0 - anchor.x))))
		overscan.y = maxi(overscan.y, int(ceil(tile_height * maxf(anchor.y, 1.0 - anchor.y))))
	_standing_overscan = overscan
	_standing_fade = 0.0 if replaced else 1.0
	_update_processing()
	queue_redraw()


## How far through the cross-dissolve the map is — 1 when nothing is changing. Public because it is
## the only observable part of the animation: a test can drive [method Node._process] by hand and
## assert the fade starts, runs and settles without rendering a frame or waiting a real second.
func standing_fade() -> float:
	return _standing_fade


## **Per-frame work is the exception here, not the rule.** This view redraws on demand
## ([method CanvasItem.queue_redraw]) and is idle the rest of the time, which is what lets a 500x500
## map cost nothing while nobody is touching it. Two things need frames — the edge scroll while
## painting, and a dissolve while one — so processing is switched on for exactly as long as one of
## them is running and off again after.
func _update_processing() -> void:
	set_process(_paint_mode or _standing_fade < 1.0)


## Where a standing thing's art lands on screen. **Pure, static and public** because it is the whole
## of the anchoring contract and the one part of it that can be got subtly wrong: an anchor half a
## percent out reads as the art bobbing against the ground as the map pans, which is invisible in a
## screenshot and obvious in motion. Being a function of its arguments alone, it can be asserted
## against directly rather than by drawing the map and reading pixels back.
static func standing_rect(at: Vector2, tile_width: float, anchor: Vector2, art: Vector2, tile: float,
		origin: Vector2, zoom: float) -> Rect2:
	var wide := tile_width * tile * zoom
	var high := wide * art.y / maxf(art.x, 1.0)
	var point := (at * tile - origin) * zoom
	return Rect2(point - Vector2(wide * anchor.x, high * anchor.y), Vector2(wide, high))


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


## What stands on one cell's ground — see the note in [method _draw_standing] for why this is asked of
## the ground rather than of the biome under it. Its own method so the rule is checkable without
## driving a redraw and reading pixels back.
##
## **A road through a cell clears it too**, by the same reasoning as the ploughed field: laying a road
## is working the ground, and a pine standing in the middle of one is the same mistake. This one
## cannot come from the ground key, because a road is finer than a cell — it takes a fifth of one —
## so the cell keeps whatever ground it had and is asked about its roads separately.
##
## **And so does anything placed on it** ([method set_standing]), for the third time by the same
## reasoning. A placed thing cannot come from the ground key either, but for the opposite reason to a
## road: its art overhangs the cell, so it is not the ground and never appears in that table.
func _scatter_variants(x: int, y: int) -> Array:
	var cell := Vector2i(x, y)
	if _road_cells.has(cell) or _standing_cells.has(cell):
		return []
	return _scatter.get(_ground_key(x, y), [])


## The roads. They belong to the same layer as everything else built on the ground, so the Terrain
## plate takes them away with the fields.
##
## Iterated over the network rather than over the visible subtile window: a road is a fifth of a cell,
## so the window is twenty-five times the cells on screen, and a hand-drawn test network is far
## smaller than that. If roads ever cover the map this wants inverting.
func _draw_roads(tile: float, textured: bool) -> void:
	if _roads.is_empty() or not _construction_layer_visible:
		return
	_draw_road_pieces(_roads, tile, textured, Color.WHITE, _road_color, {})


## The plan's pieces arrive as blank silhouettes, which is what lets a tint *be* the colour asked for
## rather than that colour multiplied into the road's own ochre — see [RoadNetwork.silhouettes].
func _draw_road_plan(tile: float, textured: bool) -> void:
	if _road_plan.is_empty():
		return
	_draw_road_pieces(_road_plan, tile, textured, ROAD_PLAN_COLOR, ROAD_PLAN_COLOR,
		_road_plan_invalid)


## One pass over a set of `{subtile -> Texture2D}`, culled to the view. [param invalid] recolours the
## subtiles inside it — which is only ever a plan, and only ever the caller's judgement.
## [param flat] is what a piece becomes once it is too small to draw art in.
func _draw_road_pieces(pieces: Dictionary, tile: float, textured: bool, tint: Color, flat: Color,
		invalid: Dictionary) -> void:
	var step := tile / float(SUBGRID_DIVISIONS)
	var view := Rect2(Vector2.ZERO, size)
	for subtile: Vector2i in pieces:
		# Snapped to whole pixels like the ground is, so two pieces meeting along an edge never leave
		# a hairline of grass showing between them.
		var left := roundf((float(subtile.x) * step - _origin.x) * _zoom)
		var top := roundf((float(subtile.y) * step - _origin.y) * _zoom)
		var right := roundf((float(subtile.x + 1) * step - _origin.x) * _zoom)
		var bottom := roundf((float(subtile.y + 1) * step - _origin.y) * _zoom)
		var rect := Rect2(left, top, right - left, bottom - top)
		if not view.intersects(rect):
			continue
		var refused := invalid.has(subtile)
		if textured:
			draw_texture_rect(pieces[subtile] as Texture2D, rect, false,
				ROAD_PLAN_INVALID_COLOR if refused else tint)
		else:
			# Too small for art. The same answer the ground gives at this distance: the shape is gone,
			# the colour is not, so a road network still reads as a network from far away.
			draw_rect(rect, ROAD_PLAN_INVALID_COLOR if refused else flat)


## Whether the things something *placed* are being drawn — see [method set_standing] and
## [constant MIN_STANDING_TILE_PX].
func is_standing_visible() -> bool:
	if _map == null or _standing.is_empty() or not _construction_layer_visible:
		return false
	return float(_map.tile_size_px) * _zoom >= MIN_STANDING_TILE_PX


## **The second pass — everything that stands on the ground rather than being part of it.** See
## [constant SCATTER_CHANNEL] for why it is a pass of its own; the short of it is that a thing with a
## silhouette overhangs its cell, so the next cell's ground would paint over it, and two that overlap
## have to be ordered near in front of far.
##
## The scattered trees and the placed things ([method set_standing]) are drawn **together**, in one
## pass over one window, because they are the same kind of object as far as sorting goes: a tree
## standing beside a field has to fall in front of it or behind it, and two passes could only ever put
## every tree in front of every field. Rows run top to bottom so between rows the ordering is free;
## within a row the items are collected and sorted, which is a handful of entries.
func _draw_standing(tile: float) -> void:
	var scattered := is_scatter_visible()
	var placed := is_standing_visible()
	if not scattered and not placed:
		return
	var overscan := _standing_overscan
	var first_x := maxi(0, int(floor(_origin.x / tile)) - overscan.x)
	var first_y := maxi(0, int(floor(_origin.y / tile)) - overscan.y)
	var last_x := mini(_map.width - 1,
		int(floor((_origin.x + size.x / _zoom) / tile)) + overscan.x)
	var last_y := mini(_map.height - 1,
		int(floor((_origin.y + size.y / _zoom) / tile)) + overscan.y)
	var height := tile * _zoom * SCATTER_TILE_FRACTION
	var view := Rect2(Vector2.ZERO, size)
	for y in range(first_y, last_y + 1):
		# `[sort key, texture, rect]`, built before anything is drawn so the row can be ordered.
		var row: Array = []
		if scattered:
			for x in range(first_x, last_x + 1):
				# **Keyed on what the ground *is*, not on what the biome says it was.** Nobody leaves a
				# pine standing in the middle of a ploughed field: working the ground clears what stood
				# on it. Because the lookup goes through [method _ground_key], that falls out of the
				# farm simply having no scatter of its own rather than from a rule about farms — and a
				# worked ground that *should* carry something (an orchard's trees, a quarry's rubble)
				# gets it by being given one.
				#
				# Only the cell a thing is **footed** in is tested. A tree rooted on the grass beside a
				# field still leans its canopy over the furrows, which is what a hedgerow looks like.
				var variants := _scatter_variants(x, y)
				if variants.is_empty():
					continue
				for slot in SCATTER_SLOTS_PER_CELL:
					var hash := MapVariation.hash32(_map.seed, x, y, SCATTER_CHANNEL + slot)
					if (hash & 0xFF) >= SCATTER_CHANCE:
						continue
					var texture := variants[int((hash >> 24) % variants.size())] as Texture2D
					if texture == null:
						continue
					var art := texture.get_size()
					var wide := height * art.x / maxf(art.y, 1.0)
					# Where in the cell this one is footed: across, and down — which is also its key.
					var across := float((hash >> 8) & 0xFF) / 255.0
					var down := float((hash >> 16) & 0xFF) / 255.0
					var foot := Vector2((float(x) + across) * tile - _origin.x,
						(float(y) + down) * tile - _origin.y) * _zoom
					row.append([float(y) + down, texture,
						Rect2(foot - Vector2(wide, height) * SCATTER_ANCHOR, Vector2(wide, height)),
						null])
		if placed:
			for item: Dictionary in (_standing.get(y, []) as Array):
				var at := item["at"] as Vector2
				row.append([at.y, item["texture"],
					standing_rect(at, float(item["tile_width"]), item["anchor"] as Vector2,
						item["art"] as Vector2, tile, _origin, _zoom),
					item["previous"]])
		if row.is_empty():
			continue
		row.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for entry: Array in row:
			var rect := entry[2] as Rect2
			# The window is grown by the overscan so nothing pops in at the edge, which means most of
			# what it now reaches is genuinely off screen. Cheaper to reject here than to draw it.
			if not view.intersects(rect):
				continue
			# **The outgoing picture at full opacity, the incoming one fading in over it.** Not two
			# translucent copies: at half and half the ground would show through both, and a field
			# mid-change would go briefly transparent — which reads as a rendering fault rather than as
			# a crop growing. The pair occupies the same rectangle, so the one underneath is covered
			# before it is uncovered, and the dissolve never lets daylight through.
			#
			# Kept as one entry rather than two so they cannot be separated by the sort: equal keys have
			# no defined order, and an outgoing frame drawn *over* its successor runs the fade backwards.
			var previous := entry[3] as Texture2D
			if previous != null and _standing_fade < 1.0:
				draw_texture_rect(previous, rect, false)
				draw_texture_rect(entry[1] as Texture2D, rect, false,
					Color(1.0, 1.0, 1.0, _standing_fade))
			else:
				draw_texture_rect(entry[1] as Texture2D, rect, false)


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
	# **Weighted by alpha, or a sprite averages toward whatever its background happens to be.** A
	# resize treats a transparent texel's colour as real, and the colour sitting in the transparent
	# part of a PNG is whatever the painting program left there — white, for anything exported out of
	# Photoshop. A field is a quarter transparent by the time its overhang is inside its atlas cell
	# ([method slice_grid]), so the ochre came out a washed pink and the flat-colour map read as if
	# somebody had turned the saturation down.
	#
	# Premultiplying first makes the resize compute `sum(rgb * a) / n` and `sum(a) / n`; dividing one
	# by the other is exactly the alpha-weighted mean, without walking a hundred thousand pixels in
	# GDScript to get it. Fully opaque art divides by one and is unaffected.
	image.premultiply_alpha()
	# Lanczos, not bilinear: a bilinear downscale straight to 1x1 samples four texels and calls that
	# the average, which for grass is whichever four blades it happened to land on.
	image.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	var mean := image.get_pixel(0, 0)
	if mean.a <= 0.0:
		return unreadable  # nothing opaque in it at all — no answer, rather than black
	return Color(mean.r / mean.a, mean.g / mean.a, mean.b / mean.a, 1.0)


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


## Cut a sheet whose cells are **larger than the thing in them**, laid out on a regular pitch from a
## given origin. [method slice_variants] divides a sheet up exactly and is right for ground tiles,
## which meet edge to edge and have nothing to spare; this is for art that overhangs its own square
## and therefore needs the sheet to leave it room.
##
## The cell is the **whole** square including that room, so the art is centred in it and every slice
## comes out the same size whatever its own silhouette does. That is what lets one `tile_width` cover
## a whole sheet ([method set_standing]) instead of a measured number per frame — and it is why the
## overhang has to be inside the cell rather than in a gutter between cells, which a slice would cut
## off and a mip level would then average a neighbour into.
static func slice_grid(atlas: Texture2D, origin: Vector2i, cell: int, columns: int,
		rows: int) -> Array[Texture2D]:
	var slices: Array[Texture2D] = []
	if atlas == null or cell <= 0 or columns <= 0 or rows <= 0:
		return slices
	for row in rows:
		for column in columns:
			var slice := AtlasTexture.new()
			slice.atlas = atlas
			slice.region = Rect2(Vector2(origin + Vector2i(column, row) * cell),
				Vector2(cell, cell))
			slice.filter_clip = true
			slices.append(slice)
	return slices


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
				if _paint_mode:
					# Drawing, not moving. The press itself paints, so a single click lays one piece.
					_painting = mb.pressed
					if mb.pressed:
						_paint_last = Vector2i(-1, -1)
						_paint_to(subtile_at(mb.position))
				else:
					# **The same button pans the map and picks things off it**, so which one this is
					# cannot be known until the button comes back up — see [constant CLICK_SLOP].
					_dragging = mb.pressed
					if mb.pressed:
						_press_position = mb.position
						_drag_distance = 0.0
					elif _drag_distance <= CLICK_SLOP:
						subtile_clicked.emit(subtile_at(_press_position))
	elif event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).relative
		if _painting:
			_paint_to(subtile_at((event as InputEventMouseMotion).position))
		elif _dragging:
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
