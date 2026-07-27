class_name ShellPalette
extends RefCounted

## The few colours the app shell paints itself with.
##
## Not a theme — there isn't one yet. Every screen builds its UI in code and paints its own
## background, and until a real [Theme] exists these are the values they agree on. Naming them here
## is what keeps a screen from quietly drifting a shade off, or from having no background at all and
## falling through to Godot's light default, which is what the game screen used to do: the shell
## went dark, the game went grey, and the two read as different applications.
##
## When a real theme lands, this is what it replaces.

## The standard page: menus, the new-game wizard, the load screen, the game itself.
const BACKGROUND := Color(0.07, 0.07, 0.10)

## Deliberately darker, for the moments before the shell proper — the eye should settle *into* the
## app rather than be handed full brightness at once.
const BACKGROUND_SPLASH := Color(0.05, 0.05, 0.08)
const BACKGROUND_LOADING := Color(0.06, 0.06, 0.09)


## The painted settlement behind the menu and the loading screen.
const ART := preload("res://core/assets/main_menu_background.png")

## Where the keep stands in the painting, as a fraction of its width — the point the crop keeps in
## the middle of the screen.
##
## The art is landscape (2752x1536) and the app is portrait, so it is always cropped horizontally:
## on a phone only about the middle third survives. Cropping around the image's *midpoint* would be
## an arbitrary choice that happens to clip the right-hand towers, because the keep does not sit at
## the middle — it sits here, a little right of it. Framing on this instead means the settlement is
## centred on every aspect the game runs at, and what falls outside (the river, the bridge, the
## outlying farms) falls outside deliberately.
const ART_FOCUS_X := 0.58

## How far the art is dimmed toward [constant BACKGROUND] behind the shell's controls. The painting
## is bright — sunlit fields, white cloud — and the shell's text and buttons are light-on-dark, so
## without this the menu is unreadable over the sky. Tuned on the device, not guessed: the art still
## reads as a place, the labels still read as labels.
const ART_SCRIM := Color(0.05, 0.05, 0.08, 0.62)


## A panel for controls that sit over [method paint_art], so they read against the painting rather
## than competing with it. Slightly darker than the scrim and inset from its contents.
static func plate_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.72)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	return style


## Add a full-rect background of [param color] as [param screen]'s first child, behind everything
## else it builds. Call it before adding any content.
static func paint(screen: Control, color: Color = BACKGROUND) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nothing in a background should ever eat a click meant for the controls in front of it.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	return bg


## Add the painted background + its scrim as [param screen]'s first children. Call before content.
##
## **Cover, never stretch**, framed on [constant ART_FOCUS_X]. The art cannot fill a portrait screen
## and keep its proportions, so it is scaled to cover and cropped — never distorted — and then slid
## so the keep sits in the middle rather than wherever the image's midpoint happened to put it.
## `KEEP_ASPECT_COVERED` cannot express that (it always centres the *image*), hence the manual size
## and offset here. The offset is clamped so the crop can never expose an edge.
static func paint_art(screen: Control) -> void:
	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(art)
	var reframe := func() -> void: _frame_art(art, screen.size)
	reframe.call()
	# The screen has no real size during `_ready`, so the first useful framing arrives with `resized`.
	screen.resized.connect(reframe)

	var scrim := ColorRect.new()
	scrim.color = ART_SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(scrim)


## Scale [param art] to cover [param view] and position it so [constant ART_FOCUS_X] lands in the
## middle, clamped to the edges so no gap can appear.
static func _frame_art(art: TextureRect, view: Vector2) -> void:
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var texture_size := Vector2(ART.get_size())
	var cover := maxf(view.x / texture_size.x, view.y / texture_size.y)
	var drawn := texture_size * cover
	art.size = drawn
	art.position = Vector2(
		clampf(view.x * 0.5 - drawn.x * ART_FOCUS_X, view.x - drawn.x, 0.0),
		clampf(view.y * 0.5 - drawn.y * 0.5, view.y - drawn.y, 0.0))
