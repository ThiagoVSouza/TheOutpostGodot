class_name BaseGameMap
extends RefCounted

## The base game's deliberately simple construction map.
##
## Two systems need the same geometry: the game screen renders it, and new-game seeding chooses the
## outpost's permanent cell. Keeping the procedural definition here gives both one source of truth.

## Large enough that the close default camera can pan for hundreds of tiles in every direction,
## while procedural storage keeps it cheaper than the old 40x28 JSON demo.
const MAP_WIDTH := 500
const MAP_HEIGHT := 500
const TILE_SIZE_PX := 128
const MAP_SEED := 1311768467

## Stable node names shared by the module's Map Layers panel and its game screen wiring.
const TILE_GRID_TOGGLE_NAME := "TileGridToggle"
const SUBGRID_TOGGLE_NAME := "SubgridToggle"
const TERRAIN_ONLY_TOGGLE_NAME := "TerrainOnlyToggle"

## The map's finest addressable square, and the unit a click resolves to. Taken from the renderer's
## own subdivision rather than restated, so the squares the 5x5 overlay draws are exactly the ones a
## player can select.
const SUBTILES_PER_TILE := OverworldMapView.SUBGRID_DIVISIONS

## The construction map currently has one biome and therefore one habitable terrain.
const HABITABLE_BIOMES: PackedStringArray = ["grass"]


## A uniform grass world: one biome, drawn from four interchangeable variants of the same ground.
static func load_map() -> TerrainMap:
	return TerrainMap.create_flat("construction-overworld", MAP_WIDTH, MAP_HEIGHT, TILE_SIZE_PX,
		"grass", MAP_SEED)


## The one biome's ground, as four variants in a single 512x512 atlas.
##
## **One atlas rather than four files** so every cell on screen draws from the same texture and the
## canvas can batch them — with four separate textures picked pseudo-randomly per cell, the texture
## changes every few tiles and the batches break up constantly. Imported VRAM-compressed with
## mipmaps: the compression is 8:1 on a texture whose alpha channel was fully opaque anyway, and the
## mipmaps are what stop the ground shimmering as the map zooms.
##
## Variants are picked per cell by [method MapVariation.pick_variant], deterministically from
## [constant MAP_SEED], so a cell keeps its ground across a save and reload. Below
## [constant OverworldMapView.MIN_TEXTURED_TILE_PX] the renderer stops drawing them entirely and
## falls back to the average of these four — see that constant for why.
const GRASS_ATLAS := preload("res://core/assets/map/atlas_grass.png")
const GRASS_ATLAS_COLUMNS := 2
const GRASS_ATLAS_ROWS := 2


## **A field, at the four points of its crop cycle.** One whole map cell of it, self-contained: a
## field is a field, not a tile of some larger field, so two of them side by side are two farms whose
## ragged edges overlap rather than one region that has been cut into squares.
##
## The sheet is four 320px cells on a 320px pitch from (32, 32), each holding a 256px field with its
## overhang around it — see [method OverworldMapView.slice_grid] for why the overhang lives *inside*
## the cell rather than in a gutter between cells.
const FARM_ATLAS := preload("res://core/assets/map/farm_atlas.png")
const FARM_ATLAS_ORIGIN := Vector2i(32, 32)
const FARM_ATLAS_CELL := 320
const FARM_ATLAS_COLUMNS := 4
## **How much painted art there is to a map tile — the one scale every sheet is drawn at.**
##
## The ground atlas has always been this: 512px holding a 2x2 of variants is 256px to the tile. Naming
## it makes it a *convention* rather than a coincidence, and it is what lets a sheet be measured
## instead of negotiated — a field painted 256px across is one tile, a house painted 128px across is
## half of one, and neither needs a scale factor written down beside it.
##
## The map draws a tile at 128 world px and zooms to 4x, so this is a 2x upscale at the very closest
## zoom and a downscale everywhere else. That is the right way round: sharp when you are looking at
## something, and the mipmaps carry the rest.
const ART_PX_PER_TILE := 256

