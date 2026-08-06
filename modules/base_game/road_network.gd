class_name RoadNetwork
extends RefCounted

## The roads laid on the map, and the autotiling that decides what each piece looks like.
##
## A road occupies **one subtile** — the square the 5x5 overlay draws, and the same unit a click
## selects — so a road is finer than anything else built on the map and joins to its four cardinal
## neighbours. Four neighbours means sixteen possible pieces, which is exactly what the atlas holds.
##
## **This owns the roads; it does not draw them.** It answers "what shape is the piece here?" with a
## texture, and [OverworldMapView] paints whatever it is handed at whatever subtile it is keyed by —
## the same division that keeps the view free of knowing what a farm is.

## Sixteen pieces in a 5x5 sheet, leaving nine cells unused. Sliced by
## [method OverworldMapView.slice_variants], so a piece's index is `row * 5 + column` in reading
## order.
const ATLAS := preload("res://core/assets/map/road_atlas.png")
const ATLAS_COLUMNS := 5
const ATLAS_ROWS := 5

## Which way a piece connects. One bit each, so a piece's shape is the sum of its neighbours and the
## whole autotiling is an array lookup rather than a pile of conditionals.
const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

## **Mask to atlas index**, read off the sheet — see `docs/ux_plan.md` for the labelled picture.
##
## The 3x3 block at the top-left is the classic minimal set: the four corners, the four T-junctions
## and the cross. The remaining seven are the extras — two straights, four dead-ends split out of the
## two capsules, and the lone stub with nothing attached, which lives on its own in the fourth row.
##
## Indexed *by mask*, so `MASK_TO_INDEX[mask]` is the piece. The table is written out rather than
## computed because there is no rule relating the two: it is the order the art happens to be drawn
## in, and a formula pretending otherwise would break the day the sheet is redrawn.
const MASK_TO_INDEX: PackedInt32Array = [
	15,  # 0    nothing attached — the isolated stub
	14,  # N    dead end
	3,   # E    dead end
	10,  # NE   corner
	9,   # S    dead end
	8,   # NS   straight
	0,   # SE   corner
	5,   # NES  T-junction
	4,   # W    dead end
	12,  # NW   corner
	13,  # EW   straight
	11,  # NEW  T-junction
	2,   # SW   corner
	7,   # NSW  T-junction
	1,   # ESW  T-junction
	6,   # NESW cross
]

## Where the roads live in game state. A flat list of coordinates rather than a dictionary keyed by
## [Vector2i] — **saves are JSON**, which has neither a vector nor a non-string key, so a dictionary
## would come back as something else than it went in.
const STATE_KEY := "roads"

## **How far each piece's edge is smeared outward before the sheet is cut up.**
##
## An atlas and mipmaps do not get on. [member AtlasTexture.filter_clip] keeps *sampling* inside a
## piece's region, but it cannot help with what is already in the reduced copies: a mip pixel on a
## cell boundary was averaged from both cells, so a piece's outermost row arrives carrying whatever
## its neighbour on the sheet happens to be — and on this sheet the neighbours include empty space.
## The result was a road whose every edge went slightly transparent, showing as grass-coloured seams
## between the pieces, at some zooms and not others because each mip level bleeds differently.
##
## Padding each cell with a copy of its own border gives the averaging something harmless to reach
## into. Eight is sized against the worst case actually drawn: a piece is a fifth of a cell, so at the
## smallest size it still draws art at ([constant OverworldMapView.MIN_TEXTURED_TILE_PX]) a
## sixty-four-unit piece is reduced to about six, and the mip kernel that far down is about ten units
## across. Eight covers all but the very deepest of that, and the rest never reaches the screen.
const PIECE_PADDING := 8

var _tiles: Dictionary = {}  ## Vector2i subtile -> true. A set; the value is never read.
## The sheet, cut up. **Static**: it is the same for every network in the process, and building it is
## a per-pixel pass that has no business running once per screen.
static var _pieces: Array[Texture2D] = []

