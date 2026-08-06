extends GutTest

## The painted scene at the top of the conversation.
##
## Almost all of this is the **fit**, because the fit is where a mistake hides: a crop a few units off
## centre, or one that has quietly started eating the top of the picture, is invisible in a screenshot
## of a symmetrical room and obvious only once somebody paints an asymmetrical one.

## The first plate's proportions, which the rule has to behave sensibly either side of.
const ART := Vector2(1024, 384)


func _scene() -> ChatScene:
	var scene := ChatScene.new()
	add_child_autofree(scene)
	return scene


func _plate() -> ImageTexture:
	var image := Image.create_empty(int(ART.x), int(ART.y), false, Image.FORMAT_RGBA8)
	image.fill(Color.hex(0x40506080))
	return ImageTexture.create_from_image(image)


# --- the fit ---------------------------------------------------------------------------------

## **A floor, a ceiling, and the picture's own proportions in between** — and which of the three
## decides the band depends on the board's shape, so all three are asserted.
func test_the_band_is_held_between_a_floor_and_a_share_of_the_screen() -> void:
	var cap := 1280.0 * ChatScene.MAX_SCENE_SCREEN_FRACTION
	assert_lte(ChatScene.MIN_SCENE_HEIGHT, cap,
		"the floor may not be above the ceiling, or one of them means nothing")

	# A wide board wants more than it may have, so the ceiling decides.
	assert_gt(1732.0 * ART.y / ART.x, cap, "the picture wants more than it may have")
	assert_eq(ChatScene.band_height(1732.0, ART, ChatScene.MIN_SCENE_HEIGHT, cap), cap)

	# A narrow board wants less than is worth showing, so the floor decides and the ceiling is not
	# reached at all.
	assert_lt(700.0 * ART.y / ART.x, ChatScene.MIN_SCENE_HEIGHT)
	assert_eq(ChatScene.band_height(700.0, ART, ChatScene.MIN_SCENE_HEIGHT, cap),
		ChatScene.MIN_SCENE_HEIGHT)

	# With no ceiling given, the picture's own proportions have their way.
	assert_almost_eq(ChatScene.band_height(1732.0, ART, ChatScene.MIN_SCENE_HEIGHT, 0.0),
		1732.0 * ART.y / ART.x, 0.001)


## **Scale to the height first, crop the sides second.** The vertical is never touched at any board
## shape — swept rather than sampled, because a rule with a breakpoint in it would pass at whichever
## two widths anyone thought to check.
func test_the_full_height_is_always_shown_and_only_the_sides_are_ever_cropped() -> void:
	var cap := 1280.0 * ChatScene.MAX_SCENE_SCREEN_FRACTION
	for width: float in [120.0, 400.0, 700.0, 853.0, 1000.0, 1400.0, 1732.0, 2400.0]:
		var height := ChatScene.band_height(width, ART, ChatScene.MIN_SCENE_HEIGHT, cap)
		var region := ChatScene.source_region(width, height, ART)
		assert_eq(region.position.y, 0.0, "top of the painting, at width %f" % width)
		assert_eq(region.size.y, ART.y, "and all of its height, at width %f" % width)
		assert_almost_eq(region.position.x, (ART.x - region.size.x) * 0.5, 0.001,
			"whatever is cropped is taken evenly off both sides, at width %f" % width)


## The scene always spans the board. While there is picture left to crop it does so at its own
## proportions; past that it is stretched sideways to reach the edges — a stopgap until the plates are
## painted nearer the band's shape.
func test_the_picture_spans_the_board_and_stretches_only_once_there_is_nothing_left_to_crop() -> void:
	var cap := 1280.0 * ChatScene.MAX_SCENE_SCREEN_FRACTION
	# How wide the plate comes out once scaled to the ceiling — the width at which cropping stops.
	var natural := cap * ART.x / ART.y

	for width: float in [400.0, 700.0, natural]:
		assert_almost_eq(ChatScene.horizontal_stretch(width, cap, ART), 1.0, 0.001,
			"still cropping, so still undistorted, at width %f" % width)
	assert_gt(ChatScene.horizontal_stretch(1732.0, cap, ART), 1.0,
		"and a desktop board is wider than this plate at this ceiling, so it is pulled to fit")
	assert_almost_eq(ChatScene.horizontal_stretch(1732.0, cap, ART), 1732.0 / natural, 0.001,
		"by exactly the shortfall, and no more")


