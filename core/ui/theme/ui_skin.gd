class_name UiSkin
extends RefCounted

## The painted UI: the ornate button plates and the parchment frame, as ready-made [StyleBoxTexture]s.
##
## **Every texture here is nine-sliced.** These are hand-drawn frames — a metal rail, rounded corners,
## rivets — and a button is asked to be anything from 200 to 600 units wide. Stretching the bitmap
## would smear the corner ornaments and thin the rail unevenly; a nine-patch holds the four corners at
## their drawn size, repeats the edges along each side, and stretches only the flat middle. The
## [code]texture_margin_*[/code] values below are the slice, measured off the art (see
## [constant BUTTON_SLICE] and [constant FRAME_SLICE]) — they are not padding, and changing them to
## "make room for text" is what breaks the corners. Text padding is [code]content_margin_*[/code],
## which is a separate set of numbers.
##
## Colour carries meaning, so the variant is chosen by *role* rather than by taste:
## [constant BROWN] is the ordinary action, [constant GRAY] is unavailable, [constant BLUE] is the one
## thing the screen wants you to do, and [constant GREEN]/[constant RED] confirm and cancel.

enum Variant { BROWN, GRAY, BLUE, GREEN, RED }

const BROWN := Variant.BROWN
const GRAY := Variant.GRAY
const BLUE := Variant.BLUE
const GREEN := Variant.GREEN
const RED := Variant.RED

const BUTTON_TEXTURES := {
	Variant.BROWN: preload("res://core/assets/ui/button_brown.png"),
	Variant.GRAY: preload("res://core/assets/ui/button_gray.png"),
	Variant.BLUE: preload("res://core/assets/ui/button_blue.png"),
	Variant.GREEN: preload("res://core/assets/ui/button_green.png"),
	Variant.RED: preload("res://core/assets/ui/button_red.png"),
}

const FRAME_TEXTURE := preload("res://core/assets/ui/frame2.png")

## The border-only frame that marks out a working area *inside* a page. Its middle is transparent —
## 90% of the file — so whatever it is laid over shows through, which is the point: on a page it
## draws a rule around the content without putting a second sheet of paper on top of the first.
const FRAME_THIN_TEXTURE := preload("res://core/assets/ui/frame_thin.png")
## Its rail is ~4px and the corner curve reaches ~12px; 16 carries the whole curve.
const FRAME_THIN_SLICE := 16.0
const FRAME_THIN_PADDING := 18.0

## The tab strip. Two states, drawn small (96x27 and 89x29), so the slice has to stay under half the
## height — 10 clears the corner on both without the top and bottom patches meeting in the middle.
const TAB_SELECTED_TEXTURE := preload("res://core/assets/ui/tab_selected.png")
const TAB_UNSELECTED_TEXTURE := preload("res://core/assets/ui/tab_unselected.png")
const TAB_SLICE := 10.0
const TAB_PADDING_H := 22.0
const TAB_PADDING_V := 12.0

## A sunken parchment field: dropdowns, and anything else that should read as somewhere a value goes
## rather than something you press. Its border is ~5px, so 10 carries the corner.
const INPUT_TEXTURE := preload("res://core/assets/ui/input_background.png")
const INPUT_SLICE := 10.0
const INPUT_PADDING_H := 16.0
const INPUT_PADDING_V := 10.0

## The progress bar's two halves. Both are 916x78 and share a footprint — the fill's opaque area is
## inset to (12,12)-(904,67), exactly the background's well — so drawing them into the *same* rect
## lands the fill inside the frame with no offsets to keep in step. See [SkinnedProgressBar].
const PROGRESS_BACKGROUND_TEXTURE := preload("res://core/assets/ui/progress_bar_background.png")
const PROGRESS_FILL_TEXTURE := preload("res://core/assets/ui/progress_bar_fill.png")

