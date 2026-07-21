# The Outpost — Decisions

Why things are the way they are: the decision, the reasoning, and the evidence — so
a later reader can tell a measured conclusion from a guess, and knows what would
justify revisiting it.

**Status:** **Decided** · **Open** · **Superseded**

Measurements: `docs/benchmarks/milestone1_results.md`. Architecture: `docs/initial_briefing.md`.

## Index

| | Decision | Status |
|---|---|---|
| **D1** | Test runner: GUT | Decided |
| **D2** | Module manifests: `.tres` | Decided |
| **D3** | Discovery matches logical resource name, not shipped filename | Decided |
| **D4** | The AI narrates and remembers; it never decides numbers | **Decided** |
| **D5** | Model ladder: Gemma E2B → Gemma E4B → Bonsai-27B | **Decided** |
| **D6** | A model is a configuration, not a file | Decided |
| **D7** | Reasoning **off** — every family, always | Decided |
| **D8** | Prefix-cache the system prompt | Decided |
| **D9** | Android on CPU, not the Adreno GPU | Decided |
| **D10** | iOS uses Metal | Decided (untested) |
| **D11** | Model recommendation: runtime heuristic, not a catalog | Decided |
| **D12** | Licensing: everything is Apache 2.0 | **Decided** |
| **D13** | Distribution differs per store | Open |
| **D14** | Optional on-device benchmark; variance is a first-class result | Open |
| **D15** | MTP drafters: not adopted, measurement untrustworthy | Open |
| **D16** | Dispatch: inference on another machine (amends the brief) | Open |
| **D18** | Voice input: abstract the seam now, build at M6 | Open |
| **D19** | AI output is grammar-constrained at the sampler, not parsed-and-retried | **Decided** — spike-verified |
| **D20** | The pipe protocol is the only AI-facing output surface | **Decided** |
| **D21** | Trace storage: files first, SQLite deferred to M5 | **Decided** |
| **D22** | Concurrency: main-thread orchestrator, async backends | **Decided** |
| **D23** | Warm KV slots per prompt family | **Decided** — desktop-verified; re-measure on phone at M6 |
| **D24** | Workflow DSL: JSON op-tree canonical form | **Decided** |
| **D25** | Resumable instances, checkpointed at suspension points | **Decided** |
| **D26** | One language, capability profiles, data-only DLC | **Decided** |
| **D27** | Complex components: engine capabilities behind registry facades | **Decided** |
| **D28** | Authoring toolchain: one headless authoring backend | **Decided** |
| **D29** | Orchestration reasons in English; only narration is localized | **Decided** |
| **D30** | The orchestrator is a fixed executor; guardrails, classification and narration are workflows (the "ribosome" model) | **Decided** |
| **D31** | Global variables: a writable, non-authoritative, persisted workflow scope beside game state | **Decided** |
| **D32** | Two workflow composition modes: call/return (`run`) and hand-off (`dispatch`) | **Decided** |
| **D17** | Benchmarking method — how to not fool yourself | Reference |

Roadmap and current status: `docs/plan.md`.

---

## D1 — Test runner: GUT, not a custom headless runner

**Decided** (2026-07-15). Maturity and lower maintenance over building one. The
brief left it unspecified; picking early unblocked the harness.

---

## D2 — Module manifests: `.tres` resources, not JSON

**Decided** (2026-07-15). Manifests are only authored and read inside Godot, so we
take editor inspectability and built-in type validation. No external tooling needs
to generate them. See D3 for the export consequence.

---

## D3 — Module discovery matches the logical resource name, not the shipped filename

**Decided** (2026-07-16)

Godot converts text resources to binary on export, so `base_game.tres` ships as
`base_game.tres.remap`. Discovery matched `ends_with(".tres")` against the *shipped*
name, found nothing, and the app booted to a blank screen — "0 module(s) loaded".
`load()` was never the problem (it resolves remaps); only the filename scan was.

**Evidence:** reproduced on a physical S26 Ultra. Invisible on desktop and to all 27
tests at the time.

**Consequence:** any code that *scans* the resource filesystem must strip `.remap`
and accept `.res`. **Desktop tests cannot catch this class of bug — only a real
export can.** This is the standing argument for keeping device deploys in the loop.

---

## D4 — The AI narrates and remembers; it never decides numbers

**Decided** (2026-07-16) — **amends the brief's AI pipeline**

**The brief says:** `plan actions → call typed tools → generate validated game
commands` — the model decides to roll, and decides the resulting command.

**What we found:** a schema constrains *shape*, not *meaning*. With tool and command
names constrained by schema enums, the model **cannot** name anything the registry
would reject — that safety boundary held on every run, exactly as the brief intends.
And it is not enough. Models reliably emit well-formed, fully-whitelisted,
**semantically wrong** commands:

| Same 17/20 roll, same prompt, same schema | Reward emitted |
|---|---|
| Gemma E2B | `grain +17` — **the die value** |
| Gemma 12B | `grain +20` |
| Bonsai-27B | `grain +15` |

Also observed: E2B granting `grain -10` for an expedition *to find* grain, and
Bonsai-4B granting **`silver +500`** to a player holding 120 who asked to *spend*
500 — sign inverted *and* an impossible action allowed. And Bonsai-4B produced
**three different outcomes for the same action in Portuguese, Spanish and French**.

**Two independent reasons this forces mechanics into code:**

1. Small models can't do it reliably, and D5 fixes a small model as the mobile
   default because it's the only thing viable on a phone. A design that only works
   on a 27B is a high-end feature, not a design.
2. **The stronger reason: model choice is a user setting (D5), so model-driven
   mechanics means model-dependent balance.** Three legitimate models paid +17, +20
   and +15 for the same roll. A strategy game's economy cannot depend on which GGUF
   the player downloaded — or which language they typed in. **This holds even if
   every model were excellent.**

**The decision.** Deterministic workflows own everything numeric. The AI's role is
narrow and deliberately so:

```
player message
  -> classify intent                        (code)
  -> read relevant memories                 (AI assists)
  -> decide whether a roll is needed        (code, per rules)
  -> roll                                   (code, seeded, deterministic, testable)
  -> compute outcome + reward from rules    (code)
  -> build + validate + apply the command   (code, existing whitelist)
  -> narrate the decided outcome            (AI)
  -> write back memories                    (AI assists)
```

**The AI reads/writes memory and writes prose under predefined conditions. It does
not adjudicate.** Both remaining jobs are what even a 2B model does well — E2B's
narratives were consistently decent even when its arithmetic was nonsense.

