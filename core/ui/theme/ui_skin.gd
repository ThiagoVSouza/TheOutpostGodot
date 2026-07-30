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
## Just the drawn rail, for contents meant to sit *against* the frame rather than inside it. See
## [method thin_frame_style].
const FRAME_THIN_RAIL := 5.0

## The tab strip. Two states, drawn small (96x27 and 89x29), so the slice has to stay under half the
## height — 10 clears the corner on both without the top and bottom patches meeting in the middle.
const TAB_SELECTED_TEXTURE := preload("res://core/assets/ui/tab_selected.png")
const TAB_UNSELECTED_TEXTURE := preload("res://core/assets/ui/tab_unselected.png")
const TAB_SLICE := 10.0
## Tighter than a button's, and the tab strip has its own font size below, because **a tab strip has
## to fit whole**. Godot's answer when it does not is to hide the overflow behind two little scroll
## arrows, which on the settings page meant the Controls tab silently vanished — a destination the
## player has no way of knowing is there. Four tabs at [constant FONT_BODY] and 22 wanted 656 of the
## 572 a phone has; at [constant TAB_FONT_SIZE] and 16 they want 512.
const TAB_PADDING_H := 16.0
const TAB_PADDING_V := 12.0
## Navigation chrome rather than something to read at length, and the words on it are short and
## high-contrast, so it is the one place that takes the small size without straining.
const TAB_FONT_SIZE := FONT_SMALL

## A sunken parchment field: dropdowns, and anything else that should read as somewhere a value goes
## rather than something you press. Its border is ~5px, so 10 carries the corner.
const INPUT_TEXTURE := preload("res://core/assets/ui/input_background.png")
const INPUT_SLICE := 10.0
const INPUT_PADDING_H := 16.0
const INPUT_PADDING_V := 10.0

## The chevron on a dropdown. Godot draws an [OptionButton]'s arrow as its own theme *icon* rather
## than as part of the field's stylebox, so a skinned field with no icon override keeps the stock
## light-grey one, which on parchment is very nearly invisible.
##
## Two of them, and the second is the point: the arrow turns over while the list is open. The down
## chevron says "there is more below"; leaving it pointing down with the list already open says
## nothing, and the flip is the cheapest possible way to show that clicking again closes it. Wired in
## [method apply_input].
const SELECT_ARROW_TEXTURE := preload("res://core/assets/ui/select_arrow.png")
const SELECT_ARROW_UP_TEXTURE := preload("res://core/assets/ui/select_arrow_up.png")

## The toggle, drawn as one image per state rather than a track with a knob laid over it — so the
## knob does not slide, it simply is on the other side. Green with the knob right is on; red with it
## left is off, which means the state reads from the colour across the room and from the knob's
## position up close.
const TOGGLE_ON_TEXTURE := preload("res://core/assets/ui/toggle_on.png")
const TOGGLE_OFF_TEXTURE := preload("res://core/assets/ui/toggle_off.png")

## Drawn at 194x85 and 195x85 — over a third the height of the settings frame, and far too big for a
## row that is [constant CONTROL_HEIGHT] tall. A [CheckButton] draws its check icon at the texture's
## own size (`icon_max_width` governs a [Button]'s *icon*, not this), so the size has to be settled
## before the theme sees it: [method scaled_texture] resamples both, which also reconciles the 1px the
## two sources differ by.
##
## **Derived from [constant CONTROL_HEIGHT] rather than written down.** It was a fixed 110x48 at
## first, and when the row height grew the toggle stayed behind and started reading as a small object
## someone had dropped into a taller row. A toggle *is* a row's control; its size is that fact, not a
## separate decision.
const TOGGLE_ASPECT := 194.0 / 85.0

## The slider's three parts: the groove, the gold that fills it up to the value, and the knob.
##
## The groove and the fill are both 130x10 and **share a footprint** — the fill's gold band is inset
## to (4,3)-(127,7), exactly the groove's well — which is the same arrangement
## [constant PROGRESS_FILL_TEXTURE] uses and for the same payoff: Godot draws both into rects that
## start at the control's left edge, so with matching footprints the gold lands inside the groove with
## no offsets to keep in step.
const SLIDER_TEXTURE := preload("res://core/assets/ui/slider.png")
const SLIDER_FILL_TEXTURE := preload("res://core/assets/ui/slider_fill.png")
const SLIDER_GRABBER_TEXTURE := preload("res://core/assets/ui/slider_button.png")

## The groove's rounded ends run to ~4px and the gold's taper to about the same; 6 carries both. The
## vertical slice has to stay under half of 10, and 4 leaves a 2px middle.
const SLIDER_SLICE_H := 6.0
const SLIDER_SLICE_V := 4.0

## The art is 10 tall; drawn at that, it was a hairline beside a [constant CONTROL_HEIGHT] row and the
## knob looked threaded onto a wire. [constant SLIDER_HEIGHT] is what it is drawn at now.
##
## **Stretched by the nine-patch, not resampled** — the opposite choice from the scrollbar, and for
## the opposite reason. The scrollbar was being made *smaller*, where a nine-patch would have shrunk
## the corner patches and thinned the moulding unevenly. Here the groove is being made *bigger*, and
## its 4px top and bottom edges are exactly what a nine-patch holds at their drawn size while
## stretching only the 2px interior — which is a flat gradient, so nothing in it can smear
## visibly. Resampling would soften the moulding for no gain.
const SLIDER_ART_HEIGHT := 10.0
const SLIDER_HEIGHT := 20.0

## The knob is a theme icon, so it cannot be stretched by a stylebox and has to be resampled to keep
## its footing against the thicker groove. 26x28 becomes 34x36.
const SLIDER_GRABBER_SCALE := 1.3

