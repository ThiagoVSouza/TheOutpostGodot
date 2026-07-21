# Handover — next steps (agent-geared)

**Audience:** an AI agent (or human) picking this project up cold — possibly
mid-milestone after a usage-limit cutoff. Follow this file top to bottom.
Keep it updated as work lands: it is a living checklist, not an archive.

Last updated: 2026-07-20 · State: **M2 is COMPLETE and verified** (PRs #7–#16).
77/77 tests green. Real E2B in the running app at 0.80–0.85 s warm —
`docs/benchmarks/milestone2_exit_e2b.md`. **M3a (workflow DSL kernel + traces) is
the current milestone and is cleared to start.**

**Every M3a gate is open.** D21 was settled 2026-07-20 (files, not SQLite) so trace
code is unblocked. D24–D28 are promoted, D29 is new, and D4 gained a substantial
amendment. **GATE 0 was satisfied by the planning conversation of 2026-07-20** — no
further direction review is needed to begin M3a. GATE 0 *does* apply again at M3b.

## 0. If you are the next agent, start exactly here

1. `git fetch` and start from `origin/main`.
2. **Read `docs/decisions.md` D4's amendment and D24–D29 first.** They are new, they
   are the whole basis of M3a, and D4's amendment changes the pipeline shape you may
   remember from the older sketch: orchestration is **authored workflow content**,
   not fixed orchestrator code.
3. **Work M3a in the order in §7** — traces first. That ordering is deliberate:
   the trace writer is what makes every later step manually verifiable, which is the
   entire reason the user wanted traces (D21).
4. Scope discipline: **JSON canonical form only, no text parser.** The `nortrix`
   text syntax in `docs/reference_dsl/` is *reference*, not this milestone's target
   (D24, D28). Building a parser now roughly doubles M3a.
5. Read §1 (context bootstrap). The T1 lessons in §2a and the T6 harness gotchas in
   §4's T6 entry will save you real time.

### What T1 changed (PR #7, all tests 37/37, verified in-app)

`AiBackend.generate()` now returns an `AiRequest` handle
(`chunk`/`completed`/`failed`/`finished` signals, `cancel()`, awaitable
`wait()`); backends must never finish it synchronously in-call.
`FakeAiBackend` completes deferred. `AiOrchestrator.handle_message()` is a
coroutine (callers `await` it) with busy guard, `cancel()` + state-change
fence, and an orchestrator-owned per-call timeout
(`ai_timeout_seconds`, default 30 s). Chat screen awaits and locks input
while in flight. New tests: `tests/integration/test_async_orchestration.gd`.

---

## ⛔ GATE 0 — no coding before a direction review with the user

**Do not write production code until the user has reviewed and confirmed the
direction in a conversation.** The user has said the plan below may need
fine-tuning before implementation starts. Specifically:

1. **Open the conversation by asking the user to review the T3, T5, and T6 task
   order below** and adjust anything before starting the selected task. T4 was
   approved and completed independently; the agreed next order is T3, T5, T6.
2. **D21 (trace storage) is separately gated:** the user has *additional
   thoughts to share* on trace storage (files vs SQLite). Do not write any
   trace-related code before that conversation happens. (This gates M3
   traces, not M2 — but do not "helpfully" scaffold traces early.)
3. There is no review-exempt task remaining. **Everything from T3 on needs the
   task-specific review first.**

---

## 1. Context bootstrap — read these, in this order

| # | File | Why |
|---|---|---|
| 1 | `docs/decisions.md` | D1–D23: every settled decision with evidence. **D4** (AI never decides numbers), **D5** (model ladder), **D19–D23** (orchestration decisions) anchor everything. **D17** = 11 ways this project produced confidently wrong benchmark numbers — read before measuring anything. |
| 2 | `docs/plan.md` | Living roadmap M2–M7 + open questions. Update it as work lands. |
| 3 | `docs/Orchestration_brainstorm.md` | The adopted orchestration spec. Its status header says what is M3 scope vs future reference. `docs/decisions.md` wins on any conflict. |
| 4 | `docs/benchmarks/milestone1_results.md` | Model/latency measurements behind D4–D9. |
| 5 | `docs/benchmarks/orchestration_spikes.md` | Phase 0 spike results (grammar + warm slots — both passed). |
| 6 | `docs/initial_briefing.md` | Original architecture brief. **No longer authoritative** on the AI pipeline (D4), dispatch (D16), or intent classification (D4 amendment) — see the note at its head. |

Also load the user's memory directory notes if you have access to them
(module layout, GDScript gotchas, Android toolchain, git workflow).

## 2. Environment cheat sheet

- **Godot 4.7.1**: `C:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe`
  (use the `_console.exe` for headless; `godot` shim + `GODOT` env var exist in
  new shells).
- **Run tests (GUT 9.6.1, 28 green as of M1):** `pwsh tools/test.ps1`
- **Validate module manifests:** `pwsh tools/validate.ps1`
- **llama.cpp:** `C:\Tools\llama.cpp\b10042\` (CUDA). Models:
  `C:\Models\gemma-4\gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf` (desktop default for
  dev; Bonsai-27B at `C:\Models\bonsai\` is the desktop-tier model, D5).
- **Known-good server line (from the spikes):**
  `llama-server.exe -m <model> -ngl 99 -c 16384 --port 8099 --host 127.0.0.1 --cache-reuse 256 -np 4 --no-webui -rea off`
- **GitHub CLI:** `C:\Program Files\GitHub CLI\gh.exe` (authed as ThiagoVSouza;
  not always on a session shell's PATH — call by full path).
- **Git workflow (non-negotiable):** feature branch → PR → user merges. Never
  commit to `main`. `git fetch` before reasoning about merge state.

### GDScript / project gotchas (each cost real debugging time)

- Variant-inference warning is treated as an **error**: never
  `var x := something.get(...)` — annotate (`var x: Variant = ...`) or cast.
- Godot 4.7 has a built-in `Logger`; ours is `class_name GameLog`. Never name
  a class `Logger`. After any `class_name` change, run `--import` once.
- Filesystem scans must handle export renames: shipped files are
  `*.tres.remap`/`*.res` (D3). Desktop tests cannot catch this class of bug.
- PowerShell 5.1: `ConvertTo-Json` mangles long strings; read files with
  `[System.IO.File]::ReadAllText`. Use PowerShell (not Git Bash) for `adb push`.

### 2a. Gotchas learned during T1 (2026-07-17)

- **Godot 4.7 treats an unawaited coroutine call as a parse error.**
  Deliberate fire-and-forget: assign the call to a lambda and `Callable.call()`
  it (tests), or make the connected lambda itself `await` (UI signals).
- **The GUT runner treats the Variant-inference warning as an error** even
  though `project.godot` shows warning level 1 — e.g. `var wr := weakref(x)`
  fails to compile under tests. Annotate: `var wr: WeakRef = weakref(x)`.
- **RefCounted cycles leak, and lambdas capturing `self` create them.** A
  backend whose request holds a cancel hook capturing that backend is a
  `backend → request → hook → backend` cycle: 8 leaked ObjectDB instances
  until `AiRequest` started clearing its hook on finish. If tests print
  "ObjectDB instances were leaked at exit", suspect a lambda cycle first.
- **Awaiting an already-completed coroutine hangs forever** (its completion
  signal already fired). If code may resume a coroutine synchronously (e.g.
  `cancel()` does), capture the result via a wrapper lambda into a dict and
  check/`wait_frames` — see `test_async_orchestration.gd` for the pattern.
- **`chat_screen.gd`'s `var _input` shadows Control's `_input()` virtual** —
  external typed access resolves to a Callable, not the LineEdit. Pre-existing;
  rename in a cleanup PR someday. Use `screen.get("_input")` meanwhile.
- **In-app verification without clicking:** a throwaway `extends SceneTree`
  script run via `--headless -s res://<tmp>.gd` boots the real autoload
  kernel; instantiate the real screen, call its submit path, assert on its
  labels. Delete the script after (never commit it).

## 3. Where the project stands

**Done:** M1 vertical slice (desktop + physical S26 Ultra), model decisions
(E2B default, `-rea off`, prefix cache), orchestration spec adopted (PR #4),
Phase 0 spikes passed (PR #5): grammar-constrained decoding works and warm
per-family KV slots work with automatic routing.

**Not done:** any real inference in-game. `AiBackend.generate()` is still
synchronous. No save/load, no memory/retrieval, no map/economy. D21 (trace
storage) unresolved pending the user's input.

---

## 4. M2 — one real turn, end to end (current milestone)

Goal: type into the Godot app, get real E2B prose back. Tasks are ordered;
each is one branch + PR unless the user says otherwise. **T1 first is
mandatory; order of T2–T6 may be fine-tuned at GATE 0.**

### T1 — Async seam for `AiBackend` (D22) — ✅ **DONE (PR #7)**

All done-when criteria met: 37/37 GUT tests green (28 converted to async +
9 new), mid-turn cancel test exists and proves zero state change, and the
real chat screen was driven headless end-to-end (busy-lock → reply →
unlock). See "What T1 changed" in §0 and the gotchas in §2a.

### T2 — `RemoteLlamaBackend` (HTTP client to `llama-server`) — DONE (PR #8)

- `RemoteLlamaBackend` POSTs non-blockingly to `/v1/chat/completions` through
  `HTTPRequest`; request payloads carry `temperature`, `max_tokens`,
  `cache_prompt: true`, and optional per-request `grammar`.
- `LlamaChatCodec` parses `content`, `finish_reason`, and the T2 timing set
  (`prompt_n`, `prompt_ms`, `predicted_n`, `predicted_ms`) from canned JSON.
  Timings appear in the existing `ai_response` trace entry; no trace storage or
  new trace code was added (D21 remains untouched).
- Explicit `cancel()` and orchestrator-owned timeout both abort and free the
  HTTP transport. Stable errors cover transport, HTTP status, invalid JSON,
  invalid response, and empty content.
- Development selects it with `OUTPOST_AI_BACKEND=remote-llama` plus optional
  `OUTPOST_AI_ENDPOINT` and `OUTPOST_AI_API_KEY`; `FakeAiBackend` remains the
  default. T5 still owns visible fallback.
- Verification: 52/52 GUT tests green, manifest validation green, intentionally
  closed localhost port gives a clear timed-out-server response, and a real E2B
  chat-screen turn completed in **1.10 s** with input busy-lock/unlock and timings
  in its trace. Details: `docs/benchmarks/milestone2_remote_backend.md`.

### T3 — Local server lifecycle (desktop only)

✅ **DONE (T3, PR #10):** `LlamaServerManager` launches the selected
`ModelProfile` through `OS.create_process`, bounds each `/health` probe, and loads
asynchronously during kernel boot. `LocalLlamaBackend` queues a turn through the
existing T2 HTTP transport until the server is ready. Windows RAM and CUDA VRAM are
measured at the runtime boundary and profile floors fail closed. A healthy server on
the configured endpoint is reused and never killed; only an app-owned PID is killed
on shutdown. `OUTPOST_AI_BACKEND=local-llama` enables this path, with Bonsai as the
catalog default and `OUTPOST_MODEL_PROFILE=gemma_e2b_desktop_cuda` for verification.

Verification: 64/64 GUT tests, including cold launch, reuse, capability rejection,
timeout cleanup, queued request, and cancellation. In the real main scene, E2B
completed both a reused-server turn and a clean cold-start turn; after the cold run,
no `llama-server` process remained.

### T4 — Model-as-configuration (D6) — DONE (PR #9)

- `ModelProfile` and `ModelCatalog` resources replace bare model paths. Every
  profile captures the server executable and weights paths, platform/backend,
  `-ngl`, total ctx, `-np`, routing-family count, `--cache-reuse`, reasoning off,
  threads, and available-RAM/VRAM floors.
- `ModelCapabilities` keeps gating deterministic: insufficient or unknown required
  RAM/VRAM fails closed, without pretending a platform-specific probe already exists.
- The catalog supplies E2B as an explicit desktop verification profile and Bonsai-27B
  Q1_0 as the D5 desktop default. `server_arguments()` makes T3's server launch a
  direct projection of the selected resource; no E2B/Bonsai code branch is needed.
- Verification: 58/58 GUT tests and manifest validation green. T3 must still prove
  process lifecycle and that it consumes this configuration at runtime.

### T5 — Visible unavailable state and bounded recovery — ✅ **DONE**

Implemented as kernel-owned `core/ai/ai_availability.gd` (AVAILABLE →
RECOVERING → UNAVAILABLE; announces `ai_availability_changed` on the event
bus). Orchestrator refuses with error `unavailable` while blocked — no backend
call, no state change, never a fake reply. Backend recovery hooks:
`AiBackend.attempt_recovery(attempt)` — base/fake always healthy;
`remote-llama` GETs `/health`; `local-llama` attempt 1 is a bounded
`LlamaServerManager.restart()` (the one-process-restart-per-outage rule),
attempts 2–3 re-probe. Chat shows system messages + a Retry button that calls
`AiAvailability.retry()` (new three-attempt sequence, first probe immediate).
`AiAvailability` is deliberately signal-driven (zero coroutines) so timers can
drive it under 4.7's unawaited-coroutine parse rule; `AiRequest` gained a
non-coroutine `outcome()` accessor for that. 8 tests in
`tests/integration/test_ai_availability.gd`; full outage→retry→restore cycle
verified against the real chat screen headless.

### T6 — Input-source seam (D18) — ✅ **DONE**

Kernel-owned `core/ai/input_router.gd` (`AiInputRouter`) is the only path from
player text to the orchestrator; `core/ai/input_source.gd` (`AiInputSource`) is a
named handle obtained via `create_source(id)`. `submit()` is fire-and-forget — the
turn's outcome (success, `busy` rejection, or failure) is broadcast on the event
bus as `AiInputRouter.EVENT_TURN_COMPLETED` (`ai_turn_completed`) carrying
`{source_id, text, result}`. The chat screen is now just the `typed` source: it
submits and renders turns from the event, so it no longer awaits the orchestrator
and no longer owns the reply path. The source id travels in the orchestrator
context and is recorded in the `build_request` trace stage.

Ownership note: the source references the router, the router holds no sources —
deliberately, so the T1 lambda/RefCounted cycle class of leak cannot recur here.

The screen echoes player text in `_on_submit` for its own submits (immediately, so
you see your words before the model answers) and in `_on_turn_completed` for turns
from any other source. Both halves of a conversation are logged whatever the source.

Verification: 77/77 GUT tests green (5 new in
`tests/integration/test_input_router.gd`: second-source end-to-end, two-source
busy collision where both sources hear back, source id in the trace, foreign-source
echo, and a no-double-echo guard on the typed path) plus manifest validation.
Driven headless against the real chat screen, and against **real E2B** for the M2
exit measurement — see `docs/benchmarks/milestone2_exit_e2b.md`.

**The echo gap was found by the real run, not by the tests** — 75 passing tests,
three of them written for this exact seam, all missed that the log showed replies
with no record of what was said. Rule 4 in §6 earned its place again.

**Two harness gotchas cost time here — they are verification artifacts, not bugs:**
`RichTextLabel.append_text()` does **not** update the `.text` property (read
`get_parsed_text()` instead), and **GDScript lambdas capture locals by copy**, so
a `var flag := false` set inside a subscribed lambda never updates outside it —
use a dict holder, the same pattern the T1 notes recommend for coroutines.

**M2 exit criteria:** real E2B turn in the running app; `-rea off` +
prefix-cache behavior confirmed in-app (~sub-second desktop turn per D7/D8);
all tests green with no model required (fake/recorded only in CI); plan.md
updated ("record what actually happened").

---

## 5. M3 — deterministic orchestration (after M2)

⛔ **Gated twice:** GATE 0 direction review applies again at M3 start (scope
fine-tuning), and **traces must not be built before the D21 conversation.**

Shape (details in the spec + plan.md): Phase 1 contracts from the spec's §27
(pipe parser/validator, tool/workflow/memory-registry contracts) → walking
skeleton: grammar-constrained intent classification (real E2B, grammar
generated from the intent registry) → one deterministic workflow (existing
dice + `grant_resource`) → bounded narration → file-based trace (pending
D21). Confidence enum is `LOW|MEDIUM|HIGH`, **log-only** (no routing
branches on it). Rework `AiOrchestrator` off the M1 model-driven tool-calling
(D4). Most of this is deterministic code, testable with `FakeAiBackend`.

## 6. Standing rules for any agent on this repo

1. **Docs are part of done.** Decisions with evidence → `docs/decisions.md`;
   roadmap movement → `docs/plan.md`; measurements → `docs/benchmarks/`.
2. **Never let the AI (the game's, or you) decide game numbers** (D4). The
   whitelisted command registry is the enforcement point — don't weaken it.
3. **Measure per D17** before trusting any number (one process at a time,
   same binary, check the governor, variance is signal).
4. **Verify in the running app**, not only tests — launch Godot and drive
   the change (D3 taught that tests alone lie about export/runtime reality).
5. **A model verdict is a model+runtime verdict** (D17 §11) — check another
   runtime before declaring a model unfit for a device.
6. When you stop mid-task, update **this file** (state line at top, tick or
   annotate the task you were in) so the next agent lands on its feet.

---

## 7. M3a — the workflow DSL kernel + traces (current milestone)

Decisions: **D24** (canonical form), **D25** (resumable instances), **D21**
(traces), **D4 amendment** (narration contract, difficulty classification),
**D29** (English reasoning). Design detail lives in
`docs/workflow_dsl_brainstorm.md` — §4 language core, §5 execution model, §6
worked examples, §12 the nine open details to settle during implementation.

Each step is one branch + PR.

### A1 — Trace writer (D21) — **DONE**

JSONL per orchestration under `user://traces/`, one stage entry per line, plus a
Markdown export. On by default in dev builds. No retention policy (M4's problem).
`AiTrace` already collects the stages; this gives it a sink.

**Done when:** a real orchestration writes a file you can read start to finish and
confirm the run behaved correctly. That is the acceptance test — a human reading
one trace — not a line-coverage number.

**Landed as:** `core/ai/ai_trace_writer.gd` (`AiTraceWriter`), constructed in
`GameKernel.boot()` as `trace_writer` and called from `AiOrchestrator._result()`
(the single funnel every return path passes through). `AiTrace` gained `id` and
`to_markdown()`. Acceptance met by reading one real dev-mode trace end to end.
**Watch:** the dev-build default would otherwise write unbounded trace files into
the real `user://` on every automated test run — `tools/test.ps1` sets
`OUTPOST_TEST_RUN=1` to opt the suite out; tests that exercise the writer build
their own pointed at a scratch dir (`tests/unit/test_ai_trace_writer.gd`,
`tests/integration/test_ai_trace_end_to_end.gd`). **After adding the new
`AiTraceWriter` `class_name`, run `--import` once** or dependent scripts fail to
parse (the standing global-class-cache gotcha).

### A2 — DSL core (D24) — **DONE**

Op registry with a `pure: true/false` flag per op, expression layer (fully
parenthesized, no precedence anywhere in canonical form), and the
**registration-time strict validator**. The validator enforces effectful-ops-at-
statement-level structurally, and D19's grammar generation later reads the same
`pure` flag — one source of truth.

**Landed as:** `core/workflow/dsl/` — `op_registry.gd` (vocabulary + purity flags;
grammar keywords like `if`/`let` are NOT registry ops, D27), `dsl_ref.gd` (sigil
rule shared by validator + evaluator), `dsl_eval_context.gd` (read-only seam),
`expression_evaluator.gd`, `workflow_validator.gd`. 36 tests across
`test_op_registry.gd`, `test_dsl_expression_evaluator.gd`, `test_workflow_validator.gd`.

**§12 details settled in a syntax review with the user (see brainstorm §4/§12):**
atomic sigils + explicit `get` op (no dotted access); lowercase operators
(`== != < <= > >=`, `+ - * / %`, `and`/`or`/`not`, `in`/`contains`, `+` concatenates);
computed keys allowed but discouraged; flat per-instance `$$` scope; and a new
**global-variable scope — D31** (`get_global`/`set_global`, non-authoritative,
persisted, capability-gated, traced; amends D4). Rule-table range-rows deferred to
M3b. **Gotchas:** JSON parses `1` as a **float** (no int type) — integer-valued
fields must accept integral floats (bit the validator; will bite the A3 executor);
GDScript Variant `==` **raises** on String-vs-number rather than returning false
(guard cross-type equality). Run `--import` after adding the new `class_name`s.

**Not built here (A3's job):** execution, `$$`/global binding at runtime, suspension
& checkpointing, the real kernel-backed `DslEvalContext`, `set_global` effect + trace.

### A3 — Resumable instances (D25) — **DONE**

Checkpoint at suspension points, the instance snapshot as save contract,
`resume_require` on every suspension, `pc_stack` encoding.

**Done when:** a suspended instance survives an app restart and resumes correctly —
and re-validates rather than trusting the world it left.

**Landed as:** `core/workflow/` — `global_store.gd` (D31), `dsl_function_registry.gd`
+ `dsl_table_registry.gd` (the names `fn`/`table_get` resolve through),
`dsl/workflow_runtime_context.gd` (real kernel-backed `DslEvalContext`),
`workflow_instance.gd` (the §5.2 snapshot + `to_dict`/`from_dict`),
`workflow_registry.gd`, and `workflow_executor.gd` (the engine). All wired into
`GameKernel`; construct per run via `WorkflowExecutor.for_kernel(kernel)`. 25 tests.

**Key design call (settled in review):** the executor uses an **explicit control
stack**, not native recursion, so a resume point serializes. `pc_stack` is a
**structured resume path** — one descriptor per frame `{sel, at, pc, loop?}` where
`sel` ∈ root/then/else/elif:N/body; loop frames carry their remaining values + pos so
a resumed loop advances deterministically. Resume re-walks the tree by the path,
re-checks `resume_require` first (§5.3, fails `stale_context`), and a declined
`confirm` cancels. Verified surviving a JSON round-trip incl. suspension nested in a
loop's if-branch. **`for` is half-open `[from, to)`. Rolls: k-th roll derives from
(seed, roll_count) — only `roll_count` is persisted, no RNG blob.**

**Deferred (noted):** nested *sub-workflow* suspension (`run` of a child that
suspends) fails `nested_suspension_unsupported` for now; `table_get` range-rows (M3b);
full save-folder wiring is M4 (the instance snapshot is already the contract).

### A4 — Migrate off v0 `WorkflowEngine` — **DONE**

Consumers: `Scheduler`, `AiOrchestrator._handle_schedule`, base_game's month-end
workflow, `test_workflow_engine.gd`, `test_scheduler.gd`. **Delete v0 in its own
PR** so the migration reviews separately from the build.

**Landed as:** `Scheduler` now validates a def when scheduled (`WorkflowValidator`) and
runs it via `WorkflowExecutor.for_kernel(kernel)` as a fresh `WorkflowInstance`; it no
longer takes/uses `WorkflowEngine`. `AiOrchestrator._handle_schedule` validates with
`WorkflowValidator` (dropped `kernel.workflows.validate_definition/default_capabilities`).
base_game's month-end workflow rewritten in the new DSL — the v0 `narrate` free-text line
(`"...${food}..."`) became `emit {msg: "base_game.month_end", values: {food: $$food}}`
(i18n discipline), and the chat screen renders `workflow_emit` instead of the retired
`workflow_narrative`. **`core/workflow/workflow_engine.gd` + `test_workflow_engine.gd`
deleted; `kernel.workflows` removed.** 131 tests green.
**Note:** a scheduled workflow that *suspends* reports `ok: false` and is not re-armed —
game-time wake re-arming in the scheduler is future work, not this migration. Month-end
does not suspend.

### A5 — Narration contract (D4 amendment)

The `narrate` op: instruction, context, verbosity, output language. Instructions
narrow enough that high verbosity decorates rather than invents. Expected to be too
tight — widen from real scenarios, not speculation.

**M3a exit — MET** (A1 traces + A3 restart-survival + A4 migration): month-end workflow
runs on the new kernel with v0 deleted; a suspended instance survives restart; one trace
reads end to end. A5 (the AI `narrate` op) remains an M3a task but is not an exit gate.

**Then M3b** — deterministic orchestration. **GATE 0 applies again there**, and its
first real task is measuring difficulty-classification stability across models,
phrasings and input languages (D17). That measurement is the one that says whether
the D4-amendment approach actually works.
