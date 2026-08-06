# The chat scene — scope and plan

> **Status, 2026-08-06.** **Phases 1 and 2 are built** — `ChatScene`, the height-driven fit, the
> bleed, the throne room, `Shift+9`, and the header giving way with the ✕ carried onto the picture.
> Phase 2 came with Phase 1 rather than after it: putting the scene flush against the top rule
> displaces the title bar by construction, so leaving it for later would only have meant looking at a
> layout nobody had chosen.
>
> Phases 3 (characters) and 4 (wiring `_play_opening`) are still ahead. The character contract in §4
> is written and `ChatScene` already draws them — what is missing is sprites and the key to cycle
> them.
>
> **The band is held between a floor and a ceiling**: `ChatScene.MIN_SCENE_HEIGHT` (420) under it and
> `MAX_SCENE_SCREEN_FRACTION` (35% of the screen, so 448) over it, with the picture's own proportions
> in between. Which of the three decides depends on the board — the ceiling on a wide one, the floor
> on a narrow one.
>
> **The fit, in order: scale to the height, then crop the sides.** All of a painting's height is
> always on screen; the vertical is never touched. Whatever will not fit across is taken evenly off
> the two sides. And where a plate is *too narrow* to reach the board's edges at that height, it is
> **stretched sideways** rather than centred with parchment showing.
>
> | | board | band | decided by | shows | stretch |
> | --- | --- | --- | --- | --- | --- |
> | Desktop | 1752 | 1732 x 448 (3.9:1) | the ceiling | the whole painting | **1.45x** |
> | Phone | 720 | 700 x 420 (1.7:1) | the floor | the middle 62% of it | none |
>
> **The stretch is a stopgap and it distorts** — `ChatScene.horizontal_stretch` reports it so the
> amount is measurable rather than something to squint at. The fix is art, not code: a plate reaches a
> desktop board's edges untouched at about **3.9:1**, and the wider it is, the more a phone crops.
>
> | plate | desktop stretch | phone crops |
> | --- | --- | --- |
> | 1024x384 (2.7:1, today) | 1.45x | 37% |
> | 1280x384 (3.3:1) | 1.16x | 50% |
> | 1536x384 (4:1) | ~none | 58% |
>
> No single aspect satisfies both — the two bands are 3.9:1 and 1.7:1. Whatever is chosen, the middle
> of a plate is what always survives, so that is where the subject belongs.
>
> `tools/capture_chat_scene.gd` shoots both, because whether the narrow crop still frames something
> worth looking at is a judgement no assertion can make.

A painted scene at the top of the conversation: one background, and optionally characters standing in
it. First plate is `throne_room.png`, 1024x384.

Decisions taken up front: the scene **keeps its full height and crops at the sides**, the board's
title bar gives way to it with the ✕ overlaid on the image, and a **dev key** drives it first.

---

## 1. The fitting rule

The instruction was "fill the whole width of the chat top area, flush to the top border". Taken
literally as a *width* fit, the painting's 8:3 gives:

| | board width | scene at 8:3 | as a share of the expanded board |
| --- | --- | --- | --- |
| Desktop (1280x800 window) | 1752 | 1732 x **650** | ~54% |
| Phone (720x1280) | 720 | 700 x **262** | ~24% |

The same picture carrying very different weight, and on a phone a wide room shrunk to a strip. So the
fit is **driven by height, not width**:

> **The image is scaled so its full height fits the scene band, centred horizontally, and whatever
> falls outside the board's width is cropped away.** It is never cropped vertically and never
> letterboxed.

The band's height is

```
height = max(MIN_SCENE_HEIGHT, board_width / image_aspect)
```

which is the whole rule, and it behaves correctly at both ends without a breakpoint:

- **Wide board** — `board_width / aspect` wins, the picture exactly fills the width, nothing is
  cropped at all. Desktop gets the full room at 650.
- **Narrow board** — `MIN_SCENE_HEIGHT` wins, the picture is drawn taller than the width can hold and
  the sides are cropped. A phone gets the throne close up rather than the whole hall in miniature,
  which is the point.

`MIN_SCENE_HEIGHT` is the one number to tune and it only bites on narrow boards. At 420 a phone shows
the middle 700 of an 1120-wide draw — about the central 62% of the painting, which for this plate is
the throne, the dais and the carpet.