## The scrollbar: a recessed channel, a stone bar that rides in it, and a plate button at each end.
##
## The art is drawn 54 across. That is what it first shipped at — nothing stretched, but on both a
## phone and a desktop window it read as a fat band down the side of the page, taking a twelfth of a
## 720-wide viewport for a control nobody looks at. [constant SCROLLBAR_SIZE] is the width it is
## actually drawn at now, and every piece is resampled to match rather than squeezed by the
## nine-patch: compressing the cross axis of a [StyleBoxTexture] shrinks the corner patches too, which
## thins the channel's moulding unevenly, and the arrow plates are theme icons that ignore the
## stylebox entirely. See [method _scrollbar_texture].
const SCROLL_TRACK_TEXTURES := {true: preload("res://core/assets/ui/scrollbar_vertical.png"),
	false: preload("res://core/assets/ui/scrollbar_horizontal.png")}
const SCROLL_GRABBER_TEXTURES := {true: preload("res://core/assets/ui/scrollbar_vertical_bar.png"),
	false: preload("res://core/assets/ui/scrollbar_horizontal_bar.png")}
## The four arrow plates. Named for the direction they point rather than for the scrollbar, because
## the scrollbar is not the only thing that steps through something: [CardPager] uses the sideways
## pair for its own arrows. The legacy app shipped a second, near-identical pair for exactly that job
## and porting them would have put two hand-drawn arrows of slightly different weight on the same
## screen.
const ARROW_UP_TEXTURE := preload("res://core/assets/ui/scrollbar_button_up.png")
const ARROW_DOWN_TEXTURE := preload("res://core/assets/ui/scrollbar_button_down.png")
const ARROW_LEFT_TEXTURE := preload("res://core/assets/ui/scrollbar_button_left.png")
const ARROW_RIGHT_TEXTURE := preload("res://core/assets/ui/scrollbar_button_right.png")

## Godot calls these decrement/increment; on a vertical bar that is up/down, on a horizontal one
## left/right. Keyed `[vertical][decrement]`.
const SCROLL_ARROW_TEXTURES := {
	true: {true: ARROW_UP_TEXTURE, false: ARROW_DOWN_TEXTURE},
	false: {true: ARROW_LEFT_TEXTURE, false: ARROW_RIGHT_TEXTURE},
}

## The size the art was drawn at, and the size it is used at. Everything else about the scrollbar is
## derived from the ratio, so this is the one number to turn if it wants to be slimmer again.
const SCROLLBAR_ART_SIZE := 54.0
const SCROLLBAR_SIZE := 36.0

## **These four are measured on the art, at the size it was drawn**, and are scaled to the drawn size
## alongside the textures — see [method _scrollbar_scale]. Keeping them in the space they were
## measured in is what lets [constant SCROLLBAR_SIZE] be turned without re-measuring anything.
##
## The track's end caps run to ~13px along its length before the channel settles into a flat dark
## groove; 14 carries the whole cap. The channel is what stretches, and it is featureless, so it
## stretches invisibly however tall the page is.
const SCROLL_TRACK_SLICE := 14.0

## The bar is 27x100 with a ~6px moulding around it and a cap detail reaching ~8px at each end. It
## only ever stretches along its length — how far depends on how much of the page is showing — so 12
## across the ends and 7 down the sides is what keeps the moulding at its drawn thickness.
const SCROLL_GRABBER_SLICE_LONG := 12.0
const SCROLL_GRABBER_SLICE_CROSS := 7.0

## The bar is drawn 27 across against the track's 54, because it is a thing that *rides in* the
## channel rather than covering the whole rail — the channel itself is only about 19 wide, so 27 sits
## in the groove and laps a little onto the moulding either side, which is where the art puts it.
##
## Godot gives the grabber the bar's full width and offers no way to inset it, so the inset is a
## **negative** [code]expand_margin[/code]: [method StyleBox.draw] adds the expand margins to the rect
## it was handed, and a negative one therefore shrinks it. Without this the 27-wide art is stretched
## across the whole bar and the moulding down its sides doubles in thickness.
const SCROLL_GRABBER_WIDTH := 27.0

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
##
## **These are viewport units, and the phone is what sets them.** The project renders a 720-wide
## viewport with `canvas_items` stretch, so on a 1080-wide device it is drawn at 1.5x; that screen
## reports 450dpi, or 2.8125 device pixels per dp. One viewport unit is therefore
## `1.5 / 2.8125 = 0.53` dp, and the scale has to be read in dp to mean anything:
##
## [codeblock]
##            was    →  now      dp on the phone   Android's floor
##   TITLE     34    →  46       18.1 → 24.5
##   HEADING   26    →  36       13.9 → 19.2       14sp for a button caption
##   BODY      20    →  30       10.7 → 16.0       14sp, 16sp to read comfortably
##   SMALL     17    →  24        9.1 → 12.8       12sp
## [/codeblock]
##
## Every rung of the old scale sat under the floor for its job, body text worst of all — this is a
## text-heavy game and its prose was rendering at eleven dp. The desktop window is scaled *down* from
## the same base (a 1280x720 window works out at 0.56x), so it was undersized there too, just less
## obviously.
const FONT_TITLE := 46
const FONT_HEADING := 36
const FONT_BODY := 30
const FONT_SMALL := 24

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
## Both grew with the type scale — a taller caption needs a taller plate — and the growth fixed a
## second thing that was never right: at 72 the page's own actions were a 38dp tap target, under
## Android's 48dp. At 92 they clear it. A row's controls still do not (34dp), and that is the
## accepted trade: making every dropdown 48dp tall would push a settings row past a fifth of the
## screen.
const BUTTON_HEIGHT := 92.0
const BUTTON_FONT_SIZE := FONT_HEADING
const CONTROL_HEIGHT := 64.0
const CONTROL_FONT_SIZE := FONT_BODY