**Consequences:**
- Balance is deterministic, testable, reproducible, and independent of hardware,
  model choice and player language.
- AI-trace replay gets stronger: outcomes are code, so a recorded session replays
  exactly.
- **This is what makes the cross-family ladder in D5 safe.** Narrative variety
  between models becomes a feature; balance stays fixed.
- ~~The `tool_calls` path is not deleted — it stays for open-ended use where no
  balance is at stake.~~ **Superseded by D20 (2026-07-17):** the pipe protocol
  is the only AI-facing output surface; `tool_calls` is retired as an output
  path.
- Cost: less emergent AI-driven mechanics than the brief imagined. Worth it.

**Residual risk:** narration can still misdescribe a correct outcome, and memory
read/write is not risk-free. Smaller surface, not zero — to be remediated in the
orchestration design.

### Amendment (2026-07-20) — how the AI participates without deciding numbers

Three refinements settled while planning M3. None weakens the rule; they say
precisely where the AI's judgment enters and what bounds it.

**1. The AI may classify into a closed enum; code owns every number.** Rather than
emitting a reward, the model answers a bounded question — *"given conditions A, B
and C, how hard is this?"* → `low | medium | hard`. Code maps that verdict onto a
threshold band, and the band lives in a **rule table** (`table_get`, D24), not in
code, so it is tunable without a rebuild. This is the same shape as intent
classification: the model proposes from a fixed set, code owns the arithmetic, and
D19 constrains the enum at the sampler.

**This is a real transfer of judgment and must be treated as one.** The
classification is now the AI-decided input that drives every downstream number. A
three-value enum is far more stable than a free number — but "medium" in one run
and "hard" in another for identical conditions produces different outcomes, just in
coarser steps. **The mitigation stack is deliberate, not incidental:** determinism
(everything numeric in the DSL), D29 (one reasoning language), prompt design,
possibly LoRA later, and model quality (Bonsai-27B is expected to classify far more
stably than E2B). None of these is a proof. **Classification stability must be
measured across models and phrasings at M3b, per D17, before it is trusted** — the
measurement that produced the +17/+20/+15 table is exactly the one to repeat here.
If it lands poorly, the approach gets rethought rather than patched.

**2. Whether a roll happens at all is workflow shape, not a universal gate.** The
pipeline sketch above reads as one fixed sequence with a roll in the middle. It is
not: the orchestration for an action is an **authored DSL workflow**, and workflows
differ. "I sing to the goats" checks that goats exist, that the character can sing,
how well, and whether any contest or event modifies it — and may end without a roll
at all. This retires D4's long-open question ("where does the line sit for requests
the rules do not cover") without needing a `narrate_only` escape value in the
difficulty enum: an action with no mechanical stake is simply a workflow whose only
effect is narration.

**3. Narration is the last step of the orchestration, and its inputs are fixed.**
The `narrate` op receives: an **instruction** on what to narrate, the **context** it
may draw on, a **verbosity level**, and an **output language** (D29). Instructions
are deliberately narrow, so that raising verbosity *decorates* the decided outcome
rather than inventing new facts. This scope is known to be tight and expected to
fall short once real scenarios exist — an accepted, recorded risk, to be widened
from evidence rather than pre-emptively.

**Guardrail for later:** the idea of letting the model *suggest what a critical
success or failure means* is fine **as narration** and forbidden **as mechanics**.
If such a suggestion ever becomes an effect, it must arrive as a whitelisted
command with code-owned numbers — otherwise it is D4 reintroduced through the back
door. Critical bands and their consequences start deliberately basic and get
amended from play.

**Amended (2026-07-17) — intent classification.** The pipeline above labels
`classify intent` as `(code)`. Code cannot classify free text ("hit him"); what
code owns is the *enum*. Corrected reading: the model proposes one intent from
a fixed registry-defined set (grammar-constrained, D19) and code validates and
routes. The boundary that matters — the model can never expand the set of
possible intents — is unchanged. The orchestration spec
(`docs/Orchestration_brainstorm.md`) is written against this reading.

---

## D5 — Model ladder: Gemma **E2B** → Gemma **E4B** → **Bonsai-27B**

**Decided** (2026-07-16) — E4B tier needs a clean re-test

| Tier | Model | Size | Why |
|---|---|---|---|
| **Mobile default** | Gemma 4 **E2B** it-qat | 2.43 GiB | Fits a phone's *available* RAM comfortably; fastest and most stable option measured |
| **Mobile, deferred** | Gemma 4 **E4B** it-qat | 3.91 GiB | **Not viable via llama.cpp** — but see the runtime question below |
| **Desktop default** | **Bonsai-27B** Q1_0 | 3.53 GiB | 26.9 B params at **54% VRAM on 8 GB**, current-gen Qwen3.6, passes the D4 protocol test |

### E4B on mobile: our runtime's problem, possibly not the model's — **deferred**

**Via llama.cpp it is unusable.** Retested at full CPU with the battery saver off and
it got *worse*: `tg` **2.01 ± 1.53** (variance 76% of the mean = thrashing). The
uncapped clock lifted `pp` 4.6x (8.57 → 39.47, compute-bound) and did nothing for
`tg` (memory-bound). Mechanism: **3.91 GiB of weights vs ~3.8 GiB available RAM** →
llama.cpp pages weights from storage every token. No clock speed fixes that.

**But the same model runs at 10+ t/s in Google's Edge Gallery on the same phone.**
That is a **5x gap against our own measurement**, and Edge Gallery is **LiteRT-LM,
not llama.cpp** — Gemma-specific kernels, a tuned OpenCL GPU path, and MTP
speculative decoding. So the honest conclusion is **not** "E4B doesn't fit a phone";
it is **"E4B doesn't fit a phone *the way we run models*."**

