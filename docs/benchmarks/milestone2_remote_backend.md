# Milestone 2 — Remote llama backend verification

Verified 2026-07-17 on the desktop development machine. This is an integration
record, not a new model-performance verdict: one live turn is not a benchmark
(see D17).

## Setup

- Godot 4.7.1 headless real app + real `base_game` chat screen.
- llama.cpp b10042, E2B UD-Q4_K_XL, CUDA full offload.
- Server: `-ngl 99 -c 16384 --port 8099 --host 127.0.0.1 --cache-reuse 256`
  `-np 4 --no-webui -rea off`.
- App selection: `OUTPOST_AI_BACKEND=remote-llama`, endpoint
  `http://127.0.0.1:8099/v1/chat/completions`.

## Result

The real screen submitted “I inspect the western palisade as sunset approaches.”
and rendered E2B prose. Input and Send locked during the request and unlocked when
the reply arrived. Total UI turn: **1,097 ms**.

The existing `AiTrace` captured the normalized backend timing fields:

| prompt_n | prompt_ms | predicted_n | predicted_ms |
|---:|---:|---:|---:|
| 5 | 258.842 | 70 | 803.224 |

These fields prove the live response path and trace visibility. They must not be
read as a fresh throughput claim: the server was already warm and only one turn was
collected.

## No-server behavior

With the remote endpoint pointed at an intentionally closed localhost port, the
orchestrator timeout aborted and released the HTTP request and returned the visible
message: “The AI server did not answer before the timeout.” Automatic fallback is
intentionally deferred to T5.