## The dark wash a modal lays over whatever it interrupted. Heavy enough that the frame reads as the
## only live thing on screen — a lighter wash left the menu behind it competing for attention.
const SCRIM := Color(0.01, 0.01, 0.02, 0.82)

## A badge's wash and hairline. Both are ink at low alpha rather than a colour of their own: a badge
## says "this card gives you Trade", which is a footnote to the card, not a second accent competing
## with the one thing on the screen that is actually coloured — the selected plate.
const BADGE_FILL := Color(0.16, 0.11, 0.07, 0.08)
const BADGE_BORDER := Color(0.16, 0.11, 0.07, 0.28)
const BADGE_RADIUS := 4
const BADGE_PADDING_H := 10.0
const BADGE_PADDING_V := 3.0

## Palette swatches and flag thumbnails use a hard ring for selection: unlike a prose card, these
## cells are small enough that a glow would blur into the colour being judged. The neutral border
## also keeps white and black swatches visible against parchment before either is selected.
const PICKER_BORDER := Color(0.16, 0.11, 0.07, 0.55)
const PICKER_SELECTED := Color(0.20, 0.48, 0.82, 1.0)
const PICKER_FILL := Color(0.82, 0.75, 0.61, 0.32)
const PICKER_RADIUS := 6
const PICKER_BORDER_WIDTH := 2
const PICKER_SELECTED_WIDTH := 5

## Selection is [constant CARD_GLOW_COLOR] around the card, not a tint on it — see that constant. The
## plate itself keeps its own colour in every state, so the only thing the pointer changes is the
## ordinary hover lift.

## A card's own shadow, lifting it off the page. **Centred, not dropped**: a card fills most of the
## step and an offset shadow on something that large reads as the card having come unstuck rather
## than as depth. Small, for the same reason — the card is big enough that a little separation is
## plenty.
const CARD_SHADOW_SIZE := 8
const CARD_CORNER_RADIUS := 6
## The sunken field a card wears is transparent for its outermost two pixels; three clears them. See
## [method shadow_style].
const CARD_SHADOW_INSET := 3.0

## The selected card, said with light instead of paint. Tinting the plate blue worked but cost the
## painting: the card's whole face went cool, and the artwork — the thing the player is actually
## choosing between — went with it. A glow leaves every pixel of the card alone and puts the signal
## in the space around it.
##
## Reusing [method shadow_style] rather than inventing a second mechanism: a glow *is* a shadow that
## is not dark and does not fall to one side.
## Light, not a border. At full strength it stopped reading as a glow and started reading as a hard
## blue rule drawn round the card — the tint problem again, one step out. Half the alpha and a
## slightly tighter spread leaves it clearly the chosen card without anything on screen looking
## outlined.
const CARD_GLOW_COLOR := Color(0.40, 0.68, 1.0, 0.5)
const CARD_GLOW_SIZE := 16

## The arrow plates' corners are cut in by six transparent pixels, so their shadow box needs the
## deepest inset of any here — this is the one that was drawing a black bar down each side.
##
## **The size has to pay for the inset.** Seven of those pixels are spent getting the box back under
## the paint, so a shadow the same size as a button's had two left to show and the arrows looked
## flat. This is [constant BUTTON_SHADOW_SIZE] plus the inset, which puts the same amount of blur
## outside the plate as every other button on the screen has.
const ARROW_SHADOW_INSET := 7.0
const ARROW_SHADOW_SIZE := BUTTON_SHADOW_SIZE + int(ARROW_SHADOW_INSET)
const ARROW_CORNER_RADIUS := 8

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

## The hairline under a section heading, and between items in a list. Ink, well short of the muted
## text above it: a rule that competes with the heading it belongs to is a rule drawn too dark.
const RULE := Color(0.16, 0.11, 0.07, 0.3)

## The wash under a hovered item in a dropdown's list, and how far Godot's own radio marks are taken
## down to read on parchment. The marks are drawn near-white; a fifth of that is ink.
const POPUP_HOVER := Color(0.16, 0.11, 0.07, 0.16)
const POPUP_MARK_TINT := Color(0.2, 0.2, 0.2)
const POPUP_ITEM_SEPARATION := 10