This deserves care, because it undercuts a conclusion we nearly shipped, and it is
the second time a runtime difference produced a fake model verdict (the first: the
PrismML fork's missing NEON kernel, D17 item 2).

**Deferred, not closed.** Open questions if it is picked up:
- Is the win LiteRT's GPU path, its Gemma kernels, MTP, or a different quant?
- Would adopting LiteRT-LM mean a *second* inference stack alongside llama.cpp
  (Android-only, no GGUF, different API) — and is that worth an E2B→E4B upgrade?
- Does anything in D9 (Android CPU over GPU) survive on a runtime with GPU kernels
  that were actually written for the model?

**Until then E2B is the mobile default**, and phone players have no local upgrade
path — which makes **D16 (dispatch) more valuable than it first appeared**.

**Why Gemma on mobile.** There is no viable Bonsai: the 4B and 8B are `qwen3`-arch
(two-to-three generations old, opaque base), and the 4B failed badly on quality —
`silver +500` to a player with 120. The 8B is 9.03 t/s (cooled, best thread count),
against a 15 t/s bar. Its 4B/8B scaling (1.9x vs a 2.04x param ratio) proves the
kernels are healthy and the model is simply too much compute for the phone.

**Why Bonsai on desktop.** Gemma has **no model between E4B (3.91 GiB) and 26B-A4B
(13.6 GB, the only quant offered — needs ~14 GB VRAM)**. The 12B was rejected: 89%
VRAM at 8K leaves ~900 MiB for rendering, and llama.cpp's own auto-fit tried to
reduce layers. Bonsai-27B does 2.2x the 12B's parameters in 56% of the space at the
same speed, leaving **~3.8 GiB for the game**.

| Desktop, RTX 4070 8 GB | Params | Size | tg128 | VRAM @ 8K |
|---|---|---|---|---|
| Gemma 12B | 11.91 B | 6.24 GiB | 29.17 | 7281 MiB (**89%**) |
| **Bonsai-27B Q1_0** | **26.90 B** | **3.53 GiB** | 26.86 | **4387 MiB (54%)** |

**Generation matters more than size.** Bonsai is not one family: 4B/8B are `qwen3`;
the 27B is `qwen35` / Qwen3.6-27B (explicit base). That predicts the quality results
better than parameter count does — the 4B fails the protocol, the 27B passes cleanly.

**The overhead is small: mainline llama.cpp loads all three.** Verified on stock
`b10042` — no PrismML fork, no 463-commit divergence, no custom build. One runtime,
prebuilt archives for Windows/Android, XCFramework for iOS. The real cost is two
chat templates, which llama.cpp reads from GGUF metadata automatically.

**Safe only because of D4.** Three models, three different rewards for one roll.

**On the numbers themselves:** absolute phone figures in this project move wildly
with CPU cap, thermals and memory — E2B alone measured 29.52, 23.24 and 7.92 across
one afternoon. **The ordering never moved.** Trust the rankings and the mechanisms;
treat any single absolute number as provisional. See D17.

---

## D6 — A model is a **configuration**, not a file

**Decided** (2026-07-16)

The settings around the model matter more than the model: reasoning-off (D7) is
worth ~4x and prefix caching (D8) ~20x on prompt — both larger than a whole model
tier. And the correct backend is per-platform and counter-intuitive (D9).

**Consequence:** an entry carries, per platform: weights + quant, backend
(CPU/CUDA/Metal), reasoning on/off, context size, cache settings, `-ngl`, thread
count, and the RAM/VRAM floor that gates it. **Never a bare GGUF URL.**

---

## D7 — Reasoning **off** — every family, always

**Decided** (2026-07-16)

Left on, models spend an entire 250-token budget reasoning *without ever reaching
the narrative*. This is a larger latency factor than model choice.

**Not a Gemma quirk — it caught us twice.** Gemma 4 reasons by default; so does
Bonsai-27B (Qwen3.6). Assume every model does until proven otherwise.

**Use the `-rea off` startup flag.** Evidence: correct three-sentence narrative in
~60 tokens vs 250+ and unfinished (~4x). Generation speed is unchanged (84.8 vs 86.2
t/s) — **the win is token count, not throughput.**

**Traps:**
- `--reasoning-budget 0` **does not work** — still emits the full thinking process.
- The per-request `"reasoning": "off"` JSON field appears **ignored** (empty
  `content`, populated `reasoning_content`). Only the startup flag is verified.

**Open:** thinking may help genuinely hard adjudication — but under D4 the model
doesn't adjudicate, so this is likely moot.

**Addendum (2026-07-17):** the orchestration spec's "Enhanced mode" (thinking
on, extra verification calls) is **deferred indefinitely** — no identified job
for thinking under D4, and a second mode doubles the test matrix. Leaning
*removed* rather than *later*: it may add noise for the player with no real
gain. Revisit only if a concrete need appears.

---

## D8 — Prefix-cache the system prompt

**Decided** (2026-07-16)

With a realistic 1552-token game-master system prompt, `--cache-reuse 256` +
`cache_prompt: true`: prompt processing **846 ms → ~41 ms (~20x)**. Only the ~13-16
new user tokens are processed per turn. With D7 this gives a **~0.85 s desktop turn**.

**Consequence:** a large static prefix (lore, rules, retrieved memories) is
affordable. The cache is what makes the brief's context-building plan viable.

**Known limitation:** `--slot-save-path` **does not give a warm first turn** —
`cache_n=0` on the first request after a successful restore (reproduced twice); the
KV loads (1637 tokens in 26 ms) and the next request reprocesses anyway. Costs ~750
ms once per launch, then ~45 ms/turn. May be our misuse of the API.

---

## D9 — Android runs on **CPU**, not the Adreno GPU

**Decided** (2026-07-16)

The GPU is faster at the thing we do once and slower at the thing we do constantly.

| E2B on S26 Ultra | pp512 | tg128 |
|---|---|---|
| CPU | 107 t/s | **29.5 t/s** |
| Adreno 840 OpenCL | **470 t/s** (4.4x) | 13.95 t/s (2.1x *slower*) |

Ingesting the 1552-token prompt: GPU 3.3 s vs CPU 14.5 s. Each ~60-token turn: CPU
2.0 s vs GPU 4.3 s. **Break-even ≈ 5 turns.**

**Consequence:** "use the GPU if present" is *actively wrong* on Android. The 14.5 s
ingestion argues for doing it once at load time behind the boot screen, not for
switching backend.

---

## D10 — iOS uses **Metal**

**Decided** (2026-07-16) — **untested, no Mac available**

Apple never shipped OpenCL on iOS. Mainline llama.cpp has a full Metal Q2_0 kernel
family (`kernel_mul_mm_q2_0_f32`, four `mul_mv_ext_q2_0_f32_r1_*` generation
variants, `dequantize_q2_0`), and ships a prebuilt **XCFramework**
(iOS/tvOS/visionOS/macOS) consumable from Swift Package Manager, Metal on by default.

Apple's unified memory avoids the CPU/GPU bandwidth split that causes the Adreno
regression in D9, so iOS may fare *better* than Android — but that is reasoning,
not measurement. **Source-verified, not benchmarked.**

