# Milestone 1 — Desktop & Android results

Closes steps 13–14 of the brief's first implementation milestone (deploy the
vertical slice to a phone; record desktop and Android performance).

Measured 2026-07-16. Re-run whenever the llama.cpp build or the quant changes —
these numbers are the input to the E2B-vs-E4B decision, not a one-off.

## Decisions taken (2026-07-16)

- **Default: E2B, CPU-only, on every platform.** Simple, predictable, and the
  fastest option for the generation-dominated workload a game turn actually is.
- **E4B: offer as an optional user setting, not the default.** It is fine on
  desktop (57.6 t/s) and unusable on a phone like the S26 Ultra (5.69 t/s,
  thrashing). Users with headroom can opt in; the model assignment must stay
  configurable per the brief, never hardcoded.
- **Adreno GPU: available but not used.** See the Android GPU section — it is
  4.4x faster at prompt and 2.1x slower at generation.

Implication for the AI layer: model choice and backend must be **runtime
configuration**, and the UI should be honest that E4B is a "better writing, much
slower, needs a strong device" trade rather than a free upgrade. A device-capability
check (available RAM vs model size) should gate or warn before enabling E4B on
mobile — the E4B phone failure was a memory-pressure failure, not a compute one.

## Headline conclusions

1. **Ship E2B, not E4B.** E4B is not viable on the target phone (5.69 t/s, and
   unstable). E2B runs at 29.5 t/s there.
2. **Disable reasoning with `-rea off`.** Gemma 4 thinks by default and will spend
   an entire 250-token budget reasoning without reaching an answer. This is the
   single biggest latency factor — bigger than model choice.
3. **Prefix-cache the system prompt.** Worth ~20x on prompt processing per turn.
4. Together these give a **~0.85 s desktop game turn**. Untested on phone.
5. **Keep the phone on CPU, not the Adreno GPU.** OpenCL works and is 4.4x faster
   at prompt processing, but 2.1x *slower* at generation — and generation is what
   a game turn is made of. Break-even ≈ 5 turns. Ingest the system prompt once at
   load time instead.

## Hardware

| | Desktop | Phone |
|---|---|---|
| Device | Samsung Galaxy Book (960XGL) | Samsung Galaxy S26 Ultra (SM-S948B) |
| CPU/SoC | Intel (Alder Lake class) | Qualcomm `canoe`, 8 cores |
| GPU | RTX 4070 Laptop, 8187 MiB VRAM, CC 8.9 | Adreno 840 |
| RAM | 31.5 GB | 10.9 GB total / ~4.0 GB available |
| OS | Windows 11 | Android 16 (SDK 36), arm64-v8a |
| Screen | — | 1080x2340, density 450 |

Desktop inference: llama.cpp **b10042** CUDA 12.4, full GPU offload (`-ngl 99`).
Phone: llama.cpp **b10043** prebuilt `bin-android-arm64` (no NDK build needed),
run from `/data/local/tmp/llama`.

Two caveats on the hardware:

- The desktop GPU is a **laptop** 4070 — wide thermal/clock variance (see error
  bars), and its 8 GB is shared with the game's own rendering.
- The phone ran **CPU-only**. The prebuilt Android binary has no GPU backend, so
  the Adreno 840 sat idle. Phone numbers are a floor, not a ceiling; a custom
  build with OpenCL/Vulkan is unexplored headroom.

## Gemma 4 12B — runs on 8 GB, but crowds out the game

Checked because a 12B was assumed not to fit. It does — the assumption was wrong.

| 12B UD-Q4_K_XL (6.24 GiB, 11.91 B params) | |
|---|---|
| `llama-bench` full GPU (`-ngl 99`) | pp512 **793.64 ± 62.60** · tg128 **29.17 ± 1.61** |
| At 8K context, full GPU | **VRAM 7281 / 8188 MiB (89%)** |
| Cold turn (1552-token system prompt) | 6.15 s (2.5 s prompt + 3.6 s generate) |
| **Warm turn** | **~4.05 s** (~24-25 t/s) |

Two caveats behind the "it runs":

- `llama-bench` uses a ~640-token context, so its KV cache is trivial. Fitting
  there says little about fitting at a useful context — hence the 8K test.
