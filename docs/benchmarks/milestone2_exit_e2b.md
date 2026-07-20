# Milestone 2 — exit criterion: real E2B turn through the finished path

Verified 2026-07-20 on the desktop development machine, after T5 (availability
gate) and T6 (input-source seam) both changed the path into the orchestrator.
This is an integration record, not a model-performance verdict — four turns in one
session is not a benchmark (D17).

**Why it was re-run:** the previous live measurement
(`milestone2_remote_backend.md`, 1,097 ms) predates T5 and T6. Both insert work
ahead of the backend call — an availability check and an event-bus reply hop — so
the number had to be re-taken rather than assumed to still hold.

## Setup

- Godot 4.7.1 headless, real app, real `base_game` chat screen instantiated from
  the screen registry and driven through the T6 `AiInputRouter`.
- llama.cpp b10042, E2B UD-Q4_K_XL, CUDA full offload, cold spawn by
  `LlamaServerManager` (no pre-existing server on 8099 — confirmed before the run).
- App selection: `OUTPOST_AI_BACKEND=local-llama`,
  `OUTPOST_MODEL_PROFILE=gemma_e2b_desktop_cuda`.
- Server arguments projected from the `ModelProfile` resource (T4), including
  `-rea off` (D7) and `--cache-reuse 256` (D8).

## Result — every turn, not an average (D17)

| Turn | State | Wall clock | prompt_n | prompt_ms | predicted_n | predicted_ms |
|---|---|---:|---:|---:|---:|---:|
| 1 | cold | 9.47 s | 66 | 101.7 | 57 | 671.3 |
| 2 | warm | 0.85 s | 20 | 65.0 | 63 | 739.9 |
| 3 | warm | 0.80 s | 19 | 63.0 | 58 | 689.6 |
| 4 | warm | 0.83 s | 18 | 69.0 | 68 | 712.8 |

All four turns returned `ok=true` with genuine narrative prose, and the
availability state was `available` at the end — no outage opened.

**Warm turns are sub-second (0.80–0.85 s), satisfying the M2 exit criterion.**
T5 and T6 cost nothing measurable: the spread is slightly *better* than the
pre-T5/T6 1,097 ms, which is within session-to-session noise and should not be
read as an improvement.

**Turn 1's 9.47 s is server startup, not inference.** Its own timings account for
only ~0.77 s; the remaining ~8.7 s is `llama-server` process spawn plus CUDA model
load. This is the cost `LlamaServerManager.ensure_started()` deliberately absorbs
during kernel boot (T3) so a player reaching the chat screen does not pay it — this
harness submits immediately on boot, so it pays it in full and is the pessimistic case.

**D8's prefix cache is visibly working.** Processed prompt tokens fall from 66 on
the cold turn to 18–20 on warm turns. Each turn sends an independent
system+user message pair (the orchestrator carries no conversation history yet),
so the cached prefix is the ~50-token M2 system prompt, and only the new user
tokens are processed. Decode throughput is flat at ~84–95 tok/s across all four.

## Limits of this measurement (D17)

- One session, one machine, four turns. No repeat sessions, so between-session
  variance is unmeasured.
- No control of background GPU load, and no governor/clock check was performed.
- Prompts differ in length and content, so the warm turns are not replicates of
  each other — they establish an order of magnitude, not a distribution.
- Decode throughput here is not comparable to the milestone-1 numbers, which used
  different prompts and a different harness.

## Defect found by this run

The chat log rendered four `Game master:` lines and **no `You:` lines**. The
harness submitted through its own `AiInputSource` rather than the screen's
`_on_submit`, and the player-text echo lives only in `_on_submit` — so a turn
originating from any source other than the screen's own text field produces a
reply with no record of what was said. Reply rendering was source-agnostic;
the prompt echo was not. This would have surfaced at M6, when voice becomes
exactly such a source.

**Fixed in the same PR:** `_on_turn_completed` now echoes the payload's `text`
when the turn came from a source other than the screen's own, so the typed path
still echoes immediately (no waiting ~0.85 s to see your own words) while every
other source gets both halves logged. Two tests cover it, including a guard
against the typed path double-echoing.

This is the argument for the repo's verify-in-the-running-app rule: 75 passing
tests, including three written specifically for this seam, all missed it. Only
rendering a real conversation showed one half of it was absent.