## The square a field's art nominally fills inside its cell — one map tile's worth. Everything between
## this and [constant FARM_ATLAS_CELL] is the ragged edge spilling past the cell it belongs to, which
## is what stops a group of fields reading as a grid.
const FARM_TILE_PX := ART_PX_PER_TILE
## And therefore how many map tiles wide the image is, which is what [method OverworldMapView.set_standing]
## asks for. Derived rather than written down: the cell is measurable off the sheet and the scale is a
## project convention, so this cannot be wrong on its own.
const FARM_TILE_WIDTH := float(FARM_ATLAS_CELL) / float(ART_PX_PER_TILE)
const FARM_GROUND := "farm"

## **A field's crop, from bare earth to standing grain.** The four frames the sheet holds, in order.
enum CropStage { PLOUGHED, SPROUTING, GROWING, RIPE }

## What each reads as to a player. The band shows this, so a field names its own state rather than
## being "Ploughed field" all year.
const CROP_STAGE_TITLES := ["Ploughed field", "Sown field", "Growing crop", "Ripe crop"]

## **The stage every field is currently at — one global, and deliberately.** Nothing decides a crop
## stage yet: there is no farming system, no growing season and no per-field planting date, so a
## per-field stage would be four hundred copies of a number nothing writes to. A dev key sets this and
## every field answers to it, which is exactly enough to judge the art and the transitions.
##
## When a farming system exists it moves onto the field itself — [method constructions] already
## returns a dictionary per field, so it becomes an entry in that and this constant goes.
static var crop_stage: CropStage = CropStage.GROWING

## Cut once and kept: the slicing is cheap but it is per-frame territory otherwise, and every field on
## the map wants the same four textures.
static var _farm_frames: Array[Texture2D] = []


## The sheet, cut into its four stages.
static func farm_frames() -> Array[Texture2D]:
	if _farm_frames.is_empty():
		_farm_frames = OverworldMapView.slice_grid(FARM_ATLAS, FARM_ATLAS_ORIGIN, FARM_ATLAS_CELL,
			FARM_ATLAS_COLUMNS, 1)
	return _farm_frames


## The art for the stage every field is currently at.
static func farm_texture() -> Texture2D:
	var frames := farm_frames()
	return frames[clampi(int(crop_stage), 0, frames.size() - 1)] if not frames.is_empty() else null


## **A field is drawn twice, and the ground copy is the one that survives distance.** The sprite in
## the standing pass is the field you see; this entry is what the *ground* under it is, and it exists
## for the zoom at which the map gives up on art entirely and falls back to flat colour
## ([constant OverworldMapView.MIN_TEXTURED_TILE_PX]). Without it a field would simply vanish into
## grass when zoomed out, instead of staying a brown or gold patch the way a road stays an ochre line.
##
## The two never disagree, because the ground entry is the same texture the sprite uses — so the
## averaged colour the map falls back to is the average of the crop actually standing there.
static func load_textures(_map: TerrainMap) -> Dictionary:
	return {
		"grass": OverworldMapView.slice_variants(GRASS_ATLAS, GRASS_ATLAS_COLUMNS,
			GRASS_ATLAS_ROWS),
		FARM_GROUND: [farm_texture()] as Array[Texture2D],
	}


## **How many field sprites go across one cell.** A farm is still a whole cell — five subtiles a side,
## one thing to select, one patch of worked ground — but it is *drawn* as a grid of smaller plots
## rather than as one picture stretched over the lot.
##
## One picture over the whole cell made a field five times the width of a cottage and twenty-five
## times its area, which is roughly true of a real field and quite wrong on a map where the two have
## to be looked at together. Two plots a side puts a plot at two and a half subtiles: still clearly a
## field, and now in a ratio to a house that the eye can hold.
##
## **The grid exactly covers the cell**, so nothing has to change about the farm being a cell: the
## ground override underneath it is never exposed, and the far-zoom colour fallback keeps working.
## Their ragged edges overlap where they meet, which is what reads as a boundary between plots rather
## than as a seam in one picture.
##
## Three a side is the other value worth trying — a plot of one and two thirds subtiles, nearer to the
## house still. It is one number.
const FARM_SPRITES_PER_CELL := 2