## The two ends of the range, spelled out. A narrow board has more picture than it can hold and crops
## it; a wide board runs out of picture and stretches what there is.
func test_a_narrow_board_crops_the_sides_and_a_wide_one_runs_out_of_picture() -> void:
	var cap := 1280.0 * ChatScene.MAX_SCENE_SCREEN_FRACTION
	var natural := cap * ART.x / ART.y   # how wide the plate is once scaled to the cap

	var narrow := ChatScene.source_region(700.0, cap, ART)
	assert_lt(narrow.size.x, ART.x, "a phone has to crop the sides")
	assert_eq(ChatScene.horizontal_stretch(700.0, cap, ART), 1.0, "and nothing is distorted")

	assert_gt(1732.0, natural, "a desktop board is wider than the plate at this ceiling")
	var wide := ChatScene.source_region(1732.0, cap, ART)
	assert_eq(wide.size.x, ART.x, "so all of the picture is shown and nothing is cropped")
	assert_gt(ChatScene.horizontal_stretch(1732.0, cap, ART), 1.0,
		"and it is pulled across the board instead of leaving parchment either side")


# --- characters ------------------------------------------------------------------------------

## The figure's own canvas, and the box within it the person actually occupies.
const FIGURE := Vector2(472, 557)
const FIGURE_CONTENT := Rect2(63, 55, 368, 502)


## **A wide board grants the spread; a narrow one runs out of room and pushes them to the sides.**
## One expression, no breakpoint — so this asserts the two ends of it rather than a rule per device.
func test_a_pair_keep_their_distance_on_a_wide_board_and_go_to_the_edges_on_a_narrow_one() -> void:
	var desktop := Vector2(1732.0, 448.0)
	var phone := Vector2(700.0, 420.0)
	var wide_figure := ChatScene.character_content_rect(Rect2(Vector2.ZERO, desktop),
		FIGURE_CONTENT, 1)
	var narrow_figure := ChatScene.character_content_rect(Rect2(Vector2.ZERO, phone),
		FIGURE_CONTENT, 1)

	# Desktop: the wish is granted whole, and they are nowhere near the edge.
	assert_almost_eq(ChatScene.character_offset(desktop, wide_figure.size.x),
		ChatScene.CHARACTER_SPREAD * desktop.y, 0.001)
	assert_gt(desktop.x - wide_figure.end.x, 100.0, "and there is board to spare beyond them")

	# Phone: the wish is not granted, and what is left puts them against the margin.
	assert_lt(ChatScene.character_offset(phone, narrow_figure.size.x),
		ChatScene.CHARACTER_SPREAD * phone.y, "there is not room for the spread")
	assert_almost_eq(phone.x - narrow_figure.end.x, ChatScene.CHARACTER_EDGE_MARGIN, 0.001,
		"so the figure sits exactly its margin from the edge")


## Sized and placed by the **figure**, not by the file. A canvas with a transparent margin round it
## would otherwise hang the person off the bottom of the band by however much space the artist left.
func test_a_character_is_measured_by_its_figure_rather_than_its_canvas() -> void:
	var band := Rect2(0.0, 0.0, 1732.0, 448.0)
	var figure := ChatScene.character_content_rect(band, FIGURE_CONTENT, 1)

	assert_almost_eq(figure.size.y, band.size.y * ChatScene.CHARACTER_HEIGHT, 0.001,
		"the person is the given fraction of the band, padding not counted")
	assert_almost_eq(figure.size.x / figure.size.y, FIGURE_CONTENT.size.x / FIGURE_CONTENT.size.y,
		0.001, "and keeps its own proportions")
	assert_almost_eq(figure.end.y, band.end.y, 0.001,
		"a bust cut off at the waist rises out of the band's bottom edge")


## The two sides are mirror images about the band's middle — so a pair are the same distance in, and
## the one on the left is not quietly nearer the edge than the one on the right.
func test_the_two_sides_are_placed_symmetrically() -> void:
	var band := Rect2(0.0, 0.0, 1732.0, 448.0)
	var right := ChatScene.character_content_rect(band, FIGURE_CONTENT, 1)
	var left := ChatScene.character_content_rect(band, FIGURE_CONTENT, -1)
	assert_almost_eq(band.get_center().x - left.get_center().x,
		right.get_center().x - band.get_center().x, 0.001)
	assert_eq(left.size, right.size)
	assert_lt(left.get_center().x, right.get_center().x)


