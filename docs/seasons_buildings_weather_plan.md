# Seasons, building stages and weather — scope and plan

> **Status, 2026-08-05.** The **crop cycle and the house are built** — the standing-sprite pass of
> §3.1, the field as a one-cell self-contained thing, and the house as a one-*subtile* thing with all
> eight states in both weathers. Seasons and weather are still ahead; §2 and §4 stand as written,
> §3 is superseded by what is recorded here.
>
> Current dev keys: `5`–`8` house build stages, `Shift+5`–`Shift+8` ruined states, `9` cycles the
> crop, `0` toggles snow.
>
> **Anything standing on the ground cross-dissolves into whatever replaces it**
> (`OverworldMapView.STANDING_FADE_SECONDS`). The view works out what changed by itself — a standing
> thing's identity is its position, so a field whose crop advanced has a predecessor to come out of
> while a field that was not there a moment ago simply appears. The outgoing picture is drawn at full
> opacity with the incoming one fading in over it, never two translucent copies, or the ground would
> show through both at the halfway point.
>
> Four things settled in the building that are worth reading before the next piece:
>
> - **A thing painted with an overhang is self-contained at its own size.** §3.1's overhang rule and
>   multi-cell footprints do not combine: tiling ragged-edged art across a rectangle puts its ragged
>   edge through the *middle* of what is meant to be one thing. A bigger holding is several sprites
>   standing together, not one sprite tiled.
> - **The anchor is bottom-centre only for art painted side-on.** Both sheets so far are painted
>   looking *down* — the field lies flat and the house shows its roof — and both sit centred in their
>   own atlas cell, so both anchor at `(0.5, 0.5)`. The rule is that the anchor matches **how the art
>   was painted**, not how the object stands. Measure the sheet; do not assume.
> - **One scale for every sheet**: `BaseGameMap.ART_PX_PER_TILE`, 256 px to a map tile. A field
>   painted 256 px across is one tile; a house painted 128 px across is half of one. This is what lets
>   a sheet be measured rather than negotiated, and it needs no per-sheet scale factor.
> - **Art with transparency needs an alpha-weighted average colour.** The flat colour a zoomed-out map
>   falls back to was being diluted by the transparent part of each atlas cell — which is white, in
>   anything exported from Photoshop — so ochre fields read as washed pink. Fixed in
>   `OverworldMapView._average_color` and it applies to every sprite from here on.
>
> **Sizes as they now stand**, everything measured in **subtiles** — which is the currency the map is
> harmonised in, because the subtile is the square the smallest thing built stands on.
>
> | | occupies | drawn |
> | --- | --- | --- |
> | House | 1 subtile | 1 subtile + overhang |
> | Field plot | — (a farm is one cell) | 2.5 subtiles, in a 2x2 grid per cell |
> | Farm | 1 cell = 5x5 subtiles | four plots, exactly covering the cell |
> | Tree | — | 1.5 subtiles tall |
>
> **A farm is still one whole cell** — one thing to select, one patch of worked ground, one entry in
> the ground-override table that gives it its colour at distance. It is only *drawn* as a grid of
> smaller plots (`BaseGameMap.FARM_SPRITES_PER_CELL`). That was the way out of the size problem that
> cost nothing: a field below one whole cell would have had to leave the cell-keyed override table and
> lose its far-zoom colour, and this keeps all of that while putting a plot at two and a half subtiles
> instead of five.
>
> **Screen units are not physical pixels.** The project designs against a 720x1280 viewport and
> stretches `canvas_items`, so at a 1280x800 window one control unit is 0.625 of a pixel. Every
> threshold in `OverworldMapView` is in control units. Anything measuring a screenshot has to divide.
>
> Two known gaps, both deliberate and both one small change away:
>
> - **A house's click target is the subtile it stands on.** Now that the building is drawn at exactly
>   one subtile this is nearly exact — only the overhang falls outside it.
> - **Houses have no flat-colour fallback** and simply vanish past
>   `OverworldMapView.MIN_STANDING_TILE_PX`. The fields do have one (they are in the ground table), so
>   a settlement still reads as a cluster of ochre patches at distance.

Test scaffolding, deliberately. Nothing here decides a season, a construction stage or the weather
from game state; keys do, so the art and the rendering can be judged before the systems that would
drive them exist. Every piece is built at the seam the real system will later plug into, and those
seams are named at the end of each section.

