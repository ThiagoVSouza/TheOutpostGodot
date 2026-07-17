# Handover — next steps (agent-geared)

**Audience:** an AI agent (or human) picking this project up cold — possibly
mid-milestone after a usage-limit cutoff. Follow this file top to bottom.
Keep it updated as work lands: it is a living checklist, not an archive.

Last updated: 2026-07-17 · State: **T3 complete — PR #10 open, ready for user merge.**
T1, T2, and T4 are merged as PRs #7, #8, and #9. The user reviewed and approved
T3's scope. The agreed next order is T5, then T6; each still requires its own plan
review before implementation.

## 0. If you are the next agent, start exactly here

1. `git fetch`, then confirm PRs #7, #8, and #9 are still merged. Start the next task from
   current `origin/main`, preserving this handover update until it is merged.
2. **Plan-review T5** with the user before production code. The agreed next
   order is T5, T6; the user expects a task-specific review before each.
3. Read §1 (context bootstrap) before touching anything. The T1 lessons in
   §2a are new since the docs were written — they will save you time.
4. D21 reminder unchanged: **no trace-related code before the user shares
   their trace-storage thoughts.** Nothing in T2–T6 touches traces.

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

### T5 — Graceful fallback (D16's rule)

- Server absent/unreachable/dies mid-session → fall back to `FakeAiBackend`
  (visible in UI as degraded, not silent), game never breaks.
- **Done when:** kill the server mid-session in a manual run → next turn
  degrades gracefully; automated test simulates backend failure.

### T6 — Input-source seam (D18)

- Orchestrator entry point takes **text from a source** (typed / future
  voice / future trace replay), not a `LineEdit`.
- **Done when:** chat screen is just one source; a test feeds text through a
  second source.

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
