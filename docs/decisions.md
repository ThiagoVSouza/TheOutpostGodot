# The Outpost — Decisions

Why things are the way they are. Each entry records the decision, the reasoning,
and the evidence behind it — so a future reader can tell a measured conclusion
from a guess, and knows what would justify revisiting it.

Status values: **Decided** · **Open** · **Superseded**

Measurements referenced here live in `docs/benchmarks/milestone1_results.md`.
Architecture context: `docs/initial_briefing.md`.

---

## D1 — Test runner: GUT, not a custom headless runner

**Status:** Decided (2026-07-15)

Chosen over building one from scratch for maturity and lower maintenance. The
brief left the runner unspecified; picking early unblocked the test harness.

---

## D2 — Module manifests: `.tres` resources, not JSON

**Status:** Decided (2026-07-15)

Manifests are only ever authored and read inside Godot, so we take the editor
inspectability and built-in type validation. No external tooling needs to generate
them.

**Consequence discovered later:** `.tres` files are rewritten to `.tres.remap` on
export, which broke filename-based module discovery (see D3). The format is still
right; the scanning code had to learn about remaps.

---

## D3 — Module discovery matches the logical resource name, not the shipped filename

**Status:** Decided (2026-07-16)

**Reasoning:** Godot converts text resources to binary on export, so
`base_game.tres` ships as `base_game.tres.remap`. Discovery matched
`ends_with(".tres")` against the *shipped* name, found nothing, and the app booted
to a blank screen with "0 module(s) loaded". `load()` was never the problem — it
resolves remaps — only the filename scan was.

**Evidence:** Reproduced on a physical S26 Ultra; invisible on desktop and in all
27 tests. Fixed and verified on-device.

**Consequence:** Any code that *scans* the resource filesystem must strip `.remap`
and accept `.res`. Desktop tests cannot catch this class of bug — only a real
export can. This is the standing argument for keeping device deploys in the loop.

---

## D4 — Default model: Gemma 4 **E2B** `it-qat` UD-Q4_K_XL, CPU-only, all platforms

**Status:** Decided (2026-07-16)

**Reasoning:** A game turn is generation-dominated, and E2B is the only option
that is fast *and* stable on the weakest target we actually tested.

**Evidence:**

| | Desktop GPU | Phone CPU |
|---|---|---|
| E2B | 103.4 ± 10.2 t/s | **29.5 ± 0.16 t/s** |
| E4B | 57.6 ± 5.3 t/s | 5.69 ± **7.34** t/s |

**Consequence:** CPU-only keeps behaviour predictable across wildly different
devices and sidesteps the Android GPU trade in D7.

---

## D5 — E4B is an **opt-in** user setting, gated by a device check

**Status:** Decided (2026-07-16)

**Reasoning:** E4B is fine on desktop and unusable on a phone like the S26 Ultra.
That is a user choice on capable hardware, not a default.

**Evidence and the important nuance:** E4B's phone failure was **memory pressure,
not compute** — 5.69 t/s with a ±7.34 error bar, *variance exceeding the mean*,
i.e. thrashing a 3.91 GiB model against ~4 GB of available RAM. E2B's ±0.16 on the
same device is rock steady.

**Consequence:** The gate must compare model size against **available** RAM with
headroom, not total RAM (the phone had 10.9 GB total and ~4 GB free — the 4
decided it). The UI must present E4B as a trade — better writing, ~half the speed,
needs a strong device — not a free upgrade.

---

## D6 — Gemma 4 **12B** is a desktop-only opt-in; not a dev default

**Status:** Decided (2026-07-16)

**Reasoning:** It runs on 8 GB, but it crowds out the game.

**Evidence:** 12B UD-Q4_K_XL (6.24 GiB) at 8K context, fully offloaded on an RTX
4070 Laptop: **7281 / 8188 MiB VRAM (89%)**, warm turn ~4.05 s, ~24-25 t/s.
llama.cpp's own auto-fit tried to reduce the layer count and only proceeded
because `-ngl 99` forced it.

The quality gap is real and worth the entry existing at all: given the same
system prompt, 12B used the Legate's name (*Vettius Calla*) and hit the style
guide's concrete-detail rule; E2B never used the named character.

**Consequence:** ~900 MiB left for rendering is survivable for today's chat screen
and not for the map that milestone 2+ adds. The brief is explicit that inference
must leave GPU capacity for the game. Suitable for users with **12 GB+ VRAM**.

---