## The bar's chamfered end caps run to ~18px and its rails are ~12px thick; 22 carries the whole
## chamfer into the corner patch. Drawn at [constant PROGRESS_HEIGHT] nothing stretches vertically —
## only the middle is asked to cover a width the art was not drawn at.
const PROGRESS_SLICE_H := 22.0
const PROGRESS_SLICE_V := 12.0
const PROGRESS_HEIGHT := 78.0

## The button plates are ~344x98 with a rail about 10px thick and a corner radius reaching ~14px.
## The slice takes 14 so the whole rounded corner travels with it.
const BUTTON_SLICE := 14.0

## `frame2.png` is 1496x986 and its corner scroll reaches ~45px at the top-left, ~40px at the
## bottom-right; 56 keeps every flourish inside the corner patch.
##
## It replaced a 210x239 first cut, which the measurements condemned: after slicing, that one had a
## 122x151 middle and the settings page stretched its top rail **17x**, so a 1:1 corner met a
## seventeen-times-magnified edge and the join visibly failed to line up. The middle here is 1384x874,
## which brings the same page down to about 1.5x.
const FRAME_SLICE := 56.0

## Room for the label inside the rail, and for a screen's content inside the frame's parchment.
const BUTTON_PADDING_H := 24.0
const BUTTON_PADDING_V := 12.0
const FRAME_PADDING := 34.0

## The type scale. Four sizes, and screens pick from them rather than inventing numbers — a page whose
## labels, hints and headings were each chosen separately is how a 26pt button ends up sitting next to
## a 16pt label looking like it wandered in from another screen.
const FONT_TITLE := 34
const FONT_HEADING := 26
const FONT_BODY := 20
const FONT_SMALL := 17

## **Two control sizes, and only two.**
##
## [constant BUTTON_HEIGHT] is a *page's* actions — the main menu's list, a dialog's answers, Back and
## Reset at the foot of a screen. Sized for a thumb rather than a mouse, and tall enough to earn the
## plate art: the drawn rail is 10px on a 98px-tall source, so a short button turns a slim rail into a
## thick one.
##
## [constant CONTROL_HEIGHT] is everything that sits *in a row of content* — a dropdown, a field, a
## button belonging to one setting. It matches the body text beside it, which is the whole point: these
## are peers on a line, not the reason the page exists.
const BUTTON_HEIGHT := 72.0
const BUTTON_FONT_SIZE := FONT_HEADING
const CONTROL_HEIGHT := 48.0
const CONTROL_FONT_SIZE := FONT_BODY

## The dark wash a modal lays over whatever it interrupted. Heavy enough that the frame reads as the
## only live thing on screen — a lighter wash left the menu behind it competing for attention.
const SCRIM := Color(0.01, 0.01, 0.02, 0.82)

## Hover lifts the plate, pressed sinks it. The art has no second state drawn, so the state reads as a
## change in light on the same plate rather than a different image — and, with [SkinnedButton], as a
## change in size: bigger under the cursor, smaller under the press.
const HOVER_TINT := Color(1.14, 1.14, 1.14)
const PRESSED_TINT := Color(0.82, 0.82, 0.82)
const HOVER_SCALE := 1.035
const PRESSED_SCALE := 0.975
## Short enough that the plate feels attached to the cursor rather than chasing it.
const HOVER_TIME := 0.09
const PRESSED_TIME := 0.06

## Drop shadows. [StyleBoxTexture] cannot draw one, so it is a [StyleBoxFlat] behind the plate, shaped
## by the same rounded rect the art is drawn on. The radii match the corners in the source art so the
## shadow does not peek out square.
const SHADOW_COLOR := Color(0.03, 0.02, 0.01, 0.55)
## What fills the shadow box behind the plate. It is never seen — the button and frame art are 99.9%
## opaque and cover this rect exactly — but it has to be *drawn*, which is the whole subtlety here.
## See [method shadow_style].
const SHADOW_FILL := Color(0.03, 0.02, 0.01, 1.0)
const BUTTON_SHADOW_SIZE := 7
const BUTTON_SHADOW_OFFSET := Vector2(0, 3)
const BUTTON_CORNER_RADIUS := 9
const FRAME_SHADOW_SIZE := 22
const FRAME_SHADOW_OFFSET := Vector2(0, 9)
const FRAME_CORNER_RADIUS := 6

