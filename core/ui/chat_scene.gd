class_name ChatScene
extends Control

## **The painted scene at the top of the conversation** — one background, and later the characters
## standing in it.
##
## It is handed a picture and draws it. Which scene belongs to which moment of the game is the
## caller's knowledge, exactly as the map view is handed textures and never learns what a farm is
## (`modules/base_game/chat_scenes.gd` holds the catalogue).
##
## Two things about it are unusual enough to be worth reading before changing anything here: it is
## fitted by its **height** rather than its width ([method band_height]), and it deliberately draws
## **outside its own rectangle** ([constant BLEED]).

## **How far past its own box the scene draws, to meet the frame.**
##
## [ChatDock] sits on a [StyleBoxTexture] that leaves [constant UiSkin.CHAT_FRAME_PADDING] of room
## inside the board's edge, of which the first [constant UiSkin.CHAT_FRAME_RULE] is painted rule. A
## picture that is to sit *against* the rule therefore has to reach back out through the difference —
## which is this, and which is the same expression [constant UiSkin.CHAT_FRAME_PADDING_BOTTOM] is,
## for the same reason at the other end of the board.
##
## **Drawn outside, not laid out outside.** A [CanvasItem] may paint beyond its bounds; what it may
## not do is claim the space, or every sibling below it would be pushed about by a picture's margin.
## So this control occupies an ordinary rectangle in the board's column and only its [method _draw]
## reaches into the frame.
##
## The requirement that comes with it: **nothing between here and the board may set
## [member CanvasItem.clip_contents]**, or the bleed is quietly cut off and the scene stops meeting
## the rule on three sides. Nothing does; `test_chat_scene.gd` pins it.
const BLEED := UiSkin.CHAT_FRAME_PADDING - UiSkin.CHAT_FRAME_RULE

## **How short the scene may get before it starts cropping its sides instead.**
##
## Only has an effect on a board too narrow to show the picture at a comfortable size — and only while
## it is under [constant MAX_SCENE_SCREEN_FRACTION] of the screen, which on the window sizes in use
## today it is not. It stays because the two numbers answer different questions: this one is a floor
## under how small a picture may be drawn, and the cap is a ceiling over how much of the screen it may
## take. On a tall screen the floor is what stops a narrow board shrinking the scene to a strip.
const MIN_SCENE_HEIGHT := 420.0

## **The most of the screen a scene may take, whatever the board's shape.**
##
## The picture wants to be `width / aspect` tall — for an 8:3 plate on a wide board that is over half
## the conversation, which leaves the chronicle and the line the player writes on sharing what is
## left. A quarter of the screen is the ceiling, and it binds on every window size in use.
##
## **What the ceiling costs is width, not height.** The picture is always scaled to show all of itself
## vertically, so holding the band down holds its width down with it — an 8:3 plate capped at 448 is
## about 1195 across, and a desktop board is half as wide again. See [method horizontal_stretch] for
## what happens then, and why it wants wider plates rather than different code.
##
## **Raising this buys width.** Every extra unit of ceiling is `aspect` units of picture, so it is the
## cheapest way to take the distortion out of a plate that is too narrow — at a third of the screen an
## 8:3 plate is stretched about a half rather than double.
const MAX_SCENE_SCREEN_FRACTION := 0.35

## Where the ✕ sits inside the scene's top-right corner once the scene has taken the board's top edge
## from the header.
const CLOSE_INSET := 10.0

## **How far from the middle of the band a character would like to stand**, in band heights — so the
## pair keep their distance from each other relative to their own size rather than to the board's, and
## a wide board does not fling them into opposite corners.
##
## It is only what they would *like*. On a board too narrow to grant it they are pushed against the
## sides instead ([method character_offset]), which is the whole of the difference between a phone and
## a desktop here: no breakpoint, just a wish and the room available.
const CHARACTER_SPREAD := 0.80

## How close a character may come to the edge of the band when the board is too narrow to keep them
## apart. Small, because on a phone they are meant to be hard against the sides.
const CHARACTER_EDGE_MARGIN := 8.0

## How tall a character is drawn, as a fraction of the band.
##
## Started at 0.90, taken from the reference composition where the crown clears the top by about a
## tenth, and came down a fifth from there: at full height the figures crowded the room they were
## meant to be standing in, and the throne behind them had no air above it. **Only the height is
## given** — the width follows from the figure's own proportions, so this is the one dial for how
## large a character is, and shrinking it also loosens the spread by leaving more room across.
const CHARACTER_HEIGHT := 0.72