**The consequence worth stating**: on desktop the scene is still 650 units, a bit over half the
expanded conversation. That follows directly from "never crop vertically" and is not something the
rule can dodge — the way back is a vertical cap, which was considered and rejected. Easy to revisit;
it is one branch in one function.

### Cropping is a source region, not a clip

The crop is done by drawing a **region** of the texture, not by clipping a control. Clipping would
mean `clip_contents` on the scene, which would also clip the bleed the next section relies on.

---

## 2. Flush to the frame

The board is a [PanelContainer] whose style leaves `CHAT_FRAME_PADDING` (19) of room inside its edge,
of which the first `CHAT_FRAME_RULE` (10) is painted rule. So "flush to the border, considering the
frame" is exactly

```
bleed = CHAT_FRAME_PADDING - CHAT_FRAME_RULE   # 9
```

— the scene is drawn 9 units left, right and up beyond the content box it is laid out in, which lands
its edges hard against the inside of the painted rule on three sides. That expression already exists
in the skin as `CHAT_FRAME_PADDING_BOTTOM`, for the same reason in the other direction, so this is a
derivation rather than a nudged number.

**Drawn outside its own rect, not laid out outside it.** A control may draw beyond its bounds; what
it may not do is claim the space. The scene therefore occupies a plain rectangle in the board's
column — the layout stays honest, the header below it sits where a header should — and only its
`_draw` reaches into the frame. The alternative, rebuilding [ChatDock] so the padding comes from an
inner [MarginContainer], is a bigger change to a well-settled file for the same picture.

The one requirement this puts on everything above it: **nothing in the chain may set
`clip_contents`.** Nothing does today; a test pins it.

Square corners, deliberately: the plate is a rectangle and the frame's inner corners are close to
square at this slice. If the art ever grows a rounded corner, this is where it would show.

---

## 3. What happens to the title bar

While a scene is showing, the board's header goes and the **✕ is overlaid on the scene's top-right**.
The image becomes the top of the panel, which is the whole point of it being flush.

With no scene, the header returns exactly as it is now. The ✕ has to keep working in both, so it
stays one button that is re-parented rather than two that could drift apart.

Note the ✕ is inert during event mode anyway — `HudShell.close_topmost` refuses while
`_event_active` — so this is about the ordinary case, not about letting a player dismiss an
unresolved decision.

---

## 4. Characters

Characters are sprites drawn over the background in the same `_draw`, and they take the **same
contract the map's standing things use** — which is deliberate: the anchoring problem is identical
and it has already been solved once.

```gdscript
{
  "texture": Texture2D,
  "at": float,      # where across the SCENE IMAGE, 0..1
  "height": float,  # how tall, as a fraction of the scene band
}
```

Anchored **bottom-centre**, because unlike a field or a roof seen from above, a character stands up
from the floor and its feet are where it meets the world.

**`at` is in image space, not board space.** A character standing beside the throne has to stay
beside the throne when the sides crop on a phone — position them against the panel and they would
slide off their own scenery at every width. This is the single detail that makes the crop and the
characters compose instead of fighting.

Feet land on `SCENE_FLOOR_LINE`, a fraction of the band's height, because the floor in a painted
interior is not at the very bottom of the frame. For this plate it is around 0.97; it is per-scene
data, not a constant, since a different background will put its floor somewhere else.

---

## 4a. Phase 3 — the base character, and its shadow

### What the art is

`character_base1.png`, 472x557. Content runs x 63–430, y 55–556 — so it is a **bust cut off at the
waist**, and its pixels **touch the bottom edge of the canvas** (no bottom padding at all). Transparent
pixels are black, which is the harmless direction.

Two things follow immediately:

- It does not stand on the scene's floor line. A waist-cut portrait belongs **flush to the bottom of
  the band**, rising out of it; put its cut edge on the throne room's floor at 0.97 and it floats
  above a sliver of flagstone. `floor_line` stays for a future full-length figure.
- **The zero bottom padding is exactly the caveat in the shader tip.** A shader cannot draw outside
  the image's own bounds, so a downward shadow offset would be clipped away on this file.

### The shadow: a shader on the figure

**The shader in the tip is what it uses**, on a node per character (`ChatCharacter`) with the
material on it — which is what the tip assumed all along when it said "select your Sprite2D or
TextureRect".