- At 8K it fits with ~900 MiB spare, and llama.cpp's own auto-fit **tried to reduce
  the layer count**, proceeding only because `-ngl 99` forced it:
  `W common_fit_params: failed to fit params to free device memory: n_gpu_layers already set by user to 99, abort`

~900 MiB is survivable for today's chat screen and not for the map that milestone
2+ adds — and the brief is explicit that inference must leave GPU capacity for the
game. So: **viable as a desktop opt-in at 12 GB+ VRAM, not a default here.**

The quality gap is real, though. Same system prompt, refusing the Legate:

> Vettius Calla stands in the center of the governor's hall, his face flushing a
> deep, mottled red as you flatly deny his request for additional silver. He slams
> a heavy hand against a cedar table, the wood groaning under the impact, and warns
> you that the Legate's reports to Pyrgos will reflect a lack of cooperation.
> Outside, the salt air carries the distant sound of hammers from the docks,
> indifferent to…

It used the Legate's **name** from the system prompt and followed the style guide's
concrete-detail rule; E2B never used the named character. That observation is the
seed for the curated quality tiers in `docs/decisions.md` D11.

Also note the 12B repo ships `mmproj-*.gguf` (it is **multimodal**) and a **256K**
context vs 128K on E2B/E4B — a different model family, not just a bigger one.

## Model throughput — `llama-bench`

| Model | Size | Params | pp512 (t/s) | tg128 (t/s) |
|---|---|---|---|---|
| **E2B** UD-Q4_K_XL — desktop GPU | 2.43 GiB | 4.63 B | 3830.50 ± 218.63 | **103.39 ± 10.20** |
| **E4B** UD-Q4_K_XL — desktop GPU | 3.91 GiB | 7.46 B | 2044.73 ± 463.05 | **57.56 ± 5.30** |
| **E2B** UD-Q4_K_XL — phone CPU | 2.43 GiB | 4.63 B | 107.49 ± 0.90 | **29.52 ± 0.16** |
| **E4B** UD-Q4_K_XL — phone CPU | 3.91 GiB | 7.46 B | 58.43 ± 7.21 | **5.69 ± 7.34** |

### E4B is not viable on the phone

E4B generates at **5.69 t/s with a ±7.34 error bar — variance larger than the
mean**. That is the signature of memory thrashing, not compute: a 3.91 GiB model
against ~4 GB available RAM, fighting zram swap. A 60-token reply would take ~10
seconds, unpredictably.

E2B's ±0.16 by contrast is rock steady — notably *more* consistent than the
thermally-throttled laptop GPU (±10.20).

On desktop E4B is merely 2x slower than E2B and fits fine. So the constraint is
mobile, and it is decisive: **E2B**.

## Android GPU (Adreno 840 via OpenCL) — helps prompt, hurts generation

Built llama.cpp b10043 from source with `-DGGML_OPENCL=ON` against NDK 27.2. The
phone already ships the full Qualcomm OpenCL stack in `/vendor/lib64`
(`libOpenCL_adreno.so`, `libadreno_compiler_cl.so`), so no device-side work was
needed. `llama-bench` reports:

```
ggml_opencl: device: 'QUALCOMM Adreno(TM) 840 (OpenCL 3.0 Adreno(TM) 840)'
Available devices:
  GPUOpenCL: QUALCOMM Adreno(TM) 840 (5561 MiB, 4537 MiB free)
```

| E2B on S26 Ultra | pp512 (t/s) | tg128 (t/s) |
|---|---|---|
| CPU (8 threads) | 107.49 ± 0.90 | **29.52 ± 0.16** |
| Adreno 840 OpenCL (`-ngl 99`) | **470.46 ± 6.92** | 13.95 ± 0.00 |
| | **4.4x faster** | **2.1x slower** |

A real trade-off, not a win. Against our 1552-token system prompt:

- ingest it once: GPU **3.3 s** vs CPU **14.5 s** (GPU saves ~11 s)
- each turn (~60 tokens): CPU **2.0 s** vs GPU **4.3 s** (CPU saves ~2.3 s *per turn*)

**Break-even ≈ 5 turns, so CPU stays the default for the game.** The 14.5 s prompt
ingestion is not an argument for GPU — it is an argument for doing it once at load
time behind the boot screen.