## The fields as things the map draws over their own cells rather than into them. See
## [method OverworldMapView.set_standing].
##
## Anchored at the **centre** of each plot, not at a front edge: a field lies flat on the ground it is
## made of, so it has no front. That is the one way it differs from a building, and it is a single
## number here rather than a second code path there.
static func farm_standing(map: TerrainMap) -> Array:
	var items: Array = []
	var texture := farm_texture()
	if texture == null:
		return items
	var per_cell := maxi(FARM_SPRITES_PER_CELL, 1)
	var step := 1.0 / float(per_cell)
	for built: Dictionary in constructions(map):
		var cells := built["cells"] as Rect2i
		for cell_y in range(cells.position.y, cells.end.y):
			for cell_x in range(cells.position.x, cells.end.x):
				for plot_y in per_cell:
					for plot_x in per_cell:
						items.append({
							"texture": texture,
							"at": Vector2(cell_x, cell_y) + Vector2(
								(float(plot_x) + 0.5) * step, (float(plot_y) + 0.5) * step),
							"tile_width": FARM_TILE_WIDTH * step,
							"anchor": Vector2(0.5, 0.5),
							"cells": [Vector2i(cell_x, cell_y)],
						})
	return items


# --- houses ---------------------------------------------------------------------------------------

## **A house is one subtile — both the ground it occupies and the building you see.**
##
## The subtile is the finest square the map addresses: the unit a road takes and a click resolves to.
## A house standing on one is therefore the smallest thing that can be built, and a field at a whole
## cell is five of them across and twenty-five in area — which is about the ratio a cottage and a
## field really stand in.
##
## **The art is drawn wider than that, and only by its overhang.** The sheet's cell is
## [constant Buildings.ATLAS_CELL] holding a [constant Buildings.NOMINAL_PX] building, so a sixth of
## what is drawn is the room around it — eaves, rubble, and one day a cast shadow — spilling past the
## square the house is founded on. The building itself lands on exactly one subtile.
##
## Note this sheet is therefore **not** at [constant ART_PX_PER_TILE]: 128px across a fifth of a tile
## is five times the ground's density. That is not an inconsistency to fix — a building is the thing
## a player looks closely at, and it is cheap to paint it at the resolution that survives being looked
## at. The scale constant is for art that tiles; this is art that is placed.
const HOUSE_SUBTILES_WIDE := 1.0
const HOUSE_TILE_WIDTH := (float(Buildings.ATLAS_CELL) / float(Buildings.NOMINAL_PX)
	* HOUSE_SUBTILES_WIDE / float(SUBTILES_PER_TILE))

## **A hamlet by the settlement, for looking at.** Subtile offsets from the outpost's own subtile, so
## they travel with it exactly as the fields do.
##
## Three in a row two subtiles apart — one subtile of gap between neighbours, which is as close as
## houses come without their overhangs touching, and what wants judging is whether that reads as a
## street. Three more standing alone, because a single house against open ground is the other thing
## worth seeing and a row cannot show it.
##
## Placed clear of the fields and of the demonstration road figure; the tests check both.
const HOUSE_SUBTILES: Array[Vector2i] = [
	Vector2i(-4, -3), Vector2i(-2, -3), Vector2i(0, -3),   # a row, a subtile apart
	Vector2i(4, -3), Vector2i(-8, -8), Vector2i(4, -8),    # and three on their own
]


