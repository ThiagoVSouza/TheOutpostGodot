# Handover — the new-game wizard, step 3

**Date:** 2026-07-30 · **Scope:** the Identity step and the flag designer. Everything
project-wide lives in `docs/handover_next_steps.md`; this file is only the wizard.

## Where things stand

- `main` is at `170e58c` (PR #77, card polish).
- **PR #78 is open** — `feat/wizard-card-scroll`: the prose scrolls inside each card,
  the pager's own scroll is gone, and every skinned scrollbar's end plates work again.
  435 tests green. Built and deployed to the S26 Ultra; boots clean, module discovery
  intact.
- Everything below is planned, not built. **It is blocked on two decisions the user
  still owes** (see the end).

## What step 3 is today

Hero name, sex, outpost name + Randomize, and the flag designer, all in one
`HFlowContainer` — two columns on desktop, two stacked blocks on a phone. Desktop uses
about a third of the page. The flag controls are three stock `ColorPickerButton`s (the
last stock Godot chrome on the wizard) and two `<` / `>` steppers that cycle **14
patterns and 13 emblems blind** — you cannot see what you are picking.

## A. Split the step

Split on a real seam — the person and the place — rather than an arbitrary halfway point:

- **Step 3 "Hero"** — hero name, sex, and later the appearance work.
- **Step 4 "Banner"** — outpost name + Randomize, and the flag designer.

The wizard goes 4 → 5 steps. This is mechanical: `_goto_step`, `_on_next` and `_on_back`
already read `_step_pages.size()` / `STEP_TITLES.size()`, and the width test iterates
`STEP_TITLES`. **`tools/capture_screens.gd` has `WIZARD_STEPS` hardcoded** — the one
place that needs hand-editing.

Recommended on *every* device, not only on a phone. The responsive alternative —
computing the step count from the window the way `CardPager` computes its card count —
makes "Step 3 of 4" mean different things on different machines, shifts every step
index, and needs a remap when a resize crosses the breakpoint mid-wizard. Five fixed
steps cost a desktop player one extra click and cost the code nothing.

The split is not cosmetic: it is what makes room for B. A swatch row plus two thumbnail
grids will not share a phone screen with three text fields.

## B. The banner designer

1. **Painted swatch rows replace the colour pickers.** Eight swatches per layer
   (Cloth / Pattern / Emblem), pick-one with a selected ring. The palette is already
   ported — `FLAG_PALETTE` in `core/screens/new_game_screen.gd` holds the legacy's eight
   hexes. Wants a `SwatchRow` in `core/ui/` and a `UiSkin.swatch_style()`.
2. **Thumbnail grids replace the `<` / `>` steppers.** A wrapping grid of square cells,
   "None" first, each showing that pattern (or emblem) in the colours currently chosen,
   retinted live when a swatch changes.
3. **A larger preview.** It is the point of the step and is currently 140px wide.

Layout: preview beside controls on desktop, above them on a phone — the same
`HFlowContainer` arrangement already load-bearing in this step.

## C. Hero customization (deferred)

Do **not** add an empty third step. Move `sex` out of the form and into the Hero step —
it is a hero attribute, not a form field, and it is already drawn as a card-style
pick-one. That gives the Hero step real content today, and the appearance UI lands
beside it when there is art. If it grows big enough to want its own step, Hero splits
again then.

## Order of work

1. Merge PR #78.
2. The split (steps 3/4, `capture_screens.gd`, tests) — small and verifiable alone.
3. Swatch rows.
4. Thumbnail grids.

Splitting first means the designer work lands in a step that already has room.

## Gotchas earned here

- **GUI input propagates up the parent chain only, never sideways to a sibling drawn
  beneath.** A card is a `PanelContainer` holding a `Button` and its content as
  siblings, so any control on the card's face that is not `MOUSE_FILTER_IGNORE` eats
  the card's click, and no `mouse_filter` value hands it back. `core/ui/card_scroll.gd`
  is the deliberate exception and explains itself.
- **A `ScrollContainer` leaves its bars' `step` at 0** so dragging and the wheel move by
  whole pixels — and `ScrollBar` moves the view by exactly that step when an end plate
  is pressed, so painted arrows do nothing. `UiSkin.SCROLL_STEP` / `custom_step` is the
  fix, set once in `apply_scroll_bar`.
- **The pattern and emblem PNGs are pure alpha masks** — `flag.gdshader` reads
  `texture(...).a` and ignores RGB. A thumbnail cannot therefore be a `TextureRect` with
  `modulate` (that multiplies the PNG's RGB, which is only white if every mask happens
  to be); it wants a ~10-line square variant of the flag shader, or a mini `FlagView`
  per cell at the cost of a pole in every thumbnail.
- **Verify the masks read at thumbnail size before building the picker around them.**
  Some heraldic patterns are fine detail that turns to mush at 56px. Render the sheet
  and look first; if several are unreadable, the cells get bigger and the grid scrolls.
- The legacy designer's content is at
  `C:/Dev/TheOutpost/content/base/screens/new-game-identity.json` (palette, 14 patterns,
  13 emblems) and its UI at `src/ui/components/flagDesigner.ts`, with captures under
  `artifacts/wizard-captures/`.

## Open decisions — blocking

1. **Five fixed steps on every device, or a responsive step count?** (Recommendation:
   fixed.)
2. **Does `sex` move into the Hero step**, with appearance joining it later — or is a
   visible appearance stub wanted now so the flow shape is real? (Recommendation: move
   `sex`, no stub.)
