# Milestone 1 — Desktop & Android results

Closes steps 13–14 of the brief's first implementation milestone (deploy the
vertical slice to a phone; record desktop and Android performance).

Measured 2026-07-16. Re-run whenever the llama.cpp build or the quant changes —
these numbers are the input to the E2B-vs-E4B decision, not a one-off.

## Headline conclusions

1. **Ship E2B, not E4B.** E4B is not viable on the target phone (5.69 t/s, and
   unstable). E2B runs at 29.5 t/s there.
2. **Disable reasoning with `-rea off`.** Gemma 4 thinks by default and will spend
   an entire 250-token budget reasoning without reaching an answer. This is the
   single biggest latency factor — bigger than model choice.
3. **Prefix-cache the system prompt.** Worth ~20x on prompt processing per turn.
4. Together these give a **~0.85 s desktop game turn**. Untested on phone.

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