The objection raised against it first — "a material belongs to a whole [CanvasItem], and the scene
paints the background too" — was **true only because the characters were being drawn in the scene's
own `_draw`**. That was a choice, not a constraint of the method, and it was presented as the latter.
Given a node each, the material lands on exactly the thing it is a shadow of. It also costs one draw
call where sampling the silhouette by hand cost twenty-four.

Two changes to the tip's shader, both required rather than preferred:

- **It samples over a disc, not once.** One offset sample is a hard copy of the silhouette shifted
  sideways, which on a figure reads as a cut-out. `TAPS` samples on a Vogel spiral — `sqrt` on the
  radius so they spread evenly by area, turned by the golden angle so they never line up into spokes
  — average into a real falloff. This is not a shortcoming of the tip: softness costs many samples
  whichever way it is reached.
- **The figure does not fill the rect it is drawn into.** This is the tip's own caveat — a canvas
  shader cannot paint outside its own primitive, and it suggested adding transparent padding to the
  PNG. That will not do here, because the art runs to the very bottom of its canvas *and* layers have
  to share a canvas. So the caller draws the texture into a rect grown by the blur radius and passes
  `pad`, the fraction of it that is room rather than picture; the shader maps UV back onto the
  texture and treats everything outside as transparent. No re-export, and it works for every layer.

Sampling is bounds-checked rather than relying on clamped edges, which would smear the last row of
pixels outward instead of fading to nothing. And the window the scene may not draw outside of arrives
as `clip_uv`, so nothing spills onto the parchment below the band.

Two things Godot will not allow, found the hard way and worth not rediscovering: **shader built-ins
such as `TEXTURE` do not exist in global shader functions**, and Godot will not accept one passed as
a `sampler2D` argument either — so the sampling is inlined in `fragment()`.

**A `CanvasGroup` is still the next step**, once a character is a stack of layers: it flattens its
children so the shader sees the composite silhouette rather than casting a shadow per garment.

### Where the two characters stand

**Positioned against the band, not the painting** — and this reverses §4's decision for characters,
deliberately. A figure that belongs to the scenery has to keep its footing on the scenery; a speaker
in a conversation is staged against the *frame*, like a portrait, and has to be at the sides of what
the player can actually see. The `floor_line` is unaffected, because there is no vertical crop.

One rule covers both breakpoints:

```
offset = min(SPREAD * band_height, band_width/2 - character_width/2 - MARGIN)
```

Each character's centre sits `offset` either side of the band's middle. The first term is what they
would like — a fixed separation, scaled to the art rather than to the board — and the second is all
the room there is. On a wide board the first wins and they sit well inside the frame; on a narrow one
the second wins and they are pushed against the edges. Nothing branches on a breakpoint.

| | band | character | offset | result |
| --- | --- | --- | --- | --- |
| Desktop | 1732 x 448 | 361 wide | 358 (wanted) | centres at 508 and 1224 — framing the throne |
| Phone | 700 x 420 | 338 wide | 173 (clamped) | centres at 177 and 523 — hard against the sides |

**The left one is mirrored** (`SPREAD` is symmetric; the flip is a negative width on the destination
rect), so the pair face each other across the room.

### Also

Import lossless with no mipmaps, like the plates — the figure is only ever downscaled a little and
block compression bands on skin.

### Built, and one note about the art

Phase 3 is in: the ring shadow, the band-space slots, the mirror, and `Shift+0` to put nobody, one
figure, then a pair on the stage. Measured in place — desktop centres at 508 and 1224 with the throne
between them, phone clamped hard against the sides with 8 units to spare.

**`character_base1.png` carried a white matte, and was re-exported without one.** The first export's
semi-transparent edge pixels averaged luminance 159 against the body's 123, with a third of them over
200 — the signature of art flattened onto white before the alpha was cut. `fix_alpha_border` could
not reach it: that setting rewrites only *fully* transparent pixels, and this was a fringe on the
partly transparent ones.

The replacement measures 112 at the edge against 127 in the body — darker than what it surrounds,
which is what an antialiased edge over transparency should be — with 2% above 200. **This is the
check worth repeating on every character layer**, since they all share the canvas and a matte on any
one of them shows up over dark backgrounds:

```
edge = (alpha > 10) & (alpha < 245)      # the antialiased fringe
```

