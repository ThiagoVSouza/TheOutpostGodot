# M3b walking skeleton — live E2B verification

**Date:** 2026-07-21 · **Model:** Gemma E2B (`gemma_e2b_desktop_cuda`, llama-server b10042, CUDA)

The full ribosome turn (D30) run end to end against a **real model** for the first time — not
the fake seams. One forage turn, driven headless through `AiOrchestrator.handle_message`.

## Input
```
"I send scouts to forage the hills for food"
```

## Result
```
OK:     true
REPLY:  "The foraging party returns, bringing back five units of food, a successful haul
         from their venture."
STAGES: turn_started → workflow_started → workflow_ai → workflow_dispatched
        → workflow_command → workflow_narrated → workflow_completed
STATE:  { food: 5 }
```

## What this confirms
- **Real classification works.** `LlamaAiRunner` asked E2B to pick from the closed intent set
  `{forage, general}`, grammar-constrained (D19); E2B returned `forage`; the entry workflow
  dispatched to the forage workflow.
- **Real narration works.** `LlamaNarrator` gave E2B the decided facts and it produced fluent
  prose describing them.
- **D4 held, live.** The `5` came from the `forage_yield` rule table applied through
  `grant_resource` (code), on a seeded roll. E2B *narrated* it — "five units of food" — but did
  not decide it. The model classified and described; code owned the number.
- The seams carry their own timeout + T5 availability reporting (`LlamaAiCall`); the executor
  awaited both AI calls in memory (D30), never checkpointing.

## Notes
- Selection is automatic: `OUTPOST_AI_BACKEND=local-llama` (non-fake) → kernel wires
  `LlamaAiRunner`/`LlamaNarrator`; the fake path stays the test default.
- Harmless: a `-s` SceneTree run logs `Identifier not found: Kernel` from `chat_screen.gd`'s
  autoload reference — the standing headless-script gotcha, not a runtime error.

## Not yet measured
This is a **single successful turn**, not the D17 stability measurement. Whether classification
stays consistent across models, phrasings and input languages — the +17/+20/+15 test repeated
on the new design — is the next step, and the one that says whether the approach holds.