## The same sixteen pieces with every pixel turned white, keeping only their alpha.
##
## **This is what makes a plan blue.** A ghost is drawn by modulating a piece, and modulating
## *multiplies* — laying blue over the road's ochre gives a muddy green, because multiplication can
## only ever darken. Against white it gives exactly the colour asked for, so the one recolouring the
## plan needs is done here, once, and the blue and the red stay where they belong: with the renderer,
## next to every other colour it draws.
##
## Static, and built the first time anything asks: it is a per-pixel pass over the sheet, which is
## cheap once and wasteful per screen — and the answer cannot differ between two of them.
static var _silhouettes: Array[Texture2D] = []


func _init() -> void:
	if _pieces.is_empty():
		_pieces = _sheet(false)


func pieces_sheet() -> Array[Texture2D]:
	return _pieces


## The white-on-alpha cut of the sheet — see [member _silhouettes].
static func silhouettes() -> Array[Texture2D]:
	if _silhouettes.is_empty():
		_silhouettes = _sheet(true)
	return _silhouettes


## Cut the atlas into its sixteen pieces, padded so that mipmaps cannot mix one into the next.
##
## [param blank] turns every pixel white, keeping its alpha — the silhouette cut a plan is drawn from.
##
## **The mipmaps are cleared first and rebuilt last**, and both matter. [method Image.set_pixel] writes
## to the full-size image and nothing else, so recolouring an image that already carries a mip chain
## leaves every reduced copy holding the original ochre — which is what made the first blue plan come
## out dark green, while every pixel this code had written was perfectly white and inspected as white.
## And the padding has to be in place before the chain is generated, or it protects nothing.
static func _sheet(blank: bool) -> Array[Texture2D]:
	var source := ATLAS.get_image()
	source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	source.clear_mipmaps()
	if blank:
		for y in source.get_height():
			for x in source.get_width():
				var alpha := source.get_pixel(x, y).a
				if alpha > 0.0:
					source.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var cell := source.get_width() / ATLAS_COLUMNS
	var padded := cell + PIECE_PADDING * 2
	var sheet := Image.create_empty(padded * ATLAS_COLUMNS, padded * ATLAS_ROWS, false,
		Image.FORMAT_RGBA8)
	for row in ATLAS_ROWS:
		for column in ATLAS_COLUMNS:
			var from := Vector2i(column * cell, row * cell)
			var to := Vector2i(column * padded + PIECE_PADDING, row * padded + PIECE_PADDING)
			sheet.blit_rect(source, Rect2i(from, Vector2i(cell, cell)), to)
			# The four sides, each a copy of the piece's own outermost row or column smeared outward.
			# Done with blits rather than a per-pixel walk: it is the same work either way, and one of
			# the two runs in C.
			for step in PIECE_PADDING:
				sheet.blit_rect(source, Rect2i(from, Vector2i(1, cell)),
					to + Vector2i(-step - 1, 0))
				sheet.blit_rect(source, Rect2i(from + Vector2i(cell - 1, 0), Vector2i(1, cell)),
					to + Vector2i(cell + step, 0))
				sheet.blit_rect(source, Rect2i(from, Vector2i(cell, 1)),
					to + Vector2i(0, -step - 1))
				sheet.blit_rect(source, Rect2i(from + Vector2i(0, cell - 1), Vector2i(cell, 1)),
					to + Vector2i(0, cell + step))
			# And the four corners, which no edge reaches — each is simply its corner pixel.
			for corner: Array in [[Vector2i(0, 0), Vector2i(-PIECE_PADDING, -PIECE_PADDING)],
					[Vector2i(cell - 1, 0), Vector2i(cell, -PIECE_PADDING)],
					[Vector2i(0, cell - 1), Vector2i(-PIECE_PADDING, cell)],
					[Vector2i(cell - 1, cell - 1), Vector2i(cell, cell)]]:
				sheet.fill_rect(
					Rect2i(to + (corner[1] as Vector2i),
						Vector2i(PIECE_PADDING, PIECE_PADDING)),
					source.get_pixel(from.x + (corner[0] as Vector2i).x,
						from.y + (corner[0] as Vector2i).y))
	sheet.generate_mipmaps()

	var texture := ImageTexture.create_from_image(sheet)
	var out: Array[Texture2D] = []
	for row in ATLAS_ROWS:
		for column in ATLAS_COLUMNS:
			var piece := AtlasTexture.new()
			piece.atlas = texture
			piece.region = Rect2(column * padded + PIECE_PADDING, row * padded + PIECE_PADDING,
				cell, cell)
			# Still worth setting even with the padding: this is what keeps the *base* level's
			# sampling inside the region, where the padding only protects the reduced ones.
			piece.filter_clip = true
			out.append(piece)
	return out


