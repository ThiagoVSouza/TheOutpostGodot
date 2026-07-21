# D17 — classification stability (the +17/+20/+15 test, repeated)

**Date:** 2026-07-21 · **Model:** Gemma E2B (`gemma-4-E2B-it-qat-UD-Q4_K_XL`, llama-server
b10042) · **Harness:** `tools/measure_classification.gd`

The measurement that decides whether the D4-amendment approach holds: does grammar-constrained
**difficulty classification** give the *same verdict* for the *same action*, regardless of how
it's phrased or what language it's in? This is the direct answer to the failure that started it
all — one model paid +17/+20/+15 for one roll across three model families, and **Bonsai-4B gave
three different outcomes for one action in Portuguese, Spanish and French.**

## Method
3 actions spanning the difficulty range, each phrased **2 ways** in **English, Portuguese and
Spanish** = 18 classifications. The model picks `low | medium | hard`, **grammar-constrained at
the sampler** (D19, GBNF alternation) so an out-of-set answer is unsampleable, at **temperature
0**, told to **reason in English** regardless of the input language (D29).

## Result — every action, one verdict across all 6 variants

| Action (intended) | en · en | pt · pt | es · es | stable? |
|---|---|---|---|---|
| gather berries by camp (low) | low · low | low · low | low · low | ✅ 6/6 |
| forage the distant hills (medium) | low · low | low · low | low · low | ✅ 6/6 |
| raid the guarded granary (hard) | hard · hard | hard · hard | hard · hard | ✅ 6/6 |

**Within-action stability across phrasing and language: 18/18 (100%).**

## What this means
- **The language-divergence problem does not reproduce.** The thing that made the old design
  unshippable — the same action scored differently per language — is gone. E2B returned the
  *identical* label for each action whether it was written in English, Portuguese or Spanish.
  This is exactly what D29 ("reason in English, only narration is localized") + grammar
  constraint + temperature 0 were designed to buy, and it delivered.
- **This is the gate, and E2B passes it.** E2B is the mobile default (D5), so its stability is
  the one that ships. The difficulty enum is stable enough to drive workflows.

## Caveats — read before over-claiming
- **One model.** E2B only. Cross-*model* agreement (E4B, Qwen, Bonsai-27B) is the next run —
  the harness is reusable (swap the loaded model, re-run). Note the original failure was *both*
  cross-language (worse — same model) and cross-model; this settles the cross-language half
  decisively for E2B.
- **`forage_far` read as `low`, not the `medium` I guessed.** That is **calibration, not
  instability** — the model has a consistent opinion that differs from the author's; it never
  wavered. The fix, if we disagree, is prompt/band design, not abandoning the approach. (And it
  is a healthy reminder that the *author's* expected labels are also just guesses.)
- **Temperature 0** removes sampling variance by construction; the meaningful signal here is that
  *prompt* variance (phrasing, language) did not move the verdict.
- **Small sample** (3 actions). Broaden the action set for confidence before trusting it in
  balance-critical places.

## Verdict
On the model that ships, grammar-constrained difficulty classification is **stable across
phrasings and input languages.** The D4-amendment approach holds. Next: repeat across the model
ladder (E4B / Qwen / Bonsai) and widen the action set — and drive it by hand in the playground.
