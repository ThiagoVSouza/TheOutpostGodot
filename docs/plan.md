# The Outpost — Plan

**Living document.** Update as work lands: move items between sections, record what
actually happened, and when a milestone changes shape say why. A plan that only ever
gets appended to is a wish list.

Decisions and their evidence: `docs/decisions.md`. Measurements:
`docs/benchmarks/milestone1_results.md`. Original brief: `docs/initial_briefing.md`
(no longer authoritative on every point — see the note at its head).

**Agent handover:** `docs/handover_next_steps.md` — task-level next steps with
gates. **GATE 0 there is binding: no production code before a direction review
with the user.**

Last updated: 2026-07-17 (T2 remote backend)

---

## Where we are

**Milestone 1 is complete** — the vertical slice runs on desktop and on a physical
S26 Ultra, and the model decisions are settled and evidence-backed.

**What exists:** core kernel (boot, modules, screens, state, commands, event bus,
clock, scheduler, workflow engine), `base_game` module (dice tool, grant_resource
command, chat screen), `FakeAiBackend`, AI trace, 28 GUT tests, Android
export/deploy tooling.

**What does not exist yet:** any real inference in-game, deterministic adjudication
(D4 is a document, not code), save/load, memory/retrieval, the map, the economy.

**The orchestration design is reviewed and adopted** (2026-07-17):
`docs/Orchestration_brainstorm.md`, reconciled with this log — D4 amended
(intent classification, `tool_calls`), D19–D23 added, Enhanced mode deferred
(D7 addendum). Its first pass is the M3 walking skeleton below.

**Two things gate the next step:**

1. `AiBackend.generate()` is **synchronous**. Fine for an instant fake; a real turn
   takes 0.85–4 s and would freeze Godot's main thread. Fixing it ripples through
   the orchestrator, chat screen and tests — so it goes before more orchestrator
   code, not after.
2. **D4 makes most of the orchestrator code, not AI** — deterministic, and therefore
   testable against `FakeAiBackend` with no model. That is a gift; use it.

---

## M2 — One real turn, end to end

**Goal:** type into the Godot app, get real E2B prose back.

- Async seam for `AiBackend` (blocks everything else; do it first) — design
  decided, D22: main-thread orchestrator; request-handle interface
  (`chunk`/`completed`/`failed` + `cancel()`); the fake must complete
  deferred, never synchronously
- ~~`RemoteLlamaBackend` — HTTP client to `llama-server`~~ **Done (T2):**
  non-blocking `HTTPRequest` transport, request cancellation/timeout cleanup,
  llama.cpp chat-response/timing parsing, canned-response tests, and an explicit
  development opt-in (`OUTPOST_AI_BACKEND=remote-llama`). Fake remains the default;
  automatic visible degradation remains T5.
- Local mode: spawn `llama-server` on `127.0.0.1`
- Model-as-configuration (D6): backend, `-rea off` (D7), `--cache-reuse` (D8), ctx,
  threads, RAM floor — never a bare GGUF path