## Marks a control whose pointer shape someone chose on purpose, so [method watch_cursors] leaves it
## alone. See the note there for why the shape itself cannot carry that.
const CURSOR_META := "outpost_cursor"


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
## [param padding] is how far inside the rail the contents are held. The default keeps text clear of
## it; a caller that wants something to *reach* the rail — a scrollbar running the full side of the
## frame — asks for [constant FRAME_THIN_RAIL] instead and pads its own contents.
static func thin_frame_style(padding: float = FRAME_THIN_PADDING) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = FRAME_THIN_TEXTURE
	_slice(style, FRAME_THIN_SLICE, StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(padding)
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
##
## An [OptionButton] also gets the painted chevron, and gets it turned over while its list is open —
## see [constant SELECT_ARROW_TEXTURE]. Anything else (a rebind button, say) simply has no arrow to
## dress, and the icon override is skipped rather than set on a control that would ignore it.
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
	# **A field must never be as wide as its longest value.** A [Button]'s minimum width is its whole
	# caption, so a field left to itself makes its text the minimum width of its row, then of the
	# page — and a Godot container does not clip, it overflows. Width belongs to the layout; a field
	# takes what it is given and trims what does not fit.
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if button is OptionButton:
		# And an [OptionButton] is worse than a [Button] here, in a way `clip_text` does not touch:
		# `fit_to_longest_item` is **on by default**, so its minimum width is the widest entry in the
		# list whatever is currently showing — a value the player may never even select. That is
		# exactly how one entry, "Average — balanced narration", pushed the whole settings page 72
		# units off the right of a 720-wide phone the moment the type scale grew. The page had no say
		# in it, and no amount of trimming the *shown* text would have helped.
		(button as OptionButton).fit_to_longest_item = false
		button.add_theme_constant_override("icon_max_width", 36)
		_apply_select_arrow(button as OptionButton)
		_apply_select_popup(button as OptionButton)


## One arrow plate, as a stylebox. Not nine-sliced and not stretched: the art is drawn at its own
## size, which is what [method arrow_button] asks for.
static func arrow_style(left: bool, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ARROW_LEFT_TEXTURE if left else ARROW_RIGHT_TEXTURE
	style.modulate_color = tint
	return style


## An arrow plate that steps a list along — a [SkinnedButton], so it answers the pointer the way every
## other button on the screen does: a shadow under it, a lift in the light, and a change in size under
## the press. It was a [TextureButton] first, which can do the light and neither of the others, and the
## result was the one control on the page that felt dead to the touch.
static func arrow_button(left: bool) -> SkinnedButton:
	var texture: Texture2D = ARROW_LEFT_TEXTURE if left else ARROW_RIGHT_TEXTURE
	return SkinnedButton.create_bare(arrow_style(left), arrow_style(left, HOVER_TINT),
		arrow_style(left, PRESSED_TINT), texture.get_size(), arrow_shadow_style())


## A card's shadow. See [method shadow_style] for why the box behind a plate has to be drawn at all,
## and why it is inset.
static func card_shadow_style() -> StyleBoxFlat:
	return shadow_style(CARD_SHADOW_SIZE, Vector2.ZERO, CARD_CORNER_RADIUS, CARD_SHADOW_INSET)


## The same shadow in blue and a little wider: what a chosen card sits in.
static func card_glow_style() -> StyleBoxFlat:
	var style := shadow_style(CARD_GLOW_SIZE, Vector2.ZERO, CARD_CORNER_RADIUS, CARD_SHADOW_INSET)
	style.shadow_color = CARD_GLOW_COLOR
	return style


## An arrow plate's shadow, inset past its transparent corners.
static func arrow_shadow_style() -> StyleBoxFlat:
	# The same drop as a captioned plate, so an arrow sits on the page at the same height as the
	# buttons around it rather than looking pressed into it.
	return shadow_style(ARROW_SHADOW_SIZE, BUTTON_SHADOW_OFFSET, ARROW_CORNER_RADIUS,
		ARROW_SHADOW_INSET)


## A short tag on a card — "Coins", "Trade". Ink on a faint wash rather than a plate: there are two
## or three of them in a row and three little painted buttons under a card would read as things to
## press.
static func badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_FILL
	style.border_color = BADGE_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(BADGE_RADIUS)
	style.content_margin_left = BADGE_PADDING_H
	style.content_margin_right = BADGE_PADDING_H
	style.content_margin_top = BADGE_PADDING_V
	style.content_margin_bottom = BADGE_PADDING_V
	return style


## One painted colour chip. [param selected] adds the blue pick-one ring without changing the colour
## itself, so selecting a chip never makes the value being compared look different.
static func swatch_style(color: Color, selected: bool, tint: Color = Color.WHITE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		clampf(color.r * tint.r, 0.0, 1.0),
		clampf(color.g * tint.g, 0.0, 1.0),
		clampf(color.b * tint.b, 0.0, 1.0),
		color.a)
	style.border_color = PICKER_SELECTED if selected else PICKER_BORDER
	style.set_border_width_all(PICKER_SELECTED_WIDTH if selected else PICKER_BORDER_WIDTH)
	style.set_corner_radius_all(PICKER_RADIUS)
	style.set_content_margin_all(0.0)
	return style


## The frame behind a square pattern/emblem sample. The sample itself is a shader child inset from
## this border, so selection can be drawn without covering fine mask detail.
static func thumbnail_style(selected: bool, tint: Color = Color.WHITE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		clampf(PICKER_FILL.r * tint.r, 0.0, 1.0),
		clampf(PICKER_FILL.g * tint.g, 0.0, 1.0),
		clampf(PICKER_FILL.b * tint.b, 0.0, 1.0),
		PICKER_FILL.a)
	style.border_color = PICKER_SELECTED if selected else PICKER_BORDER
	style.set_border_width_all(PICKER_SELECTED_WIDTH if selected else PICKER_BORDER_WIDTH)
	style.set_corner_radius_all(PICKER_RADIUS)
	style.set_content_margin_all(0.0)
	return style


static func apply_thumbnail(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", thumbnail_style(selected))
	button.add_theme_stylebox_override("hover", thumbnail_style(selected, HOVER_TINT))
	button.add_theme_stylebox_override("pressed", thumbnail_style(true))
	button.add_theme_stylebox_override("hover_pressed", thumbnail_style(true, HOVER_TINT))
	button.add_theme_stylebox_override("focus", thumbnail_style(true, HOVER_TINT))
	button.add_theme_stylebox_override("disabled", thumbnail_style(selected,
		Color(1, 1, 1, DISABLED_ALPHA)))


## Dress a [LineEdit] as the same sunken parchment field a dropdown wears, so a name the player types
## and a value they pick read as the same kind of thing.
##
## Not folded into [method apply_input]: that takes a [Button], and a [LineEdit] shares none of its
## theme — different stylebox names (`read_only`, not `disabled`), and a caret and selection colours a
## button has no use for. The *look* is shared; the wiring cannot be.
##
## The pointer is left alone on purpose. [method watch_cursors] skips [LineEdit] because Godot already
## gives it an I-beam, which is the right answer for text and the wrong one for everything else here.
static func apply_line_edit(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal", input_style())
	field.add_theme_stylebox_override("focus", input_style(HOVER_TINT))
	field.add_theme_stylebox_override("read_only", input_style(Color(1, 1, 1, DISABLED_ALPHA)))
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", INK_MUTED)
	field.add_theme_color_override("font_uneditable_color", INK_MUTED)
	# The caret has to be ink too — the stock one is near-white and vanishes on parchment, so the
	# player cannot see where they are typing.
	field.add_theme_color_override("caret_color", INK)
	field.add_theme_color_override("font_selected_color", LABEL)
	field.add_theme_color_override("selection_color", Color(INK, 0.4))
	field.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	field.custom_minimum_size.y = CONTROL_HEIGHT


## A card the player picks one of: the wizard's backgrounds and locations, and anything else that is a
## choice made by pressing rather than by opening a list.
##
## Selection is not drawn here at all: it is [method card_glow_style], put on the container *behind*
## the card by whoever builds it. A card carries an image and a paragraph, and there is nowhere on its
## face to put a mark that does not fight them — so the mark goes in the space around it instead. Use
## with `toggle_mode` and a [ButtonGroup].
##
## `hover_pressed` is set as well as `hover`. Without it, moving the pointer over the *already*
## selected card drops it back to the plain hover plate — harmless now that selection is the glow
## rather than the plate, but it would still flicker under the pointer.
static func apply_card(button: Button) -> void:
	button.add_theme_stylebox_override("normal", input_style())
	button.add_theme_stylebox_override("hover", input_style(HOVER_TINT))
	button.add_theme_stylebox_override("pressed", input_style())
	button.add_theme_stylebox_override("hover_pressed", input_style(HOVER_TINT))
	button.add_theme_stylebox_override("focus", input_style(HOVER_TINT))
	button.add_theme_stylebox_override("disabled", input_style(Color(1, 1, 1, DISABLED_ALPHA)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", INK_MUTED)
	button.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)


## Light a card as though the pointer were on it, for the part of its face that is not the button.
##
## A card with a scroll region over its prose ([CardScroll]) has a control between the pointer and the
## plate, and a [Button] can only see a pointer that reaches it — so half the card would stop lighting
## up while staying perfectly clickable. Hover is not decoration on a card: it is the only thing that
## says the whole face is one target rather than a picture with a paragraph under it.
##
## Both resting boxes are set, not just [code]normal[/code]. A chosen card is a pressed toggle, so it
## draws [code]pressed[/code] instead, and overriding one of the two would light every card except the
## one already picked.
static func set_card_hover(button: Button, hovered: bool) -> void:
	var style := input_style(HOVER_TINT) if hovered else input_style()
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("pressed", style)


## The chevron, and the flip that follows the list.
##
## [signal Window.visibility_changed] rather than a pair of open/close signals: Godot 4's [Window] has
## `about_to_popup` but no matching hide signal, so one handler reading [member Window.visible] covers
## both edges — including the list being dismissed by clicking away, which no open-signal pairing
## would have seen.
static func _apply_select_arrow(options: OptionButton) -> void:
	options.add_theme_icon_override("arrow", SELECT_ARROW_TEXTURE)
	# Godot insets the arrow by `arrow_margin` *only* — it does not read the stylebox's right content
	# margin the way the text does. Left at the stock 4 the chevron sits hard against the field's
	# moulding while the lettering is 16 clear of it, and the row reads lopsided.
	options.add_theme_constant_override("arrow_margin", int(INPUT_PADDING_H))
	var popup := options.get_popup()
	popup.visibility_changed.connect(func() -> void:
		options.add_theme_icon_override("arrow",
			SELECT_ARROW_UP_TEXTURE if popup.visible else SELECT_ARROW_TEXTURE))


## The list the field opens.
##
## **This was the gap the first pass left**: skinning an [OptionButton] dresses the *field*, and the
## popup is a separate [PopupMenu] with its own theme — so a painted parchment field opened a flat
## grey Godot list, on the one page that has no other stock chrome left. Nothing here needs new art:
## the panel is the same sunken field the button wears, so the list reads as the field having grown
## rather than as a second window over it.
##
## The radio marks are Godot's own, **darkened**. They are drawn near-white for a dark theme and are
## invisible on parchment; they are also the only shape in the popup that says which item is current,
## so dropping them was not an option. [method tinted_texture] takes them down to ink and keeps the
## shapes — see the note there about icons whose [member Resource.resource_path] is empty, which the
## built-in theme's are.
static func _apply_select_popup(options: OptionButton) -> void:
	var popup := options.get_popup()
	popup.add_theme_stylebox_override("panel", input_style())
	popup.add_theme_stylebox_override("hover", popup_hover_style())
	popup.add_theme_stylebox_override("separator", separator_style())
	for state in ["font_color", "font_hover_color", "font_accelerator_color"]:
		popup.add_theme_color_override(state, INK)
	popup.add_theme_color_override("font_disabled_color", INK_MUTED)
	popup.add_theme_color_override("font_separator_color", INK_MUTED)
	popup.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	# Room to put a finger on a row, the same reasoning as CONTROL_HEIGHT.
	popup.add_theme_constant_override("v_separation", POPUP_ITEM_SEPARATION)
	popup.add_theme_constant_override("item_start_padding", int(INPUT_PADDING_H))
	popup.add_theme_constant_override("item_end_padding", int(INPUT_PADDING_H))
	# Language choices carry rectangular flags whose source SVGs are intentionally high-resolution.
	# Keep all OptionButton icons at text scale instead of letting a source asset dictate row height.
	popup.add_theme_constant_override("icon_max_width", 36)
	for icon in ["radio_checked", "radio_unchecked", "checked", "unchecked"]:
		var texture := popup.get_theme_icon(icon, "PopupMenu")
		if texture != null:
			popup.add_theme_icon_override(icon, tinted_texture(texture, POPUP_MARK_TINT))


## The wash under the item the pointer is on. A [StyleBoxFlat], not the field texture: this is drawn
## per *item*, and the field's moulded border repeated down every row would read as a stack of
## separate fields rather than one list.
static func popup_hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = POPUP_HOVER
	style.set_corner_radius_all(4)
	return style


## The rule under a section heading. Brown, so it belongs to the parchment — Godot's own is a cool
## blue-grey line drawn for a dark theme, and on this page it was the one thing still tinted from
## somewhere else.
static func separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = RULE
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style


## What the pointer says about [param control]: a hand when there is something to click, the ordinary
## arrow when there is not.
##
## The hand is the *default* for every interactive control in the app — see [method watch_cursors],
## which is what actually applies it. This is for the exceptions: a control that is
## [code]disabled[/code] but still takes the pointer, which is not something the default can know,
## because a button is nearly always disabled after it is added rather than before. A `planned` row
## does not need it — that sets `MOUSE_FILTER_IGNORE`, so the pointer never reaches the control at
## all and the shape underneath is what shows.
static func apply_cursor(control: Control, clickable: bool = true) -> void:
	control.set_meta(CURSOR_META, true)
	control.mouse_default_cursor_shape = (Control.CURSOR_POINTING_HAND if clickable
		else Control.CURSOR_ARROW)


## Make every interactive control in the app show a hand, from now on. Called once, at boot.
##
## **A tree hook rather than a line in each helper, because the cursor is not themeable.**
## [member Control.mouse_default_cursor_shape] is a node property, so [OutpostTheme] — which is how
## every other app-wide default here is set — cannot carry it. The alternative was a call beside each
## of the ~35 places a button is built, in eight files, which is a rule that survives exactly until
## the next screen forgets it.
##
## [signal SceneTree.node_added] fires for controls built long after their screen was mounted (the
## settings page rebuilds itself on a reset; the chat log grows all game), which a one-shot walk of
## the tree at mount time would miss.
##
## A control that has been through [method apply_cursor] is left alone. **"Still on
## [constant Control.CURSOR_ARROW]" cannot stand in for "nobody has decided yet"**, which is what the
## first cut of this tried: the arrow is also the deliberate answer for a disabled control, and since
## a screen sets that before adding the control to the tree, the default then arrived afterwards and
## put the hand back on the one control that had asked not to have it. The mark is what tells an
## unset control from a settled one.
##
## [LineEdit] is not in the list, and for the same reason it must not be: it overrides the shape
## itself and wants an I-beam.
static func watch_cursors(tree: SceneTree) -> void:
	tree.node_added.connect(func(node: Node) -> void:
		if not (node is BaseButton or node is Slider or node is ScrollBar or node is TabBar):
			return
		var control := node as Control
		if not control.has_meta(CURSOR_META):
			apply_cursor(control))


## Dress a [CheckButton] as the painted toggle.
##
## **Every stylebox is emptied.** A [CheckButton] is a [Button], so it arrives wearing whatever plate
## the default theme gives one — on this page a dark slab from [OutpostTheme], showing as a blot
## behind the toggle. The painted art is the whole control; there is nothing for a plate to do behind
## it. `h_separation` goes with it: that is the gap between a caption and the icon, and these carry no
## caption, so left at its default it only pads the control out wider than the image.
##
## The disabled states are the same two images, as with [method apply_slider] — no third state is
## drawn, and a `planned` row fades the whole control anyway. RTL is not handled: Godot would want
## genuinely mirrored art for `checked_mirrored`/`unchecked_mirrored` (the knob has to change sides),
## and nothing in the app is translated yet, so there is no right answer to bake in.
static func apply_toggle(check: CheckButton) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		check.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	check.add_theme_constant_override("h_separation", 0)
	var size := Vector2i(roundi(CONTROL_HEIGHT * TOGGLE_ASPECT), roundi(CONTROL_HEIGHT))
	var on := scaled_texture(TOGGLE_ON_TEXTURE, size)
	var off := scaled_texture(TOGGLE_OFF_TEXTURE, size)
	check.add_theme_icon_override("checked", on)
	check.add_theme_icon_override("checked_disabled", on)
	check.add_theme_icon_override("unchecked", off)
	check.add_theme_icon_override("unchecked_disabled", off)


## One half of a slider: [param fill] picks the gold rather than the groove it runs in.
##
## **The vertical content margins are what set the drawn height**, which is the one thing here that is
## not cosmetic. Godot works out how tall to draw a slider's groove as the stylebox's minimum size
## *plus* its centre size, and neither is the texture's height — so this is the only lever there is.
## The centre is fixed at [code]SLIDER_ART_HEIGHT - 2 * SLIDER_SLICE_V[/code] (2px), and the margins
## make up the rest of [constant SLIDER_HEIGHT].
##
## Two ways to get this wrong, both of which look like a bug elsewhere: zeroing the margins the way
## every other stylebox in this file does squashes the groove to that 2px centre, and leaving them
## unset falls back to the texture margins, which sum back to the art's own 10 and silently ignores
## [constant SLIDER_HEIGHT] entirely. The horizontal margins are zero on purpose — they would only add
## a minimum width, and the groove is meant to take whatever width the row gives it.
static func slider_style(fill: bool, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = SLIDER_FILL_TEXTURE if fill else SLIDER_TEXTURE
	style.texture_margin_left = SLIDER_SLICE_H
	style.texture_margin_right = SLIDER_SLICE_H
	style.texture_margin_top = SLIDER_SLICE_V
	style.texture_margin_bottom = SLIDER_SLICE_V
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var centre := SLIDER_ART_HEIGHT - 2.0 * SLIDER_SLICE_V
	var margin := maxf(0.0, (SLIDER_HEIGHT - centre) * 0.5)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.modulate_color = tint
	return style


## Dress a [Slider] — groove, gold, and the knob that rides between them.
##
## Godot calls the filled part [code]grabber_area[/code]: it is drawn from the control's left edge to
## the knob, which is what makes it read as a level rather than a track with a marker on it. The knob
## itself is an icon, so its hover lighting is a baked copy; see [method tinted_texture].
##
## The disabled knob is the same image, not a greyed one — there is no second knob drawn, and a
## [code]planned[/code] row already fades the whole control. Compare [method apply_button], where a
## disabled plate really does become the gray one: there the alternative art exists.
static func apply_slider(slider: Slider) -> void:
	slider.add_theme_stylebox_override("slider", slider_style(false))
	slider.add_theme_stylebox_override("grabber_area", slider_style(true))
	slider.add_theme_stylebox_override("grabber_area_highlight", slider_style(true, HOVER_TINT))
	var knob := scaled_texture(SLIDER_GRABBER_TEXTURE, Vector2i(
		roundi(SLIDER_GRABBER_TEXTURE.get_width() * SLIDER_GRABBER_SCALE),
		roundi(SLIDER_GRABBER_TEXTURE.get_height() * SLIDER_GRABBER_SCALE)))
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", tinted_texture(knob, HOVER_TINT))
	slider.add_theme_icon_override("grabber_disabled", knob)


## How far the scrollbar art is taken down from the size it was drawn at.
static func _scrollbar_scale() -> float:
	return SCROLLBAR_SIZE / SCROLLBAR_ART_SIZE


## A scrollbar texture at the size the bar is actually drawn.
##
## **Resampled rather than left to the nine-patch.** A [StyleBoxTexture] asked to draw into a rect
## narrower than its own slice shrinks the corner patches to fit, so the channel's moulding would come
## out thinner at the ends than along the sides. And the arrow plates are theme *icons*, which are
## drawn at the texture's own size and never consult the stylebox at all — so without this they would
## simply have stayed 54 wide beside a 36-wide track.
static func _scrollbar_texture(texture: Texture2D) -> Texture2D:
	var scale := _scrollbar_scale()
	if is_equal_approx(scale, 1.0):
		return texture
	return scaled_texture(texture, Vector2i(
		maxi(1, roundi(texture.get_width() * scale)),
		maxi(1, roundi(texture.get_height() * scale))))


## The channel a scrollbar's grabber rides in. [param vertical] picks the art drawn for that axis —
## the two are not rotations of each other, and the caps would run the wrong way round.
static func scroll_track_style(vertical: bool) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _scrollbar_texture(SCROLL_TRACK_TEXTURES[vertical])
	_slice(style, SCROLL_TRACK_SLICE * _scrollbar_scale(),
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	style.set_content_margin_all(0.0)
	return style


## The bar itself, inset into the channel. See [constant SCROLL_GRABBER_WIDTH] for why the inset is a
## negative expand margin, and [method button_style] for what [param tint] does.
static func scroll_grabber_style(vertical: bool, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _scrollbar_texture(SCROLL_GRABBER_TEXTURES[vertical])
	var scale := _scrollbar_scale()
	var long_slice := SCROLL_GRABBER_SLICE_LONG * scale
	var cross_slice := SCROLL_GRABBER_SLICE_CROSS * scale
	var along := long_slice if vertical else cross_slice
	var across := cross_slice if vertical else long_slice
	style.texture_margin_top = along
	style.texture_margin_bottom = along
	style.texture_margin_left = across
	style.texture_margin_right = across
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	# Zero, so the shortest the bar may get is its own two end caps rather than those plus padding:
	# Godot builds the grabber's minimum length out of this. The inset below is the only margin here
	# doing any work.
	style.set_content_margin_all(0.0)
	var inset := -(SCROLLBAR_SIZE - SCROLL_GRABBER_WIDTH * scale) * 0.5
	if vertical:
		style.expand_margin_left = inset
		style.expand_margin_right = inset
	else:
		style.expand_margin_top = inset
		style.expand_margin_bottom = inset
	style.modulate_color = tint
	return style


## How far one press of an end plate moves the view: a line and a half of body text, which is enough
## that a click plainly did something and little enough to nudge a paragraph into view.
##
## **Without this the plates are painted buttons that do nothing.** A [ScrollContainer] leaves its
## bars' [member Range.step] at 0 — it scrolls by whole pixels, which is what makes dragging the
## grabber and the wheel smooth — and [ScrollBar] moves the view by exactly that step when an end
## plate is pressed. Zero. The grabber works, the wheel works, and the one control that looks most
## like a button is inert, which reads as a broken widget rather than a deliberate one.
## [member ScrollBar.custom_step] is the override that exists for this, and -1 (its default) means
## "use the step", so it has to be set to a real number rather than left alone.
const SCROLL_STEP := FONT_BODY * 1.5


## Dress one [ScrollBar] — channel, bar, and the two end plates.
##
## The end plates are theme **icons**, and a theme icon has no modulate, so the hover and press
## lighting the plates elsewhere get for free has to be baked into copies of the image; see
## [method tinted_texture]. The bar is a stylebox and takes its tint directly.
static func apply_scroll_bar(bar: ScrollBar) -> void:
	bar.custom_step = SCROLL_STEP
	var vertical := bar is VScrollBar
	bar.add_theme_stylebox_override("scroll", scroll_track_style(vertical))
	bar.add_theme_stylebox_override("scroll_focus", scroll_track_style(vertical))
	bar.add_theme_stylebox_override("grabber", scroll_grabber_style(vertical))
	bar.add_theme_stylebox_override("grabber_highlight", scroll_grabber_style(vertical, HOVER_TINT))
	bar.add_theme_stylebox_override("grabber_pressed", scroll_grabber_style(vertical, PRESSED_TINT))
	for decrement in [true, false]:
		var texture := _scrollbar_texture(SCROLL_ARROW_TEXTURES[vertical][decrement])
		var name := "decrement" if decrement else "increment"
		bar.add_theme_icon_override(name, texture)
		bar.add_theme_icon_override(name + "_highlight", tinted_texture(texture, HOVER_TINT))
		bar.add_theme_icon_override(name + "_pressed", tinted_texture(texture, PRESSED_TINT))
	if vertical:
		bar.custom_minimum_size.x = SCROLLBAR_SIZE
	else:
		bar.custom_minimum_size.y = SCROLLBAR_SIZE


## Dress both of a [ScrollContainer]'s bars. The container reaches its scrollbars through methods
## rather than children, which is why this exists rather than screens walking the tree.
static func apply_scroll_container(scroll: ScrollContainer) -> void:
	apply_scroll_bar(scroll.get_v_scroll_bar())
	apply_scroll_bar(scroll.get_h_scroll_bar())


## Copies of the art made at load time, keyed by what was asked of them. The settings page rebuilds
## every control on a reset and on a window-mode change, and asks for the same handful of images each
## time; without this each rebuild would leave another set behind.
static var _derived_textures: Dictionary = {}


## A copy of [param texture] with its brightness multiplied by [param tint], for the one place a
## stylebox's [code]modulate_color[/code] is not available: theme icons.
static func tinted_texture(texture: Texture2D, tint: Color) -> Texture2D:
	# The tints here are uniform greys, so brightness alone says all of it — contrast and saturation
	# stay at 1.0, which leaves the art's own colour untouched.
	return _derive(texture, "tint@%.3f" % tint.r,
		func(image: Image) -> void: image.adjust_bcs(tint.r, 1.0, 1.0))


## A copy of [param texture] resampled to [param size]. For theme icons again: a [CheckButton] draws
## its check at the texture's own size, so art drawn larger than the control has to be resized on the
## way in rather than constrained on the way out.
static func scaled_texture(texture: Texture2D, size: Vector2i) -> Texture2D:
	return _derive(texture, "size@%v" % size,
		func(image: Image) -> void: image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS))


## Run [param edit] over a decompressed copy of [param texture]'s image, cached under
## [param key]. Every caller here is preparing a theme icon, which cannot be adjusted once the
## theme holds it.
static func _derive(texture: Texture2D, key: String, edit: Callable) -> Texture2D:
	# Godot builds its default theme's icons at runtime from embedded SVG, so those arrive with an
	# **empty** `resource_path` — keyed on that alone, every built-in icon would collide on one cache
	# entry and the first one derived would be handed back for all of them. The theme returns the same
	# instance each time it is asked, so the id is a stable key for exactly the textures the path
	# cannot name.
	var name := texture.resource_path if not texture.resource_path.is_empty() \
		else str(texture.get_instance_id())
	var cache_key := "%s|%s" % [name, key]
	if _derived_textures.has(cache_key):
		return _derived_textures[cache_key]
	var image: Image = texture.get_image().duplicate()
	if image.is_compressed():
		image.decompress()
	edit.call(image)
	var derived := ImageTexture.create_from_image(image)
	_derived_textures[cache_key] = derived
	return derived


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
##
## **Which makes a hole in the art a hole through to this.** `frame2.png` shipped with a 1px-wide,
## 40px-tall transparent scratch in it; over flat parchment grain it is invisible in an image viewer,
## and in the game it was a hard black hairline down the menu, the settings page and the exit modal.
## The fill is not optional and cannot be lightened — it sits behind the dark button plates too — so
## the guarantee it depends on is the art's, and `test_ui_textures.gd` is what holds the art to it.
## [param inset] pulls the drawn box *inside* the plate, and is required for any plate whose art is
## not opaque right to its edge.
##
## The fill is only invisible while something covers it. A button plate is opaque corner to corner so
## nothing shows; the arrow plates are not — their rounded corners are cut in by six transparent
## pixels, and the sunken field a card wears by two — and through those the near-black fill was
## drawing as a hard dark band down the sides of every arrow and across the top of every card. It
## reads exactly like a clipped shadow, which is what sent me looking at containers first; the alpha
## of the art is where the answer was. Shrinking the box by more than the transparent margin puts the
## fill back under paint, and the blur still spreads outward from there.
static func shadow_style(size: int, offset: Vector2, radius: int, inset: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = true
	style.bg_color = SHADOW_FILL
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = size
	style.shadow_offset = offset
	style.set_corner_radius_all(radius)
	# The shadow belongs to the plate in front of it, so the container must not inset that plate.
	style.set_content_margin_all(0.0)
	if inset > 0.0:
		style.expand_margin_left = -inset
		style.expand_margin_right = -inset
		style.expand_margin_top = -inset
		style.expand_margin_bottom = -inset
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