## The houses, as identified things — the same shape [method constructions] returns for a field, with
## `subtile` where a field has `cells`, because a house is founded on one subtile and a field on one
## whole cell.
static func houses(map: TerrainMap) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	if map == null:
		return built
	var site := outpost_site(map)
	if site.x < 0:
		return built
	var origin := site * SUBTILES_PER_TILE
	for index in HOUSE_SUBTILES.size():
		var subtile := origin + HOUSE_SUBTILES[index]
		if not Rect2i(0, 0, map.width * SUBTILES_PER_TILE,
				map.height * SUBTILES_PER_TILE).has_point(subtile):
			continue
		built.append({
			"id": "house_%d" % index,
			"kind": KIND_CONSTRUCTION,
			"title": Buildings.title(),
			"subtile": subtile,
		})
	return built


## The house founded on [param subtile], or an empty dictionary. The counterpart to
## [method construction_at], one grid finer.
static func house_at(map: TerrainMap, subtile: Vector2i) -> Dictionary:
	for built: Dictionary in houses(map):
		if (built["subtile"] as Vector2i) == subtile:
			return built
	return {}


## The houses as things the map draws over the subtile they stand on. See
## [method OverworldMapView.set_standing].
##
## Anchored at the **centre**, like a field and unlike the front-edge anchor a side-on building would
## want: this art is painted looking down on the roof, and it sits centred in its own cell — measured
## off the sheet, where every frame's content is within a few pixels of the cell's middle on both
## axes. What the anchor has to match is how the art was painted, not how a building stands.
static func house_standing(map: TerrainMap) -> Array:
	var items: Array = []
	var texture := Buildings.texture()
	if texture == null:
		return items
	for built: Dictionary in houses(map):
		var subtile := built["subtile"] as Vector2i
		items.append({
			"texture": texture,
			"at": (Vector2(subtile) + Vector2(0.5, 0.5)) / float(SUBTILES_PER_TILE),
			"tile_width": HOUSE_TILE_WIDTH,
			"anchor": Vector2(0.5, 0.5),
			# Whole cells, because this only keeps trees from growing through it and a cell is the
			# grid the scatter is hashed on. A house shades its whole yard.
			"cells": [subtile / SUBTILES_PER_TILE],
		})
	return items


## Everything the map draws over the ground rather than into it, in one list — which is what the view
## takes, because fields and houses have to sort against each other and against the trees.
static func standing(map: TerrainMap) -> Array:
	var items := farm_standing(map)
	items.append_array(house_standing(map))
	return items


## **A few fields by the settlement, for looking at.** Offsets from the cell the outpost is founded
## on rather than absolute positions, so they stay with the settlement if the siting rule changes.
##
## **One cell each.** They were rectangles of three and six cells until the painted art arrived, and
## that art settled the question: a field is drawn with a ragged edge that spills a little past its
## own square, which is what stops a group of them reading as a grid. Tile six copies of it edge to
## edge and you get six ragged edges criss-crossing the *middle* of what is supposed to be one field —
## far more visible than the outer edge the raggedness was for. So a field is one cell and complete in
## itself, and a bigger farm is several of them standing together with their edges overlapping.
##
## Some are placed in touching clusters and some alone, because the thing worth judging is exactly
## that: whether neighbours overlap into something that reads as a larger holding, or as a pile of
## squares. They keep clear of the demonstration road figure, which the tests check.
##
## Nothing decides these yet — there is no farming system to ask. When there is, it replaces this
## constant and neither the renderer nor the selection ladder changes.
const FARM_CELLS: Array[Vector2i] = [
	Vector2i(-4, -2), Vector2i(-3, -2), Vector2i(-4, -1),  # a cluster of three
	Vector2i(1, -3), Vector2i(2, -2),                      # a loose pair
	Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(1, 2),      # a row with a gap in it
	Vector2i(3, 1), Vector2i(4, 1),                        # a pair off to the east
]