## D7 — Android runs on **CPU**, not the Adreno GPU

**Status:** Decided (2026-07-16)

**Reasoning:** The GPU is faster at the thing we do once and slower at the thing
we do constantly.

**Evidence:** E2B on S26 Ultra, Adreno 840 via OpenCL vs CPU:

| | pp512 | tg128 |
|---|---|---|
| CPU | 107 t/s | **29.5 t/s** |
| Adreno OpenCL | **470 t/s** (4.4x) | 13.95 t/s (2.1x *slower*) |

Ingesting the 1552-token system prompt: GPU 3.3 s vs CPU 14.5 s. Each ~60-token
turn: CPU 2.0 s vs GPU 4.3 s. **Break-even ≈ 5 turns**; a session is many turns.

**Consequence:** "Use the GPU if present" is *actively wrong* on Android. The 14.5 s
ingestion is an argument for doing it once at load time behind the boot screen, not
for switching backend.

**What would change this:** the OpenCL build warns it lacks optimised kernels for
several quant types, so 13.95 t/s is likely not Adreno's ceiling. Untested:
partial offload (`-ngl` 1..98), Vulkan, Hexagon NPU.

---

## D8 — iOS will use **Metal**; OpenCL is not an option there

**Status:** Decided (2026-07-16) — **untested** (no Mac available)

Apple never shipped OpenCL on iOS. llama.cpp provides a prebuilt **XCFramework**
(iOS/tvOS/visionOS/macOS) consumable from Swift Package Manager, Metal on by
default. Apple's unified memory avoids the CPU/GPU bandwidth split that causes the
Adreno generation regression in D7, so iOS may behave *better* than Android — but
this is reasoning, not measurement.

---

## D9 — Reasoning **off** by default, via the `-rea off` startup flag

**Status:** Decided (2026-07-16)

**Reasoning:** Gemma 4 thinks by default, and left on it will spend an entire
250-token budget reasoning *without ever reaching the narrative*. This is a larger
latency factor than model choice.

**Evidence:** `-rea off` → correct three-sentence narrative in ~60 tokens (~4x
turn-latency cut). Generation speed is unchanged (84.8 vs 86.2 t/s) — **the win is
token count, not throughput**.

**Traps found:**
- `--reasoning-budget 0` **does not work** — still emits the full thinking process.
- The per-request `"reasoning": "off"` JSON body field appears to be **ignored**
  (empty `content`, populated `reasoning_content`). Only the startup flag is verified.

**Open:** thinking may be genuinely useful for hard adjudication (rules, contested
outcomes) even if it is wrong for narration. Revisit as a per-intent setting rather
than a global once the orchestrator classifies intent.

---

## D10 — Prefix-cache the system prompt

**Status:** Decided (2026-07-16)

**Evidence:** With a realistic 1552-token game-master system prompt and
`--cache-reuse 256` + `cache_prompt: true`: prompt processing **846 ms → ~41 ms
(~20x)**. Only the ~13-16 new user tokens are processed per turn. Combined with D9
this gives a **~0.85 s desktop game turn**.

**Consequence:** A large static prefix (lore, rules, retrieved memories) is
affordable — the cache is what makes the brief's context-building plan viable.

**Known limitation:** `--slot-save-path` **does not give a warm first turn**.
`cache_n=0` on the first request after a successful restore, reproduced twice; the
KV loads (1637 tokens in 26 ms) but the next request reprocesses anyway. Player
pays ~750 ms once per launch, then ~45 ms/turn. May be our misuse of the API —
worth revisiting or reporting upstream if first-turn latency ever matters.

---

## D11 — MTP drafters: **not adopted**, and the measurement is not trustworthy

**Status:** Open (2026-07-16)

Measured no speedup; slightly *hurt* E2B (85.6 vs 91.6 t/s). **Do not act on
this** — it is most likely our error: Unsloth's card says a recent llama.cpp
auto-discovers the drafter from `-hf` and that `--model-draft` should not be
passed; we passed `-md` explicitly, which probably engages generic speculative
decoding rather than the native MTP path. Retest via the `-hf` form before
concluding anything.

---

## D12 — Model recommendation: **runtime heuristic** on available RAM + OS, not a downloadable catalog

**Status:** Decided (2026-07-16)

**Reasoning:** A curated set of recommendations derived from available RAM and
platform is simpler, works offline, needs no server, and avoids shipping a
content-distribution system before we can run a single model in-game. New models
arrive with app updates, which a Steam game ships anyway.