## The blank cut of a piece, for drawing it as a plan rather than as a road.
static func silhouette_for_mask(mask: int) -> Texture2D:
	return silhouettes()[MASK_TO_INDEX[mask]]


func has_road(subtile: Vector2i) -> bool:
	return _tiles.has(subtile)


func add(subtile: Vector2i) -> void:
	_tiles[subtile] = true


func remove(subtile: Vector2i) -> void:
	_tiles.erase(subtile)


func count() -> int:
	return _tiles.size()


func is_empty() -> bool:
	return _tiles.is_empty()


func clear() -> void:
	_tiles.clear()


## How a piece at [param subtile] connects, given the roads around it.
##
## [param also] lets a caller ask the question as though some further subtiles were roads too, which
## is what makes a plan's ghosts join up with the network they are about to become part of instead of
## each drawing as an isolated stub.
func mask_at(subtile: Vector2i, also: Dictionary = {}) -> int:
	var mask := 0
	if _linked(subtile + Vector2i(0, -1), also):
		mask |= NORTH
	if _linked(subtile + Vector2i(1, 0), also):
		mask |= EAST
	if _linked(subtile + Vector2i(0, 1), also):
		mask |= SOUTH
	if _linked(subtile + Vector2i(-1, 0), also):
		mask |= WEST
	return mask


func _linked(subtile: Vector2i, also: Dictionary) -> bool:
	return _tiles.has(subtile) or also.has(subtile)


func piece_for_mask(mask: int) -> Texture2D:
	return _pieces[MASK_TO_INDEX[mask]]


func pieces() -> Array[Texture2D]:
	return _pieces.duplicate()


## Every road as `{subtile -> Texture2D}`, which is what [OverworldMapView.set_roads] takes.
##
## Rebuilt whole rather than patched: adding one piece re-shapes its neighbours as well as itself,
## and at the scale a hand-drawn test network reaches, working out which four those are costs more
## than simply asking all of them again.
func textures() -> Dictionary:
	var out: Dictionary = {}
	for subtile: Vector2i in _tiles:
		out[subtile] = piece_for_mask(mask_at(subtile))
	return out


## The same, for a set of subtiles that are only *planned* — shaped as though they and the existing
## network were already one thing, so a ghost meeting a real road draws the junction it would become.
func plan_textures(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for subtile: Vector2i in plan:
		out[subtile] = piece_for_mask(mask_at(subtile, plan))
	return out


## Which map cells hold any road at all. The renderer wants this to clear scatter: a road running
## through a cell takes the tree standing in it, the same way ploughing does.
func cells(subtiles_per_tile: int) -> Dictionary:
	var out: Dictionary = {}
	for subtile: Vector2i in _tiles:
		out[Vector2i(subtile.x / subtiles_per_tile, subtile.y / subtiles_per_tile)] = true
	return out


## Roads as a flat `[x0, y0, x1, y1, …]` list for the save. Sorted, so a saved world that has not
## changed produces a byte-identical file rather than one that differs by dictionary order.
func to_state() -> Array:
	var keys: Array = _tiles.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var out: Array = []
	for subtile: Vector2i in keys:
		out.append(subtile.x)
		out.append(subtile.y)
	return out


## Read roads back. Tolerates a missing or malformed value by ending up empty — a save written before
## roads existed simply has no key, and that is not an error.
func from_state(data: Variant) -> void:
	_tiles.clear()
	if not (data is Array):
		return
	var flat := data as Array
	# A trailing odd value is a truncated pair and is dropped rather than read as a coordinate with a
	# zero for its partner, which would put a road on the top edge of the world.
	for i in range(0, flat.size() - 1, 2):
		_tiles[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