## **The plots as things rather than as coloured cells.** The renderer only ever needed to know which
## ground was ploughed, so the farms were a flat cell-to-name dictionary and there was no such object
## as *a* farm — which is precisely what a player clicking one is asking for. Each plot is now
## identified, and [method load_ground_overrides] is derived from this list so the thing the player
## selects and the thing the map draws cannot describe different cells.
##
## `cells` is absolute, resolved against the outpost's site. Empty when the map has no habitable cell
## to found on, which is also when there is nothing to draw.
static func constructions(map: TerrainMap) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	var site := map.find_cell_nearest_centre(HABITABLE_BIOMES)
	if site.x < 0:
		return built
	for index in FARM_CELLS.size():
		var cells := Rect2i(site + FARM_CELLS[index], Vector2i.ONE)
		# A field placed off the edge of the world is dropped whole rather than clipped: half a farm is
		# a thing nothing built, and the outpost is at the map's middle so this cannot happen today.
		if not Rect2i(0, 0, map.width, map.height).encloses(cells):
			continue
		built.append({
			"id": "farm_%d" % index,
			"kind": KIND_CONSTRUCTION,
			# The crop is what the field currently *is*, so it is what the band should call it.
			"title": CROP_STAGE_TITLES[int(crop_stage)],
			"ground": FARM_GROUND,
			"cells": cells,
		})
	return built


## The construction covering [param cell], or an empty dictionary. Point 4 of the selection brief —
## "click any part of it, get the whole of it" — is this method: the caller never sees the cell it
## asked about, only the thing that occupies it.
static func construction_at(map: TerrainMap, cell: Vector2i) -> Dictionary:
	for built: Dictionary in constructions(map):
		if (built["cells"] as Rect2i).has_point(cell):
			return built
	return {}


static func load_ground_overrides(map: TerrainMap) -> Dictionary:
	var overrides: Dictionary = {}
	for built: Dictionary in constructions(map):
		var cells := built["cells"] as Rect2i
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				overrides[Vector2i(x, y)] = String(built["ground"])
	return overrides


## **One tree, on purpose.** It is here to prove the parts that are easy to get wrong and impossible
## to see in a test — the ground anchor, the near-in-front-of-far sorting, and the second pass that
## stops the next cell's ground painting over a canopy. Density and variety are dials to turn once
## there is a set of trees and a reason for a particular cell to be wooded; today every grass cell is
## a candidate and [constant OverworldMapView.SCATTER_CHANCE] keeps it sparse.
const TEST_TREE := preload("res://core/assets/map/test_tree.png")


static func load_scatter(_map: TerrainMap) -> Dictionary:
	return {"grass": [TEST_TREE] as Array[Texture2D]}


# --- selection ----------------------------------------------------------------------------------

## What kind of thing a selection is. The band shows a construction and bare ground differently, and
## the Terrain plate hides one of them and not the other.
const KIND_CONSTRUCTION := "construction"
const KIND_TERRAIN := "terrain"
const KIND_ROAD := "road"

## How a biome reads to a player. The renderer's key is a texture name; this is the word for it.
const BIOME_TITLES := {
	"grass": "Grassland",
}

## **The rungs above a construction are not built yet.** The selection ladder walks from the smallest
## occupant of a clicked subtile up through its containers until one is big enough on screen to be
## worth aiming at ([constant OverworldMapView.MIN_SELECTABLE_PX]); today that walk has two rungs,
## bare ground and a construction, and stops.
##
## The two rungs above it — **settlement** and **region** — have no data behind them. The outpost is a
## single cell in state (`GameSession.OUTPOST_SITE_STATE_KEY`) with no footprint, and there is no
## notion of a region anywhere in the project. Inventing either here would mean a shape a real
## settlement system throws away.
##
## When they exist, they slot in at [method selection_at]: give a construction a `settlement` id,
## return the settlement's own footprint as the next candidate when the construction fails the
## threshold, and the far-zoom behaviour — click anywhere in a town and get the town — follows without
## touching the renderer. See `docs/ux_plan.md`, "the selection ladder".
##
## Note also that at that point [method OverworldMapView._draw_selection] wants the footprint's bounds
## rather than a traced perimeter: it is four neighbour lookups per subtile, which is right for a
## building and wrong for a province.