## **Nothing in the scene may spill out of it.** The shadow is why this matters: it is a ring of copies
## dropped below a figure that already stands on the band's bottom edge, so unclipped it lands on the
## parchment the conversation is written on.
func test_what_falls_outside_the_picture_is_cropped_away() -> void:
	var band := Rect2(0.0, 0.0, 1000.0, 400.0)
	var art := Vector2(100.0, 200.0)

	# Wholly inside: all of the texture, untouched.
	assert_eq(ChatScene.clipped_region(Rect2(100.0, 100.0, 200.0, 200.0), band, art),
		Rect2(0.0, 0.0, art.x, art.y))

	# Hanging off the bottom by a quarter of its height: the bottom quarter of the texture goes, and
	# what is left is still anchored at the top of it.
	var over := Rect2(100.0, 200.0, 200.0, 400.0)   # 200 of its 400 units are below the band
	var region := ChatScene.clipped_region(over, band, art)
	assert_eq(region.position, Vector2.ZERO, "the top of the picture is kept")
	assert_almost_eq(region.size.y, art.y * 0.5, 0.001, "and exactly the half that fitted")
	assert_eq(region.size.x, art.x, "with nothing taken off the sides")
	assert_eq(over.intersection(band).size.y, 200.0, "the destination is trimmed to match")

	# Off the left, so the region starts partway into the texture rather than at its edge.
	var left := Rect2(-100.0, 0.0, 200.0, 200.0)
	assert_almost_eq(ChatScene.clipped_region(left, band, art).position.x, art.x * 0.5, 0.001)

	# Wholly outside is nothing at all, rather than a rectangle of nonsense.
	assert_eq(ChatScene.clipped_region(Rect2(-500.0, 0.0, 100.0, 100.0), band, art), Rect2())
	assert_eq(ChatScene.clipped_region(Rect2(0.0, 0.0, 0.0, 0.0), band, art), Rect2())


## **The shadow needs room in the rect before the shader can use it.** A canvas shader only paints
## inside its own primitive, so a figure drawn at exactly its own size could not cast anything past
## its edge — which for this art matters most at the bottom, where the canvas has no padding at all.
func test_a_figure_is_given_room_around_it_for_the_shadow_to_spread_into() -> void:
	var scene := _scene()
	scene.size = Vector2(1732.0, 10.0)
	var figure := ImageTexture.create_from_image(
		Image.create_empty(int(FIGURE.x), int(FIGURE.y), false, Image.FORMAT_RGBA8))
	scene.show_scene(_plate(), 0.97, [
		{"texture": figure, "content": FIGURE_CONTENT, "side": 1},
	])

	var nodes: Array[Node] = []
	for child in scene.get_children():
		if child is ChatCharacter:
			nodes.append(child)
	assert_eq(nodes.size(), 1, "one node per figure, carrying its own shadow material")

	var node := nodes[0] as ChatCharacter
	assert_true(node.material is ShaderMaterial, "the shadow is a shader on the figure itself")
	var canvas := ChatScene.character_canvas_rect(
		ChatScene.character_content_rect(Rect2(Vector2.ZERO, scene.size), FIGURE_CONTENT, 1),
		FIGURE_CONTENT, FIGURE)
	assert_gt(node.size.x, canvas.size.x, "the node is wider than the picture it draws")
	assert_gt(node.size.y, canvas.size.y, "and taller, so the shadow has somewhere to go")
	# And the shader is told how much of the rect is room rather than picture, or it would stretch the
	# figure across the padding instead of leaving it empty.
	var pad := (node.material as ShaderMaterial).get_shader_parameter("pad") as Vector2
	assert_gt(pad.x, 0.0)
	assert_gt(pad.y, 0.0)


## The whole canvas is placed by where the *figure* on it has to land, so a transparent margin never
## pushes the person off the band's bottom edge.
func test_the_canvas_is_positioned_by_the_figure_painted_on_it() -> void:
	var band := Rect2(0.0, 0.0, 1732.0, 448.0)
	var figure := ChatScene.character_content_rect(band, FIGURE_CONTENT, 1)
	var canvas := ChatScene.character_canvas_rect(figure, FIGURE_CONTENT, FIGURE)

	var scale := figure.size.y / FIGURE_CONTENT.size.y
	assert_almost_eq(canvas.size.x, FIGURE.x * scale, 0.001, "the canvas is drawn to the same scale")
	assert_almost_eq(canvas.position.x, figure.position.x - FIGURE_CONTENT.position.x * scale, 0.001,
		"and offset so the figure on it lands where it was placed")
	assert_lt(canvas.position.y, figure.position.y, "its top margin is above the figure's head")
	assert_eq(ChatScene.character_canvas_rect(figure, Rect2(), FIGURE), Rect2(),
		"a content box with no height is no canvas at all")


## The scene takes whoever it is handed, and takes nobody just as readily.
func test_a_scene_can_be_shown_with_and_without_anyone_in_it() -> void:
	var scene := _scene()
	scene.size = Vector2(1732.0, 10.0)
	var figure := ImageTexture.create_from_image(
		Image.create_empty(int(FIGURE.x), int(FIGURE.y), false, Image.FORMAT_RGBA8))

	scene.show_scene(_plate(), 0.97)
	assert_true(scene.has_scene())
	scene.show_scene(_plate(), 0.97, [
		{"texture": figure, "content": FIGURE_CONTENT, "side": 1},
		{"texture": figure, "content": FIGURE_CONTENT, "side": -1},
	])
	assert_true(scene.has_scene(), "and a full stage is still a scene")


