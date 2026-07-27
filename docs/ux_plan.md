# The Outpost — Game UX plan

**Source:** the six wireframes in `docs/UX/`, added 2026-07-27.

| File | State it describes |
|---|---|
| `Desktop_Main_Game_Interface.png` | The base state, annotated — every region is named |
| `Desktop_Expand_chat.png` | Chat expanded over the map |
| `Desktop_Menu_Screen.png` | A side-menu destination open as a page |
| `Mobile_Main_Game_Interface.png` | The same base state re-flowed + the expanded menu list |
| `Mobile_Expanded_chat.png` | Chat expanded on a phone |
| `Mobile_Menu_Screen.png` | A page on a phone |

This document is the implementation plan for them. It is a plan, not a decision
record: where it changes something already decided, it says so and names the entry
that owes an update.

---

## 1. What the wireframes specify

### 1.1 Persistent chrome

Present in every state, on both platforms. Nothing here is ever replaced — only what
sits *inside* it changes.

| Region | Contents | Backed by today |
|---|---|---|
| Top bar | Flag (overhangs below the bar) · domain name "Black Rock" · domain **level** "Outpost" · coins `10000` with `-123` in red · population `100` with `+12` in green · date "January 1st 374" · speed buttons `❚❚ > >> >>>` | flag ✅ `FlagView`, name ✅ `Entities`, coins ~ (`gold`), the rest ✗ |
| Left rail (desktop) | Seven icon buttons: Domain, Population, Economy, Military, Diplomacy, Knowledge, Main Menu | ✗ |
| Bottom-right | Map Layers | ✗ (one layer exists) |
| Bottom edge | Chat input + send `>`, full width, always visible | ✅ |
| Centre | The overworld map | ✅ but as an *overlay*, not the base layer |

**Mobile re-flows the same regions, it does not redesign them.** The date drops to a
second right-aligned row, only `>>>` stays in the top bar, and the left rail collapses
into a bottom-right **Menu** button that expands to a labelled list. That list has
**eight** entries, not seven: Map Layers folds in, plus a Return button to dismiss it.

### 1.2 The four states

1. **Main** — map visible, chat collapsed to its input line.
2. **Expanded chat** — event/location image at top, message list (`King says:` /
   `You say:` with avatar slots), an inline **reasoning timeline**
   (`Understanding request` → ⚪20 `Roll Dice: 20 - Critical Success` →
   `Analyzing the result`), collapse chevron top-right.
3. **Page** — `Page Title` + ✕, empty body. One shape, seven destinations.
4. **Event** — not drawn separately, but specified by the layout rules below. The
   game master is presenting something that demands an answer: time is stopped, chat
   is full height, and it cannot be resized away.

States 2 and 3 share their geometry exactly. Building them as one component is the
wireframes' strongest structural hint.

### 1.3 Layout rules

These came from the design review on 2026-07-27 and are not visible in the drawings.

1. **Desktop, page open + chat opened → both at half height, both interactive.** The
   content area splits vertically; the player can read a page and talk at the same time.
2. **The split is draggable to any position.**
3. **During an active event the split is locked**: chat takes the full height and time
   is stopped. Not a preference — a hard state.
4. **Everything animates**: button hover, expand/collapse, panel open/close.
5. **Mobile has no split.** Page and chat are mutually exclusive — opening chat hides
   the page. If the on-screen keyboard comes up, chat halves; in event mode the image
   hides rather than the conversation shrinking further.
6. **Keys:** `Esc` closes the topmost thing. `Space` stops time, and pressing it again
   returns to the *previous* speed. `Enter` opens chat.

Rule 6 lands well on what exists. `BACK_CLOSE` is already `KEY_ESCAPE`. `PASS_DAY` is
already `KEY_SPACE` and is exactly the action being replaced, so the key keeps its
meaning-in-spirit while changing mechanism. `Enter` needs care only because a focused
`LineEdit` submits on it — but `_unhandled_input` already gives the focused input
first claim, which `chat_screen.gd` documents as the reason `FOCUS_INPUT` can be a
bare letter. Same mechanism, no new problem.

---

## 2. What this changes structurally

### 2.1 The map and the chat swap places

Today `chat_screen.gd` is the routed screen and `MapOverlay` is a child it opens. The
wireframes invert that: the map is the base layer and chat is a dock over it.
`map_overlay.gd`'s reason for existing ("routing away would drop the chat log")
disappears, because neither is a route any more — both live inside one screen.

### 2.2 A second navigation layer

`ScreenRouter` swaps one whole screen and knows nothing about a *current panel*. It
stays exactly as it is for splash → loading → menu → wizard → game. Inside the game,
a **panel host** with persistent chrome around it is a different thing and needs its
own small layer. Main Menu is one of the seven destinations and opens as a panel
(Save / Load / Settings / Quit to title) — the player does not leave the game shell
unless they choose to.

