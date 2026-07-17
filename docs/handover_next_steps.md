# Handover — next steps (agent-geared)

**Audience:** an AI agent (or human) picking this project up cold — possibly
mid-milestone after a usage-limit cutoff. Follow this file top to bottom.
Keep it updated as work lands: it is a living checklist, not an archive.

Last updated: 2026-07-17 · State as of: PR #5 merged (Phase 0 spikes passed)

---

## ⛔ GATE 0 — no coding before a direction review with the user

**Do not write production code until the user has reviewed and confirmed the
direction in a conversation.** The user has said the plan below may need
fine-tuning before implementation starts. Specifically:

1. **Open the conversation by asking the user to review the M2 task order
   below** and adjust anything before you start.
2. **D21 (trace storage) is separately gated:** the user has *additional
   thoughts to share* on trace storage (files vs SQLite). Do not write any
   trace-related code before that conversation happens. (This gates M3
   traces, not M2 — but do not "helpfully" scaffold traces early.)
3. If the user is unavailable and you were explicitly told to proceed, the
   only safe starting point is **T1 (async seam)** — it is required under
   every possible fine-tuning of the plan. Everything after T1 needs the
   review first.

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

### T1 — Async seam for `AiBackend` (D22) — *the unavoidable first PR*

- Rework `AiBackend` to return a **request handle** exposing
  `chunk`/`completed`/`failed` signals + `cancel()`. Orchestrator, chat
  screen and tests convert to `await`/signal handling.
- `FakeAiBackend` must complete via `call_deferred` — **never synchronously
  in the same call** — so reentrancy/cancellation bugs surface in tests.
- Timeouts: orchestrator-owned (race completion vs `SceneTreeTimer`).
- **Done when:** all GUT tests green (updated for async); chat screen still
  round-trips the M1 fake flow; a `cancel()` mid-fake-turn test exists;
  launching the app and typing a message still works (verify by running it).

### T2 — `RemoteLlamaBackend` (HTTP client to `llama-server`)

- POST `/v1/chat/completions`; `temperature`, `max_tokens`, `cache_prompt:
  true`, per-request `grammar` (string field — spike-proven).
- Non-blocking transport per D22 (`HTTPRequest` is fine pre-streaming; a
  polled `HTTPClient` if/when token streaming is wanted).
- Parse `timings` (prompt_n/prompt_ms/predicted_n/predicted_ms) into the AI
  trace.
- Honor `cancel()` (abort the HTTP request) and the orchestrator timeout.
- **Done when:** with a hand-started server, a real chat turn produces E2B
  prose in the running app; with no server, requests fail cleanly into T5's
  fallback path (or a clear error until T5 lands); unit tests cover response
  parsing + error mapping with canned JSON (no live server in CI tests).

### T3 — Local server lifecycle (desktop only)

- Spawn `llama-server` via `OS.create_process` from a model configuration;
  poll `/health` until ok; terminate on quit. Desktop-only guard — mobile
  cannot exec (that is M6's GDExtension work, not this).
- **Done when:** cold app start → first real turn with no manual server; app
  quit leaves no orphan process; a stale port / already-running server is
  detected and reused or reported, not doubled (the 2026-07-17 spike found a
  leftover server holding 2.8 GB VRAM — detect that case).

### T4 — Model-as-configuration (D6)

- A model entry is a **configuration resource**, never a bare GGUF path:
  weights path, backend, `-ngl`, ctx total, `-np` (slot count ≥ routing
  family count, D23), `--cache-reuse`, `-rea off` (D7), threads, RAM/VRAM
  floor that gates it (D11).
- **Done when:** T3 spawns entirely from a config resource; swapping E2B ↔
  Bonsai-27B is a config change, no code change; tests validate config
  parsing + floor gating.

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