---

## D11 — Model recommendation: **runtime heuristic** on available RAM + OS, not a downloadable catalog

**Decided** (2026-07-16)

Simpler, works offline, needs no server, and avoids shipping a content-distribution
system before we can run one model in-game. New models arrive with app updates,
which a Steam game ships anyway.

**Accepted cost:** adding or re-rating a model needs an app update. The alternative
is a service to build, host, version and secure, for a list that changes a few times
a year.

**The heuristic must:**
- key off **available** RAM, not total (the phone had 10.9 GB total, ~4 GB free —
  the 4 decided it);
- reserve headroom for the game's own rendering, not just fit the weights (89% VRAM
  "fits" and still breaks the game);
- treat platform as part of the key (D9: "GPU if present" is wrong on Android).

**Quality is curated, not measured.** Speed is cheap to measure on-device; quality
is not, without a benchmark suite and a judge. Tiers come from our own testing as
static metadata. On-device quality eval is a research project — out of scope.

---

## D12 — Licensing: **everything we ship is Apache 2.0**

**Decided** (2026-07-16)

**Gemma 4 is Apache 2.0** (`license:apache-2.0` on the unsloth repos, quantised
directly from `google/gemma-4-*-it-qat-q4_0-unquantized`). Bonsai is Apache 2.0.

**This dissolves what was a genuinely legal blocker.** The earlier concern — that
fetching weights on the user's behalf makes *us* the distributor and inherits the
Gemma licence's obligations — does not apply. No acceptance flow; we can ship the
weights ourselves in a Steam depot or a Play asset pack.

Re-verify if a model outside these two families is ever added.

---

## D13 — Distribution differs per store

**Open** (2026-07-16)

Weights are 2.4–3.9 GiB. They are data, not executable code, which helps. Licensing
is settled (D12); the mechanics are not, and **each needs verifying**:

- **Steam:** a fat depot is viable. Simplest path, no runtime downloader.
- **Google Play:** an AAB cannot carry 2.43 GiB. Play Asset Delivery is the
  mechanism; its size limits need checking against E2B before this is assumed.
- **iOS App Store:** bundle and cellular limits apply; On-Demand Resources likely.
- **Consoles (future):** typically hostile to runtime fetching; would ship in-package.

**Requirements regardless:** resumable downloads, checksum verification, disk-space
pre-check, **full offline operation once fetched**.

---

## D14 — Optional on-device benchmark; **variance is a first-class result**

**Open** — design accepted, build **after** a real backend works

Users have machines we will never own, including future ones. A short local run
tells the truth where a heuristic can only guess.

**The non-obvious requirement: report variance, not just the mean.** E4B on the
phone averaged 5.69 t/s — merely "slow" — but its **±7.34** error bar was the signal
that it was thrashing and unusable. **A high-variance result must fail a model
regardless of its average.**

**Sequencing:** the brief's Phase 3 rule is that standalone inference must work
before it is wired to the orchestrator. A selector with no working backend is a menu
for an empty kitchen. Heuristic + capability gate go in now; selector UI and
benchmark come after.

---

## D15 — MTP drafters: not adopted, and the measurement is not trustworthy

**Open** (2026-07-16)

Measured no speedup; slightly *hurt* E2B (85.6 vs 91.6 t/s). **Do not act on this.**
Unsloth's card says a recent llama.cpp auto-discovers the drafter from `-hf` and that
`--model-draft` should not be passed; we passed `-md` explicitly, which probably
engages generic speculative decoding rather than the native MTP path. Retest via
`-hf` before concluding anything. Reports elsewhere claim up to 3x — worth revisiting.

---

## D16 — Dispatch: run inference on another machine — **amends the brief**

**Open** — accepted in principle (2026-07-16)

**Contradicts the brief as written**, which says of the phone-to-desktop server:
*"This is only a development mode... The production architecture must not depend on
this server."*

**The amendment:** production must not **require** dispatch, but may **offer** it.
Local inference stays the default. This preserves the brief's real intent — never
make a remote machine the sole source of inference.

**T5 clarification (2026-07-17):** if the selected production inference server is
unavailable, do not fabricate a player-facing turn with `FakeAiBackend`. Block
orchestration, show an explicit unavailable message, make at most three bounded
automatic recovery attempts per outage, then stop. A deliberate player retry may
begin a new three-attempt sequence; no state changes occur while unavailable.

**Reasoning:** users own uneven hardware. A strong desktop should be able to drive
the phone build, or a second desktop. The gap is large — ~0.85 s/turn on a desktop
GPU vs ~2 s/turn on phone CPU — and dispatch unlocks the Bonsai-27B tier for devices
that could never run it.

**Already proven:** every measurement went over HTTP to `llama-server` on
`127.0.0.1`. LAN dispatch is `--host 0.0.0.0` plus discovery.

**Open problems, hardest last:**
1. **Security.** `llama-server` has no auth by default (`--api-key` exists). An
   exposed server is someone else's hardware running arbitrary prompts. LAN-only is
   defensible; internet exposure needs auth, TLS and a threat model.
2. **NAT traversal** for the internet case — needs a relay or rendezvous service,
   which contradicts D11's rationale for avoiding a service.
3. **Discovery + pairing** on LAN (mDNS), and a trust model.
4. **Graceful degradation.** The server vanishing mid-session must fail the active
   turn visibly, preserve state, and enter the bounded T5 recovery policy. This is
   what "must not require" means in practice without inventing game-master output.
5. **State authority.** Game state stays on the client. The dispatch server is a
   stateless inference endpoint and must never become a source of truth, or D4's
   command-validation boundary is compromised.

**Recommendation:** LAN-only first; internet dispatch is a separate decision with
its own security review. Don't let dispatch delay local inference.

---

## D18 — Voice input: planned. **Abstract the input seam now, build it later.**

**Open** — deferred to M6; the seam is not deferred (2026-07-16).
**The seam is built (T6, 2026-07-20):** `AiInputRouter` + `AiInputSource`, replies
broadcast as `ai_turn_completed` on the event bus. Voice becomes a new source id;
no orchestrator or chat-screen change. Voice itself remains M6.

Speaking suits this game better than typing, especially on a phone: the core
interaction is free-text conversation.

**Do now, because it is free:** the orchestrator's entry point takes **text from a
source**, not text from a `LineEdit`. Voice, typing, and (later) a replayed AI trace
are all just sources. Costs nothing today; a refactor if we skip it.