### 2.3 Time becomes real

`❚❚ > >> >>>` is the Paradox model: time flows, the player pauses to act. That
**reverses the 2026-07-24 call** recorded in `plan.md` under *In-play time-advance*,
which chose explicit "Let a day pass" over auto-advance. `decisions.md` owes an entry
for the reversal — the reasoning being that the wireframed HUD is built around a
world that moves on its own, and a strategy game's pause button is a different
promise from a turn button.

`GameClock` stays the authority. A driver calls `advance(1)` on a timer; nothing
below the UI learns that time became continuous.

### 2.4 A real `Theme`

Six wireframes of consistent chrome is where `ShellPalette` stops scaling — its own
docstring says "when a real theme lands, this is what it replaces." It also fixes the
unthemed exit dialog already on the next-steps list.

---

## 3. Architecture

```
core/ui/
  hud_shell.gd     mechanism only: named regions, breakpoint, panel host, split
  hud_panel.gd     the "Page Title + ✕" shape, shared by pages and expanded chat
  motion.gd        named durations + easing, so transitions cannot drift per screen
  theme/           the real Theme (phase 2)

core/calendar/
  time_driver.gd   accumulates delta, calls GameClock.advance(1) at the current speed
  date_format.gd   total_days → "January 1st 374"

modules/base_game/screens/
  game_screen.gd   composes the above: map base layer, top-bar widgets, the seven
                   destinations, the chat dock. Replaces chat_screen + map_overlay.
```

**One shell, not two scenes.** Desktop and mobile have identical regions and differ
only in placement, so a width breakpoint inside `HudShell` swaps rail ↔ menu button
and split ↔ mutually-exclusive. Two scenes would drift within a week.

### 3.1 The world gate

Rule 3 says time stops during an event. The driver must not ask the UI about that —
so the gate is a kernel-level predicate the driver reads and the UI *also* reads:

> The clock refuses to advance while the orchestrator is busy, a `confirm` is pending,
> or a `PlanTicker` tick is draining.