Decisions taken up front: seasons on **Shift+1..4** (speeds keep 1/2/3), a **winter-only repaint**
for buildings, and **one ground atlas per terrain with seasons as rows**.

---

## 1. What changes, and who owns it

| Thing | Changes with season | Changes with stage | Owner |
| --- | --- | --- | --- |
| Ground (grass) | atlas row | — | `modules/base_game/seasons.gd` |
| Ground (farm) | atlas row | — | `seasons.gd` |
| Roads | default / winter sheet | — | `seasons.gd` + `road_network.gd` |
| Trees | per-season sprite | — | `seasons.gd` |
| Buildings | default / winter sprite | 7 appearances | `modules/base_game/buildings.gd` |
| Wash, particles | — | — | `core/map/weather_view.gd` |

**`OverworldMapView` learns nothing about seasons.** It already takes its texture tables from the
caller (`setup(map, textures)`, `set_scatter`, `set_ground_overrides`, `set_roads`) and its own
docstring is emphatic that it draws what it is handed and never learns what a farm is. A season is
therefore a different set of tables pushed at it, not a mode inside it. The only core additions are
`set_textures()` (the swap `setup` cannot do on its own) and a standing-sprite pass that buildings
and trees share.

---

## 2. Season

### 2.1 Model

```gdscript
# modules/base_game/seasons.gd
enum Season { SPRING, SUMMER, AUTUMN, WINTER }
```

Four static tables, keyed by season, returning exactly what the view's existing setters take:
`textures_for(season) -> Dictionary`, `scatter_for(season) -> Dictionary`,
`road_atlas_for(season) -> Texture2D`.

All four seasons' textures are `preload`ed at parse time and all four seasons' averaged biome
colours derived once at setup, so a switch is a dictionary swap and a `queue_redraw` with no frame
hitch. `_derive_biome_colors()` reads pixels back off the GPU — doing that per switch is the one
thing that would make this stutter, so it is cached per season instead.

### 2.2 Ground atlas layout

One `1024x1024` PNG per terrain type: **4 columns (variants) x 4 rows (seasons)**, 256 px per cell.
`OverworldMapView.slice_variants(atlas, 4, 4)` already produces exactly this in reading order, so a
slice index is `season * 4 + variant` and no new slicing code is needed.

Row order is fixed as **spring, summer, autumn, winter** (the enum order), and that is the one thing
about these files the code cannot check for you.

### 2.3 Roads

`RoadNetwork.ATLAS` is a preloaded const and `_pieces` is a `static var Array[Texture2D]` cached
once for the whole process. Season-swapping roads means that cache becomes keyed:
`static var _pieces: Dictionary  # atlas -> Array[Texture2D]`, with `textures()` taking the sheet to
use. Small change, but it is the one place where the season reaches into an existing static.

Only a winter sheet is needed initially — spring mud is a nice-to-have that costs a fourth file.

### 2.4 Keys

`Shift+1` spring, `Shift+2` summer, `Shift+3` autumn, `Shift+4` winter.

Handled by a new `_dev_map_keys(event)` in `game_screen.gd`, called from `_unhandled_input` and
guarded by a single `const DEV_MAP_KEYS := true`. **Not** added to `input_actions.gd`: that file's
own doc says only actions with something behind them live there, and these are scaffolding that
should vanish with one constant rather than leave rebindable entries pointing at nothing.

### 2.5 The seam for real

`GameClock` runs 30-day months, so `season = (clock.months_elapsed() / 3) % 4` is a one-line
derivation whenever a season should follow the calendar. Nothing here persists — reload resets to
summer.

---

## 3. Buildings that overhang their tile

This is the part with a real design decision in it, and it is worth getting the contract right once
because trees, buildings and everything else with a silhouette will use it.

### 3.1 The standing-sprite contract

A building is not terrain and cannot be drawn as terrain, for the two reasons the existing
`SCATTER_CHANNEL` docstring already gives: it overhangs the cell it stands on, so the next cell's
ground would paint over its roof, and two that overlap must be sorted near-in-front-of-far. Both
fall out of a **second pass** over the visible window — which the map already does for trees.

So buildings join that pass rather than getting one of their own. One structure, one sort:

```gdscript
# what core is handed, per standing thing
{
  "texture": Texture2D,
  "tile_width": float,      # how many MAP TILES wide the IMAGE is (not the footprint)
  "foot": Vector2,          # world position, in tiles, of the footprint's front-centre
  "foot_inset": float,      # optional, default 0.0 — see below
}
```