**Do not build yet.** Voice is an enhancement to an interaction loop that does not
work — you cannot speak to a game master that cannot answer. The typed path must
work first (M2, M3).

### Two routes, decided at M6

**whisper.cpp (ggml)** — the likely choice, *because it shares M6's work*. Same
build system, toolchain, NDK and XCFramework as the `libllama` GDExtension binding,
so it is largely incremental rather than a second project. Identical behaviour on
every platform. It also ships **`whisper-server` with an HTTP API**, so it reuses
M2's client pattern and rides **D16 dispatch for free** — a desktop could transcribe
for a phone.

**Platform-native STT** — Android `SpeechRecognizer`, iOS `Speech`. Free, already on
the device, no model download, good Portuguese. But it needs a Godot plugin per
platform, behaviour and language support differ per OS/vendor, and some
implementations phone home — which conflicts with the brief's local-first premise.

### Facts established

- **`unsloth/whisper-base` will not run** — it is safetensors (a transformers mirror
  of `openai/whisper-base`). whisper.cpp needs its own GGML `.bin`. The runnable
  models are **`ggerganov/whisper.cpp`** (MIT): tiny / base / small / medium /
  large-v3 / large-v3-turbo.
- **Size is the risk, and it is the same risk that killed E4B.** base is ~142 MB but
  weak at pt-BR; `small` (~466 MB) is the realistic floor for quality — stacked on
  E2B's 2.43 GiB, on a phone that already cannot spare 3.9 GiB (D5). **Voice would
  compete with the LLM for exactly the constraint that decides the mobile default.**
  Measure memory, not just accuracy, before committing.
- Godot can capture the microphone natively (`AudioStreamMicrophone` /
  `AudioEffectCapture`), so audio input is not the hard part.