This is the invariant `_on_pass_day` already enforces ("the world must not move under
an unresolved action"), made continuous. `PlanTicker`'s existing drain guard — written
for a race that only occurred when `advance(n)` emitted several `day_passed` at once —
becomes load-bearing rather than defensive, because real time hits it constantly.

"Active event" is the UI's name for the same predicate being closed. Today that means
a pending `confirm` (B4b); later it means authored event templates too. It must live
where both the driver and the shell can see it, not in a screen field.

---

## 4. Phases

### Phase 1 — the HUD shell and the map as base layer

`HudShell` + `HudPanel` + `motion.gd`; `game_screen.gd` composing them; the map moved
underneath; the split (rule 1) with its drag (rule 2) and its mobile
mutually-exclusive variant (rule 5).

**Nothing may regress.** The current dev row (save / load / new game / trace toggle /
dev ask) moves into the Main Menu panel, and the on-screen-keyboard handling in
`chat_screen._process` moves to the dock rather than being dropped — it is the fix for
a real device bug, not decoration.

*Done when:* both breakpoints render in `tools/capture_screens.gd`; a page and chat
can be open together on desktop at a dragged split; opening chat on mobile hides the
page; every control that existed before still works.

### Phase 2 — Theme, motion, and the top bar for real

The `Theme` resource, applied to the shell screens as well so the app stops being two
visual languages. Then the top bar's real contents: flag, domain name, coins,
population, date. `core/calendar` has `total_days` and 30-day months but no month
names and no era, so the date formatter is new work.

*Done when:* the top bar reads live state on desktop and mobile, and the exit dialog
is themed.

### Phase 3 — the chat dock

**Completed (2026-07-27):** structured avatar-backed message rows, the event-image placeholder,
and a shared `AiTimeline` renderer are implemented. The game conversation and playground render
the same trace, including `workflow_rolled` dice results; `tools/capture_screens.gd` now captures
a real resolved turn as visual evidence.

Message rows with avatar slots, replacing the single `RichTextLabel` blob. The
reasoning timeline maps onto `AiTrace` almost exactly — classify → roll → narrate —
and the playground already renders it, so that renderer gets extracted into a shared
control rather than written twice. Event image slot with placeholder art. Collapse
chevron, with the phase-1 transitions.

*Done when:* a real turn shows its dice roll in the conversation.

Showing the roll is also a design statement worth making deliberately: D4 says the
rules decide every number and the AI only narrates. In-chat dice make that invariant
something the player can see rather than something the architecture merely promises.

### Phase 4 — time

**Completed (2026-07-27):** `TimeDriver` advances the authoritative clock every five seconds at
1x (2.5 seconds at 2x, 1.25 at 3x), with speed reset to paused after a load. The kernel-owned
world gate stops time for AI work, pending confirmations, and plan-tick drains; the confirmation
UI renders that state as a locked, full-height event conversation. Desktop shows all four controls;
mobile retains `>>>` as specified. The capture tool records this active-event state.

`TimeDriver`, the four speeds, the world gate, event mode, and the key bindings. The
driver is off under `OUTPOST_TEST_RUN` and `GameClock` remains the authority, so the
suite stays deterministic. Speed does **not** persist into a save — loading opens
paused.

New actions: `toggle_pause` (Space, remembering the previous speed per rule 6),
`speed_1/2/3`, `open_chat` (Enter). `PASS_DAY` retires. `BACK_CLOSE` gains the panel
stack. Each moves out of the settings screen's `planned` list only as it lands — that
discipline exists precisely to stop a rebindable key that does nothing.

*Done when:* time runs, Space toggles it back to the speed it was at, and an event
stops it without the driver knowing what an event is.

### Phase 5 — the seven destinations

**Completed (2026-07-27):** `HudPanelRegistry` is the module registration seam for in-game pages.
The base game contributes Domain, Population, Economy, Military, Diplomacy, Knowledge, Main Menu,
and Map Layers. Domain and Population render current state; the four unavailable systems say exactly
what is deferred; Map Layers names the real base-terrain layer. The HUD contrast was lifted at the
same time so pages, buttons, and chrome read as distinct layers over the map.

A panel registry so modules contribute pages, mirroring how they already register
screens and commands. Domain and Population can read real state today. Economy,
Military, Diplomacy and Knowledge become titled empty pages until M7 fills them —
honest placeholders, not fake data. Map Layers ships with the one layer that exists.

---

## 5. What needs game systems that do not exist

Named here so no one builds a convincing-looking lie into the top bar.

- **Coins / population deltas.** `-123` and `+12` are per-tick income and upkeep. No
  economy produces them. Seed a `population` resource and render `0` deltas until M7,
  rather than inventing numbers.
- **Domain level.** "Outpost" implies a ladder (Outpost → Village → Town → …). It is
  the game's growth axis and nothing models it. Display a placeholder tier; design the
  system in M7.
- **Event imagery.** Needs an art key on events and a pipeline behind it.
- **Map layers.** Only the base biome layer was ported; corner blending, decorations
  and season tint are deferred map polish.
- **Date epoch.** "Year 1" (`core/calendar/date_format.gd`) is a placeholder — no lore
  has fixed when the calendar starts, so Phase 2 picked the outpost's own founding.
  Twelve English month names are a placeholder too; a setting-appropriate calendar is
  content work, not UI work, and can replace both without touching `GameClock`.

---

## 6. Open questions

| Question | Needed by |
|---|---|
| How fast is 1x? A day per second is a different game from a day per ten seconds. | Phase 4 |
| Does an AI turn pause time, or only a `confirm`? The gate as written pauses on both — worth feeling in the hand. | Phase 4 |
| Is the reasoning timeline always shown, or a preference? It is transparency for some players and clutter for others. | Phase 3 |

---

## 7. Traps to carry in

- **`set_anchors_and_offsets_preset`, not `set_anchors_preset`**, for anything built
  in code — the latter preserves the current rect, and a code-built control has none
  at `_ready`. This is what made the Map button open an invisible overlay.
- **Keyboard height is physical pixels**, the margins it feeds are stretched logical
  units — ~1.5x apart on the S26 Ultra. Same trap as `SafeArea`.
- **Safe-area insets now touch three edges**, not one: rail, dock and top bar all sit
  against screen edges.
- **Test count is the branch-drift detector.** Baseline is **413** as of Phase 2 (PR #63).
- **`tools/capture_screens.gd` is how you look at the game — but only if it runs
  windowed.** Under `--headless` it hangs forever on `RenderingServer.frame_post_draw`,
  which the dummy renderer never fires. It has found real bugs every time the flow was
  rendered rather than asserted, including three a real phone found that no desktop
  capture could (Phase 1): a base-layer screen needs its own background paint or the
  map's letterboxed edges (it contains-fits, never crops) show Godot's default grey
  instead of the shell's dark background; a floating element must anchor to the region
  it visually floats over (`_stage`), not the shell as a whole, or it lands on
  whatever chrome happens to sit at that corner of the *window*; and Android's touch
  pinch-zoom needs `input_devices/pointing/android/enable_pan_and_scale_gestures`
  (off by default) plus an `InputEventMagnifyGesture` handler — single-finger pan
  works without either, via mouse-from-touch emulation, which is why only zoom read
  as broken.
- **A compile error one file away can misreport as "nonexistent function."** A
  Variant-inference error inside `date_format.gd` (an untyped array literal assigned
  with `:=`) surfaced as `Invalid call. Nonexistent function 'format' in base
  'GDScript'` at the *call site* in `game_screen.gd`, not at the broken file — cost real
  time chasing a naming collision that did not exist. If a freshly-added class's static
  call fails after `--import`, suspect the new file does not compile at all before
  suspecting the class cache.