## **The shadow behind a character.** Cast by [ChatCharacter]'s own [ShaderMaterial] — these are the
## numbers it is given; `core/ui/theme/character_shadow.gdshader` is how it uses them.
##
## The scene does not draw the shadow itself, and briefly did: sampling the silhouette by hand cost
## twenty-four draws a figure, and a material could not be used *here* because one belongs to a whole
## [CanvasItem] and this one paints the background too. Giving each figure a node of its own settles
## that — the material lands on exactly the thing it is a shadow of — and it is the same arrangement a
## stack of layers will want, flattened by a [CanvasGroup] so the shadow comes from the composite
## silhouette rather than from each garment separately.
const CHARACTER_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.7)
## See the shader: the disc average is about a half where it matters most, so without this the darkest
## the shadow ever gets is half the opacity above. Two makes the number mean what it says at the
## figure's own edge.
const CHARACTER_SHADOW_GAIN := 2.0
## **How far the blur reaches, in band heights** — this is what makes it read as a shadow rather than
## an outline, and the first version was a third of this and looked like a rim.
const CHARACTER_SHADOW_RADIUS := 0.075
## Where the shadow sits against the figure. Small next to the radius on purpose: the figure is
## composited into a painted room rather than standing under a lamp, so what lifts it off the plate is
## a soft darkness gathered behind it, nudged down, not a shape thrown to one side.
const CHARACTER_SHADOW_DROP := Vector2(0.0, 0.018)

var _background: Texture2D = null
## Where the floor is in this particular painting, as a fraction of the scene's height — **not** a
## constant, because a different background puts its floor somewhere else. Characters' feet land here.
var _floor_line := 1.0
var _characters: Array = []
## One [ChatCharacter] per figure on stage, in step with [member _characters].
var _figures: Array[ChatCharacter] = []
## Re-parented onto the scene while one is showing, so the board's close control keeps working when
## the header it normally lives in has given way to the picture.
var _close: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refit)
	visible = false


## Show [param background], with its floor at [param floor_line] (a fraction of the scene's height)
## and [param characters] standing in it, each `{texture, content, side, height}` — see
## [method _place_characters].
func show_scene(background: Texture2D, floor_line: float = 1.0, characters: Array = []) -> void:
	_background = background
	_floor_line = clampf(floor_line, 0.0, 1.0)
	_characters = characters.duplicate()
	_rebuild_figures()
	visible = _background != null
	_refit()


func clear_scene() -> void:
	_background = null
	_characters.clear()
	_rebuild_figures()
	visible = false
	custom_minimum_size.y = 0.0


func has_scene() -> bool:
	return _background != null


## Hand the scene the board's close control, to carry while it owns the board's top edge. Passing
## [code]null[/code] gives it back. **One button re-parented rather than two that could drift apart**:
## the ✕ has to behave identically whether it is sitting on a picture or in a header.
func set_close_control(close: Control) -> void:
	_close = close
	_refit()


# --- geometry ------------------------------------------------------------------------------------

## **How tall the scene band is** — the picture's own proportions, held between a floor and a ceiling.
##
## - `drawn_width / aspect` is what the picture would like: exactly enough to show all of itself
##   across the full width of the board.
## - [constant MIN_SCENE_HEIGHT] is the floor, so a narrow board draws the picture bigger and crops
##   its sides rather than shrinking the whole room to a strip.
## - [param cap] is the ceiling — [constant MAX_SCENE_SCREEN_FRACTION] of the screen — and on every
##   window size in use it is the one that binds.
static func band_height(drawn_width: float, art: Vector2, minimum: float = MIN_SCENE_HEIGHT,
		cap: float = 0.0) -> float:
	if art.x <= 0.0 or art.y <= 0.0 or drawn_width <= 0.0:
		return 0.0
	var wanted := maxf(minimum, drawn_width * art.y / art.x)
	return minf(wanted, cap) if cap > 0.0 else wanted


## **Which part of the picture is on screen, as a region of the texture.**
##
## **Scale to the height first, crop the sides second** — in that order, and the order is the whole
## rule. The picture is sized so that *all* of its height fills the band, and then whatever will not
## fit across is taken evenly off the two sides. It is never cropped vertically and never squashed:
## a painting's top and bottom are always both on screen.
##
## The crop is always centred. There is no reason to prefer one side of a painting, and one drifting
## off centre as the board narrows is invisible until the art has something on one side of it.
##
## **A board wider than the picture is not this method's problem.** It reports the whole texture, and
## the picture is stretched across the band instead — see [method horizontal_stretch].
##
## Pure and static so the fit can be asserted directly: a crop a few units off centre is invisible in
## a screenshot of a symmetrical room and obvious only once somebody paints an asymmetrical one.
static func source_region(band_width: float, height: float, art: Vector2) -> Rect2:
	if art.x <= 0.0 or art.y <= 0.0 or height <= 0.0 or band_width <= 0.0:
		return Rect2()
	# One scale, taken from the height, so the vertical is never touched.
	var scale := height / art.y
	var shown := minf(band_width / scale, art.x)
	return Rect2((art.x - shown) * 0.5, 0.0, shown, art.y)