## Text on the parchment inside [method frame_style]. The shell's near-white [code]TEXT[/code] is for
## dark panels and vanishes on this — anything sitting on the frame has to be written in ink.
const INK := Color(0.16, 0.11, 0.07)
const INK_MUTED := Color(0.16, 0.11, 0.07, 0.6)

## A label on a coloured plate.
const LABEL := Color(0.98, 0.96, 0.92)

## The gray plate is *light*, so a disabled label is written in ink like the parchment rather than in
## the shell's translucent white, which on this plate is very nearly invisible. Fully opaque: the
## fading is [constant DISABLED_ALPHA]'s job, applied to the whole button at once.
const LABEL_DISABLED := Color(0.22, 0.19, 0.16)

## How far a disabled button recedes. Applied as [member CanvasItem.modulate] on the whole control, so
## the plate, its caption and its drop shadow fade together and the button reads as one faded object
## rather than a solid plate with washed-out lettering on it.
const DISABLED_ALPHA := 0.55

## A shadow cast *under* the label, lifting it off the plate.
##
## **[Button] cannot draw this.** Its theme has `font_outline_color`/`outline_size` and nothing else —
## `font_shadow_color` and `shadow_offset_*` exist only on [Label], so overriding them on a button is
## a no-op that fails silently. [SkinnedButton] therefore draws its caption as a real [Label] over an
## empty plate; [method label_style] is what dresses it.
const LABEL_SHADOW := Color(0.05, 0.03, 0.02, 0.75)
const LABEL_SHADOW_OFFSET := Vector2i(0, 3)