## What a click on [param subtile] has picked, or an empty dictionary for nothing selectable there.
##
## [param view] is asked whether each candidate is large enough on screen, so the answer changes with
## the zoom without this method knowing anything about zoom. [param constructions_visible] is the
## Terrain plate: with the works hidden, a click lands on the ground they were built on.
##
## Returns `{kind, title, footprint, art, owned}` — `owned` because who holds a thing is game state,
## which map content has no business reading.
static func selection_at(map: TerrainMap, view: OverworldMapView, subtile: Vector2i,
		constructions_visible: bool = true, roads: RoadNetwork = null) -> Dictionary:
	if map == null or view == null or not view.has_subtile(subtile):
		return {}
	var cell := subtile / SUBTILES_PER_TILE
	if constructions_visible:
		# **A road is exactly one subtile, and selecting one selects only that.** Unlike a farm, whose
		# cells are one thing built at one moment, a road network is whatever the player has drawn —
		# it can run the width of the map, and outlining the whole connected run would mark a thin
		# snake across the screen in answer to a click on one square of it. A run may want to become
		# selectable when there is something to *do* to a whole road; there is not yet.
		if roads != null and roads.has_road(subtile):
			return {
				"kind": KIND_ROAD,
				"title": "Road",
				"footprint": subtile_footprint(subtile),
				"art": RoadNetwork.ATLAS,
				"owned": true,
			}
		# **A house is one subtile, and selecting one selects that subtile.** It is drawn wider than
		# that — see [constant HOUSE_TILE_WIDTH] — so the outline sits inside the roof rather than
		# round it. That is the truthful mark: it encloses the ground the house is founded on, which
		# is the thing a player is acting on, rather than the extent of a painting.
		var house := house_at(map, subtile)
		if not house.is_empty():
			return {
				"kind": KIND_CONSTRUCTION,
				"title": String(house["title"]),
				"footprint": subtile_footprint(subtile),
				"art": Buildings.texture(),
				"owned": true,
			}
		var built := construction_at(map, cell)
		if not built.is_empty():
			var footprint := construction_footprint(built)
			# Too small to aim at. The rung above is the settlement, which does not exist yet — so
			# this is where the walk stops and the click means nothing. See the note above.
			if not view.is_footprint_selectable(footprint):
				return {}
			return {
				"kind": KIND_CONSTRUCTION,
				"title": String(built["title"]),
				"footprint": footprint,
				"art": farm_texture(),
				"owned": true,
			}
	var ground := subtile_footprint(subtile)
	if not view.is_footprint_selectable(ground):
		return {}
	var biome := map.biome_at(cell.x, cell.y)
	return {
		"kind": KIND_TERRAIN,
		"title": String(BIOME_TITLES.get(biome, biome.capitalize())),
		"footprint": ground,
		"art": GRASS_ATLAS,
		"owned": false,
	}


# --- building -----------------------------------------------------------------------------------

## The tools the build bar offers. Roads are the only thing that can be built yet, and demolishing is
## its mirror rather than a general tool: it removes roads, because roads are all there is to remove.
const TOOL_ROAD := "road"
const TOOL_DEMOLISH := "demolish"

## Whether a road may be laid on [param subtile].
##
## **Open ground only.** A construction owns its whole cells, so a road may not cross a ploughed
## field — that is the one rule the brief asked for. Trees do not object: a road through woodland
## clears what stood in its way, which the renderer does by itself.
##
## A subtile that already carries road is **not** invalid; it is simply nothing to do. Painting back
## over a road you have just drawn is how anyone draws, and flashing it red would be telling the
## player off for the ordinary way of using the tool.
static func can_build_road(map: TerrainMap, subtile: Vector2i, roads: RoadNetwork) -> bool:
	if map == null or roads == null:
		return false
	if roads.has_road(subtile):
		return false
	# **A house refuses only the subtile it stands on**, not the cell around it, because a subtile is
	# all it occupies. A road running up to a door is a road running up to a door.
	if not house_at(map, subtile).is_empty():
		return false
	return construction_at(map, subtile / SUBTILES_PER_TILE).is_empty()


