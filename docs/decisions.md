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
- The `tool_calls` path is not deleted — it stays for open-ended use where no
  balance is at stake. **No game rule may depend on it.**
- Cost: less emergent AI-driven mechanics than the brief imagined. Worth it.

**Residual risk:** narration can still misdescribe a correct outcome, and memory
read/write is not risk-free. Smaller surface, not zero — to be remediated in the
orchestration design.

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
Local inference stays the default and the fallback. This preserves the brief's real
intent — never ship a game that is broken without a server.

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
4. **Graceful degradation.** The server vanishing mid-session must fall back to
   local, not break the game. This is what "must not require" means in practice.
5. **State authority.** Game state stays on the client. The dispatch server is a
   stateless inference endpoint and must never become a source of truth, or D4's
   command-validation boundary is compromised.

**Recommendation:** LAN-only first; internet dispatch is a separate decision with
its own security review. Don't let dispatch delay local inference.

---

## D18 — Voice input: planned. **Abstract the input seam now, build it later.**

**Open** — deferred to M6; the seam is not deferred (2026-07-16)

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