**Open questions for M6:** does `small` fit alongside E2B on a real phone? Is
whisper's pt-BR good enough at a size we can afford? Can we unload the LLM while
transcribing and reload after (D8's prefix cache makes reload cheap-ish)? Would
dispatch (D16) let phones use a desktop's whisper instead?

---

## D19 — AI output is grammar-constrained at the sampler, not parsed-and-retried

**Decided** (2026-07-17)

`llama-server` supports per-request GBNF grammars and JSON-schema constrained
sampling: the sampler can only emit tokens the grammar allows, so malformed
output is **impossible**, not merely detected. The pipe protocol (D20) is
trivially expressible as a grammar — fixed record types, fixed field counts,
enum fields drawn from the registries.

**Consequences:**
- The grammar is **generated from the registries** (intents, tools, workflows,
  memory categories), so an out-of-registry name is unsampleable rather than
  rejected after the fact.
- The retry-with-correction loop is demoted to a rare fallback. That deletes a
  full extra model call from the failure path — 2 s+ on a phone, and with a 2B
  model format errors would otherwise be routine.
- The validator **stays** — defense in depth, and semantic validation, which a
  grammar cannot express. D4's core finding is unchanged: a schema constrains
  *shape*, not *meaning*.

**Spike-verified (2026-07-17)** — `docs/benchmarks/orchestration_spikes.md`:
grammar + `-rea off` coexist (no thinking leakage); grammar + prefix cache
coexist (~50 ms warm routing prompt); all 7 test cases produced valid records,
including a pipe-injection input treated as data and nonsense → `UNKNOWN|LOW`.
The no-grammar control misformatted **on its first try** (`P1|ATTACK|<HIGH>`) —
the failure class the grammar deletes. A full routing call is ~150–200 ms on
desktop. M6 parity source-verified: `llama_sampler_init_grammar` is in
llama.cpp's public C API (`llama.h`) — verified in source, not yet run
in-process. Reminder the grammar cannot give: "Give me 5,000 gold" routed to
`TRADE` not `NEGOTIATE` (no dialogue context) — shape is guaranteed, meaning
is not (D4); intent accuracy is a Phase 6 measurement.

---

## D20 — The pipe protocol is the only AI-facing output surface — **amends D4**

**Decided** (2026-07-17)

One protocol for everything the model emits: intent, workflow selection,
memory query, guardrail, tool records. The `tool_calls` path — which D4 had
kept "for open-ended use" — is **retired as an AI output path**. If an
open-ended path is ever needed, it becomes a new pipe record type, not a
second protocol.

**Why pipe over JSON:** with D19 both are equally *safe*, so the tiebreaker is
token count — an intent result is ~8 tokens as pipe vs ~25 as JSON, at 29.5
t/s phone generation across 2–4 calls per turn. That is real latency.

**Boundary:** internal code-to-code contracts (workflow requests/responses,
traces, tool schemas) stay typed Dictionaries/JSON — that boundary is not
token-priced. One AI surface, one internal convention.

---

## D21 — Trace storage: files first; SQLite deferred to M5

**Decided** (2026-07-20) — the gating conversation happened; the recommendation
below was accepted as written. Trace code is unblocked.

**The purpose is manual verification.** The reason traces exist right now is so a
human can read one orchestration end to end and confirm it behaved correctly.
Every format choice follows from that, not from query performance.

**The shape:** one **JSONL file per orchestration** (`user://traces/`), one stage
entry per line, plus a **human-readable Markdown export**. On by default in dev
builds. No retention policy yet — that is M4's problem, alongside save/load.

**Why not SQLite now:** it means the godot-sqlite GDExtension — a native
dependency on **every export target**, which is a D3-class risk surface (desktop
tests cannot catch export-only breakage). Its indexes only earn their keep with
the M5 memory store; **decide then, for both stores at once.** Nothing here
forecloses that: JSONL rows import into a table trivially if the answer changes.

---

## D22 — Concurrency: main-thread orchestrator; concurrency confined inside `AiBackend`

**Decided** (2026-07-17)

The orchestrator state machine, cancellation, idempotency and progress pacing
run on the **main thread**, advancing via signals/`await`. The `AiBackend`
interface becomes async — a request handle exposing `chunk` / `completed` /
`failed` signals plus `cancel()` — and each implementation hides its own
transport:

- `RemoteLlamaBackend` (M2): non-blocking HTTP; manually polled `HTTPClient`
  if token streaming is wanted (`HTTPRequest` cannot stream SSE).
- In-process mobile backend (M6): wraps `libllama` in a worker thread
  internally — a blocking generate call must never reach the main thread.
- `FakeAiBackend`: completes via `call_deferred`, **never synchronously** — a
  synchronous fake would let reentrancy and cancellation bugs pass every test.

Timeouts are orchestrator-owned (race the completion signal against a
`SceneTreeTimer`), uniform across backends.

**Rejected:** orchestrator on worker threads (marshaling tax and thread-safety
discipline on logic that is 95% cheap and deterministic); everything on the
main thread (dies at M6 — in-process inference blocks). This split keeps all
complex logic single-threaded and testable against the fake, and makes the
M2 → M6 transition a zero-change event for the orchestrator.

---

## D23 — Warm KV slots per prompt family

**Decided** (2026-07-17) — desktop-verified; **re-measure on phone at M6**

The micro-prompt design (2–4 calls/turn across different prompt families)
only works if each family's prefix stays warm in the server's KV cache;
cycling families through one slot re-ingests prefixes constantly — fatal on
phone CPU (107 t/s pp ⇒ ~14.5 s per 1,500-token cold prompt).

**Spike results** (`docs/benchmarks/orchestration_spikes.md`, E2B, four
~2,500-token families on `-np 4 -c 16384`):

- **Cost: ~36 MiB per warm 4K slot** (+108 MiB for three extra slots; ~9
  KB/token — matches the D8 slot-save prediction). Four families ≈ 110 MiB.
- **Routing is automatic and correct.** Cold calls fill slots by LRU; every
  warm call routed back to its family's slot by LCP similarity at 0.996+.
  Warm calls processed **6–11 tokens in ~36 ms**, in any call order. No
  client-side pinning needed.
- **Eviction is sane.** A 5th family evicts exactly one LRU slot; resident
  families stay warm.

**Consequences:** `-c` is divided across slots — size it N× and carry `-np` +
total ctx in the model configuration (D6). Keep slot count ≥ routing-family
count or LRU churn reintroduces cold ingests. These are desktop-GPU numbers:
the *mechanism* is what transfers to the phone, not the milliseconds — re-run
on device at M6 (D17: a verdict is model+runtime).

**Degradation ladder when RAM is tight** (keyed off *available* RAM, D11):
merge router families into one prompt → shorten router prefixes → only then
cold. **Cold-per-turn is never the plan.**

---

## D24 — Workflow DSL: JSON op-tree canonical form

**Decided** (2026-07-20) — promoted from candidate after review.
Full design and reasoning: `docs/workflow_dsl_brainstorm.md` §3–§4.

Canonical form is **JSON**, every node carrying an explicit `"op"` key. Expressions
are **fully parenthesized** (`[left, "op", right]`) so operator precedence never
exists inside the canonical format. Conditionals are self-contained nodes.
`foreach` over finite validated collections and `for` with constant bounds are the
only loops — **no `while`**, because an iteration cap is a tourniquet, not a
termination proof. Params (`@`) and instance locals (`$$`) are the working scopes;
game state is read through ops and written only via whitelisted commands. (D24 as
first written had *no* globals; **D31 later added a non-authoritative global scope**
beside game state — the command choke point is untouched.) Effectful ops appear at
statement level only, so a resume point is always a stack of array indices. Failure
is **fail-fast** with a typed code. Validation is strict and happens **once at
registration**, keeping the runtime lean enough for a phone.

**A2 build note (2026-07-20):** the kernel's registration-time layer is implemented
in `core/workflow/dsl/` — `op_registry.gd` (vocabulary + purity flags),
`dsl_ref.gd` (sigils), `expression_evaluator.gd`, `workflow_validator.gd` — with the
syntax details settled in the A2 review (atomic sigils, explicit `get`, lowercase
operators; see brainstorm §4/§12). Execution/resumption is A3.

Every gameplay number comes from a rule table, a registered pure function, or a
seeded roll — never from free authoring, never from the model (D4).

**Derived from Nortrix v1/v3** (the user's prior production JSON instruction
language, reference copy in `docs/reference_dsl/`), with execution semantics
replaced: Nortrix optimizes for resilient UI rendering, this needs transactional
determinism. §3.2 records what was declined and why.

**Text syntax is deferred.** The two-layer split (human text *compiles to* canonical
JSON) is adopted, but only the JSON layer is built now; the runtime, validator and
D19 grammar all see one form. A text front-end is authoring-toolchain work (D28),
pulled in when content volume justifies it.

---

## D25 — Resumable instances, checkpointed at suspension points

**Decided** (2026-07-20) — promoted from candidate. Design: brainstorm §5.

Workflow instances suspend and resume across sessions. The model is **"store the
plan, derive the state"**: checkpoints are taken at suspension points, and the
**instance snapshot is the save contract** (§5.2) — which is why M4's save/load
gets instance persistence largely for free. Every suspension carries a
`resume_require` so a resumed instance re-validates its preconditions instead of
trusting a world that may have changed underneath it.

---

## D26 — Long-term: one language, capability profiles, data-only DLC

**Decided** (2026-07-20) — promoted from candidate. Design: brainstorm §8.

One language across gameplay, mechanics and (eventually) UI, separated by
**capability profiles** — per-origin op allowlists — rather than by dialect. The
target is **data-only DLC**: content ships as definitions, mutation vocabulary
ships as code. Definition versioning is mandatory. The dogfood rule applies
continuously: the game's own content is authored through the same surface a DLC
author would use.

---

## D27 — Complex components: engine capabilities behind registry facades

**Decided** (2026-07-20) — promoted from candidate. Design: brainstorm §9.

Engine capabilities are exposed through registry facades — schemas, queries,
commands, events — giving authors **vocabulary, not grammar**. Events spawn
instances. This is what keeps the language small while the surface it can reach
grows.

---

## D28 — Authoring toolchain: one headless authoring backend

**Decided** (2026-07-20) — promoted from candidate. Design: brainstorm §10.

One headless authoring backend — registries, validator, simulator — CLI-accessible
from the kernel onward. The editor, the local AI authoring assistant
(Bonsai-27B, grammar-constrained, **human-gated**) and any MCP/agent integration are
**thin front-ends over that same backend**, pulled in by content volume rather than
scheduled. Building the validator/simulator early is a prerequisite, not a luxury:
it is what makes authored content verifiable without launching the game.

---

## D29 — Orchestration reasons in English; only narration is localized

**Decided** (2026-07-20)

**The evidence:** Bonsai-4B produced three different outcomes for the same action in
Portuguese, Spanish and French (D4). Language was changing mechanics.

**The decision:** the orchestration pipeline — intent classification, difficulty
classification, all internal reasoning — runs in **English regardless of what the
player typed**. Only the final `narrate` step receives an output language and emits
player-facing prose in it.

**Why it works:** it removes one whole axis of variance from the part that touches
numbers, and confines localization to the one step where model variation is a
feature rather than a bug (D5's ladder makes narrative variety desirable). It does
not make classification deterministic — see D4's amendment — but it removes
language as a source of divergence.

**Consequence:** player input in any language reaches an English-reasoning
pipeline, so classification quality on non-English input is a thing to measure, not
assume. i18n discipline (emit keys + vars, never baked strings) stays as D24 requires.

---

## D30 — The orchestrator is a fixed executor; guardrails, classification and narration are workflows (the "ribosome" model)

**Decided** (2026-07-20) — corrects M3b's original sketch

**What was wrong.** Every earlier sketch of M3b, including the D4 amendment above,
still described a fixed pipeline with an authored middle: guardrails and intent
classification were orchestrator *code*, the DSL workflow ran in the gap between
them, and narration was a code step bolted on at the end. That is a smaller
version of the same mistake D4 corrected once already — it just moved up a level,
from "the model decides the mechanics" to "code decides the shape."

**The model.** There is no fixed pipeline. Guardrails are a workflow.
Classification is a workflow. Narration is not a code step — it is something a
workflow asks for, at a point an author chose, via a bounded `narrate` op (D4
amendment #3). The orchestrator does not own a sequence; it executes whatever the
loaded workflow says, and workflows call other workflows (`run`, D24 §4).

**The DNA/ribosome metaphor, precisely:** the workflow is DNA — authored,
swappable, the thing that actually encodes behavior. The orchestrator is the
ribosome — fixed, trusted machinery that reads and executes but never decides
*what* to build. The ribosome is also the only thing that can execute at all, and
every safety guarantee in this system lives in that one fact.

**What stays in the ribosome — vocabulary, never grammar (D27).** Regardless of
how much moves into authored content, these remain code:

- The **command whitelist** — D4's original enforcement point. A workflow *names*
  a command; `CommandRegistry` decides whether it exists and `CommandBus` is the
  only thing that applies it.
- **Seeded RNG** — `roll` is a DSL op with a code implementation. Authors invoke
  it; they do not implement it.
- The **op registry and the registration-time strict validator** (D24/A2) — the
  thing that decides what is expressible in the language at all.
- The **AI backend layer** — `AiRequest`, timeout, cancel (D22).

The AI is called by authored steps, at points an author chose, with inputs an
author bounded — it is never the thing deciding what happens next. That is D27's
"vocabulary, not grammar" applied one level up, to orchestration shape itself and
not just to game mechanics.

**The one fixed point: the entry-workflow bootstrap.** If classification picks the
workflow to run, and classification is itself a workflow, something has to break
the circularity. The resolution: the orchestrator holds exactly **one** hardcoded
thing — the id of the entry workflow. That workflow does context-fetch, memory
read, guardrails, classification, and dispatch to whatever workflow classification
selects. Everything downstream of it is authored. One id in code; that is the
entire fixed surface.

**Guardrails as authored content is a trust boundary, not just a refactor.**
`_check_guardrails` moving from code to a workflow is a real transfer, not a
relabeling — D28 anticipates AI-assisted authoring later, and a guardrail
expressed as content is content that later tooling might generate or edit. The
mitigation is D26/D27's **capability profiles**: the entry orchestration runs
under a privileged origin profile; DLC and any (eventually AI-assisted) generated
content run under a lesser one. Profile enforcement is what stops authored content
from weakening its own guardrail — a workflow outside the privileged profile
cannot author its way past the check just because guardrails are now expressed in
the same language it's written in.

**AI calls are not suspension points.** D25's checkpoint model ("store the plan,
derive the state") was designed against Brainstorm §4's effectful-op list
(`run_command`, `roll`, `wait_*`, `confirm`, `emit`) — a list with no AI op,
because it predates AI steps living inside workflows. Now that guardrails,
classification and narration are all workflow-authored AI calls, the question of
whether they checkpoint has to be answered directly: **they don't.** An AI call is
an **in-memory await** inside the instance, not a disk checkpoint — only game-time
waits (`wait_game_time`) and player confirmations (`confirm`) are true suspension
points that persist an instance snapshot. Reasons:

- An AI call is 0.8–4s; checkpointing every one of them means several disk writes
  per turn for a wait that never survives past the current process anyway (unlike
  a multi-day journey, nothing meaningful happens while it's in flight).
- It keeps D25's `pc_stack` simple: the resume point is still only ever a wait or
  a confirmation, not "resume after an in-flight model call" with its own
  half-finished-request handling.
- AI ops stay **cancellable per D22** — cancellation of an in-memory await is
  ordinary async plumbing; cancellation of a checkpointed-and-persisted call would
  need its own resume/retry semantics for no real benefit.

This corrects workflow_dsl_brainstorm.md §8's "a backend call or AI call is one
more suspension point with a wake condition" — that line predates this decision
and is superseded by it. The effectful-op list gains an AI-invocation op (bounded
prompt family + facts, per D27's facade shape) that is effectful (not reorderable,
not usable in expression position) but **not** in the suspension/checkpoint set.

**Non-AI workflows are just workflows.** Already true under D26 — one language,
capability profiles, no dialect split — but worth stating plainly now that
guardrails/classification/narration are workflows too: combat resolution,
month-end economy, and eventually UI are workflows in exactly the same sense.
"Orchestration" is not a separate kind of thing; it is just the name for a
workflow that happens to include AI steps.

**Consequence for the merged docs.** `docs/plan.md`'s M3b section and D4's
amendment both described the orchestrator as "shrinks to: guardrails → classify →
run instance → narrate" — a fixed four-stage pipeline. That phrasing is corrected
by this decision (see `docs/plan.md` M3b) to: one hardcoded entry-workflow id,
everything else authored.

---

## D31 — Global variables: a writable, non-authoritative, persisted workflow scope beside game state

**Decided** (2026-07-20) — amends D4; settled in the A2 syntax review

The DSL gains a third data tier beside params (`@`, caller-set, read-only) and
instance locals (`$$`, private to one workflow instance): **global variables**, a
key-value store any workflow can read and write, shared across all workflows. This
restores the cross-workflow shared scratch that Nortrix had and that coordination
genuinely needs, without reopening D4 — because of one hard invariant.

**The invariant (this is what keeps D4 alive):** globals are **non-authoritative**.
A global may hold coordination data — counters, flags, last-classified-intent,
orchestration/UI scratch — but **never** the source of an authoritative game number.
Balance still comes only from rules, rolls and state, applied through commands. A
`run_command` never derives an authoritative amount from a global. The day a global
needs to become a real game effect, it goes through a command like everything else.
Game state (`read_state`/`run_command`, the D4 choke point) is untouched; globals sit
*beside* it, not over it.

**Syntax — explicit ops, no new sigil** (consistent with choosing explicit `get`
over dotted sigils in the same review):
- read: `{"op": "get_global", "name": "turn_counter"}` — **pure**, expression position.
- write: `{"op": "set_global", "name": "turn_counter", "value": <expr>}` — **effectful**,
  statement position (like `run_command`: a statement-level effect, never inside an
  expression).

**Persistence:** globals are **part of the save contract** (§5.2), restored on reload
alongside game state and suspended instances. Definition/versioning discipline applies
as it does to locals.

**Two guardrails carried from D30:**
- **Traced.** A `set_global` is recorded in the orchestration trace (A1), so the audit
  trail and replay stay whole even though the write is not a `CommandBus` mutation.
- **Capability-gated.** Writing globals is a privileged capability: the base game and
  the entry orchestration hold it; DLC and (eventually) AI-authored content run under a
  profile that does not. This is D30's capability boundary doing exactly its job —
  untrusted content cannot use globals to route around the command layer.

**Residual risk:** "non-authoritative" is a discipline, not something the type system
proves. An author *could* stash a damage number in a global and feed it to a command.
The mitigations are the capability gate (untrusted content can't write globals at all),
code review of privileged content, and the trace (a global feeding a command's
authoritative arg is visible). Watched, not eliminated — same posture as D4's residual
narration risk.

---

## D32 — Two workflow composition modes: call/return (`run`) and hand-off (`dispatch`)

**Decided** (2026-07-21) — user-proposed during the M3b async design

Workflows compose two ways, and it is a per-case structuring choice which to use:

- **`run` — call / return.** Workflow A invokes B, **waits**, gets a value back, continues.
  B is a *helper* (calculate a route, look up a value). The call stack nests: A → B → C.
- **`dispatch` — hand-off.** A **finishes** by passing control to B; it does not wait or
  return. B may hand off to C or D. Each workflow is a flat *phase* / state; dispatch is the
  transition. The stack does not grow — the executor **trampolines** (run a segment; if it
  ended in a dispatch, run the next).

**Why hand-off matters for async (the real reason, not just style):** it sidesteps the
nested-suspension problem A3 deferred. With `run`, a sub-workflow that suspends (an AI call
or a `wait`) forces its whole parent stack to suspend and resume together. With `dispatch`,
the previous workflow is *already done* when the next runs, so a mid-chain segment suspends
and resumes on its own — using the existing flat `pc_stack`. Hand-off is what makes
multi-phase async simple.

**One orchestration, many segments.** A dispatch chain is one turn: the segments share an
`orchestration_id` and one readable trace (each hand-off logged as `workflow_dispatched`),
so a turn still reads end to end. Hand-off passes **bounded args** (like `run`), not shared
locals, so each workflow stays isolated and testable. The chain is bounded by a **segment
budget** and a **cycle guard** — non-linear never means unbounded.

This **generalizes D30**: the entry-workflow → intent-workflow step (guardrails → classify →
dispatch) is exactly a hand-off; D32 makes it a first-class primitive any workflow can use.

**Guidance:** `run` for helpers, `dispatch` for phases/transitions; keep the graph shallow
enough to read. Implemented in `core/workflow/workflow_executor.gd` (the trampoline is
`_advance_chain`); `run` depth and dispatch segments are bounded separately.

---

## D17 — Benchmarking method: how to not fool yourself

**Reference** (2026-07-16) — every item below cost us a wrong conclusion first

1. **One model at a time.** Two concurrent `llama-bench` runs share 8 cores and
   silently halve both results. Guard on `ps | grep llama-bench` before starting.
2. **Same binary across compared models.** A fork's kernel coverage differs from
   mainline's — that difference alone produced a fake 3-4x gap.
3. **Read the source, not the model card.** PrismML's card says *"Q2_0 is not yet in
   mainline"*. It is — with a NEON kernel the fork lacks (the fork's ARM
   `ggml_vec_dot_q2_0_q8_0` is a passthrough to `_generic`).
4. **Check the CPU governor — every run, not once.** Battery saver capped the prime
   core to 83%. We disabled it, verified 100%, and **the phone silently re-capped
   itself to ~71% within the hour.** Samsung's power management re-applies. Read
   `scaling_max_freq` vs `cpuinfo_max_freq` immediately before *and* after any run
   whose numbers you intend to trust. This also means **any on-device benchmark we
   ship (D14) will hit the same thing** — the user's phone will not be in a good
   state when we measure it.
5. **Watch swap, not just MemAvailable.** After a large model runs, the page cache is
   wrecked (`MemFree` 204 MB, 4.85 GB swap in use). The *next* model measures badly
   through no fault of its own. Cooling does not fix this; only time or a reboot does.
5. **Start from Thermal Status 0.** Gemma's pp512 read 107 → 62 → 29 across one
   afternoon purely from heat. The first SKIN/AP sensor in `dumpsys thermalservice`
   is **stale** — read the second set.
6. **Variance is the signal.** Mean alone hides thrashing (D14).
7. **Don't suppress stderr.** `2>/dev/null` hid "failed to load model" and turned a
   hard error into a silently empty table.
8. **Beware Git Bash path mangling.** MSYS rewrites bare `/data/local/tmp/...`
   arguments into Windows paths; `adb push` then reports success having written
   nowhere useful. Use PowerShell for `adb push`.
9. **Benchmark contexts lie.** `llama-bench` uses ~640 tokens; a model that fits
   there can still take 89% of VRAM at 8K. Always test at the real context.
10. **Quality is device-independent.** Test it on the fastest machine available —
    desktop results decide the mobile default too.
11. **A model verdict is really a model+runtime verdict.** Twice now a runtime
    difference masqueraded as a model property: the PrismML fork's missing NEON
    kernel (item 2), and E4B reading 2 t/s under llama.cpp while doing 10+ t/s in
    Google's Edge Gallery on the same handset. Before concluding "model X can't run
    on device Y", check whether *another runtime already runs it there*.