## Whether painting [param subtile] with a given tool should add it to the plan at all, and whether
## it is a piece that may be applied. Returns one of the three states the band and the ghosts need:
## `"skip"` (nothing to do here), `"valid"`, or `"invalid"`.
##
## The distinction between skip and invalid is the whole of the feedback: a road already there is
## skipped silently, while a road across a farm shows red and says why the finished run has a gap.
static func plan_state(map: TerrainMap, subtile: Vector2i, roads: RoadNetwork,
		tool: String) -> String:
	if map == null or roads == null:
		return "skip"
	if tool == TOOL_DEMOLISH:
		# Only a road can be demolished, and dragging across bare ground on the way to one is not an
		# error — there is simply nothing there.
		return "valid" if roads.has_road(subtile) else "skip"
	if roads.has_road(subtile):
		return "skip"
	return "valid" if can_build_road(map, subtile, roads) else "invalid"


## A construction's cells as the subtile rectangle the map outlines.
static func construction_footprint(built: Dictionary) -> Array[Rect2i]:
	var cells := built["cells"] as Rect2i
	return [Rect2i(cells.position * SUBTILES_PER_TILE, cells.size * SUBTILES_PER_TILE)] as Array[Rect2i]


## One subtile, as the same shape a construction's footprint has — so the map outlines both by one
## path and bare ground is not a special case anywhere downstream.
static func subtile_footprint(subtile: Vector2i) -> Array[Rect2i]:
	return [Rect2i(subtile, Vector2i.ONE)] as Array[Rect2i]


# --- the demonstration network --------------------------------------------------------------------

## **A road figure laid beside the outpost that uses every one of the sixteen pieces.** Turn this off
## and a new game opens on unbuilt ground.
##
## It exists to make a wrong atlas obvious the moment the map appears, rather than after somebody
## happens to draw the one junction that is broken. It is a test fixture living in content, like
## [constant FARM_CELLS] — and like those, whatever eventually decides where roads go replaces it.
const DEMO_ROADS_ENABLED := true

## A lattice — a square ring with a bar across each middle. That one shape accounts for eleven of the
## sixteen: four corners at its corners, four T-junctions where the bars meet the ring, the crossroads
## at the centre, and straight runs along every span between them.
##
## Nine subtiles to a side, with the bars at 0, 4 and 8. Three-subtile runs between junctions are what
## makes a misalignment visible: a straight meeting a corner is exactly where a connector drawn off
## the centreline shows as a step, and at one subtile apart there is no straight to compare against.
const DEMO_ROAD_GRID_ORIGIN := Vector2i(-16, 0)
const DEMO_ROAD_GRID_SIZE := 9

## The five the lattice cannot produce, because every piece in it is attached on at least two sides:
## the four dead-ends and the lone stub with nothing attached at all.
##
## A pair of subtiles side by side is *two* dead-ends — the left one points east, the right one west —
## so three short marks cover all four, plus one on its own for the isolated piece. They are spaced
## three apart so that nothing here accidentally joins onto anything else, which would quietly turn a
## dead-end into a straight and lose the case being demonstrated.
const DEMO_ROAD_STUBS_ORIGIN := Vector2i(-4, 2)

## A second row, below the lattice, for the arrangements it cannot show.
##
## The lattice proves every *piece* exists. These prove the pieces still work when they are pushed
## together in the ways a lattice never does — chained diagonally, wrapped as tightly as a loop can
## be, packed solid, repeated along one spine, and run side by side without touching. Between them
## they are where a piece drawn a pixel off its centreline, or one that reaches past its own edge,
## stops being subtle.
##
## **Placed on the row the opening view can actually hold.** The first attempt sat a row above the
## lattice and was cut in half by the top of the stage: the map opens roughly three cells above the
## outpost and four below, so the room to spare is underneath, not over. This row runs either side of
## the southern field, which is why the figures below are spaced the way they are.
const DEMO_ROAD_FIGURES_ORIGIN := Vector2i(-30, 15)


