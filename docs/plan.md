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

Last updated: 2026-07-20 (M2 complete and verified; M3 split into M3a/M3b)

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

~~**Two things gate the next step:**~~ **Both resolved.** The async seam shipped in
T1 (D22), and D4-makes-most-of-this-code remains the standing gift: nearly all of
M3a is deterministic and testable against `FakeAiBackend` with no model at all.

**Milestone 2 is complete** (2026-07-20). Real E2B prose in the running app, warm
turns at 0.80–0.85 s with the prefix cache visibly working — measured through the
finished T5/T6 path, not an earlier one. See `docs/benchmarks/milestone2_exit_e2b.md`.

**Gates now:** none blocking. D21 was settled 2026-07-20 and trace code is
unblocked; D24–D29 are promoted. GATE 0 for M3a was satisfied by the planning
conversation on 2026-07-20.

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
  development opt-in (`OUTPOST_AI_BACKEND=remote-llama`). Fake remains the default
  for tests and intentional offline development; T5 owns the production unavailable
  state and recovery policy.
- ~~Local mode: spawn `llama-server` on `127.0.0.1`~~ **Done (T3):**
  `OUTPOST_AI_BACKEND=local-llama` loads the configured desktop profile, probes
  Windows available RAM and CUDA VRAM, starts `llama-server` asynchronously, and
  polls `/health`. A healthy existing server is reused; only a process owned by the
  app is terminated on exit. Bonsai remains the default and
  `OUTPOST_MODEL_PROFILE=gemma_e2b_desktop_cuda` selects the E2B verification
  profile. The local backend preserves the `AiRequest` contract while startup is in
  progress, then delegates requests to the T2 HTTP transport.
- Model-as-configuration (D6): backend, `-rea off` (D7), `--cache-reuse` (D8), ctx,
  threads, RAM floor — never a bare GGUF path
- **T4 done:** `ModelProfile` + `ModelCatalog` resources carry backend, executable
  and weights paths, `-rea off` (D7), `--cache-reuse` (D8), ctx, slots, threads,
  and RAM/VRAM floors. E2B remains an explicit verification profile; Bonsai-27B is
  the configured desktop default (D5). T3 will consume the selected resource to
  launch the server.