**Consequence / accepted cost:** adding or re-rating a model requires an app
update. Accepted — the alternative (a remote catalog) is a service to build, host,
version and secure, for a list that changes a few times a year.

**The heuristic must, per D5 and D6:**
- key off **available** RAM, not total;
- reserve headroom for the game's own rendering, not just fit the weights (D6's
  89% VRAM "fits" and still breaks the game);
- treat platform as part of the key (D7: the right backend differs per OS, and
  "GPU if present" is wrong on Android).

**Quality is curated, not measured.** Speed is cheap to measure on-device; quality
is not, without a benchmark suite and a judge. Quality tiers come from our own
testing (e.g. D6's named-character observation) as static metadata. An on-device
quality eval is a research project and is out of scope.

---

## D13 — Optional on-device benchmark, and **variance is a first-class result**

**Status:** Open — design accepted, build **after** a real backend works

**Reasoning:** Users have machines we will never own, including future ones. A
short local run (the `llama-bench` pattern we already use) tells the truth where a
heuristic can only guess.

**The non-obvious requirement:** report **variance, not just mean**. E4B on the
phone averaged 5.69 t/s — merely "slow" — but its ±7.34 error bar was the actual
signal that it was thrashing and unusable. A high-variance result must fail a model
regardless of its average.

**Sequencing:** the brief's Phase 3 rule is that standalone inference must work
before it is wired to the orchestrator. A model selector with no working backend is
a menu for an empty kitchen. Catalog/heuristic + capability gate go into the
architecture now (the brief already requires model assignment to stay
configurable); the selector UI and benchmark come after.

---

## D14 — A model is a **configuration**, not a file

**Status:** Decided (2026-07-16)

**Reasoning:** The settings around the model matter more than the model. D9
(reasoning off) is worth ~4x and D10 (prefix cache) ~20x on prompt — both larger
than the E2B→E4B gap. And the correct backend is per-platform and counter-intuitive
(D7).

**Consequence:** a model entry carries, per platform: weights + quant, backend
(CPU / OpenCL / Metal / CUDA), reasoning on/off, context size, cache settings,
`-ngl`, thread count, and the RAM/VRAM floor that gates it. Never a bare GGUF URL.

---

## D15 — Model distribution differs per store; **open**

**Status:** Open (2026-07-16)

Weights are 2.4-6.2 GiB. They are data, not executable code, which helps — but
each platform constrains the answer differently and **each needs verifying before
committing**:

- **Steam (Windows/macOS):** a fat depot is viable; Steam is built for large
  content. Simplest path, no runtime downloader.
- **Google Play:** an APK/AAB cannot carry a 2.4 GiB model. Play Asset Delivery
  (install-time / fast-follow / on-demand) is the mechanism, and its size limits
  need checking against E2B's 2.43 GiB before this is assumed to work.
- **iOS App Store:** bundle and cellular-download limits apply; On-Demand
  Resources is the likely mechanism. Needs verification.
- **Consoles (future):** typically hostile to runtime content fetching; the model
  would likely have to ship in the package.

**Requirements regardless of mechanism:** resumable downloads, checksum
verification, disk-space pre-check, and **full offline operation once fetched**.

**Licensing — needs a decision, not an assumption.** Gemma ships under terms the
user must accept. If the game fetches weights on the user's behalf, *we* are the
distributor and inherit those obligations; if the user fetches them from Hugging
Face themselves, they accept directly. This is a legal question that shapes the UX
and should be settled before the downloader is built.

---

## D17 — Game mechanics live in **code**, not in the model. The AI narrates; it does not adjudicate.

**Status:** Proposed (2026-07-16) — **amends the brief's AI pipeline**

**The brief says:** `plan actions → call typed tools → generate validated game
commands`. That is, the model decides to roll, and decides the resulting command.

**What we found:** a schema constrains *shape*, not *meaning*. Both halves matter,
and only one works.

**Evidence** — same system prompt, same JSON schema (tool/command names constrained
by enum, so the model *cannot* name anything the registry would reject):

| | E2B (the default, per D4) | 12B |
|---|---|---|
| Valid JSON, whitelisted names | always | always |
| Roll before deciding | **no** — went straight to a command | **yes** — clean `tool_calls:[roll_die]`, empty commands/narrative |
| Obeys "commands must be empty on turn 1" | **no** — rolled *and* granted +10 in one reply | yes |
| Sensible reward for a 17/20 roll | **no** — `grant_resource(grain, +17)`, using the *die value* as the amount | `+20` (plausible) |
| Sensible sign | **no** — `grant_resource(grain, -10)` for an expedition *to find* grain | yes |

So E2B reliably emits well-formed, fully-whitelisted, **semantically wrong**
commands. The safety boundary held perfectly — and safety is not correctness.

**Two independent reasons this forces mechanics into code:**

1. **The default model cannot do it.** D4 fixes E2B as the default because it is
   the only model viable on a phone. A design that only works on 12B is not a
   design; it is a high-end feature.

2. **The stronger reason: model choice is a user setting (D5, D6), so
   model-driven mechanics means model-dependent game balance.** The same action
   would grant +17 grain on E2B and +20 on 12B. In a strategy game, the economy
   cannot depend on which GGUF the player downloaded. This argument holds *even if
   every model were as good as 12B*.

**Decision:** the orchestrator owns adjudication.

```
player message
  -> classify intent                       (code)
  -> decide whether a roll is needed       (code, per rules)
  -> roll                                  (code, seeded, deterministic, testable)
  -> compute outcome + reward from rules   (code)
  -> build + validate + apply the command  (code, existing whitelist)
  -> model narrates the decided outcome    (AI)
```

The model's remaining jobs — understanding intent and writing prose — are exactly
what E2B *is* good at. Its narratives were consistently decent even when its
arithmetic was nonsense.

**Consequences:**
- Game balance becomes deterministic, testable and reproducible — and stops being
  a property of the player's hardware.
- The AI trace and replay story get stronger: outcomes are code, so a recorded
  session replays exactly.
- The brief's `tool_calls` path is not deleted. It stays for genuinely open-ended
  tool use where no balance is at stake, and may be enabled as an enhancement on
  high-tier models. But **no game rule may depend on it**.
- Cost: less emergent AI-driven mechanics than the brief imagined. This is the
  trade for consistency, and it is worth it.

**Open:** where the line sits for a request the rules do not cover ("I want to
sing to the goats"). Probably: no state change, narrate only.

---

## D16 — Dispatch: run inference on another machine — **amends the brief**

**Status:** Open — accepted in principle (2026-07-16)

**This contradicts the brief as written** and the brief should be updated. It
currently says of the phone-to-desktop llama.cpp server: *"This is only a
development mode... The production architecture must not depend on this server."*

**The amendment:** production must not **require** dispatch, but may **offer** it.
Local inference stays the default and the fallback; dispatch is optional
acceleration. This preserves the brief's actual intent — never ship a game that is
broken without a server — while allowing the feature.

**Reasoning:** users own uneven hardware. Someone with a strong desktop should be
able to drive the phone build, or a second desktop, rather than being held to the
weakest device's limits. Given D4-D7, the gap is large: ~0.85 s/turn on a desktop
GPU versus ~2 s/turn on phone CPU, and dispatch unlocks E4B/12B quality (D5, D6)
for devices that could never run them.

**Already proven:** every measurement in `milestone1_results.md` went over HTTP to
`llama-server` on `127.0.0.1`. LAN dispatch is `--host 0.0.0.0` plus discovery —
the transport and the prefix-caching behaviour are validated. What is *not* proven
is everything below.

**Topologies:** desktop → phone (same LAN), desktop → desktop, and — much harder —
over the internet.

**Open problems, roughly in order of difficulty:**

1. **Security.** `llama-server` has no auth by default (`--api-key` exists). An
   exposed server is someone else's hardware executing arbitrary prompts. LAN-only
   is defensible; internet exposure needs auth, TLS and a threat model, and should
   not be built casually.
2. **NAT traversal** for the internet case — port forwarding, relay, or a
   rendezvous service (which is a service to run, contradicting D12's rationale for
   avoiding one).
3. **Discovery + pairing** on LAN (mDNS), and a trust model for pairing.
4. **Graceful degradation.** The server vanishing mid-session must fall back to
   local inference, not break the game. This is what "must not require" means in
   practice.
5. **Save/state authority.** Game state stays on the client. The dispatch server is
   a stateless inference endpoint — it must never become a source of truth, or the
   command-validation boundary in the brief is compromised.

**Recommendation:** ship **LAN-only** first (much of it already works), treat
internet dispatch as a separate later decision with its own security review. Do not
let dispatch delay local inference — it is an enhancement to a working game, and
per the brief's own logic the game must be complete without it.