## **How much the picture is stretched sideways to reach the board's edges** — 1.0 when it is not.
##
## The scene always spans the full width of the board; that was the first thing asked of it. At the
## capped height a plate narrower than the board has nothing left to crop, and the only two ways to
## fill what remains are to stretch it or to leave the board's parchment showing either side. It
## stretches.
##
## **This is a stopgap and it distorts.** A 1024x384 plate on a desktop board is pulled to about twice
## its proper width, which a room full of columns shows plainly. The fix is art rather than code: a
## plate near the band's own shape — about 5:1 at this ceiling — crops its sides on a phone and
## reaches a wide board's edges with no stretch at all. This exists so the amount is measurable rather
## than something to squint at.
static func horizontal_stretch(band_width: float, height: float, art: Vector2) -> float:
	if art.x <= 0.0 or art.y <= 0.0 or height <= 0.0 or band_width <= 0.0:
		return 1.0
	return maxf(band_width / (height * art.x / art.y), 1.0)


## Where the picture is painted, in this control's own coordinates — starting [constant BLEED] up and
## left of its box, and running the full bled width.
func _picture_rect() -> Rect2:
	var art := _background.get_size()
	var band_width := size.x + BLEED * 2.0
	# The full width of the board, always — stretching the picture sideways when there is not enough of
	# it left to reach the edges ([method horizontal_stretch]).
	return Rect2(-BLEED, -BLEED, band_width,
		band_height(band_width, art, MIN_SCENE_HEIGHT, _height_cap()))


## The ceiling on the band, as a share of the whole screen. Taken from the **viewport**, not from the
## board: the cap is about how much of what the player is looking at a picture may occupy, and the
## board's own height already answers to the scene through the layout.
func _height_cap() -> float:
	if not is_inside_tree():
		return 0.0
	return get_viewport_rect().size.y * MAX_SCENE_SCREEN_FRACTION


## Recompute the height this control asks the board's column for, and put the ✕ back in its corner.
##
## **The height is a function of the width**, which the container only knows once it has laid this out
## — hence [signal Control.resized] rather than a value set at build time. Guarded against re-entry by
## only writing a minimum that actually differs: setting it re-runs the layout, which resizes this,
## which arrives back here.
func _refit() -> void:
	if _background == null:
		return
	var picture := _picture_rect()
	# The picture starts a bleed *above* this box, so the room it needs below the box's top edge is
	# that much less than its own height.
	var wanted := maxf(picture.size.y - BLEED, 0.0)
	if not is_equal_approx(custom_minimum_size.y, wanted):
		custom_minimum_size.y = wanted
	_place_characters(picture)
	if _close != null and is_instance_valid(_close):
		var close_size := _close.size
		if close_size == Vector2.ZERO:
			close_size = _close.get_combined_minimum_size()
		_close.position = Vector2(picture.end.x - close_size.x - CLOSE_INSET,
			picture.position.y + CLOSE_INSET)
	queue_redraw()


func _draw() -> void:
	if _background == null:
		return
	var picture := _picture_rect()
	draw_texture_rect_region(_background, picture,
		source_region(picture.size.x, picture.size.y, _background.get_size()))


## **How far a character's centre sits from the middle of the band** — what they would like, or all
## the room there is, whichever is less.
##
## The one expression that covers both breakpoints without either being named. On a wide board
## [constant CHARACTER_SPREAD] wins and the pair stand well inside the frame with the scene between
## them; on a narrow one the room runs out first and they are pushed hard against the sides. Pure and
## static, because "does a phone actually put them at the edges" is a question worth asking of the
## arithmetic rather than of a screenshot.
static func character_offset(band: Vector2, character_width: float) -> float:
	var wanted := CHARACTER_SPREAD * band.y
	var room := band.x * 0.5 - character_width * 0.5 - CHARACTER_EDGE_MARGIN
	return maxf(minf(wanted, room), 0.0)


## **Where a character is drawn, as the box its *figure* occupies** — not the box its file occupies.
##
## [param content] is where the figure actually is on the shared canvas. Layered characters must all
## be painted on one canvas or their hair would not sit on their head, so the canvas is an alignment
## grid and cannot be trimmed; the figure inside it is what has to be placed, sized and spaced. Taking
## the padding as part of the character would hang them off the band's bottom edge by however much
## transparent space the artist happened to leave.
##
## [param side] is -1 for the left of the band and +1 for the right.
static func character_content_rect(picture: Rect2, content: Rect2, side: int,
		height: float = CHARACTER_HEIGHT) -> Rect2:
	if content.size.y <= 0.0:
		return Rect2()
	var high := picture.size.y * height
	var wide := content.size.x * (high / content.size.y)
	var centre := picture.get_center().x + float(side) * character_offset(picture.size, wide)
	# Anchored to the **bottom of the band**, not to the scene's floor line: this art is a bust cut
	# off at the waist, so it rises out of the bottom edge rather than standing on the flagstones.
	return Rect2(centre - wide * 0.5, picture.end.y - high, wide, high)


