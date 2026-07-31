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

Last updated: 2026-07-27 (**M8 added** — the game UX shell is wireframed and planned, and it runs
*before* M7; it reverses the in-play time-advance call to real-time-with-pause, so `decisions.md`
owes an entry. Before that: M6 Phase 2 — the model runs on the phone. Before that: a painted menu
background and a real game icon; the Android UX
pass: portrait, legible scaling, a back button that asks
before it quits, and a keyboard that no longer covers the input — all verified on a real S26 Ultra.
Before that: wizard choices drive the game, audio, the outpost on the overworld, a settings screen,
the real logo. The flow is run in a window each time via `tools/capture_screens.gd`, which keeps
finding real bugs)

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

## M5 — Memories, plans, and retrieval

**Goal:** the game master remembers, and the world carries agendas of its own.

**Rescoped 2026-07-23.** `docs/briefing1.md` (revised on PR #36) is this milestone's
design input. Plans and memories are **one subsystem, not two**: a plan is structured
memory with an agenda and a next wake time. The scope grew from "memory and retrieval"
to include plans because the briefing's living world — character intentions, faction
directions, background plots, the corrupt-steward class of sub-quest — all reduces to
the same storage + tick machinery, and building memory without the agenda field means
building it twice.

- **Measure first (D17's lesson)** — **done (2026-07-23)**: `tools/measure_classification.gd`
  gained an `OUTPOST_MEASURE=plan_tick` mode — the five closed transitions (escalate /
  hold / de_escalate / mutate / resolve) with per-label descriptions (D33), each scenario
  holding its structured fields constant and varying only the narrative across 2 phrasings
  × en/pt/es. Run on E2B: **`docs/benchmarks/plan_tick_stability.md`**. Result: cross-language
  stability holds (10/12 triples identical across languages, no three-way split — the old
  catastrophic failure does not reproduce), but plan-tick is harder than difficulty and the
  measurement earned **three format decisions**, which the design task below now inherits:
  (1) keep the structured-fields-constant / narrative-varies shape — it anchored the model
  hard; (2) **`mutate` is the weak label** (never fired; a 2B won't detect "the plot changes
  character" from a description) — code-own it or replace with concrete named transitions;
  (3) give plan **direction hysteresis** so a lone temp-0 mis-tick (seen ~1/6 at boundaries)
  self-corrects instead of collapsing the plot.
- **Design the plan format** — **done (2026-07-23, D36)**. GATE 0 review settled two forks:
  direction is a **numeric intensity (0–100) with split-threshold hysteresis bands** (a lone
  ~1/6 mis-tick can't flip the band), and a **universal transition set**
  (escalate/hold/de_escalate/resolve) with plot mutation **owned by code** in the template
  (`mutate` dropped — a 2B never picked it). A plan is a JSON object under `GameState["plans"]`,
  mutated only via the whitelisted `apply_plan_transition` command.
- **Plan-format walking skeleton** — **done (2026-07-23)**. The corrupt-steward template end to
  end: a `PlanTicker` (stateless; plans are in GameState, saved by B2) runs due plans off the
  clock → the `plan_tick` workflow classifies a transition → the command owns the numbers
  (bounded nudge, hysteresis band, code-owned revenge spawn). Pure `Plans` logic +
  FakeAiRunner-driven; 20 new tests, 268 green. The ticker serializes ticks (a suspend-at-`ai`
  vs `clock.advance(n)` race a test caught). **Still stubbed:** the "latest development" a tick
  shows the model is a placeholder — real memory retrieval (in English, D35) is the next piece.
- **Memories + retrieval** — **store + read side done (2026-07-23, D37)**. `MemoryStore`:
  an append-only English (D35) JSONL log in the workspace dir (D34 named this — not a
  whole-part rewrite, not the GameState snapshot; `SaveWorkspace.clear()` wipes it on new
  game/load for free, and it survives a close/reopen). Retrieval is **entity-tag + recency**
  (D37): given a plan's subjects, the most recent memories that share one — one hop, no model
  call, deterministic. Wired into the plan tick, whose "latest development" stub is now gone.
  9 new tests, 277 green. D8's prefix caching is what makes a large retrieved context
  affordable (~20x).
- **The `remember` write op + a self-sustaining plan loop** — **done (2026-07-23, D37)**. A new
  effectful DSL op `remember` appends an authored English line to the store, tagged with the
  entities an expression supplies (authored text, no model call — the review's chosen mode). The
  plan tick records each development it produces, tagged with the plan's subjects, so **a tick's
  development is the next tick's retrieved context** — the plan feeds itself with no external
  writer. 3 more tests, 280 green. **Deferred:** the *AI-summarized* write-behind (memories from
  player turns/events by a summarizer — D35's stage; `remember` gains an AI mode there), and
  slot-snapshot inclusion (a named save doesn't carry its memories yet). The AI drill-down
  (briefing) stays deferred until a measurement shows tag+recency isn't enough.
- **English-only internals + a background write-behind stage (D35).** Non-English input
  is translated at the boundary before it is stored or retrieved; only `narrate`
  localizes out. Translation, memory writes and plan updates are **deferred to a
  post-orchestration stage** so the player only ever waits for the narration — folded
  into the classify call only on the rare turn that needs English *this turn*. Three
  requirements: a synchronous no-AI raw-event record in the D34 workspace (so a failed
  background write is retryable), this turn's facts carried in-memory into the next turn
  (the consistency window), and both raw + English forms stored (English authoritative).
  The stage runs on the **Scheduler** (A4), which is why the A4 re-arm deferral below is
  now on M5's critical path.
- **Plans** — JSON files that *code owns* (facts, goals, stance/direction, linked
  entities, next wake), advanced by scheduled **plan-tick workflows**. The AI chooses
  transitions from closed described sets and parameterizes plots from an **authored
  template library**; it never authors workflows (D30) and never emits numbers (D4).
  Background plans tick on a coarse game-time cadence with a per-tick model-call
  budget, prioritizing plans near the player.
- **Retrieval** — the briefing's multi-step indexed drill-down (index → sub-index →
  entries). Every hop is a model call, so indexes are designed so one hop usually
  suffices; description quality over schema cleverness. **Files-first** (D21
  precedent); SQLite means the godot-sqlite GDExtension and stays deferred until a
  measurement says JSON scanning hurts.
- **Entity/character engine** — **done (2026-07-23, D38)**. The world's cast — characters,
  factions, locations — as authoritative state under `GameState["entities"]`, mutated only
  via whitelisted commands (`create_entity`, `adjust_disposition`) and saved by B2.
  Disposition-toward-the-player is the modelled relationship (the briefing's assessment
  mechanic). `Entities.resolve`/`names` turns a plan's or memory's `subjects` ids into named
  characters. **Engine, not content** (user's call): no cast seeded, no scenario authored —
  those come with in-game testing. 10 tests, 290 green.
- **Promoted prerequisites** (were M4 deferrals, now blocking): scheduler re-arming
  of suspended workflows (A4), nested sub-workflow suspension (A3), trace
  retention (A1).

**Living-world blocks complete (2026-07-23):** plans (D36), memories (D37), entities (D38),
and the commands/ops that move them. **Next is a joint step — not more plumbing:** wire a new
game that seeds a starting world (cast + an opening plot), drive it in the real game flow, then
adjust and author content. The AI/workflow/memory subsystems are deliberately not to be
deep-polished further before that in-game testing (user's steer, 2026-07-23).

**GATE 0 applies.** The direction *input* is settled (the briefing1 review,
2026-07-23), but the task-level direction review with the user is still owed before
M5 production code — the measurement task above is exempt, per the M3b precedent.

---

## M6 — Mobile shipping path + voice

**Goal:** the game ships on a phone, and you can talk to it.

**Phase 1 — the in-process binding, on Windows — done (2026-07-27).** The
GDExtension in `gdextension/` binds `libllama` directly; `InProcessLlamaBackend`
implements the existing `AiBackend` seam, so **nothing above the backend layer
changed** — the orchestrator, the D22 request contract and the T5 availability
policy all took it as-is. Selected with `OUTPOST_AI_BACKEND=in-process-llama`.
Full build recipe and the four traps it cost: `gdextension/README.md`.

- **It is faster than the transport it replaces.** A full orchestrator turn
  (classify → dispatch → forage → narrate) runs in **423–513 ms** against M2's
  0.80–0.85 s subprocess+HTTP warm baseline; raw warm generation is 123 ms. So
  the mobile prerequisite is not a desktop compromise — it is a desktop win.
- **The measurement that matters most is the one that nearly did not happen.**
  CUDA offload failed *silently*: ggml loads backend plugins with a bare
  `LoadLibraryW`, so `ggml-cuda.dll`'s own CUDA-runtime imports resolved against
  Godot's install directory rather than the addon folder, the load failed, and
  `dl_error()` returns `""` with discovery running `silent=true`. Nothing was
  printed; every layer simply landed on the CPU and turns took **34 s** instead
  of 0.5 s. A working-but-40x-slow path that reports no error is the shape of
  bug this project keeps finding, and only a number caught it.
- **Backend discovery is lazy**, on the model-load worker thread: loading
  `ggml-cuda.dll` is ~535 MB plus CUDA context creation, and doing it at module
  init charged every Godot process holding the addon — including the test suite,
  which runs on `FakeAiBackend` and never loads a model.
- 4 new tests (**411 green**), model-free by design; one of them asserts the
  native class is registered, so a broken native build fails the suite instead
  of surfacing as a backend that mysteriously never becomes ready.
- **Not tracked, deliberately:** `addons/outpost_llama/bin/` is ~1.1 GiB of
  llama.cpp + CUDA runtime DLLs, all reproducible by
  `tools/setup_gdextension.ps1`.

**Phase 2 — Android — done (2026-07-27), verified on a real S26 Ultra.** The
game now runs a local LLM **on the phone**, which is the thing M6 exists for.
llama.cpp is cross-compiled from source with NDK 27.2 (upstream publishes no
Android binaries) at the same pinned tag the Windows DLLs come from.

- **A full orchestrator turn takes 4 s on the device** — classify → dispatch →
  forage → narrate, with the rules applying `grant_resource` and D4 holding (the
  model narrated, the code chose the number). The first turn after launch is
  ~40 s because it absorbs loading 2.4 GiB of weights once.
- **That 4 s was 11 s until one build flag changed.** `GGML_NATIVE=OFF` is
  required for any cross-compile and *silently* selects the `armv8-a` baseline —
  without dotprod, the instruction Q4 matmul lives on. Naming
  `GGML_CPU_ARM_ARCH=armv8.2-a+dotprod` is worth **2.75x** and is the difference
  between unplayable and playable. `i8mm` is deliberately left off: it would cut
  support to 2021+ devices and ggml compiles those kernels unconditionally, so an
  older core would not run slower, it would SIGILL.
- **The bug the phone found, which the desktop had been hiding:** the hand-rolled
  chat template used **Gemma 3**'s `<start_of_turn>` markers against a **Gemma 4**
  model, which wants `<|turn>` / `<turn|>`. Nothing errored — the model echoed the
  framing back, and a turn narrated
  `<start_of_turn>The foraging party returns empty-handed.</start_of_turn>` to the
  player. Markers are now detected in the vocabulary, and an unrecognised format
  **fails the request instead of guessing**. `tools/check_llama_turn.gd` guards it,
  because 413 green tests could not: the suite is model-free by design.
- **On a phone the in-process backend is the platform default**, not an opt-in:
  there is no environment to configure and no alternative runtime. `ModelProfile`
  gained a `runtime` field (`server` | `in_process`) so a mobile profile can
  honestly name no server executable, and the catalog picks its default by
  platform.
- Two Android packaging rules learned the hard way, both in `gdextension/README.md`:
  never ship `libc++_shared.so` (Godot's template already has it; a second copy
  makes apksigner reject the APK *after* the export reports success), and every
  `.so` needs 16 KB page alignment (Android 15+, and required by Play for new
  uploads — the device names every offending library in a dialog).
- 2 new tests (**413 green**). `addons/outpost_llama/bin/` stays gitignored and
  fully reproducible via `tools/setup_gdextension.ps1`, which now builds both
  platforms.

- ~~**In-process GDExtension binding to `libllama`**~~ **Windows and Android
  done**; iOS remains (D10, no Mac) — M2's subprocess approach cannot ship on mobile
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

**M8 below comes first.** Four of its seven in-game destinations (Economy, Military,
Diplomacy, Knowledge) are the systems in this milestone, and its top bar wants numbers
— per-tick income and upkeep, a domain-level ladder — that only exist once this lands.
M8 ships those as honest placeholders; M7 is where they stop being placeholders.

---

## M8 — The game UX shell (wireframed 2026-07-27)

**Sequencing: M8 runs *before* M7, despite the number.** The wireframes describe the
shell M7's systems plug into, and it can be built ahead of them because a category page
with nothing behind it is an honest titled empty page, not a blocker.

**Full plan: `docs/ux_plan.md`.** Source: six wireframes in `docs/UX/` — desktop and
mobile, each in three states (main / expanded chat / menu page).

**What they specify:** persistent chrome that is never replaced — top bar (flag, domain
name, domain *level*, coins and population with per-tick deltas, date, speed buttons
`❚❚ > >> >>>`), a left icon rail of seven destinations, a Map Layers button, and a
chat input pinned to the bottom edge — with the overworld map as the centre. Mobile
**re-flows the same regions rather than redesigning them**: the rail becomes a
bottom-right menu button, the date wraps to its own row, and Map Layers folds into the
menu list. Expanded chat and a menu page share their geometry exactly, so they are one
component: title/close bar, body, the dock below.

**Three structural moves it forces.** (1) **The map and the chat swap places** — the map
becomes the base layer and chat a dock over it, which retires `MapOverlay` and its
"routing away would drop the chat log" reason for existing. (2) **A second navigation
layer**: `ScreenRouter` keeps splash → menu → wizard → game, while a *panel host* with
persistent chrome around it handles in-game destinations; Main Menu is one of them and
opens as a panel, so the player never involuntarily leaves the game shell. (3) **A real
`Theme`** — six wireframes of consistent chrome is exactly where `ShellPalette`'s own
"when a real theme lands, this is what it replaces" comes due, and it takes the
unthemed exit dialog with it.

**Layout rules agreed in the same review, not visible in the drawings:**

1. Desktop, page open and chat opened → **both at half height, both interactive**; the
   content area splits vertically so the player can read and talk at once.
2. The split is **draggable to any position**.
3. During an **active event** the split is locked: chat takes full height and **time is
   stopped**. A hard state, not a preference.
4. **Everything animates** — button hover, expand/collapse, panel open/close. Named
   durations and easing in one place, or they drift per screen the way colours did.
5. **Mobile has no split**: page and chat are mutually exclusive, opening chat hides the
   page. Keyboard up halves the chat; in event mode the image hides rather than
   shrinking the conversation further.
6. **Keys:** `Esc` closes the topmost thing; `Space` stops time and pressing it again
   **returns to the previous speed**; `Enter` opens chat.

Rule 6 costs almost nothing: `BACK_CLOSE` is already `KEY_ESCAPE`, and `PASS_DAY` is
already `KEY_SPACE` and is the very action being replaced, so Space keeps its
meaning-in-spirit while changing mechanism. `Enter` is safe because `_unhandled_input`
already gives a focused `LineEdit` first claim — the same reason `FOCUS_INPUT` can be a
bare letter without stealing typing.

**This reverses the in-play time-advance call below (2026-07-24).** The speed buttons are
the Paradox model — time flows, the player pauses to act — where that entry chose explicit
"Let a day pass" over auto-advance. **`decisions.md` owes an entry** for the reversal; the
reasoning is that the wireframed HUD is built around a world that moves on its own, and a
strategy game's pause button is a different promise from a turn button. Mechanically it is
contained: `GameClock` stays the authority and a `TimeDriver` calls `advance(1)` on a timer,
so nothing below the UI learns that time became continuous. What it does change is that
**`PlanTicker`'s drain guard becomes load-bearing** — it was written for a race that only
occurred when `advance(n)` emitted several `day_passed` at once, and real time will hit it
constantly. The driver reads a **world gate** (orchestrator busy, `confirm` pending, or a
tick draining) rather than asking the UI anything; "active event" is the UI's name for that
same predicate being closed.

**Phases** (detail and acceptance criteria in `docs/ux_plan.md`): 1 — the HUD shell and
the map as base layer, **with nothing regressing** (the dev row moves into the Main Menu
panel; the on-screen-keyboard handling moves to the dock, since it is the fix for a real
device bug). 2 — `Theme`, motion, and the top bar reading live state, which needs a date
formatter (`total_days` and 30-day months exist; month names and an era do not). 3 — the
chat dock: message rows with avatar slots, and the reasoning timeline, which maps onto
`AiTrace` almost exactly (classify → roll → narrate) so the playground's renderer gets
extracted rather than written twice. **In-chat dice are a deliberate design statement:**
D4 says the rules decide every number and the AI only narrates, and this makes that
invariant visible to the player instead of merely promised by the architecture. 4 — time:
`TimeDriver`, the four speeds, the world gate, event mode, and the new bindings
(`toggle_pause`, `speed_1/2/3`, `open_chat`; `PASS_DAY` retires), off under
`OUTPOST_TEST_RUN` so the suite stays deterministic, and speed deliberately **not**
persisted — a loaded game opens paused. 5 — a panel registry so modules contribute pages,
mirroring how they already register screens and commands.

**Systems the wireframes assume and the game lacks** — named so nobody builds a
convincing-looking lie into the top bar: the `-123`/`+12` deltas are per-tick income and
upkeep that no economy produces (seed `population`, render `0` until M7); **domain level**
("Outpost") implies a growth ladder nothing models; event imagery needs an art key and a
pipeline; Map Layers has one layer, since corner blending, decorations and season tint were
deferred. Four of the seven destinations — Economy, Military, Diplomacy, Knowledge — are
titled empty pages until M7, on purpose.

---

## Unscheduled — cheap, self-contained, do anytime

**UI skin — the settings page is fully painted (2026-07-28, finished 2026-07-29).** The painted shell
landed for the splash, menu, exit modal, loading bar and settings page (`core/ui/theme/ui_skin.gd` +
`SkinnedButton`, `SkinnedProgressBar`, `ModalDialog`). **The last four pieces — scrollbars, the
dropdown chevron, the slider and the toggle — came in on 2026-07-29**: `UiSkin.apply_scroll_container`,
`apply_slider`, `apply_toggle`, and the chevron through `apply_input`, which also turns it over while
the list is open. The art table that stood here is closed — **no new texture is owed**.

**Correction (2026-07-29).** This entry claimed that no control on the settings page was stock Godot
chrome any more. That was wrong twice over, and both were fixed the same day:

- **A dropdown's *list* is a separate `PopupMenu` with its own theme.** Skinning the `OptionButton`
  dresses the field; the flat grey list it opened went unnoticed because nothing in the first pass
  ever opened one. Now `UiSkin._apply_select_popup` gives it the field's own parchment, ink
  lettering, and Godot's radio marks darkened to read on it — no new art, and the list reads as the
  field having grown rather than as a window over it.
- **The section rules were still the shell's cool blue-grey.** They are now brown
  (`UiSkin.separator_style`), which is what `separator.png` was going to be for; the texture is no
  longer needed for this. Measured: the rule went from `(188,182,176)` to `(169,148,119)`.

The lesson is cheap to state and was expensive to miss: **a control that opens something is two
controls.** Check the opened state, not just the closed one.

Still open, and structural rather than art: the painted controls are applied per-control rather than
through a `Theme`, so the other screens — the chat log, the HUD pages — still get Godot's own
scrollbars and fields until someone calls the `apply_*` helpers on them. Folding these into
`OutpostTheme` is the real fix and is the natural next step. The one thing that **cannot** go there is
the pointer shape: `mouse_default_cursor_shape` is a node property, not a theme item, which is why
`UiSkin.watch_cursors` is a `SceneTree.node_added` hook installed at boot instead.

Two things the finished set is worth remembering for:

- **The groove/fill pair paid off exactly as hoped.** `slider.png` and `slider_fill.png` are both
  130x10 with the gold inset to the groove's well, so Godot's slider — which draws both from the
  control's left edge — lands the fill inside the groove with no offsets to keep in step, the same
  trick `progress_bar_background`/`_fill` uses.
- **Draw near the final size still holds, and the toggle is the exception that proves it.** At 194x85
  it is four times the height of the row it sits in, and a `CheckButton` draws its check icon at the
  texture's own size (`icon_max_width` governs a `Button`'s *icon*, not this), so it had to be
  resampled on the way in — `UiSkin.scaled_texture`, cached. That works, and Lanczos down to 110x48
  kept the corner ornaments, but it is a step the other textures do not pay.

**Conventions that earned themselves** — draw near the final size, opaque edge to edge, and keep
ornaments inside a predictable corner inset. Two bugs came from ignoring this: `frame1` at 210x239
stretched its top rail **17x** on the settings page (fixed by `frame2` at 1496x986, now 1.5x), and
`TILE_FIT` on that frame repeated the paper grain about four times over as visible banding.
`UiSkin._slice()` now takes the stretch mode per texture, with the reasoning on both sides.

**Move module loading into the loading screen — deferred 2026-07-28, do not lose.** `modules.load_all()`
runs inside `GameKernel.boot()`, so it happens *before* the first scene can mount. Measured at **170ms
of the ~2.3s startup** — small, but it is real work sitting in front of the first frame, and the
loading screen exists precisely to be where loading is visible. The reason it was not done with the
splash consolidation: `boot()` returning a fully-wired kernel is what the entire test suite builds on
(`GameKernel.new()` + `add_child_autofree`), so moving a boot step out is an architectural change that
has to be designed against that contract rather than folded into a UI fix. The same slot is where the
**AI prefix-cache warm-up (D8)** belongs — `loading_screen.gd` already carries a TODO for it, and that
one is not 170ms. Do both at once.

**App shell + new-game flow** — **first pass done (2026-07-23)**: the full flow **splash →
loading → main menu → new game → game start** runs with placeholder UI. New pieces: a
`ScreenRouter` (`core/navigation/`) since no navigation existed (boot mounted one screen);
core app-shell screens (`core/screens/`, registered by `AppShell`); a `create_plan` command
(the gap where nothing ever put a plan into `GameState["plans"]`); a `Module.seed_new_game`
hook + `GameSession.begin_new_game` that seeds a **minimal placeholder living world** (hero from
the wizard, a small cast with dispositions, resources, one ticking plot, an opening line) —
scaffolding the authored content replaces. Also fixed a latent bug: `start_new` now resets the
in-memory stores (state/globals/clock/instances), not just the workspace, so a mid-session new
game is a clean world (D34). `OUTPOST_PLAYGROUND=1` still bypasses the shell.

**In-play time-advance — done (2026-07-24):** time is turn-driven and the player passes it
explicitly (chosen model over auto-per-turn/hybrid). The chat screen's dev "advance 1 month"
button is now a real **"Let a day pass"** control + a day indicator; advancing the clock fires
`day_passed`, the `PlanTicker` ticks due plots off its own subscription, and each tick surfaces a
`base_game.plan_ticked` chronicle line (i18n key + values, D24) so a background plot moving is
visible in-game. The seeded `steward_extortion` plot's wake dropped 30 → **3 days** so the loop is
observable in a short hands-on session (placeholder pacing). New end-to-end test drives the real
seed through real clock advances; 301 green.

**Narrated opening — done (2026-07-24):** a fresh game plays a narrated opening once (the throne
room, the king's charge) instead of a static line. Narration is a workflow (D30): the seed stashes
the opening's **facts** (`opening = {hero, years}`, D4 — code decides), base_game authors a
single-beat `opening` workflow (`narrate` over those facts), and the chat screen runs it through the
executor on first entry to a fresh game, renders the prose, and clears the facts so it does not
replay on remount. Falls back to a plain line if the narrator returns nothing (outage/stub). A
fuller multi-beat opening can grow in the workflow without touching the screen. 302 green.

**Overworld map: first pass — done (2026-07-24, PR #47).** The legacy Tauri overworld ported to
Godot: a corner-blending auto-tiler in the original, this first pass renders the **base biome
layer** it composes over. `core/map/MapVariation` ports the legacy per-cell hash byte-for-byte
(locked to JS-generated reference vectors); `core/map/TerrainMap` decodes the terrain-set + map
JSON; `core/map/OverworldMapView` culls/fits/pans/zooms. base_game's `MapOverlay` hosts it as a
**child overlay** from the chat screen (the router is stateless, so routing away would drop the
chat log). 32 biome textures + a demo map ported to `modules/base_game/assets/map/`. 20 new tests,
311 green at merge. **Deferred:** corner-blend mask overlays, tile decorations, season tint; tying
the map to gameplay (outpost position, travel) — polish over this base layer, not urgent.

**Flag component — done (2026-07-24, PR #48).** The legacy flag-compositing system (base cloth →
tinted pattern → tinted emblem → fold-shading effect, one shader pass) ported as a reusable
widget ahead of the wizard: `FlagValue` (design data, round-trips the legacy JSON unchanged) +
`FlagView` (a texture-cached `ColorRect` that live-renders a `FlagValue` in one draw call). 14
patterns, 13 emblems, base+effect cloth textures under `modules/base_game/assets/`. 315 green at
merge.

**New-game wizard — done (2026-07-24).** The legacy 4-step flow (Background → Location → Identity
→ Settings), captured from the legacy Tauri wizard config and rebuilt as one screen
(`core/screens/new_game_screen.gd`) with internal step state rather than one router screen per
step, since the accumulated selections need to survive the walk without being threaded through
`on_enter` params at every hop. Background (5 cards: merchant/knight/noble/mercenary/scholar) and
Location (4 cards: coast/valley/forest/mountains) are simple card-selects — legacy background art
per card was not ported, text only. Identity collects hero name, sex, outpost name (with a
randomize button over the legacy name list), and a flag designer built on `FlagView` — three
`ColorPickerButton`s (cloth/pattern/emblem) plus prev/next cycling through patterns and emblems,
mirroring `flag_preview.gd`'s dev-preview logic. Settings picks narration verbosity
(short/average/long). Finishing hands a fuller `fields` map to `begin_new_game`; base_game's
`seed_new_game` now names the outpost entity from it and stashes background/location/sex/verbosity
under `GameState["profile"]` and the flag under `GameState["outpost_flag"]`. 5 new
integration tests drive the real screen through the autoload `Kernel` (the `test_confirmation_ui`
pattern), including a full walk to `begin_new_game` asserting the collected fields landed. 320
green. **Still deferred:** module-pick screen + a module-config-driven wizard
(nothing to configure yet — this wizard's fields are all base_game's); Settings/Help/News screens;
legacy background art per card.

**The game screen joins the painted skin — done (2026-07-30).** M8 shipped the in-game shell's
*structure* and never dressed it: `game_screen.gd`, `hud_shell.gd`, `hud_panel.gd` and
`chat_message_list.gd` between them made **zero** `UiSkin` calls, so everything inside the game ran
on `OutpostTheme`'s flat dark default while every screen outside it was painted parchment. Two
visual languages in one product, which is why the game read as a prototype next to a finished
wizard. Now: the top bar, the rail and the dock sit on `UiSkin.chrome_style()` — `frame_style` held
closer to its moulding, deliberately **not** `thin_frame_style`, which draws a border with nothing
behind it and left the dark background showing through; `HudPanel` is the wizard's own framed page,
shadow and all; rail destinations, Send, Yes/No and Retry are `SkinnedButton` plates; the four
speeds are field plates with an overridden `pressed` box (a card's selection is its host's glow, so
`apply_card` alone leaves all four looking identical); the dock's chevron is the skin's select arrow
instead of the characters `^` and `v`; conversation rows get a framed portrait mount. **Every piece
of lettering that moved onto parchment had to change colour** — `UiSkin.label_style` paints the
cream caption a *dark plate* needs, and the message BBCode's `wheat`/`gray`/`orange` were picked for
the same dark panel; on paper the narrated opening was the palest thing on the page. **The top bar
is the one strip that cannot re-flow**: at the desktop type size it wanted ~870 units of a 720-wide
phone and a Godot container does not clip, so it pushed the date and the speed control off-screen —
it drops to `FONT_SMALL` and sheds the placeholder `+0` deltas below the breakpoint. The inline
reasoning timeline is **gone from the conversation** (the user's call): it is a developer's view of
the orchestration and it was sitting in the middle of the fiction. `AiTrace` is untouched and the
playground still renders it; a dev overlay of its own is the replacement, not a row in the
chronicle. 445 green, both breakpoints captured.

**Wizard Hero/Banner split + banner designer — done (2026-07-30).** The flow is now five fixed
steps on every device: Background → Location → Hero → Banner → Settings. Hero owns hero name and
sex (with no empty appearance placeholder); Banner owns the outpost name and the flag. The three
stock colour pickers and two blind steppers are replaced by five compact property rows: Cloth
colour, Pattern, Pattern colour, Emblem, Emblem colour. Each opens a focused themed modal. Colour
modals show only a simple hue-and-saturation board; shape modals contain
None + all 14 patterns / None + all 13 emblems. A square alpha-mask shader renders thumbnails without
a flagpole and retints them live; 72-unit cells keep every mask readable at the phone breakpoint.
The preview is larger and an `HFlowContainer` places it beside controls on desktop and above them on
a phone. `capture_screens.gd` records both breakpoints and both modal kinds. 445 green.

**Language preference — done (2026-07-30).** Both Settings surfaces share one 24-entry catalog with
the requested locale codes, native language names and flag emoji. The main Settings screen persists
the player's default in `settings.cfg`; the wizard pre-selects that default and copies its code into
the new game's `profile.language`. Bundled MIT-licensed `flag-icons` SVGs provide consistent visual
flags on platforms such as Windows that render Unicode flags as letter pairs. Translation remains
deliberately unchanged for now. The 24 choices open in a 560-unit themed scroll viewport on desktop
and mobile, avoiding Godot 4.7.1's `PopupMenu.max_size` bug while keeping every language reachable.
The selected field and each option now use phone-sized 84/80-unit touch targets. Option rows pass
drag gestures to the modal's 16-unit-deadzone scroll container, and a bundled, label-only subset of
Noto Sans CJK supplies the Korean, Japanese, Simplified Chinese and Traditional Chinese glyphs on
devices whose default font does not include them.

**The wizard's choices start driving the game — done (2026-07-25).** The wizard had been collecting
answers nothing read. Two are now wired, and the flow was finally **run in a window** rather than
asserted headless.

- **Verbosity → the narrator.** `GameState["profile"].verbosity` now sets
  `kernel.narration.level`, re-derived by `GameKernel.apply_player_preferences()` on **both**
  `new_game_started` and `game_loaded`. The load half matters as much as the new-game half:
  `narration` is deliberately not in the save (load-isolation classifies it RUNTIME), so without
  re-deriving it a loaded game would be narrated at whatever the *previous* game chose. The Settings
  step now speaks `NarrationSettings`' own vocabulary (`short`/`normal`/`long`, shown as
  Short/Average/Long) so the stored answer *is* the level — nothing translates. This surfaced a
  latent bug: `BASE` had no entry for `normal`, so it fell back to short's base and "Average"
  behaved as a second "Short". `normal` now plants the base where an authored literal resolves to
  itself. `NarrationSettings.LEVELS` also separates what a *player* may pick from `PROSE_LADDER`
  (what a narrator may be asked to write at) — `full` is a rung, never a preference.
- **The flag flies in-game.** The chat screen's status row now shows the outpost's banner and name,
  read from `GameState["outpost_flag"]` via `FlagValue.from_dict` — the first real reuse of the flag
  component outside its own designer, which is why it was built. `FlagView.aspect()` replaces the
  art's pixel ratio being written out as a literal at each call site.
- `GameSession` now names the keys both ends agree on (`PROFILE_STATE_KEY`, `PROFILE_VERBOSITY`,
  `OUTPOST_FLAG_STATE_KEY`): the core wizard collects the answers, a module writes them into state
  while seeding, and core reads back the parts it owns — by constant, not by matching literals.
- ~~**Still not consumed:** `background` and `outpost_location`~~ **Wired (2026-07-25), see below.**

**Background + location now drive the start — done (2026-07-25).** The last two wizard answers
were reviewed against the legacy Tauri wizard's actual "starts with" data (`new-game-setup.json`,
an `apply_effect_set` workflow keyed by background/location) before coding anything, per the
content-decision gate #50 raised. The legacy numbers assume a full economy (population
happiness/loyalty/trust, a tech tree, per-tick production, a wood/stone/leather/coins palette) —
none of which exists in this port — so the numbers are a rescaled, **deliberately provisional**
first pass onto what actually exists (`food`/`gold`, entity traits/disposition, the memory store),
explicitly agreed with the user as being about proving the wiring works, not locking in a balance.

- **One table, `base_game_module.gd`'s `BACKGROUND_EFFECTS`/`LOCATION_EFFECTS`,** keyed by the
  wizard's own ids: an optional resource grant (on top of the flat starting grant), an optional
  disposition nudge to an *existing* entity (only where the flavor text plausibly implies a
  relationship — Knight→king, Noble→steward; the other three touch no relationship rather than
  inventing one), a trait, and one origin-memory line. Every number and string lives in the table;
  `seed_new_game` and the new `_apply_start_effect` helper never branch on the id directly, so
  retuning the balance is a one-place edit.
- **Memories, not just state.** Each choice records one line via `MemoryStore` (background tagged
  to `hero`, location tagged to `outpost`, `kind: "origin"`) — the M5 memory system's first content
  about how the game itself started, not only about the steward plot. This was `briefing1.md`'s
  original vision for the wizard ("writes the initial memories those choices imply"), previously
  unbuilt.
- **Deliberately still not touched:** `outpost_location` → map placement. `BaseGameMap
  .HABITABLE_BIOMES` has no forest/mountain biome in the demo terrain set, so there is nothing to
  honour the choice with yet — placement stays the existing "nearest habitable cell to centre" rule
  regardless of location, unchanged from before this work. New resource types (`wood`/`stone`) were
  also deliberately left out — technically cheap (`GrantResourceCommand`'s resource name is
  free-form and the status line already renders whatever keys exist) but currently inert, since
  nothing spends them yet.
- **Tests read the table, not literal numbers** (the user's explicit structural ask): every new
  test picks *whichever* background/location entry has the field it's exercising and asserts the
  resulting state matches that entry's own values — a resource/disposition test compares against a
  same-seed baseline with no choice made and checks the *delta* equals the table's `amount`/
  `disposition_delta`, so retuning the table (or the flat starting grant) never requires rewriting
  a test. One additional test drives every single background/location id and asserts zero
  `command_rejected` events, catching a bad `disposition_target` typo without a per-entry
  assertion. 8 new tests, 370 green. **Verified live** (a throwaway driver script, deleted after):
  Knight + Mountains produced exactly the combined expected state — food 30, gold 15, hero traits
  `[founder, knight]`, king disposition 15, and both origin memories recorded and correctly tagged.

**`tools/capture_screens.gd` (new).** Mounts each registered screen in a real window, renders it and
saves a PNG (`user://screens/`, or `OUTPOST_CAPTURE_DIR`). It exists because "verified headless
only" is how UI regressions get in — GUT proves the wiring and says nothing about what a screen
*looks* like. It asserts nothing; it produces evidence. It immediately earned itself: the card-select
grid was sizing cards to a fixed width, so five backgrounds pushed the third column **off-screen
with no scrollbar to reach it** (cards now share the row and wrap their text), and the game screen
painted no background at all, falling through to Godot's light default — the shell went dark and the
game went grey, reading as two different applications. `ShellPalette` (`core/screens/`) now names
the few colours the shell paints with, replacing the same near-black copied into five screens.

**Settings screen — done (2026-07-25), mostly as marked placeholders.** `core.settings`, reached from
the main menu, with six tabs: Gameplay, Audio, Video, Controls, Language, Accessibility. Built out to
its **full shape** deliberately, because the shape is a design document — it is where you can see that
rebinding needs an `InputMap` that does not exist, that a resolution list needs a window-mode policy
nobody has decided, and roughly how much is left.
- **Every unwired control is disabled *and* tagged `planned`.** A slider that moves and changes
  nothing is worse than an empty section, because it looks finished. Disabled alone is not enough
  either — a greyed control reads as "unavailable right now", not "not built yet", so the tag carries
  the difference. A test asserts one tag per inert control, no more and no fewer.
- **What actually works:** the four audio levels (master/music/effects/ambience, live on their buses
  and persisted), narration length, and the preferred language code. Language selection is saved
  and pre-selects new games; interface and narration translation remain future work.
- **New `AppSettings`** (`core/settings/`, kernel field `settings`) — a `ConfigFile` at
  `user://settings.cfg`, an ini because it is the one file a player may reasonably hand-edit when
  something has gone wrong. Deliberately narrow: it stores only settings wired to something, since a
  persisted key nothing reads is worse than an obviously-empty section. Distinct from
  `GameState["profile"]` on purpose — **how loud the music is belongs to the person, not to a
  settlement**, so loading a different save must not change it (classified RUNTIME in
  `test_load_isolation.gd` for that reason). Defaults are a complete playable configuration, so a
  missing *or damaged* file reads as "unset" rather than refusing to start.
- **Narration is now two layers, each with one job.** `AppSettings.narration_level` is the person's
  usual preference and pre-selects the wizard's Settings step (previously a hardcoded default forever,
  no matter how often they changed it); the per-game value in `profile` is what governs a game once it
  exists. Changing it in Settings writes both, and calls `apply_player_preferences()` so a game in
  progress hears it immediately.
- `AudioManager` gained `MIXER_LEVELS` (= `master` + the three manifest `CATEGORIES`): `master` is a
  level over the others rather than a place cues live, and no manifest declares `master` cues.
- **Still deferred:** everything tagged. Cheapest to make real next are window mode and V-Sync (a few
  `DisplayServer` calls plus two `AppSettings` keys); the expensive one is key rebinding, which needs
  the `InputMap` actions defined first — the tab's list is the intended set.

**The splash shows the real logo (2026-07-25).** `core/assets/pangea_logo.png` on a true black field,
scaled to a share of the viewport in its own aspect so it holds its proportion on a phone and on a
desktop. As supplied the asset was an **opaque near-white plate with the mark knocked out to full
transparency**, so on black it read as a dark mark inside a white badge; it was **inverted on
2026-07-26** to a white mark directly on black (see below). An animated reveal is still to come.

**Device verification of the whole shell — done (2026-07-27, S26 Ultra).** The pieces that shipped
without a phone attached are now confirmed on hardware, in one pass over a clean install:

| Checked | Result |
|---|---|
| Portrait orientation, font legibility, safe area | Correct; content clear of the status bar and the gesture bar |
| Hardware back → confirm dialog | "Exit The Outpost?" shown; **Cancel leaves the app running** — the behaviour that used to be an instant, silent quit |
| On-screen keyboard vs the chat input | Input, Send and the dev rows all sit **above** the keyboard |
| Menu art crop | Frames the keep exactly as the desktop render at 1080x2340 predicted |
| Splash logo | White mark directly on black |
| Launcher icon | Renders and reads at launcher size, upscaled from 101x101 as accepted |
| Wizard in portrait | All five background cards on screen, nothing clipped |
| Start bonuses (#57) | Merchant + Coast gave **gold 33** = base 10 + 15 + 8, live on device |

**One cosmetic finding, not fixed:** the exit dialog is Godot's unthemed `ConfirmationDialog`, so on a
1080x2340 screen it is small and its title truncates to "Please Confirm…". Usable, and it belongs
with the wider theming gap (there is still no `Theme`) rather than a one-off size override here.

**Menu background + game icon — done (2026-07-26).** Two supplied images wired up: a painted
settlement behind the main menu and the loading screen, and a watchtower as the app's icon.

- **Moved out of `docs/`.** They arrived in `docs/Assets/`, which is no place for runtime art (the
  same call the splash logo got): they now live in `core/assets/` beside `pangea_logo.png`, named
  for what they are — `main_menu_background.png`, `game_icon.png`.
- **`ShellPalette.paint_art()`** puts the painting behind a screen, and the menu's controls sit on a
  `plate_style()` panel over it. Both were needed: the art is bright (sunlit fields, white cloud)
  and the shell is light-on-dark, so a full-screen scrim alone still left the *disabled* menu items
  — low-contrast by design — invisible against the lit farmhouse and stonework.
- **The icon needs no export-preset entry:** Godot generates the whole Android launcher set
  (mdpi→xxxhdpi, adaptive foreground/background/monochrome) from `application/config/icon`, which
  now points at `game_icon.png`. Verified by unpacking the built APK, not assumed.

**Both source images are used as supplied — settled 2026-07-26, not open questions.**

- **The background is landscape (2752x1536) and the app is portrait, so it is always cropped.** That
  is the accepted behaviour rather than a stopgap: there is no portrait-native variant coming, so
  the crop is designed rather than tolerated. It scales to cover and is framed on `ART_FOCUS_X`
  (0.58) — **the keep's own position in the painting**, not the image's midpoint, which is a
  different point and would clip the right-hand towers. The settlement therefore sits centred at
  every aspect the game runs at, and the river, bridge and outlying farms fall outside the frame
  deliberately. `KEEP_ASPECT_COVERED` cannot express a focal point (it always centres the image),
  which is why the size and offset are computed instead, clamped so no edge can show.
- **The icon is 101x101 and Godot upscales it for the Android launcher set.** Accepted as-is.

**The splash logo is inverted (2026-07-26)** — a white mark directly on black, replacing the
white badge with the mark knocked out of it. Not a plain alpha inversion: the surround outside the
badge is transparent too and would have become an opaque white field. Only the *enclosed* knocked-out
region is the mark, so the transform flood-fills from the border to identify the surround, leaves it
transparent, and inverts everything else — plate to nothing, mark to the same off-white ink the
plate used, anti-aliased edges carried through. Done once with a throwaway Godot script (deleted);
the asset in the repo is the result.

**Audio — done (2026-07-25).** There was no player at all; the assets had been staged for weeks.
`AudioManager` (`core/audio/`, kernel field `audio`, a Node because it owns `AudioStreamPlayer`s)
plays cues **by name** from a module's `audio.json` — `play_music("main_menu")`, `play_sfx("ui_click")`
— so no screen ever names a file and re-scoring is a data change. Streams load on first play and are
cached: music files are the largest assets in the project, and preloading them would spend that on
the splash screen and on every headless test run.
- **Volume lives in two places on purpose.** A cue's `volume` in the manifest is the *mix* decision
  (this click is quieter than that one) and belongs to whoever authored the sound; a category's level
  is the *player's* decision and lives on an audio bus. New `default_bus_layout.tres` gives
  Music/SFX/Ambience a bus each, so a settings screen can offer three sliders without touching
  content.
- **Click sounds are wired centrally**, off a new `ScreenRouter.screen_mounted` signal the kernel
  listens on: every screen's buttons get the sound, including ones added after `_ready`. A UI sound
  that some controls make and others do not reads as a bug, and that is what hand-wiring drifts into.
  The router stays ignorant of audio — it announces the mount, the kernel decides what that means.
- The shell is scored (`AppShell.SHELL_MUSIC`, started on the splash) and the game screen stops it;
  asking for the track already playing is a **no-op, not a restart**, so menu → wizard → menu does
  not keep starting the theme over.
- Playback defaults **off under the test runner**, the same guard the trace writer and memory store
  use. Without it every suite loaded a 3.5 MB ogg and left a live playback open at exit, which the
  engine reports as leaked instances — noise that would mask a real leak. `GameKernel._exit_tree`
  also cuts the music dead rather than fading it, since on the way out there is no next frame.

**The outpost is on the map — done (2026-07-25).** The map was decorative; now it shows a
settlement. Seeding chooses the site and records it in `GameState["outpost_site"]`, so it is world
state that survives a save rather than a rule re-evaluated whenever the map opens (a rule that
changed would move the town between one look and the next). `TerrainMap.find_cell_nearest_centre()`
takes the acceptable biomes as an **argument** — which ground can hold a settlement is the game's
decision, not the map format's — and `OverworldMapView.set_marker()` pins **the caller's own
`Control`**, which is how core stays free of anything content-specific: `base_game` pins a
`FlagView`, and core never learns flags exist. Markers keep a fixed screen size (a settlement that
shrank with the zoom would vanish exactly when you zoom out to find it) and hide when their cell
leaves the view. `modules/base_game/map_content.gd` (`BaseGameMap`) now owns the map's content paths
and loaders, which the overlay and the seed both needed.
- **Placeholder placement rule, deliberately simple:** the habitable cell nearest the map's middle.
  Deterministic, never in the sea. Not yet varied per game (needs a per-world seed, which does not
  exist — the only seed here belongs to the map content) and not yet matched to the wizard's
  `outpost_location`, because the demo terrain set has **no forest or mountain biome** to put a
  "Forest" or "Mountains" start on; any mapping would be invented rather than honoured.

**Bug the capture tool found: the map overlay had never actually rendered.** `set_anchors_preset()`
recomputes offsets to *preserve the control's current rect*, and the overlay is built in code, so at
`_ready` it was 0×0 inside a parent that already had a size — baking in offsets of `-width,-height`
and pinning it to nothing. The Map button opened an invisible overlay for two days, through 20
passing tests. Fixed with `set_anchors_and_offsets_preset()`. Screens loaded from a `.tscn` get away
with the other call only because their scene file already stores a full rect; the trap is
script-built Controls, and the audit found this was the only one.

**Overworld map — first pass (2026-07-24):** ported the legacy Tauri overworld into Godot. The
old renderer is a corner-blending auto-tiler (mask atlases, biome priorities, tile compositor,
season tint); this pass draws the **base biome layer** — each cell's biome texture with the
deterministic per-cell variant. `core/map/`: `MapVariation` (the `variation.ts` hash ported
byte-for-byte, locked to reference vectors in tests), `TerrainMap` (decodes the terrain-set +
map-layer JSON, ported from `mapData.ts`), `OverworldMapView` (a `Control` that culls to the view
rect, fits, and supports drag-pan + wheel-zoom). Assets copied to
`modules/base_game/assets/map/` (32 biome textures 256², the demo map + terrain JSON). base_game
`MapOverlay` loads the data/textures and hosts the view; the chat screen opens it as a **child
overlay** (the `ScreenRouter` is stateless, so routing away would drop the chat log). 20 map tests,
311 green. **Deferred (the blending polish over this base layer):** corner-blend mask overlays,
whole-tile ground decorations, season tint; a proper routed map screen once the router grows a
stack; wiring the map to gameplay (the outpost's position, travel).

**New-game wizard — flow captured, not yet built:** the legacy new-game is a 4-step content-driven
wizard — **Background** (merchant/knight/noble/mercenary/scholar, each with starting bonuses),
**Location** (coast/valley/forest/mountains, difficulty/fertility/barbarians), **Identity** (hero
name, sex, outpost name, flag designer), **Settings** — collecting a `fields` map handed to
begin-new-game. Screens are JSON (`heading`/`card-choice`/`field`/`choice`/`flag-designer` body
types). This is the shape the deferred module-config wizard should take: the current single-field
new-game screen grows into this multi-step flow, its `fields` feeding `seed_new_game`.

**Key bindings are real — done (2026-07-26).** The Controls tab listed 21 intended bindings against
**zero** defined input actions; `docs/Remember.md` has promised rebinding since the start. It now
works, for the actions that have something behind them.

- **`core/input/input_actions.gd` (`InputActions`)** declares the action set and its defaults, and
  is the only thing that knows a keycode. Screens ask `event.is_action(InputActions.PASS_DAY)` and
  never learn which key that is — **that indirection is what rebinding is**. Installed on the
  [InputMap] at boot, and reinstalled from scratch on every change, so no stale event survives.
- **Scoped to eight actions, deliberately:** focus input, pass a day, open the map, zoom in/out,
  settings, quick save, back/close. The other thirteen (roster, chronicle, quick-load, screenshot,
  key panning, …) **have no feature behind them** and keep their `planned` tag — a binding the
  player can change and then watch do nothing is exactly the failure the tag exists to prevent.
  Moving one across is a two-line change when its feature lands.
- **Overrides only are stored** (`[input]` in `settings.cfg`, keyed by action). An action the player
  never touched has no entry, so changing a *default* still reaches everyone who had not
  deliberately chosen otherwise, rather than being frozen into every existing config file.
- **A key drives exactly one action.** Taking a key from another action leaves that one holding
  **nothing** — which needed a state the store did not have: `AppSettings.UNBOUND` (-1) is
  *deliberately no key*, distinct from `NO_KEY` (0, "no override"). Storing the latter would fall
  back to the default — the very key just taken away — and the clash would have survived its own
  fix. The action stays registered on the InputMap so `is_action()` callers keep answering false
  rather than erroring.
- **Escape cancels a rebind rather than binding itself**: it is the key a player reflexively presses
  to back out of a mode, and losing "Back / close" to a mis-click is unpleasant to undo. Capture
  runs in `_input`, ahead of `_unhandled_input`, so a key that already drives something is still
  capturable. "Reset all bindings" clears only the `[input]` section — a player clearing their keys
  does not lose their volumes.
- **`back_close` unifies with the Android work:** the Escape key and the phone's gesture-back now
  both call `GameKernel.request_back()`, so the confirm-before-exit built on the Android pass serves
  the desktop too.
- 17 new tests (407 green). **Verified in a running app** (throwaway driver, deleted): a synthesised
  keypress travels InputMap → viewport → the screen's handler → the same method the on-screen button
  calls, a day actually passes, and **after a rebind the new key works while the old one stops** —
  which is the only assertion that proves the indirection is real rather than decorative.

**Video settings finished + start bonuses retuned — done (2026-07-26).** Three decisions the user
handed over rather than made one at a time.

- **Resolution, Monitor and Frame rate cap are now real**, on a policy chosen here: resolution is a
  *windowed desktop* setting (fullscreen and borderless take their size from the screen; on a phone
  the OS owns the window), monitor only means anything with more than one display attached, and the
  frame cap applies everywhere — it is a battery setting on a phone more than a smoothness one.
  Both conditional controls are **disabled with the reason showing** rather than hidden or left
  live-but-inert. Defaults are all "leave it alone" (`UNSET` / `-1` / `0`): on a first run the OS
  has already sized and placed the window sensibly, and V-Sync is what should limit the frame rate
  until the player says otherwise. A stored-but-out-of-range monitor is **kept, not erased** — a
  laptop that chose "monitor 2" at the desk gets it back when docked.
- **This forced a distinction the screen did not have:** a control can now be *finished but not
  applicable right now* (Resolution outside Windowed, Monitor with one display), which looks
  identical to *not built yet* — both greyed. `PLANNED_META` marks the latter, and the
  one-tag-per-planned-control test counts against that mark instead of against every disabled
  control, so the two cannot be confused. **Render scale keeps its tag**: it is the viewport's *3D*
  scale and this is a 2D game, so it is a reminder to delete it, not to build it.
- **Start bonuses retuned** (still provisional). Two defects a human found by reading the table:
  Scholar granted no number at all — an option that changes nothing reads as the one nobody should
  pick — and Coast and Forest were the *same* grant, so two of four cards differed by prose alone.
  Now the resource *type* follows each card's own economy (Coast/Mountains pay gold for trade and
  ore; Valley/Forest pay food) and the *amount* follows its stated fertility/difficulty. Two
  resources cannot make four locations qualitatively unique — that waits on the economy (M7).
  **Two new tests encode the defects rather than the numbers:** every choice must grant at least one
  mechanical effect, and no two locations may share a (type, amount) pair. Retuning stays a
  one-place edit.
- Verified against a real window (throwaway driver, deleted): the cap reaches `Engine.max_fps`, a
  windowed size is applied, the same size is **correctly ignored** in fullscreen, and an
  out-of-range monitor is skipped rather than crashing. 390 green.

**Video settings: window mode + V-Sync — done (2026-07-25).** The two controls #52 called out as
"cheapest to make real next" are now wired, following the same shape as narration/audio:
`AppSettings` gained `window_mode()`/`vsync_mode()` (persisted in the `video` section of
`settings.cfg`, unknown stored values refused back to a known default rather than trusted) and
`apply_video()`, which pushes them onto the real `DisplayServer` — guarded by
`DisplayServer.get_name() == "headless"` so the test runner's dummy driver never gets a real call,
the same shape as the trace writer/audio/persistence test-runner guards. Called at boot (right
after `apply_audio`) and whenever the settings screen's two now-live Video-tab rows change.
"Borderless" is windowed + the borderless flag (not a resize to the monitor); "Fullscreen" is
Godot's own `WINDOW_MODE_FULLSCREEN`. **Verified against a real window**, not only headless: a
throwaway driver script (deleted after, per the standing convention) drove all three window modes
and all three V-Sync modes through the real `DisplayServer` and read back what actually landed.
One real-platform finding, not a bug: requesting Adaptive V-Sync silently lands as plain V-Sync
under this machine's Compatibility/OpenGL 3.3 driver — reproduced with a raw `DisplayServer` call
bypassing this code entirely, so it is the renderer's own fallback, not this change's doing.
`tools/capture_screens.gd`'s Video-tab capture confirms the two rows now render enabled
(un-tagged) beside the rest of the tab's still-`planned` rows. 362 tests green (356 + 6 new).

**Android UX pass — done (2026-07-26).** The milestone-1 deploy list, closed on a real S26 Ultra
(export → install → drive → screenshot, every item verified on the device rather than headless).
It had been deferred since M1 and had only grown: a stray back-press could discard a whole wizard
run, a settings screen and a seeded world, all of which landed after the list was written.

| Issue | Resolution |
|---|---|
| Landscape orientation | **Fixed.** `display/window/handheld/orientation=1` (portrait). |
| Fonts far too small | **Fixed.** `canvas_items` stretch over a 720x1280 reference viewport, `expand` aspect — the UI is authored at phone scale and scales up, instead of being drawn at raw 450dpi. |
| No safe-area handling | **Fixed — and the finding was that there is nothing to inset.** See below. |
| Back button quits instantly | **Fixed.** `quit_on_go_back=false` + a kernel-owned handler; confirm-to-exit dialog. |
| Keyboard overlays input | **Fixed.** The chat screen grows its bottom margin by the keyboard's height. |

- **Back button (the priority item).** `application/config/quit_on_go_back` is now off, so
  `GameKernel._handle_hardware_back()` is the only thing deciding what a press does. The mounted
  screen gets first refusal via an optional `on_hardware_back() -> bool`, which every shell screen
  implements as *exactly what its own on-screen Back/Cancel does* (the wizard steps back a step, the
  settings screen returns to whoever opened it, the splash skips); anything that declines — the main
  menu, the game screen — falls through to a **confirm-to-exit dialog** (the user's call over a
  press-back-again toast: explicit, and assertable in a test where a timing-based pattern is not).
  The lifecycle save already ran unconditionally and still does; what was missing was never state,
  it was a screen vanishing without asking.
- **The bug only the device could find: Android delivers `WM_GO_BACK_REQUEST` twice per press**
  (~2 ms apart, measured). One press took the wizard from step 2 straight to the main menu. Guarded
  by acting at most once per process frame; there is a regression test for the duplicate *and* one
  proving a genuinely separate press still navigates.
- **Safe area: the honest answer is 0.** `screen_get_usable_rect()` returns **1080x2100 of a
  1080x2340 screen** — Android hands the app a window with the navigation bar already excluded, so
  `get_display_safe_area()` matches it and there is nothing left to avoid. The first attempt inset
  the whole router host, which produced the *opposite* of safe: it read the window size during boot
  before it settled, shrank the app below the window Android had correctly sized, and left a strip
  no screen painted (screens paint their background *inside* the host) that fell through to Godot's
  light grey — the app visibly not filling the screen. Replaced with `SafeArea.bottom()`, applied as
  **padding on the screens whose controls sit on that edge**, never as a smaller canvas. It measures
  0 on this device, which is correct; it is kept for the devices and orientations where the window
  *is* full-bleed (gesture navigation, a side cutout in landscape).
- **`display/window/handheld/orientation` is an int enum, not the string the docs suggest.** Setting
  it to `"portrait"` parses, reads back as `"portrait"`, and is **silently ignored by the exporter** —
  the APK manifest still declared landscape. Only `=1` produces
  `uses-implied-feature: android.hardware.screen.portrait`. Two full export/install cycles were spent
  on the string form before checking the built manifest with `aapt dump badging`; **that check is the
  fastest way to know whether an export setting actually took.**
- **Keyboard height is in physical pixels**, and the margin it feeds is in the stretched logical
  units — 1.5x apart here, so the raw number reserved half again too much room and left a dead band.
  The same physical-vs-logical trap sits behind `SafeArea` and is handled there too.

~~**`export_presets.cfg`**~~ — **tracked as of 2026-07-26.** Godot's template gitignores it, but a
fresh clone then cannot export at all: the Android orientation fix lives in the tracked
`project.godot` and still needs this file to reach an APK. Audited before committing — no keystore
path, alias or password (Godot keeps debug-signing details in *editor* settings), and the only
credential-shaped keys, `apk_expansion/SALT` and `public_key`, are empty. The `.gitignore` now
carries that reasoning plus the condition that would reverse it: if a *release* keystore is ever
configured here, its path and password move out to editor settings or an untracked override first.

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