Caveat: the OpenCL build warns `TODO: implement BF16, Q4_0, Q4_1, Q5_0, Q5_1,
Q8_0, IQ4_NL support`, so the kernels may lack an optimised path for this quant.
**13.95 t/s is probably not Adreno's ceiling.** Untested knobs: partial offload
(`-ngl` between 0 and 99, to put prompt-heavy layers on GPU and keep generation on
CPU), the Vulkan backend, and the Hexagon NPU backend.

Build gotcha: `libomp.so` must be pushed from the NDK alongside the binaries
(`toolchains/llvm/prebuilt/windows-x86_64/lib/clang/18/lib/linux/aarch64/libomp.so`)
or the executable will not link on device. Host CMake cannot configure
OpenCL-Headers (no MSVC on this machine) — copy `CL/*` into the NDK sysroot by hand.

Build lives at `C:\Dev\_build\llama.cpp\build_ocl`; device copy at
`/data/local/tmp/llama_ocl`.

### iOS

OpenCL is **not** available on iOS (Apple never shipped it there). The iOS path is
**Metal**, via llama.cpp's prebuilt **XCFramework** (iOS/tvOS/visionOS/macOS),
consumable from Swift Package Manager; Metal is enabled by default on Apple
platforms. Unified memory means Apple GPUs do not have the CPU/GPU bandwidth split
that hurts Adreno generation here, so iOS may well behave better than Android —
but this is **untested** (no Mac available). Maps onto the brief's `AiBackend`
abstraction as `AndroidLlamaBackend` (OpenCL) vs `IosLlamaBackend` (Metal).

## Reasoning — Gemma 4 thinks by default, and it dominates latency

Gemma 4 emits a `[Start thinking]` block before answering. Left on, every test run
consumed the **entire 200–250 token budget on reasoning and never reached the
narrative**. Raw tok/s badly overstates responsiveness.

| Setting | Result |
|---|---|
| default (reasoning on) | 250 tokens of thinking, no narrative produced |
| **`-rea off`** | **narrative in ~60 tokens, correct style, no thinking** |
| `--reasoning-budget 0` | **does not work** — still emitted the full thinking process |

`-rea off` is the flag. `--reasoning-budget 0` is a trap: it looks like it should
suppress thinking and does not.

Generation speed is unchanged (84.8 vs 86.2 t/s) — **the win is token count, not
throughput**: ~60 tokens instead of 250+ and unfinished. Roughly a 4x cut in turn
latency.

There is also a server-level `-rea off` startup flag, which is what we verified.
The per-request `"reasoning": "off"` JSON body field appeared to be **ignored** —
requests still returned empty `content` with a populated `reasoning_content`. Use
the startup flag; do not rely on the body field without retesting.

## Prompt prefix caching — worth ~20x on prompt processing

Tested with `llama-server`, a realistic 1552-token game-master system prompt
(world, factions, resources, calendar, rules, approved tools/commands, style),
`--cache-reuse 256`, `cache_prompt: true`, E2B on GPU.

| Turn | cached tokens | new tokens | prompt ms | predict ms | total |
|---|---|---|---|---|---|
| cold (first ever) | 0 | 1567 | **845.8** | 662.6 | ~1508 ms |
| warm | 1552 | 13 | **43.4** | 883.9 | 927 ms |
| warm | 1552 | 16 | **40.9** | 809.8 | 851 ms |

The system prompt is processed **once**; later turns process only the new user
message. Prompt time drops **846 ms → ~41 ms (~20x)**. The longer the system
prompt grows (lore, memories, retrieved content), the bigger this gets — it is
what makes a large static prefix affordable.

**A full turn with reasoning off + caching on: ~0.85 s on desktop.**

### Slot save/restore does NOT give a warm first turn

`--slot-save-path` persists a slot's KV cache to disk and restores it on a fresh
server. Both halves appear to work:

- save: 1637 tokens → 15.58 MB in 44–57 ms
- restore: 1637 tokens ← 15.58 MB in 24–26 ms

But it does not deliver the point of the exercise. On a freshly started server,
after a successful restore:

```
post-restore req 1:  cache_n=0     prompt_n=1562  prompt_ms=733.5   <- no hit
post-restore req 2:  cache_n=1552  prompt_n=15    prompt_ms=44.5    <- hit
```

The first request after a restore **reprocesses the whole prompt** and only then
populates the in-memory cache. Reproduced twice, consistently. So restore cannot
currently be used to skip the cold start.