and the draw is the scatter formula generalised:

```
w    = tile_width * tile_size_px * zoom
h    = w * art.y / art.x
p    = (foot * tile_size_px - origin) * zoom
rect = Rect2(p - Vector2(w * 0.5, h * (1.0 - foot_inset)), Vector2(w, h))
sort key = foot.y
```

**The anchor is fixed at bottom-centre.** No per-building anchor tuning, no numbers to discover by
nudging a sprite until it stops bobbing as the map pans — which is exactly the failure mode the
scatter's hand-measured `SCATTER_ANCHOR = (0.34, 0.91)` represents, and it is fine for one test tree
and unmanageable for a set of buildings.

`foot_inset` is the single escape hatch: a normalised fraction of image height by which the
footprint's front edge sits *above* the image's bottom edge. It exists only for sprites with a
shadow cast forward. Default 0.

### 3.2 What that means for you when painting

Five rules, and they are the whole of it:

1. **Transparent background**, straight alpha.
2. **256 px per map tile of image width.** Same density as the ground atlas cells; a 2.5-tile-wide
   image is 640 px wide. The map's `MAX_ZOOM` is 4.0 against a 128 px tile, so this is a 2x upscale
   at the very closest zoom and correct everywhere else.
3. **The image's bottom edge is the front edge of the building's footprint**, and the image is
   **horizontally centred** on the footprint. Everything else — roof, eaves, chimney smoke — hangs
   up and sideways off that.
4. **Nothing below the bottom edge**, including cast shadow. Paint the shadow falling back and to
   the side, or use `foot_inset` and tell me the number.
5. Image height is free. A tall building is simply a tall image; the aspect ratio does the rest.

Import settings that matter, because two of them fail silently:

- **Mipmaps ON.** The view sets `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` on itself; without mips in the
  import that setting does nothing and the sprite shimmers as the map moves.
- **Fix Alpha Border ON.** Transparent pixels default to black RGB, and the mip levels average them
  into the silhouette — a dark halo round every roofline that appears at some zooms and not others.
  This is the same class of bug `RoadNetwork.PIECE_PADDING` exists to solve.
- **Lossless**, not VRAM-compressed, for building sprites. DXT5 bands soft alpha edges, and there
  are a handful of these rather than the thousands of ground cells that made compression worth it.

### 3.3 Sorting, culling and distance

- **Sort** is the footprint's front edge in world Y. Rows already run top to bottom in the pass, so
  between cells this is free; within a cell the existing sort widens to cover buildings too.
- **Overscan** is currently the constant `SCATTER_OVERSCAN = (1, 2)`, which is right for a tree and
  wrong for a three-storey house rooted four rows below the bottom of the screen. It becomes
  derived: `ceil(max tile_height)` rows above and below, `ceil(max tile_width / 2)` columns either
  side, computed from whatever is actually in the set.
- **Distance.** Trees stop drawing at `MIN_SCATTER_TILE_PX = 40` because a tree stops being a tree
  well before the ground stops being ground. A building is a landmark and should survive further
  out, so it gets its own lower threshold (~16 px/tile) and, below that, its **footprint rect in the
  sprite's averaged colour** — the same fallback the ground and the roads already make, through the
  same `_average_color`.

### 3.4 Stages and states

Seven appearances, as one flat list rather than two crossed axes:

```
foundation → early → late → finished → { abandoned | ruin | burnt }
```

Crossing stage with condition would give 28 combinations of which 21 are meaningless — a burnt
foundation is not a thing anyone builds art for. Once finished, the condition replaces the
appearance; before then there is only the stage.

| Key | Appearance |
| --- | --- |
| `5` | foundation |
| `6` | early construction |
| `7` | late construction |
| `8` | finished |
| `Shift+5` | abandoned |
| `Shift+6` | ruin / destroyed |
| `Shift+7` | burnt |

### 3.5 Selection comes free

The house is registered through `BaseGameMap.constructions()` alongside the farm plots — an `id`, a
`title`, a `cells: Rect2i` and a `ground` key for the trodden plot beneath it. That single entry
gets it, at no extra cost: the selection ladder (`selection_at`), click-any-part-get-the-whole-thing
(`construction_at`), the outline (`construction_footprint`), the Terrain layer plate hiding it, and
the rule that a road may not be laid across it (`can_build_road`). The standing sprite is drawn over
the plot; the plot is what the map already knows how to reason about.