Its mean luminance should come out *below* the opaque body's, not above.

Un-matting in the pipeline was tried on the first export and deliberately reverted: it would have
left `core/assets/` differing from `docs/UI/`, and the next export of a hair or clothing layer would
have silently undone it. Fixing it at source, as here, is the durable answer.

---

## 5. Where things live

Same split as the map, for the same reason: **core renders, the module knows what exists.**

- `core/ui/chat_scene.gd` — a [Control] that is handed a background, a floor line and a list of
  characters, and draws them. Knows nothing about throne rooms.
- `modules/base_game/chat_scenes.gd` — the catalogue: which scenes there are, what art each uses,
  where its floor is, and which characters stand in it.
- `core/assets/ui/chat_backgrounds/throne_room.png` — alongside the other painted chrome.

**Import settings**: no mipmaps (the plate is upscaled at every size the board reaches, so there are
no reduced levels to sample), and **lossless** rather than VRAM compression — the stone and the sky
are broad smooth gradients, which is exactly what block compression bands, and one plate at 1024x384
is 1.5 MB uncompressed.

---

## 6. What replaces what

`game_screen.gd` currently builds `_event_image`: a 140-tall [PanelContainer] with a thin frame and
the caption "Event illustration — artwork arrives with the authored event". It is never hidden, so
today there is a permanent empty box in the conversation. The scene replaces it, and shows nothing at
all when there is no scene to show.

`_show_question` sets `_event_image.visible = true`, which becomes a no-op and goes.

---

## 7. Dev keys

Following the map art, and behind the same `DEV_MAP_KEYS` constant:

| | |
| --- | --- |
| `Shift+9` | cycle the scene — none, throne room, whatever else exists |
| `Shift+0` | cycle who is standing in it — nobody, one figure, a pair |

**Press `Shift+9` first.** `Shift+0` only changes how many figures the *current* scene is drawn with;
with no scene showing there is nothing for it to put them in.

**And the board must not keep the keyboard.** Showing a scene opens the conversation, and opening the
conversation puts the caret in the chat field — a focused [LineEdit] swallows every printable key, so
the dev key that opened the scene would be the last one to work and the next would type a bracket
into the conversation. `_show_chat_scene` releases that focus again; only the automatic grab is
undone, so a player who clicks into the field still gets their typing. Pinned by
`tests/integration/test_chat_scene_keys.gd`, because nothing about the failure looks like a bug —
the key simply stops doing anything.

Not in [InputActions], for the reason that file states: an action bound to something that does not
exist is a binding the player can change and then watch do nothing.

**The real trigger is `_play_opening`**, and it is one line when the art is ready to be judged. That
method already runs the `opening` workflow — the throne room and the king's charge — so the plate was
painted for a moment that already exists in the game. The dev key comes first only because replaying
a new game to look at a picture is a poor way to iterate.

---

## 8. Tests

The geometry is a pure function of board width, image size and the minimum height, so it can be
asserted rather than eyeballed:

- the picture is never letterboxed and never cropped vertically, at any width;
- a wide board crops nothing; a narrow board crops **only** the sides, symmetrically;
- the bleed equals `CHAT_FRAME_PADDING - CHAT_FRAME_RULE`, so the scene meets the rule exactly;
- a character at `at = 0.5` stays on the same piece of scenery at every board width — the property
  the whole image-space decision exists to guarantee;
- nothing between the scene and the board sets `clip_contents`, or the bleed is silently cut off;
- the scene is not counted into `ChatDock.collapsed_height`, and is hidden with the rest of the
  expanded board.

---

## 9. Phasing

**Phase 1 — the scene draws.** `ChatScene`, the fitting rule, the bleed, the throne room, `Shift+9`.
*Done when* the plate sits flush under the rule at every window size with nothing clipped and no
letterboxing.

**Phase 2 — the header gives way.** The ✕ overlaid, the title suppressed while a scene shows.

**Phase 3 — characters.** The contract in §4, `Shift+0`, placeholder sprites if none have been
painted. *Done when* a character stands on the floor and keeps its place on the scenery as the board
is resized from desktop to phone.

**Phase 4 — the opening.** Wire `_play_opening` to the throne room, and give the catalogue a way for
a workflow to name a scene.

Phase 1 is the one with the geometry in it; the rest is content and wiring.