- ~~T5 revised~~ **Done (T5):** kernel-owned `AiAvailability` implements the
  policy — a backend failure (never a cancellation) blocks orchestration with a
  visible outage state on the event bus; at most three automatic recovery probes
  per outage (2 s/5 s/10 s backoff; `local-llama`'s first attempt is a bounded
  manager restart, `remote-llama` probes `/health`); a stable UNAVAILABLE state
  with a chat Retry control that starts a new sequence; zero backend calls and
  zero state changes while blocked. The kernel placement matters: the workflow
  DSL runtime (PR #12 §8) becomes this state's second consumer.
- ~~Input seam takes **text from a source**, not from a `LineEdit` (D18)~~
  **Done (T6):** kernel-owned `AiInputRouter` is the only path from player text to
  the orchestrator. Sources (`AiInputSource`) submit by id and never hold a result:
  every turn — success, busy rejection, or failure — is broadcast as
  `ai_turn_completed` on the event bus, tagged with its originating source. The chat
  screen is now just the `typed` source; it renders whatever turn completes,
  whichever source produced it, so future voice (M6) and trace replay (M4) plug in
  without touching it. The source id rides in the orchestrator context and lands in
  the `build_request` trace stage.

**Why first:** biggest remaining unknown, and the async change is cheapest now.

**Free consequence:** this *is* D16 dispatch. Local is dispatch to `127.0.0.1`;
remote is a config change. Add a QR carrying `{url, api-key}` and LAN pairing is a
scan (D16).

**Known limit:** `RemoteLlamaBackend` **cannot ship on mobile** — iOS forbids
spawning executables, Android blocks exec from app data. That is M6. M2 is a
desktop-and-dev capability that happens to also be a shipped feature (dispatch).

---

## M3 — split into two phases (decided 2026-07-20)

M3 now has two phases, run in order. **Downstream milestones keep their numbers** —
M4 is still save/load, M6 is still mobile+voice. That is deliberate: renumbering
would invalidate 16 milestone references in `decisions.md` alone (13 of them to M6),
and brainstorm §11 already assumed the DSL lands inside M3.

**Why the DSL goes first:** M3b's deterministic workflows need a workflow runtime
worth building on, and D4's difficulty bands live in DSL rule tables. Building the
pipeline on the v0 engine would mean building it twice. The cost is that the
+17/+20/+15 problem stays unfixed one phase longer — accepted knowingly.

---

## M3a — The workflow DSL kernel + traces (current)

**Goal:** an authored workflow language the game's mechanics can actually live in,
and traces a human can read to verify an orchestration behaved correctly.

- **Traces first** (D21) — **done (A1)**: `AiTraceWriter` writes JSONL per
  orchestration (one stage per line) + a Markdown export under `user://traces/`,
  on by default in dev builds. `AiTrace` gained an `id` and `to_markdown()`; the
  writer is the sink it was missing. On-by-default is opt-out under
  `OUTPOST_TEST_RUN` (set by `tools/test.ps1`) so the suite never writes unbounded
  files into a real dev's `user://` — no retention policy yet (M4). Verified by a
  human reading one real trace end to end, the stated reason traces exist at all.
- **DSL core** (D24) — **done (A2)**: `core/workflow/dsl/` — op registry (vocabulary
  + purity flags), sigil resolution, expression evaluator, registration-time strict
  validator. JSON canonical form only — **no text parser** (deferred to D28). A
  collaborative syntax review settled the open §12 details: atomic sigils + explicit
  `get` (no dotted access), lowercase operators, computed keys allowed, and a new
  **global-variable scope (D31)**. Validator accepts the two worked examples and
  rejects every purity/structure violation; 36 new tests.
- **Resumable instances** (D25) — **done (A3)**: `core/workflow/` — the executor
  (`workflow_executor.gd`) runs validated workflows on an **explicit control stack**
  (so a resume point serializes), with real effects through CommandBus/EventBus and
  the D31 `GlobalStore`. Suspends at `wait_game_time`/`confirm` and resumes from a
  **structured `pc_stack`** (the §12 open detail, settled in review) that survives a
  JSON round-trip — including suspension nested inside a loop's if-branch — and
  re-checks `resume_require` on wake (§5.3). 25 tests. The instance snapshot
  (`workflow_instance.gd`) is the save contract; M4 wires the save folder.
- **Migrate off v0** — **done (A4)**: `Scheduler` runs due workflows through
  `WorkflowExecutor` (validated when scheduled), `AiOrchestrator._handle_schedule`
  validates with `WorkflowValidator`, and base_game's month-end workflow is rewritten
  in the new DSL (`let`/`emit`/`run_command`; its old `narrate` free-text line became
  an `emit` of a message key + values, per the i18n discipline). The chat screen
  renders `workflow_emit`. **`WorkflowEngine` v0 and its test are deleted.** 131 green.
- **Narration contract** (D4 amendment) — **done (A5)**: the `narrate` op —
  instruction, context, verbosity, output language — is registered vocabulary
  (effectful, statement-only), validated (instruction/verbosity are authored
  literals, never computed — D4), and executed through a `DslNarrator` seam
  (`FakeNarrator` default). It surfaces prose as `result.narration`, a
  `workflow_narrated` event, and an optional `$$as` binding. **Seam is synchronous
  for now** — the real `AiBackend`-backed narrator makes it an in-memory await (D30)
  and turns the executor into a coroutine; that lands with M3b. 5 tests.

**Exit — met** (A1+A3+A4): the month-end workflow runs on the new kernel with v0
deleted; a suspended instance survives a restart; a trace of one orchestration is
readable end to end. A5 remains as an M3a task but is not part of the exit criteria.

---

## M3b — Deterministic orchestration (D4)

**Goal:** the same action produces the same economy regardless of model or language.

```
orchestrator (code): holds exactly one hardcoded thing — the entry workflow's id

entry workflow (authored): context-fetch, memory read, guardrails,
  classify intent (AI proposes from a registry-defined enum; code validates
  — D4 amended), dispatch to the workflow that intent selects

selected workflow (authored, M3a kernel): its own shape decides what happens —
  preconditions, modifiers, difficulty classification (AI, closed enum), a
  seeded roll if the action warrants one, or none at all — then
  build/validate/apply command (code: CommandRegistry + CommandBus, the
  whitelist), narrate the decided outcome (AI: instruction + context +
  verbosity + language, itself just an op a workflow invokes), write back
  memories (AI)
```

**Note the change from the original sketch:** "decide roll → roll → compute
outcome" was never fixed orchestrator code (D4 amendment). Neither are guardrails,
classification, or narration (D30) — those are authored workflows too, not
orchestrator stages. The orchestrator does not own a sequence at all; it executes
whatever workflow is loaded, and workflows call other workflows. The DNA is the
workflow; the orchestrator is the ribosome — fixed, trusted machinery that
executes but never decides what to build. The one fixed point is the entry
workflow's id, hardcoded in the orchestrator to break the bootstrap circularity of
"classification picks the workflow, but classification is itself a workflow." See
D30 for the full model, the capability-profile trust boundary this puts on
guardrails-as-content, and why AI calls are in-memory awaits rather than
checkpointed suspension points.

**Spec:** `docs/Orchestration_brainstorm.md` (reviewed 2026-07-17; its status
header separates M3 scope from target-architecture reference).

- ~~**Phase 0 spikes first**~~ **Done (2026-07-17), both passed** —
  `docs/benchmarks/orchestration_spikes.md`. D19: grammar + `-rea off` +
  prefix cache all coexist; no-grammar control misformatted on its first try.
  D23: ~36 MiB per warm 4K slot, automatic LCP slot routing (no pinning),
  warm routing calls ~36 ms. The micro-prompt design stands. Phone re-measure
  deferred to M6.
- **Walking skeleton** — **built with fakes (M3b-3)**: `AiOrchestrator` is now the
  ribosome (D30) — it runs one hardcoded entry workflow per turn. base_game authors
  the flow: entry workflow (`require guardrail → ai classify_intent → dispatch
  $$intent`) → forage workflow (`roll → branch → grant_resource → narrate`). The op
  vocabulary it uses — `ai` (classify), `dispatch` (hand-off), `narrate` (prose) —
  landed in M3b-1/2. The M2 tool-calling orchestrator and its tests were retired
  (D4/D20). **Real E2B-backed runner/narrator now built and verified live:**
  `LlamaAiRunner` (grammar-constrained classify, D19) + `LlamaNarrator` (bounded
  prose), auto-selected when a real backend is active; timeout + T5 reporting live at
  the seam (`LlamaAiCall`). A live forage turn on E2B classified, dispatched, granted
  the table's `5`, and narrated "five units of food" — **D4 holding on a real model**
  (`docs/benchmarks/m3b_walking_skeleton_e2b.md`).
- **Narration quality + a widened action set** — **done (2026-07-22)**. The intent set
  went from 2 labels to 5 (`forage`, `hunt`, `rest`, `build`, `general`) as deliberately
  different workflow shapes: two gathering workflows that differ only in table data, one
  that resolves with no roll, and one refused in fiction by its own precondition. The raw
  d20 no longer reaches the narrator — `table_get` gained **range rows** (the A2 deferral)
  and the workflows band the roll through a rule table, branching on the band's name; the
  die is traced (`workflow_rolled`) instead of narrated, and the `workflow_narrated` record
  now carries the context the model was given.
  **Two findings only the live run produced:** a grammar-constrained closed set is *not*
  enough on its own — with bare label names E2B forced "I sing to the goats" into `forage`,
  and only per-label descriptions (new `PromptFamily.descriptions`) moved it to the
  catch-all; and category words in the facts get announced as verdicts ("The outcome is
  steady.") unless the narrator is explicitly told to let them colour word choice instead.
  Both classes are the same mistake — a mechanical term reaching the player as fiction.
- **Measure classification stability** (D17) — **first result in, and it holds.**
  `tools/measure_classification.gd`: difficulty (`low|medium|hard`), grammar-constrained,
  temp 0, reason-in-English (D29), across 3 actions × 3 languages (en/pt/es) × 2 phrasings
  on **E2B**. **18/18 within-action stability** — every action got one identical verdict
  regardless of phrasing or language. The language-divergence that broke the old design
  (Bonsai-4B: 3 outcomes in pt/es/fr) **does not reproduce**
  (`docs/benchmarks/d17_classification_stability.md`). Caveats: one model (E2B, the shipping
  default); one action read `low` vs the guessed `medium` — calibration, not instability;
  small action set. **Next:** repeat across the ladder (E4B/Qwen/Bonsai). *(The action set
  was widened to five on 2026-07-22.* **Re-read the measurement in light of D33:** it used
  bare label names, and `low|medium|hard` are self-explanatory in a way `general` is not, so
  the result probably stands — but the tool should carry descriptions before the ladder run,
  or it measures a prompt the game no longer uses.*)*
- AI output only via the pipe protocol (D20); `tool_calls` retired
- Rules own every number. The AI never emits a `grant_resource` amount.
- Rework `AiOrchestrator`: it currently does the brief's model-driven tool calling,
  which D4 removed.
- Heavy test coverage — almost all of this is testable with `FakeAiBackend`.

**Why it matters:** measured today — the same 17/20 roll paid **+17 / +20 / +15**
across three models, and Bonsai-4B gave three different outcomes for one action in
pt/es/fr. Every system built before this is built on the wrong foundation.

~~**Open (D4):** where the line sits for requests the rules do not cover ("I sing to
the goats").~~ **Closed 2026-07-20** (D4 amendment): there is no universal roll
gate. Such an action is simply a workflow whose only effect is narration — the
question dissolves once orchestration shape is authored per intent rather than
fixed in code.

---

## M4 — Save/load + migrations (current milestone)

**Goal:** state survives closing the app.

**GATE 0 satisfied 2026-07-22.** Chosen deliberately *because it is content-independent*:
M3b's prompts, labels, instructions and balance tables are scaffolding that the finished
game will replace, so refining them further buys nothing. Save/load is machinery that
survives whatever the final workflows look like. Direction settled in that review:

- **Multiple named slots**, not a single continuous save. The format therefore needs a
  save *index*, not one file.
- **A pending question is re-presented after a load**, not silently cancelled — A3 already
  re-proves `resume_require` on wake and cancels on a declined confirm, so the safety this
  needs is built.
- **JSON**, not binary: the project is already JSON canonical form throughout (D24, traces,
  instance snapshots), migrations over JSON are far cheaper to write and test, and a save
  you can read in a text editor is a save you can debug.

Tasks, one branch + PR each:

- **B1 — instance store** — **done (2026-07-22)**. `WorkflowInstanceStore` on the kernel owns
  suspended instances between the turn that suspended and the wake that resumes them.
  **This was a real hole, not a formality:** D25 made instances resumable and A3 proved the
  snapshot round-trips, but *nothing held one* — the executor returned a suspended instance
  and `AiOrchestrator` discarded it, so the capability had no owner and there was nothing for
  a save to contain. `AiOrchestrator.resume(instance_id, outcome)` closes the loop through
  the same busy guard and result contract as a fresh turn, and turns now carry a
  `pending_instance` handle. A pending question survives a serialize → fresh-kernel → resume
  cycle. Orphan handling is explicit: answering twice fails `unknown_instance`, and a question
  whose workflow no longer exists is dropped rather than carried into every future save.
- **B2 — the real `SaveManager`** — **done (2026-07-22)**. One JSON file per slot under
  `user://saves/`, capturing `GameState`, `GlobalStore` (D31), the clock, the B1 instance store
  and per-module data with each module's manifest version stamped for B3.
  **Two design calls worth keeping:** there is **no index file** — each save is
  self-describing and `slots()` derives the list by scanning, which removes the entire class of
  bug where an index disagrees with the files beside it; and **slot ids are opaque and
  generated**, never derived from the player's name, so filenames stay out of the player's
  hands (no sanitizing, no collisions between names that normalize alike, no unicode filename
  surprises) and the name is just metadata the player may reuse freely.
  Writes go through a temp file with the slot's previous contents kept as `.bak` and are
  re-read before being trusted, so a crash can lose the newest save but never the slot. A save
  from a newer build is **refused**, not guessed at. Verified across two separate Godot
  processes against the real `user://`.
- **B3 — module-declared migrations** — **done (2026-07-22)**. `Module.save_migrations()`
  returns [SaveMigration] steps tagged with the `manifest.version` that introduced each;
  `SaveMigrator` applies every step newer than the version stamped in the save, oldest first,
  so each step only ever knows about its own change. Versions compare **numerically per
  component** — as strings "0.10.0" sorts before "0.2.0", which would silently stop migrating
  at the tenth release.
  **Migrations run before anything is applied**: they are pure, so a load either happens
  completely or not at all. Migrating as each module restored would leave the world
  half-overwritten when step three of five failed.
  Lifecycle cases all decided rather than left to chance: a module with **no stamp** in the
  save (added since) migrates nothing rather than replaying its history from "0.0.0"; a save
  from a **newer build of a module** is refused; a step that returns garbage stops the load;
  and data belonging to a module that is **not loaded right now is carried forward untouched**,
  so disabling a DLC and saving does not erase what it owned — losing content by turning
  something off is not a choice a player knowingly makes.
  *Not built: a migration chain for the core envelope (`SAVE_VERSION`). There are no v0 saves
  and no second version, so the mechanism would have zero users; the version check already
  refuses anything newer. Add the chain when `SAVE_VERSION` first moves.*
- **B4a — session lifecycle, two-layer** — **done (2026-07-22)**. Policy revised before merge
  after the user challenged whole-file autosaving; the result is **D34**.
  `SaveWorkspace` (`user://current/`) is the live game as **separate parts**, written at every
  turn boundary and every OS lifecycle event but **only where the content changed**. A slot
  file is a whole snapshot, written deliberately or on a long game-time cadence. Crash contract:
  lose the turn in progress, nothing more.
  On Android the OS kills backgrounded apps without warning, so the lifecycle write
  (`APPLICATION_PAUSED`, close, back) is the only guaranteed one — and because a checkpoint
  only writes what moved, it is cheap enough to always take. **No autosave interval**: a
  checkpoint that writes nothing costs a comparison, so throttling could only add a way to lose
  a turn.
  Resume order is workspace → newest snapshot → new game; the workspace wins even against a
  wall-clock-newer snapshot, because it *is* the game being played.
  **The rule that matters most:** an older build meeting newer data **stops** and leaves it
  completely untouched. The first implementation fell through to a fresh start, which cleared
  the workspace — a downgrade would have silently destroyed a settlement.
  `AtomicFile` now holds the durability logic (tmp → verify → `.bak` → rename) once, shared by
  both layers.
- **B4b — the confirmation UI + slot management** — **done (2026-07-22)**. The chat screen
  shows a pending question with Yes/No and **locks input until it is answered** — a `confirm`
  guards an action the rules have not applied yet, so a turn running alongside it would leave
  the world in a state neither answer describes. A question asked before the game was closed is
  **re-presented on entry** (the GATE 0 call for M4), and dropped when a new game starts (D34's
  load-leak rule reaching the UI). Plus a slot dropdown with Load / New game, and a dev-only
  workflow that stops to ask so the path is drivable in the running app.
  **This closes B1's standing-rule-4 debt:** confirm → suspend → store → save → restart →
  re-present → resume was correct in tests since B1 but had never been driven by anything a
  player touches. It is now, and it found a real bug — see the handover.
  **M4 is complete.**

**Deferred within M4** (inherited, not forgotten): trace retention (A1 left it as "M4's
problem" — dev builds write unbounded trace files into `user://`), scheduler re-arming of
suspended workflows (A4), nested sub-workflow suspension (A3, `nested_suspension_unsupported`),
and AI-trace persistence → replay, which **D4 makes genuinely achievable** (outcomes are code,
so a recorded session replays exactly).

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
| Warm-slot behavior on the phone (desktop-verified 2026-07-17) | D23 | M6 |
| Grammar via the in-process sampler API (source-verified, never run) | D19 | M6 |
