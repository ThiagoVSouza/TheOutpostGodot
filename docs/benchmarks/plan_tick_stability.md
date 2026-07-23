# Plan-tick stability (D17 method, applied one level up)

**Date:** 2026-07-23 · **Model:** Gemma E2B (`gemma-4-E2B-it-qat-UD-Q4_K_XL`, llama-server
b10042) · **Harness:** `tools/measure_classification.gd` (`OUTPOST_MEASURE=plan_tick`)

The first M5 measurement, taken **before** the plan format is designed (plan.md M5): does a
background plan advance the *same way* regardless of how its latest development is worded or in
what language? Same discipline as D17 difficulty — grammar-constrained closed set (D19), temp 0,
reason in English (D29), labels carry descriptions (D33) — but the question is harder, because a
plan tick reads a whole *situation*, not a one-line action.

## Method
Six scenarios drawn from the briefing's examples (corrupt steward, brewing revolt, hired raid,
trade bid, watchful neighbor). Each holds two structured fields **constant** — what the situation
is, and its current direction — and varies only the **latest development** across **2 phrasings**
in **English, Portuguese and Spanish** = 36 ticks. The model picks one of five transitions:
`escalate | hold | de_escalate | mutate | resolve`, each with a one-line description in the
prompt. Holding the structure constant and varying only the narrative is deliberate: the
narrative is the part a real tick will draw from retrieved memory, so it is the part whose
stability actually matters.

## Framing — which rows are the signal (D35)

This run predates **D35** (internals are English; input is translated at the boundary before it is
stored or retrieved). Under D35 a plan tick never sees non-English text — a plan's
`latest_development` comes from a memory, and memories are stored in English. So the two axes here
carry different weight:

- **The English phrasing axis is the primary signal** — does the same English situation, worded
  two ways, get the same transition? This is what a real tick faces, and it is what the format
  decisions below rest on.
- **The pt/es rows are defense-in-depth** — "if a stray non-English string leaks past the
  boundary, does it still classify sanely?" Reassuring (see the cross-language result), but not
  the question the plan format answers.

The three format findings below all come from the English runs and English phrasing sensitivity,
so D35 does not weaken them.

## Result

| Scenario (guessed) | en · en | pt · pt | es · es | within-scenario |
|---|---|---|---|---|
| steward_refused (escalate) | escalate · de_escalate | escalate · de_escalate | escalate · de_escalate | split by phrasing (3/3) |
| revolt_appeased (de_escalate) | de_escalate · **escalate** | de_escalate · de_escalate | de_escalate · de_escalate | 5/6 |
| bandits_unopposed (escalate) | escalate · escalate | escalate · escalate | **hold** · escalate | 5/6 |
| trade_signed (resolve) | resolve · resolve | resolve · resolve | resolve · resolve | ✅ 6/6 |
| neighbor_quiet (hold) | hold · hold | hold · hold | hold · hold | ✅ 6/6 |
| steward_exposed (mutate) | escalate · escalate | escalate · escalate | escalate · escalate | ✅ 6/6 (off-guess) |

**Cross-language stability (the D17 headline): 10 of 12 (scenario, phrasing) triples returned the
identical label across all three languages; 34 of 36 verdicts agree with their triple's majority.**
The two exceptions are single-language outliers (one English, one Spanish), never a three-way
split.

## What this means

- **The catastrophic failure does not reproduce — again.** The thing that killed the old design
  (Bonsai-4B: *three different outcomes* for one action in pt/es/fr) never appeared. The worst
  case here was two labels with one language dissenting. Cross-language stability carries up from
  difficulty classification to the richer plan-tick judgment. The D4/D29/D33 stack holds one
  level up.

- **Plan-tick is genuinely harder than difficulty** (3/6 fully stable here vs difficulty's 3/3),
  but the diagnosis matters more than the count, and most of it is not language instability:
  - **steward_refused split by *phrasing*, not language** — every language agreed within each
    phrasing. "Refused and **mocked him before the court**" read `escalate` (a public
    provocation); "turned down and **had him escorted out**" read `de_escalate` (a firm but
    orderly refusal). Those are arguably *different situations*, so this is the model being
    meaning-sensitive, not unstable. **The real lesson: for a whole situation, writing two
    phrasings that hold meaning constant is much harder than for a one-line action.** The harness
    varied intent without meaning to.
  - **revolt and bandits each had one lone temp-0 outlier (1/6)** at a boundary. Notably the
    language variants were sometimes *steadier than English* — on revolt's second phrasing,
    English was the dissenter and pt/es agreed.
  - **`mutate` never fired.** steward_exposed was perfectly stable but the model chose `escalate`
    on all six, never "the plot changes character." A 2B model does not reliably reach an
    abstract meta-transition from a description alone.

## Design implications for the plan format (the reason this was measured first)

1. **Keep the structured-fields-constant, narrative-varies shape.** It anchored the model hard —
   `trade_signed` and `neighbor_quiet` were rock-solid across all six variants. A plan that owns
   its `situation` and `direction` and feeds retrieved memory as the variable part is the right
   representation.
2. **`mutate` as authored is the weak label — do not rely on the model to detect a plot changing
   character.** Options: make plot-type changes **code-detected** (a transition fired when the
   direction field's own logic sees a trigger), drop `mutate` from the model's set, or replace it
   with concrete named transitions (e.g. `turn_to_revenge`) that a description can actually pin
   down. This is the plan-tick analogue of D33's "the catch-all needs a reason to exist."
3. **Design for single-tick noise, not against it.** At temp 0 a boundary situation still mis-read
   1-in-6. A plan's direction should have **hysteresis** — one tick should nudge a stance, not
   collapse the plot — so a lone bad tick self-corrects on the next one. This is a *format*
   decision the measurement earned: do not build plans that bet everything on one verdict.

## Caveats — read before over-claiming
- **One model** (E2B, the mobile default D5). Cross-model (E4B / Qwen / Bonsai) is the next run;
  the harness is reusable (`OUTPOST_MODEL_PROFILE=…`, re-run).
- **`expect` is a calibration guess, not a key** (D17). `steward_exposed` reading `escalate` over
  the guessed `mutate` is the model having a consistent opinion, which finding 2 above acts on.
- **Small sample** (6 scenarios). Widen before trusting plan-ticks in balance-critical places.
- **Temperature 0** removes sampling variance by construction; the signal is that *prompt*
  variance (phrasing, language) moved the verdict only twice in 36.

## Verdict
Grammar-constrained plan-tick classification is **stable enough to build on**. Under D35 the
primary result is English phrasing stability (the format findings above); the cross-language rows
are defense-in-depth and reassuring — the old catastrophic per-language divergence does not
reproduce. The residual instability is concentrated where the design can route around it: drop or
code-own `mutate`, write phrasings/plans that don't smuggle meaning changes, and give plan
direction hysteresis so a single mis-tick doesn't matter. Measure the ladder before trusting it in
balance. Next M5 step: design the plan format on these three findings.