func test_a_scene_with_no_picture_asks_for_no_room() -> void:
	var scene := _scene()
	assert_false(scene.has_scene())
	assert_false(scene.visible, "and nothing at all is drawn where there is nothing to show")
	assert_eq(ChatScene.band_height(1000.0, Vector2.ZERO), 0.0, "art with no size has no band")
	assert_eq(ChatScene.source_region(1000.0, 0.0, ART), Rect2())
	assert_eq(ChatScene.source_region(0.0, 320.0, ART), Rect2())
	assert_eq(ChatScene.horizontal_stretch(1000.0, 0.0, ART), 1.0)


# --- meeting the frame -----------------------------------------------------------------------

## The scene reaches back out through the difference between the board's padding and its painted rule,
## so its edges land against the inside of the rule rather than a padding's width in from it.
func test_the_bleed_is_the_padding_less_the_rule() -> void:
	assert_eq(ChatScene.BLEED, UiSkin.CHAT_FRAME_PADDING - UiSkin.CHAT_FRAME_RULE)
	assert_gt(ChatScene.BLEED, 0.0, "there is room to reach into, or the scene cannot meet the rule")


## **The bleed is drawn, not claimed.** The picture starts a bleed above the control's own box, so the
## room it needs *below* that box is its height less the bleed — otherwise every scene would push the
## conversation down by a margin's worth of nothing.
func test_the_scene_claims_only_the_room_below_its_own_top_edge() -> void:
	var scene := _scene()
	scene.size = Vector2(1732.0, 10.0)
	scene.show_scene(_plate(), 0.97)
	assert_true(scene.has_scene())
	assert_true(scene.visible)

	var height := ChatScene.band_height(1732.0 + ChatScene.BLEED * 2.0, ART,
		ChatScene.MIN_SCENE_HEIGHT,
		scene.get_viewport_rect().size.y * ChatScene.MAX_SCENE_SCREEN_FRACTION)
	assert_almost_eq(scene.custom_minimum_size.y, height - ChatScene.BLEED, 0.01)

	scene.clear_scene()
	assert_false(scene.has_scene())
	assert_eq(scene.custom_minimum_size.y, 0.0, "and it gives the room back")


## Nothing between the scene and the board may clip, or the bleed is silently cut off and the picture
## stops meeting the rule on three sides — with no error and no obvious symptom beyond a thin line of
## parchment that should not be there.
func test_nothing_between_the_scene_and_the_board_clips_its_bleed() -> void:
	var dock := ChatDock.new()
	add_child_autofree(dock)
	var node: Node = dock.scene
	while node != null and node != dock.get_parent():
		var control := node as Control
		if control != null:
			assert_false(control.clip_contents,
				"%s clips, which would cut the scene's bleed off" % control.name)
		node = node.get_parent()


# --- the board ------------------------------------------------------------------------------

## While a scene is showing it owns the board's top edge, so the header gives way to it — a title bar
## above the picture would put a strip of parchment between it and the frame it is reaching for.
func test_a_scene_takes_the_boards_top_edge_from_the_header() -> void:
	var dock := ChatDock.new()
	add_child_autofree(dock)
	dock.set_expanded(true)
	var header: Control = dock.get("_header")
	var close: Control = dock.get("_close")
	assert_true(header.visible, "with no scene the board keeps its title bar")
	assert_eq(close.get_parent(), header)

	dock.set_scene(_plate(), 0.97)
	assert_true(dock.has_scene())
	assert_false(header.visible, "the picture is the top of the board now")
	assert_eq(close.get_parent(), dock.scene,
		"and the one close control is carried onto it rather than replaced")

	dock.set_scene(null)
	assert_false(dock.has_scene())
	assert_true(header.visible, "the title bar comes back when the picture goes")
	assert_eq(close.get_parent(), header)


## A collapsed board is the input row and nothing else. The scene is part of the expanded board, so it
## may not add so much as a unit to the strip's height.
func test_a_scene_is_not_counted_into_the_collapsed_strip() -> void:
	var dock := ChatDock.new()
	add_child_autofree(dock)
	dock.set_expanded(false)
	var bare := dock.collapsed_height

	dock.set_scene(_plate(), 0.97)
	dock.set_expanded(false)
	assert_false(dock.scene.visible, "hidden with the rest of the expanded board")
	assert_almost_eq(dock.collapsed_height, bare, 0.01,
		"and the strip is exactly as tall as it was")

	dock.set_expanded(true)
	assert_true(dock.scene.visible, "and back when the board opens")
