extends GutTest

## The painted UI textures, checked for the one defect that is invisible in an image viewer and
## glaring in the game.
##
## **Why this test exists.** `frame2.png` shipped with a 1px-wide, 40px-tall fully transparent
## scratch at (26, 395)-(26, 434) — a stray erase in the source art, over flat parchment grain, and
## so completely unnoticeable in any tool that shows the image on a light background. In the game it
## was a hard black hairline on the menu, the settings page and the exit modal, because what sits
## *behind* a frame is [method UiSkin.frame_shadow_style]'s opaque near-black fill. That fill is
## deliberate — Godot 4.7 draws no shadow at all without it ([method UiSkin.shadow_style] explains) —
## and it is invisible only for as long as the art in front is genuinely opaque. A hole in the art is
## therefore not a cosmetic flaw in the art; it is a hole through to the shadow box.
##
## The art is redrawn and re-exported by hand, so the defect can come back with the next export of
## any of these files. That is what makes this worth a test rather than a one-time fix.

## Alpha at or below this is a hole. The textures are painted with soft edges, so this asks for
## *fully* transparent rather than merely faint — an antialiased edge pixel is not a defect.
const HOLE_ALPHA := 8
## And what counts as solid on either side of one.
const OPAQUE_ALPHA := 250


func test_no_painted_texture_has_a_scratch_through_it() -> void:
	var checked := 0
	for path in _ui_textures():
		var image := (load(path) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		checked += 1
		var scratch := _find_scratch(image)
		assert_eq(scratch, Vector2i(-1, -1),
			"%s is solid at (%d, %d)" % [path.get_file(), scratch.x, scratch.y])
	assert_gt(checked, 10, "and the scan actually found the textures to check")


## The first pixel that is transparent while the two pixels *across* it are solid — a scratch one
## pixel wide, in either direction. Deliberately not "any transparent pixel surrounded by opaque
## ones": these scratches run in a line, so a pixel in the middle of one has transparent neighbours
## along it, and requiring all four sides to be solid finds only the two end pixels of a 40px run.
##
## A texture drawn with a genuinely open middle passes: [constant UiSkin.FRAME_THIN_TEXTURE] is 90%
## transparent, and no pixel in that opening has solid art on both sides of it.
func _find_scratch(image: Image) -> Vector2i:
	for y in range(2, image.get_height() - 2):
		for x in range(2, image.get_width() - 2):
			if image.get_pixel(x, y).a8 > HOLE_ALPHA:
				continue
			var across_x := (image.get_pixel(x - 1, y).a8 >= OPAQUE_ALPHA
				and image.get_pixel(x + 1, y).a8 >= OPAQUE_ALPHA)
			var across_y := (image.get_pixel(x, y - 1).a8 >= OPAQUE_ALPHA
				and image.get_pixel(x, y + 1).a8 >= OPAQUE_ALPHA)
			if across_x or across_y:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _ui_textures() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://core/assets/ui")
	assert_not_null(dir, "the painted UI textures are where this test expects them")
	if dir == null:
		return paths
	for file in dir.get_files():
		# Exported builds leave a `.import` beside the source and read a `.remap`; asking for the
		# source path is what works in both, which the Android export bug taught the hard way.
		if file.ends_with(".png"):
			paths.append("res://core/assets/ui/".path_join(file))
	paths.sort()
	return paths