## One nine-sliced button plate. [param tint] is applied as [member StyleBoxTexture.modulate_color].
static func button_style(variant: Variant, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURES[variant]
	_slice(style, BUTTON_SLICE)
	style.set_content_margin_all(BUTTON_PADDING_V)
	style.content_margin_left = BUTTON_PADDING_H
	style.content_margin_right = BUTTON_PADDING_H
	style.modulate_color = tint
	return style


## The parchment frame a screen's contents sit on.
##
## Its middle **stretches** where the button plates tile. After a 44px slice `frame1` has only a
## 122x151 middle left, and a menu or a settings page is several times that in both directions — tiled,
## the paper's grain repeats about four times over and the seams read as banding across the panel.
## Stretching a broadly even parchment is invisible; tiling it is not. The plates keep [code]TILE_FIT[/code]
## because their middle is a fine rail grain that thins out when stretched, and they are never asked to
## cover more than about twice their drawn width.
static func frame_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = FRAME_TEXTURE
	_slice(style, FRAME_SLICE, StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(FRAME_PADDING)
	return style


## Dress [param button] in [param variant], with its hover/pressed lighting and the disabled plate.
##
## The disabled plate is always [constant GRAY] whatever the variant: "you cannot do this" has to read
## the same everywhere, and a dimmed blue plate still looks like the primary action.
static func apply_button(button: Button, variant: Variant) -> void:
	button.add_theme_stylebox_override("normal", button_style(variant))
	button.add_theme_stylebox_override("hover", button_style(variant, HOVER_TINT))
	button.add_theme_stylebox_override("pressed", button_style(variant, PRESSED_TINT))
	button.add_theme_stylebox_override("focus", button_style(variant, HOVER_TINT))
	button.add_theme_stylebox_override("disabled", button_style(Variant.GRAY))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, LABEL)
	button.add_theme_color_override("font_disabled_color", LABEL_DISABLED)


## The border-only frame for a working area inside a page. Stretched, not tiled, for the same reason
## [method frame_style] is: its middle is a plain rule, and a repeat would show as a seam in it.
static func thin_frame_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = FRAME_THIN_TEXTURE
	_slice(style, FRAME_THIN_SLICE, StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(FRAME_THIN_PADDING)
	return style


## One tab plate. The unselected one is the dark wood, the selected one the parchment that continues
## into the page below it.
static func tab_style(selected: bool) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = TAB_SELECTED_TEXTURE if selected else TAB_UNSELECTED_TEXTURE
	_slice(style, TAB_SLICE, StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(TAB_PADDING_V)
	style.content_margin_left = TAB_PADDING_H
	style.content_margin_right = TAB_PADDING_H
	return style


## A sunken field for a value — a dropdown's background, not a button's plate.
static func input_style(tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = INPUT_TEXTURE
	_slice(style, INPUT_SLICE, StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(INPUT_PADDING_V)
	style.content_margin_left = INPUT_PADDING_H
	style.content_margin_right = INPUT_PADDING_H
	style.modulate_color = tint
	return style


## Dress an [OptionButton] (or any [Button] acting as a field) as a sunken parchment input. Its
## lettering is ink, not the plates' near-white: the field is light.
static func apply_input(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, input_style(
			HOVER_TINT if state in ["hover", "focus"] else Color.WHITE))
	button.add_theme_stylebox_override("disabled", input_style(Color(1, 1, 1, DISABLED_ALPHA)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", INK_MUTED)
	# A field is a peer of the text beside it, so it takes the row's size, not a button's.
	button.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	button.custom_minimum_size.y = CONTROL_HEIGHT


## Dress a button's caption: the plate's lettering, with the shadow [Button] itself cannot draw.
## [param disabled] picks the ink used on the gray plate.
## A disabled caption casts none: the shadow is what lifts lettering off the plate, and a control
## that is meant to have receded should be flat against it.
static func label_style(label: Label, font_size: int, disabled: bool = false) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LABEL_DISABLED if disabled else LABEL)
	label.add_theme_color_override("font_shadow_color",
		Color(LABEL_SHADOW, 0.0) if disabled else LABEL_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0 if disabled else LABEL_SHADOW_OFFSET.x)
	label.add_theme_constant_override("shadow_offset_y", 0 if disabled else LABEL_SHADOW_OFFSET.y)


## A drop shadow to put on a container *behind* the thing casting it. [StyleBoxTexture] has no shadow
## of its own, which is the whole reason this exists.
##
## [b]`draw_center` must stay true.[/b] The obvious way to write this — centre off, so only the shadow
## shows — draws no shadow at all in Godot 4.7: turning the centre off skips the shadow with it. And
## the shadow is not a ring; it is a filled rounded rect the size of the box plus the blur, so a
## transparent fill leaves a dark slab showing through the middle. Both failures were reproduced
## side by side before landing this. The way that works is an opaque fill ([constant SHADOW_FILL])
## that the plate in front covers completely, leaving only the blur beyond its edges visible.
static func shadow_style(size: int, offset: Vector2, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = true
	style.bg_color = SHADOW_FILL
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = size
	style.shadow_offset = offset
	style.set_corner_radius_all(radius)
	# The shadow belongs to the plate in front of it, so the container must not inset that plate.
	style.set_content_margin_all(0.0)
	return style


static func button_shadow_style() -> StyleBoxFlat:
	return shadow_style(BUTTON_SHADOW_SIZE, BUTTON_SHADOW_OFFSET, BUTTON_CORNER_RADIUS)


static func frame_shadow_style() -> StyleBoxFlat:
	return shadow_style(FRAME_SHADOW_SIZE, FRAME_SHADOW_OFFSET, FRAME_CORNER_RADIUS)


## The nine-patch itself: the same slice on all four sides. [param mode] decides what happens to the
## edges and the middle — tiling keeps a fine grain at its drawn density, stretching keeps a broad
## texture seamless. Which one is right depends on how far past its drawn size the art is asked to go;
## see [method frame_style] and [method button_style].
static func _slice(style: StyleBoxTexture, margin: float,
		mode: StyleBoxTexture.AxisStretchMode = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT) -> void:
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.axis_stretch_horizontal = mode
	style.axis_stretch_vertical = mode