## **Which part of a texture is still inside [param bounds] once it is drawn into [param dest]** — the
## region to pass alongside `dest.intersection(bounds)`.
##
## The scene is a window onto a painting and **nothing in it may spill out of that window**. The
## shadow is what makes this matter: it is a ring of copies dropped below the figure, and the figure
## already stands on the band's bottom edge, so without this the shadow falls out of the picture and
## onto the parchment the conversation is written on.
##
## Clipping by region rather than by [member CanvasItem.clip_contents], which is not available here:
## the scene deliberately draws [constant BLEED] outside its own rectangle to meet the frame, and a
## control that clipped its own drawing would cut that off as well.
static func clipped_region(dest: Rect2, bounds: Rect2, art: Vector2) -> Rect2:
	var visible := dest.intersection(bounds)
	if dest.size.x <= 0.0 or dest.size.y <= 0.0 or not visible.has_area():
		return Rect2()
	var scale := Vector2(art.x / dest.size.x, art.y / dest.size.y)
	return Rect2((visible.position - dest.position) * scale, visible.size * scale)


## Draw [param texture] into [param dest], showing only what falls inside [param bounds].
func _draw_texture_clipped(texture: Texture2D, dest: Rect2, bounds: Rect2, tint: Color) -> void:
	var visible := dest.intersection(bounds)
	if not visible.has_area():
		return
	draw_texture_rect_region(texture, visible,
		clipped_region(dest, bounds, texture.get_size()), tint)


## **Where the whole canvas lands on screen, given where the figure on it has to end up.**
##
## Layers share a canvas — a hat has to be painted on the same grid as the head it sits on — so what
## is placed is the figure and what is *drawn* is the canvas around it. Backing one out of the other
## here means the transparent margin lands where the art intends rather than being positioned in its
## own right, which would hang the person off the bottom of the band by however much space the artist
## happened to leave.
static func character_canvas_rect(figure: Rect2, content: Rect2, canvas: Vector2) -> Rect2:
	if content.size.y <= 0.0:
		return Rect2()
	var scale := figure.size.y / content.size.y
	return Rect2(figure.position - content.position * scale, canvas * scale)


## Put each figure where it belongs and hand it the window it may not draw outside of. The drawing
## itself belongs to [ChatCharacter], which carries the shadow in a shader of its own — see that class
## for why a node each rather than a pass over this one's `_draw`.
##
## **Staged against the band rather than pinned to the painting**, which is the opposite of how the
## scenery works and is deliberate: a figure that belongs to the room has to keep its footing on the
## room, but a speaker in a conversation is framed like a portrait and belongs at the sides of what
## the player can actually see. Only the horizontal differs — there is no vertical crop, so a height
## given against the painting and one given against the band are the same number.
func _place_characters(picture: Rect2) -> void:
	var drop := CHARACTER_SHADOW_DROP * picture.size.y
	var radius := CHARACTER_SHADOW_RADIUS * picture.size.y
	# Enough room in the rect for the blur to reach its full extent in any direction, plus wherever
	# the drop has carried it. A shader cannot paint outside its own primitive.
	var spread := radius + maxf(absf(drop.x), absf(drop.y))
	for index in _characters.size():
		var character: Dictionary = _characters[index]
		var node: ChatCharacter = _figures[index]
		var texture := character.get("texture") as Texture2D
		var content := character.get("content", Rect2(Vector2.ZERO, texture.get_size())) as Rect2
		var side := int(character.get("side", 1))
		var figure := character_content_rect(picture, content, side,
			float(character.get("height", CHARACTER_HEIGHT)))
		node.place(texture, character_canvas_rect(figure, content, texture.get_size()),
			spread, drop, radius, picture, side < 0)


## Keep one [ChatCharacter] per figure on stage. Rebuilt rather than pooled: the stage changes when a
## scene does, which is rarely, and a spare node kept around is a node that can be left showing
## somebody who has walked off.
func _rebuild_figures() -> void:
	for node: ChatCharacter in _figures:
		node.queue_free()
	_figures.clear()
	for character: Dictionary in _characters:
		if character.get("texture") == null:
			continue
		var node := ChatCharacter.new()
		node.set_shadow(CHARACTER_SHADOW_COLOR, CHARACTER_SHADOW_GAIN)
		add_child(node)
		_figures.append(node)
	# A figure with no texture is dropped, so the two lists have to be brought back into step or
	# `_place_characters` would pair a node with the wrong record.
	var staged: Array = []
	for character: Dictionary in _characters:
		if character.get("texture") != null:
			staged.append(character)
	_characters = staged