## The awkward arrangements, as offsets from [constant DEMO_ROAD_FIGURES_ORIGIN]. Each figure starts
## four subtiles clear of the last, which is far enough that none of them joins onto its neighbour and
## quietly becomes one larger shape.
static func _demonstration_figures() -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	# **A staircase.** Every step is a corner meeting another corner — the lattice only ever puts a
	# corner next to a straight, so a corner whose two arms disagree looks fine there and ugly here.
	var stair := Vector2i(40, 0)
	out.append(stair)
	for _step in 3:
		stair += Vector2i(1, 0)
		out.append(stair)
		stair += Vector2i(0, 1)
		out.append(stair)
	out.append(stair + Vector2i(1, 0))

	# **The tightest loop there is**: a three-by-three ring, with a single subtile of straight between
	# one corner and the next.
	var ring := Vector2i(48, 0)
	for i in 3:
		out.append(ring + Vector2i(i, 0))
		out.append(ring + Vector2i(i, 2))
	out.append(ring + Vector2i(0, 1))
	out.append(ring + Vector2i(2, 1))

	# **Solid ground.** Every inner subtile is a crossroads and every edge subtile a T-junction, which
	# is the one case where the pieces are judged against each other on all four sides at once.
	var block := Vector2i(54, 0)
	for y in 3:
		for x in 3:
			out.append(block + Vector2i(x, y))

	# **A comb**: one spine with three teeth, so the same T-junction repeats along a straight run and
	# any drift between the two shows as a wobble rather than as a single step.
	var comb := Vector2i(0, 0)
	for i in 7:
		out.append(comb + Vector2i(i, 0))
	for tooth: int in [1, 3, 5]:
		out.append(comb + Vector2i(tooth, 1))
		out.append(comb + Vector2i(tooth, 2))

	# **Two runs with one empty subtile between them** — as close as two roads come without becoming
	# one. This is where a piece that reaches past its own cell edge shows up, because the gap it
	# eats into is only a single subtile wide.
	var parallel := Vector2i(10, 0)
	for i in 5:
		out.append(parallel + Vector2i(i, 0))
		out.append(parallel + Vector2i(i, 2))

	return out


## Every subtile of the demonstration figure, in absolute coordinates. Empty when the map has nowhere
## to found an outpost, and when the figure is switched off.
##
## Corners of the lattice are produced twice by the loop below; a road is a set, so that is harmless
## and cheaper than the arithmetic to avoid it.
static func demonstration_roads(map: TerrainMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not DEMO_ROADS_ENABLED or map == null:
		return out
	var site := outpost_site(map)
	if site.x < 0:
		return out
	var origin := site * SUBTILES_PER_TILE

	var grid := origin + DEMO_ROAD_GRID_ORIGIN
	var last := DEMO_ROAD_GRID_SIZE - 1
	for step in DEMO_ROAD_GRID_SIZE:
		for line: int in [0, last / 2, last]:
			out.append(grid + Vector2i(step, line))
			out.append(grid + Vector2i(line, step))

	var stubs := origin + DEMO_ROAD_STUBS_ORIGIN
	out.append(stubs)                        # attached to nothing
	out.append(stubs + Vector2i(3, 0))       # points east
	out.append(stubs + Vector2i(4, 0))       # points west
	out.append(stubs + Vector2i(7, 0))       # points south
	out.append(stubs + Vector2i(7, 1))       # points north

	var figures := origin + DEMO_ROAD_FIGURES_ORIGIN
	for at: Vector2i in _demonstration_figures():
		out.append(figures + at)
	return out


## The cell a new outpost is founded on.
##
## **Placeholder rule, deliberately simple: the cell nearest the map's middle.** It is deterministic,
## so the site survives a save and reload. It is not yet varied per game (there is no per-world map
## seed), or matched to the wizard's location (this construction map has only grass).
static func outpost_site(map: TerrainMap) -> Vector2i:
	return map.find_cell_nearest_centre(HABITABLE_BIOMES)