Consequence is mild: the player pays the ~750 ms prompt processing **once per app
launch**, then ~45 ms per turn. Acceptable — but this may be a llama.cpp quirk or
a misuse of the API on our side, and is worth revisiting (or reporting upstream)
if first-turn latency ever matters.

## MTP drafters — inconclusive, do not act on this yet

| Config | Prompt t/s | Generation t/s |
|---|---|---|
| E2B baseline | 830.8 | 91.6 |
| E2B + MTP (`-md`) | 763.1 | 85.6 (−6.5%) |
| E4B baseline | 497.5 | 47.5 |
| E4B + MTP (`-md`) | 631.9 | 50.3 (+5.9%) |

The ~57 MB drafters produced no meaningful speedup and slightly *hurt* E2B. Most
likely a harness error, not a property of the models: Unsloth's card says a recent
llama.cpp **auto-discovers the drafter from `-hf`** and that `--model-draft`
should not be passed. We passed `-md` explicitly, which probably engages generic
speculative decoding rather than the native MTP path. **Retest via the `-hf` form
before concluding anything.**

## Android — Phase 1 (game without real AI)

APK: 26.98 MB, arm64-v8a only, `com.ntxgames.outpost.godot`, gl_compatibility,
rendering on OpenGL ES 3.2 / Adreno 840.

### Works

- Boots; kernel loads `base_game`; chat screen shows as start screen.
- Touch input, Samsung keyboard, Enter-to-submit.
- Full slice round-trips: `You: I send scouts to forage the hills` →
  `Game master: The world is quiet. (fake response)` via FakeAiBackend.
- Install + launch scripted: `tools/export_android.ps1 -Install -Run`.

### Bug found and fixed by this step

The app first booted to a **blank grey screen — "0 module(s) loaded"**. Godot
converts text resources to binary on export, so `base_game.tres` ships as
`base_game.tres.remap`; discovery matched `ends_with(".tres")` on the shipped
filename and found nothing. Invisible on desktop, fatal on device. Fixed in
`core/modules/module_registry.gd` (match the logical name). This is the whole
argument for keeping step 13 in the milestone.

### Open UI issues (found, not fixed — out of scope for steps 13–14)

| Issue | Detail |
|---|---|
| **Landscape orientation** | App runs landscape (2340x1080). No orientation set in `project.godot`. A text/chat game almost certainly wants portrait. |
| **Fonts far too small** | Default theme at density 450 is barely legible. The brief lists font readability as a Phase 1 check — currently a fail. |
| **No safe-area handling** | Content starts at the extreme top-left. Punch-hole camera and rounded corners will clip it. |
| **Back button quits instantly** | No confirmation, state lost. Godot's default. Bad for a game with unsaved state — and there is no save/load yet. |
| **Keyboard overlays UI** | Layout does not shift; the on-screen keyboard covers the input area in landscape. |

### Not yet tested

Save/load (no save system exists yet), backgrounding/resume, battery, thermal
behaviour under sustained inference, and the brief's benchmark scenarios (map
idle/moving, large settlement) — those need a map, which does not exist at
milestone 1.

## Reproducing

Desktop llama.cpp: `C:\Tools\llama.cpp\b10042` (CUDA 12.4 + cudart).
Models: `C:\Models\gemma-4\`. Phone: `/data/local/tmp/llama` (binaries + models).

```powershell
# raw throughput
C:\Tools\llama.cpp\b10042\llama-bench.exe -m C:\Models\gemma-4\gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf -ngl 99 -p 512 -n 128 -r 3

# phone (adb)
adb shell "cd /data/local/tmp/llama && LD_LIBRARY_PATH=/data/local/tmp/llama ./llama-bench -m /data/local/tmp/llama/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf -p 512 -n 128 -r 2"

# server with reasoning off + prefix caching
C:\Tools\llama.cpp\b10042\llama-server.exe -m C:\Models\gemma-4\gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf -ngl 99 -c 8192 --port 8099 --cache-reuse 256 -np 1 -rea off
```

Gotcha when scripting the server from Windows PowerShell 5.1: `ConvertTo-Json`
mangles long strings into `{"value":...}` objects, and `Get-Content -Raw` reads
UTF-8 as ANSI. Use `[System.IO.File]::ReadAllText(path, UTF8)` and
`System.Web.Script.Serialization.JavaScriptSerializer` instead.
