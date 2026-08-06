class_name Buildings
extends RefCounted

## **One house, at every state it can be in.** The atlas and the table that says which frame is which,
## and nothing else — where houses stand and what the map does with them is [BaseGameMap]'s, so this
## has no idea a map exists.

## Sixteen frames on a **6 x 3** grid of 192px cells from (32, 32): eight states, each painted twice,
## once clear and once under snow. Two slots at the end of the last row are empty.
##
## Each cell holds a 128px building with its overhang around it — the same arrangement the fields use
## and for the same reason, so both go through [method OverworldMapView.slice_grid]. Measured off the
## sheet: the widest frame reaches 15px past the nominal square and the tallest 20px, both comfortably
## inside the 32px the cell allows.
const ATLAS := preload("res://core/assets/map/house1_atlas.png")
const ATLAS_ORIGIN := Vector2i(32, 32)
const ATLAS_CELL := 192
const ATLAS_COLUMNS := 6
const ATLAS_ROWS := 3
## The building square inside that cell. The remaining 32px a side is the room its overhang, and one
## day its shadow, is painted into — see [constant BaseGameMap.HOUSE_TILE_WIDTH] for how the two
## become a size on the map.
const NOMINAL_PX := 128

## **What a building looks like, as one list rather than two crossed axes.** A stage of construction
## and a state of ruin are alternatives, not dimensions: a house is being built until it is finished
## and can be wrecked afterwards, so there is no such thing as a burnt foundation. Crossing them would
## give thirty-two combinations of which twenty-four are art nobody will ever paint.
enum Appearance { FOUNDATION, EARLY, LATE, FINISHED, RUIN, DAMAGED, BURNT, ABANDONED }

## How each reads to a player.
const APPEARANCE_TITLES := [
	"Foundation", "House under construction", "House nearly finished", "House",
	"Ruin", "Damaged house", "Burnt-out house", "Abandoned house",
]

## **Which slot on the sheet each appearance is, indexed by the enum.**
##
## Written out rather than computed, because there is no rule relating the two — the sheet is six
## wide and holds sixteen frames in an order that is nearly, but not quite, "all eight clear then all
## eight snowed". The four build stages open row 0, the first two of their snowed copies finish that
## row, the four ruined states open row 1, and the *remaining* two snowed build stages finish it. Any
## formula pretending otherwise would break the day the sheet is re-exported one column wider.
##
## Reading order, so a slot is `row * ATLAS_COLUMNS + column`, exactly as the road atlas indexes its
## pieces.
const CLEAR_SLOTS: PackedInt32Array = [0, 1, 2, 3, 6, 7, 8, 9]
const SNOW_SLOTS: PackedInt32Array = [4, 5, 10, 11, 12, 13, 14, 15]

## **The state every house is currently in — one global, and deliberately.** There is no construction
## system, no fire and no decay, so a per-house state would be a number nothing writes to. Dev keys
## set these and every house answers, which is exactly enough to judge the art.
##
## When something does decide a building's state it moves onto the building; [method BaseGameMap.houses]
## already returns a dictionary each, so it becomes an entry in that and these go.
static var appearance: Appearance = Appearance.FINISHED
## Whether the snowed copy of each frame is the one drawn. **Not a season** — there is no season
## system yet ([code]docs/seasons_buildings_weather_plan.md[/code]); this is the switch that makes
## half the sheet reachable, and it becomes `season == WINTER` the day seasons land.
static var snow := false

## Cut once and kept. The slicing is cheap, but it has no business running per frame and every house
## on the map wants the same sixteen textures.
static var _frames: Array[Texture2D] = []


## The sheet, cut into its sixteen frames in reading order.
static func frames() -> Array[Texture2D]:
	if _frames.is_empty():
		_frames = OverworldMapView.slice_grid(ATLAS, ATLAS_ORIGIN, ATLAS_CELL, ATLAS_COLUMNS,
			ATLAS_ROWS)
	return _frames


## The frame for [param which], snowed or not. Falls back to the clear copy rather than to nothing if
## a snow slot is ever missing, so a half-finished sheet shows the wrong weather instead of a hole.
static func frame(which: Appearance, snowed: bool) -> Texture2D:
	var all := frames()
	var slots := SNOW_SLOTS if snowed else CLEAR_SLOTS
	var index := clampi(int(which), 0, slots.size() - 1)
	var slot := slots[index]
	if slot < 0 or slot >= all.size():
		slot = CLEAR_SLOTS[index]
	return all[slot] if slot < all.size() else null


## The frame for the state every house is currently in.
static func texture() -> Texture2D:
	return frame(appearance, snow)


static func title() -> String:
	return String(APPEARANCE_TITLES[clampi(int(appearance), 0, APPEARANCE_TITLES.size() - 1)])