The band's title should read the appearance — "House (under construction)" — which is one line in
`selection_at`.

### 3.6 The seam for real

`Buildings.appearance` is a plain runtime var on the one test house. A construction system replaces
it with per-building state and a tick that advances it; nothing about the renderer changes.

---

## 4. Weather

**A flat overlay across the whole map, and nothing more.** Weather does not reach down into the
world: it does not sway a tree, darken a roof, wet a road or change anything the map draws. It is a
sheet of effect laid over the finished picture, and everything below it is unaware of it. That is a
deliberate boundary, not a shortcut — it means weather can be built, judged and thrown away without
touching a single line of the terrain, scatter or building code.

A new `core/map/weather_view.gd`: a `Control` with `mouse_filter = IGNORE`, added to
`_shell.base_layer` **above** the map view. It owns both halves of an effect — the full-screen wash
and the particles — because splitting one effect across two nodes to keep the wash under the
selection outline is not worth the seam. (Caveat, stated rather than discovered later: the wash
therefore tints the grid overlays and the selection outline slightly. Both are drawn bright enough
to survive it.)

| Key | Effect | Made of |
| --- | --- | --- |
| `Ctrl+0` | clear | — |
| `Ctrl+1` | rain | streak particles, downward + lateral bias; cool grey wash |
| `Ctrl+2` | snow | flake particles, slow fall + lateral drift; pale cool wash |
| `Ctrl+3` | fog | 2–3 layers of a soft tileable cloud, panning at different speeds; desaturating wash |
| `Ctrl+4` | windy | no precipitation — motes and leaves streaking across; faster cloud drift |
| `Ctrl+5` | overcast | wash only, no particles |
| `Ctrl+6` | storm | rain at a higher rate, heavy wash, timed white flash |

Particles are `GPUParticles2D` in **screen space** — they do not pan or zoom with the map. That is
both cheaper and more correct for an overlay: weather is between the player and the world, not in
it, and a snowflake that slid sideways when the map was dragged would read as a thing lying on the
ground rather than falling in front of the camera.

Season and weather stay orthogonal — snow in summer is available, and being able to produce it is
the point of a test harness.

### 4.1 Deferred: weather that reaches into the world

Recorded here so it is a decision rather than an omission. None of this is in scope now; each is a
separate, self-contained piece of work that composes onto the overlay above without changing it.

- **Trees and crops leaning in wind.** A vertex shader on the standing-sprite pass, swaying each
  sprite about its bottom-centre anchor by a function of world position and time. The anchor
  contract in §3.1 is what makes this possible later — every standing thing already knows where it
  meets the ground, which is exactly the pivot such a shader needs.
- **Wet ground and snow lying.** A second texture row or a blend weight per ground cell, driven by
  weather rather than season. Cheap to draw, expensive in art.
- **Snow accumulating on roofs.** Distinct from the winter repaint of §3.4: that is a season, this
  would be a weather state that comes and goes.
- **Puddles, footprint trails, wind-blown smoke from chimneys.** All content-side, all later.
- **Weather driving gameplay.** Nothing here writes to game state. The seam is a world-state key
  read by the same place that will eventually read the season from `GameClock`.

---

## 5. Textures to provide

### Ground — atlases, 1024x1024, 4 cols (variants) x 4 rows (seasons), 256 px cells

| File | Notes |
| --- | --- |
| `core/assets/map/atlas_grass.png` | **Replaces** the current 2x2 512² atlas. Rows: spring, summer, autumn, winter. |
| `core/assets/map/atlas_farm.png` | Replaces `test_farm1.png`. Seasons read naturally: ploughed wet earth / green rows / golden stubble / snow-dusted furrow. |

### Roads — 5x5 sheets, existing layout and 8 px per-cell padding

| File | Notes |
| --- | --- |
| `core/assets/map/road_atlas.png` | Exists. Becomes the non-winter sheet. |
| `core/assets/map/road_atlas_winter.png` | New. Same 16 pieces, same positions. |

### Trees — individual PNGs, 256 px per tile of width, transparent

`tree_pine_spring.png`, `_summer.png`, `_autumn.png`, `_winter.png`. The existing `test_tree.png`
becomes the summer one.

### The test house — individual PNGs, bottom-centre anchored per §3.2

| File | Season variants |
| --- | --- |
| `house_foundation.png` | — |
| `house_early.png` | — |
| `house_late.png` | — |
| `house_finished.png` | + `house_finished_winter.png` |
| `house_abandoned.png` | — |
| `house_ruin.png` | — |
| `house_burnt.png` | — |