- Graceful fallback to `FakeAiBackend` when the server is absent (D16's rule)
- Input seam takes **text from a source**, not from a `LineEdit` (D18)

**Why first:** biggest remaining unknown, and the async change is cheapest now.

**Free consequence:** this *is* D16 dispatch. Local is dispatch to `127.0.0.1`;
remote is a config change. Add a QR carrying `{url, api-key}` and LAN pairing is a
scan (D16).

**Known limit:** `RemoteLlamaBackend` **cannot ship on mobile** — iOS forbids
spawning executables, Android blocks exec from app data. That is M6. M2 is a
desktop-and-dev capability that happens to also be a shipped feature (dispatch).

---

## M3 — Deterministic orchestration (D4)

**Goal:** the same action produces the same economy regardless of model or language.

```
message -> classify intent (AI proposes from enum; code validates — D4 amended)
        -> recall memories (AI)
        -> decide roll (code, rules) -> roll (code, seeded)
        -> compute outcome + reward (code, rules)
        -> build/validate/apply command (code, whitelist)
        -> narrate the decided outcome (AI) -> write back memories (AI)
```

**Spec:** `docs/Orchestration_brainstorm.md` (reviewed 2026-07-17; its status
header separates M3 scope from target-architecture reference).

- ~~**Phase 0 spikes first**~~ **Done (2026-07-17), both passed** —
  `docs/benchmarks/orchestration_spikes.md`. D19: grammar + `-rea off` +
  prefix cache all coexist; no-grammar control misformatted on its first try.
  D23: ~36 MiB per warm 4K slot, automatic LCP slot routing (no pinning),
  warm routing calls ~36 ms. The micro-prompt design stands. Phone re-measure
  deferred to M6.
- **Walking skeleton:** grammar-constrained intent classification (real E2B)
  → one deterministic workflow (existing dice + `grant_resource`) → bounded
  narration → file-based trace (D21 — **revisit before building traces**)
- AI output only via the pipe protocol (D20); `tool_calls` retired
- Rules own every number. The AI never emits a `grant_resource` amount.
- Rework `AiOrchestrator`: it currently does the brief's model-driven tool calling,
  which D4 removed.
- Heavy test coverage — almost all of this is testable with `FakeAiBackend`.

**Why it matters:** measured today — the same 17/20 roll paid **+17 / +20 / +15**
across three models, and Bonsai-4B gave three different outcomes for one action in
pt/es/fr. Every system built before this is built on the wrong foundation.

**Open (D4):** where the line sits for requests the rules do not cover ("I sing to
the goats"). Probably: narrate, no state change.

---

## M4 — Save/load + migrations

**Goal:** state survives closing the app.

- `core/save/save_manager.gd` is still a stub seam
- Module-declared migrations (the brief requires this; cheaper now than retrofitted)
- AI-trace persistence → replay, which **D4 makes genuinely achievable** (outcomes
  are code, so a recorded session replays exactly)

**Independent of the AI work.** Unblocks Android backgrounding/resume, and makes the
Back-button problem worth fixing (right now there is nothing to lose).

---

## M5 — Memory and retrieval

**Goal:** the game master remembers.

- D4's other AI job: read/write memory
- The brief's "retrieve relevant memories and game knowledge"
- D8's prefix caching is what makes a large retrieved context affordable (~20x)

---

## M6 — Mobile shipping path + voice

**Goal:** the game ships on a phone, and you can talk to it.

- **In-process GDExtension binding to `libllama`** — required; M2's subprocess
  approach cannot ship on mobile
- Per-platform builds: Windows CUDA, Android arm64 CPU (done once already), iOS
  Metal via XCFramework (D10 — source-verified, never run)
- **Voice input via whisper.cpp** (D18) — same ggml toolchain, so largely
  incremental here. Models: `ggerganov/whisper.cpp` GGML `.bin`, **not** safetensors
- **Measure memory, not just accuracy** — whisper `small` (~466 MB) on top of E2B
  (2.43 GiB) competes for exactly the constraint that killed E4B (D5)
- Possible home for the **E4B/LiteRT-LM question** (D5): E4B does 2 t/s under
  llama.cpp and 10+ t/s in Google's Edge Gallery on the same handset. If that gap is
  the runtime, a mobile quality upgrade may exist after all

---

## M7 — The game

Map, economy, settlement, factions. The brief's benchmark scene
(`tools/benchmark.ps1`, still a stub) only becomes meaningful here — its scenarios
are all map-idle / map-moving / large-settlement.

---

## Unscheduled — cheap, self-contained, do anytime

**Android UI issues** (found during the milestone-1 deploy, deliberately not fixed):

| Issue | Note |
|---|---|
| Landscape orientation | No orientation set; a chat game wants portrait |
| Fonts far too small | Default theme at density 450 is barely legible |
| No safe-area handling | Content at extreme top-left; punch-hole will clip it |
| Back button quits instantly | No confirmation, state lost. **Gets urgent at M4** |
| Keyboard overlays input | Layout does not shift |

**`export_presets.cfg`** — required to export, gitignored by Godot's default. Ours
holds no secrets. Untracked pending a decision; without it
`tools/export_android.ps1` cannot run on a fresh clone.

**MTP retest via `-hf`** (D15) — our `-md` measurement is untrustworthy; reports
elsewhere claim up to 3x.

---

## Carried open questions

| Question | Decision | Blocking |
|---|---|---|
| Does E4B's 5x gap vs Edge Gallery mean LiteRT-LM, and is a 2nd runtime worth it? | D5 | M6 |
| Per-store distribution: Play Asset Delivery / iOS ODR size limits vs 2.43 GiB | D13 | shipping |
| Internet dispatch needs a rendezvous — service, Tailscale, or document-and-defer? | D16 | post-M2 |
| Whisper `small` alongside E2B on a real phone — does it fit? | D18 | M6 |
| Where do rules end and narration begin for uncovered requests? | D4 | M3 |
| Trace storage files vs SQLite — additional thoughts to review together | D21 | M3 traces |
| Warm-slot behavior on the phone (desktop-verified 2026-07-17) | D23 | M6 |
| Grammar via the in-process sampler API (source-verified, never run) | D19 | M6 |