Eight files. A winter repaint of any of the other six is a drop-in addition later — the table takes
a per-season entry and falls back to the default when there is none, so adding one is one line and
one file with nothing else to change.

Suggested footprint for the test house: **2x2 tiles**, image ~2.5 tiles wide → 640 px wide canvas,
height whatever the building wants.

### Weather — small, and I will generate placeholders so this is testable before the art lands

| File | Size | Notes |
| --- | --- | --- |
| `weather_rain_streak.png` | 8x64 | soft white vertical streak |
| `weather_snowflake.png` | 96x32 | three flake shapes in a 3x1 strip |
| `weather_fog.png` | 512x512 | **tileable**, soft greyscale cloud with alpha |
| `weather_mote.png` | 24x24 | leaf / dust speck |

### Why atlases for ground and individual files for buildings

Not a style preference — the two cases pull opposite ways:

- **Ground tiles** are drawn tens of thousands of times per frame at minimum zoom. One atlas means
  every cell on screen samples the same texture and the canvas batches them; separate files break
  the batch every few tiles. This reasoning is already written into `map_content.gd` and the season
  dimension does not change it.
- **Buildings** are a handful on screen, so batching buys nothing. They have wildly different sizes,
  which an atlas grid wastes space on; their soft alpha edges are the worst case for mip bleed
  across atlas cell boundaries (the bug `PIECE_PADDING` was written to fix, on sprites far more
  sensitive to it); and iterating one stage's art should touch one file rather than force a re-export
  of everything.

---

## 6. Files touched

**New**
- `modules/base_game/seasons.gd` — enum, per-season tables
- `modules/base_game/buildings.gd` — appearances, art table, the test house
- `core/map/weather_view.gd` — wash + particles
- `core/assets/map/weather/*` — placeholder art
- `tests/unit/test_seasons.gd`, `tests/unit/test_buildings.gd`,
  `tests/integration/test_season_and_stage_keys.gd`

**Changed**
- `core/map/overworld_map_view.gd` — `set_textures()`; scatter pass generalised into a standing pass
  taking buildings too; derived overscan; building distance threshold + flat fallback
- `modules/base_game/road_network.gd` — `_pieces` cache keyed by sheet; `textures(atlas)`
- `modules/base_game/map_content.gd` — house registered as a construction; farm ground per season
- `modules/base_game/screens/game_screen.gd` — `DEV_MAP_KEYS`, `_dev_map_keys()`, weather view wiring
- `tests/unit/test_overworld_map_view.gd`, `tests/unit/test_map_content.gd` — extended

Untouched on purpose: `input_actions.gd` (see §2.4), the selection dock, the HUD shell.

---

## 7. Phasing

Each phase is independently visible in the running game and independently revertable.

**Phase 0 — placeholders.** Generate stand-in art for everything in §5 (tinted variants of the
existing atlas, flat-colour house stages, procedural weather sprites) so every later phase is
testable the day it is written rather than blocked on painting.

**Phase 1 — season.** `seasons.gd`, `set_textures()`, the road sheet cache, `Shift+1..4`. Ground,
farm, trees and roads all change together. *Done when* all four seasons switch instantly with no
hitch and no seams.

**Phase 2 — the standing-sprite pass.** The contract in §3.1: buildings and trees in one sorted
pass, derived overscan, distance threshold and flat fallback, plus a debug overlay (`Shift+9`)
drawing each sprite's footprint rect and anchor cross so a misaligned sprite is obvious rather than
subtly wrong. *Done when* the house sits on its plot without bobbing at any zoom or pan, and sorts
correctly against trees in front of and behind it.

**Phase 3 — stages and states.** The seven appearances, `5..8` and `Shift+5..7`, the house
registered as a construction so selection and road-blocking pick it up. *Done when* clicking any
part of the house selects the whole house and the band names its stage.

**Phase 4 — weather.** `weather_view.gd` and `Ctrl+0..6`. *Done when* each effect reads as itself
over every season without hiding the map.

**Phase 5 — tests and docs.** Per §6, plus a note in `docs/ux_plan.md` retiring the "season tint is
deferred" line and the Settings screen's `planned` row for it.

Rough weight: phases 1 and 4 are straightforward; phase 2 is where the care goes and where a wrong
call is expensive to unpick later; phase 3 is mostly content once phase 2 is right.
