# outpost_llama — in-process llama.cpp binding (M6)

Binds `libllama` **in-process** through a GDExtension, instead of M2's
subprocess + HTTP transport. That transport works on desktop and **cannot ship on
mobile**: iOS forbids spawning subprocesses and Android blocks exec from app
data. This is the M6 prerequisite named in `docs/plan.md`.

**Windows and Android both ship.** iOS (Metal, D10) is still follow-on and has
never been run — there is no Mac. The C++ is platform-agnostic; what differs per
platform is the build config and how llama.cpp is obtained.

The two platforms get llama.cpp differently, because upstream publishes binaries
for only one of them:

| | Windows | Android |
|---|---|---|
| llama.cpp | prebuilt **b10042** release, linked through import libs generated from each DLL's export table (the release ships no `.lib`) | **cross-compiled from source** at the same tag with NDK 27.2, arm64-v8a |
| Compute | CUDA (`ggml-cuda.dll`, discovered as a plugin) | CPU only, per D9 — the CPU backend is linked into `libggml.so`, since `GGML_BACKEND_DL` is off, so there is no plugin search path to get wrong |
| Selected by | `OUTPOST_AI_BACKEND=in-process-llama` | **the platform default** — a phone has no environment to configure and no alternative runtime |

## Build

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_gdextension.ps1
```

Nothing under `thirdparty/`, `build_tmp/` or `addons/outpost_llama/bin/` is
tracked — that folder alone is ~1.1 GiB of llama.cpp and CUDA runtime DLLs, all
of it reproducible. The tracked source is `src/`, `SConstruct`, and the
`.gdextension` descriptor beside the addon.

## Run

Desktop:

```
$env:OUTPOST_AI_BACKEND = "in-process-llama"
$env:OUTPOST_MODEL_PROFILE = "gemma_e2b_desktop_cuda"
```

Android — no environment variable is involved; the in-process backend is the
platform default. Push the weights to the path named by the
`gemma_e2b_android_cpu` profile in `config/ai/model_catalog.tres`, then:

```
adb push <model>.gguf /storage/emulated/0/Android/data/com.ntxgames.outpost.godot/files/models/
powershell -File tools/export_android.ps1 -Install -Run
```

An app can always read its own external files directory without a permission,
which is why the weights live there rather than in `user://` (which is internal
storage that `adb push` cannot write to directly).

`InProcessLlamaBackend` (`core/ai/in_process_llama_backend.gd`) implements the
existing `AiBackend` seam, so nothing above the backend layer — orchestrator,
D22 request contract, T5 availability policy — changed to accommodate it. A
missing model is reported loudly (`push_error` naming the path) rather than
appearing as an AI that is silently never available.

## Measured (2026-07-27, Gemma 4 E2B Q4_K_XL)

Desktop, RTX 4070 Laptop:

| | CPU-only | CUDA |
|---|---|---|
| Raw generation, warm | 3854 ms | **123 ms** |
| Full orchestrator turn (classify → dispatch → forage → narrate) | 34313 ms | **423–513 ms** |

For reference, the M2 subprocess+HTTP baseline was 0.80–0.85 s warm, so the
in-process path is *faster* than the transport it replaces, on top of being the
one that can ship on a phone.

Android, Galaxy S26 Ultra (Snapdragon 8 Elite, 3.99 GiB available RAM):

| Full orchestrator turn, warm | |
|---|---|
| baseline `armv8-a` | 11 s |
| **`armv8.2-a+dotprod`** | **4 s** |

The first turn after launch is ~40 s because it absorbs the one-time load of
2.4 GiB of weights; every turn after that is the warm number. **`GGML_NATIVE=OFF`
is required for a cross-compile and silently selects the `armv8-a` baseline** —
no dotprod, the instruction Q4 matmul lives on. Setting `GGML_CPU_ARM_ARCH`
explicitly is worth 2.75x and is the difference between unplayable and playable.

`i8mm` is deliberately **not** enabled: it would cut support to 2021+ devices,
and ggml compiles these kernels unconditionally, so an unsupported core does not
degrade gracefully — it SIGILLs. `dotprod` is present on every Cortex-A75-or-later
(2018+) core.

## Four traps, each of which cost real time

**1. The llama.cpp Windows release ships no import library.** `.lib` files are
generated from each DLL's own export table (`dumpbin /exports` → `.def` →
`lib.exe /def`). Only plain C names are taken: `llama.dll` also exports ~20
mangled C++ internals that are not public API.

**2. Headers must come from the DLL's exact commit.** `llama.h` describes a C
ABI; a header from a different build mismatches struct layouts silently rather
than failing to compile.

**3. ggml's CUDA backend fails to load, silently, and falls back to CPU at ~40x
the cost.** `ggml-backend-dl.cpp` loads backend plugins with a bare
`LoadLibraryW(absolute_path)` — no `LOAD_WITH_ALTERED_SEARCH_PATH`. Windows
therefore resolves `ggml-cuda.dll`'s *own* imports (`cudart64_*`, `cublas64_*`,
`cublasLt64_*`) against the **application** directory, which for an addon is
Godot's install folder, not `addons/outpost_llama/bin`. The load fails; ggml's
`dl_error()` returns `""` and discovery runs with `silent=true`, so **nothing is
printed** — the only symptom is that every layer lands on the CPU.
`register_types.cpp` pre-loads each third-party runtime DLL by absolute path
with `LOAD_WITH_ALTERED_SEARCH_PATH` first; once a module is in the process,
Windows satisfies imports naming it from the loaded module. `llama-server.exe`
never hits this because its application directory *is* the folder holding every
DLL.

**4. A `godot::String` at namespace scope aborts the whole extension.** It is
constructed during static initialization, before the GDExtension interface binds
its function pointers. Windows reports only *"Error 1114: a dynamic link library
(DLL) initialization routine failed"* and the extension does not load at all.
Use plain C++ types for globals here.

**5. The chat template is the model's, and guessing it does not fail loudly.**
`llama_chat_apply_template` only substring-matches a fixed list of known
templates; it cannot render Jinja2, and this model ships 16 KB of Jinja macros,
so detection returns -1. The first fallback written here assumed **Gemma 3**'s
`<start_of_turn>` / `<end_of_turn>` — but the Gemma 4 E2B/E4B builds this game
ships use **`<|turn>` / `<turn|>`** (tokens 105/106, `<turn|>` being the EOT).
Nothing errored. The model simply saw an unfamiliar format and echoed it back,
and a turn on the phone narrated, in full:

> `<start_of_turn>`The foraging party returns empty-handed.`</start_of_turn>`

The markers are now **detected in the vocabulary** (`_is_single_token`), and if
neither the template engine nor that check can establish the format the request
**fails** rather than guessing — a wrong guess produces plausible prose with the
framing leaking through, which is worse than an unavailable narrator the
availability policy already knows how to handle. `tools/check_llama_turn.gd`
guards it, because 413 green tests could not: the suite is model-free by design.

**6. Two Android packaging rules, both of which fail at signing or on-device.**
*Do not ship `libc++_shared.so`* — Godot's template already includes it, and a
second copy makes apksigner reject the APK (*"Multiple ZIP entries with the same
name"*) **after** the export has reported success. And *every `.so` needs 16 KB
page alignment* (`-Wl,-z,max-page-size=16384`, or
`ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON` for the cmake build): Android 15+ can
use 16 KB pages, Google Play requires it of new uploads, and the device shows a
system dialog naming every offending library.

## Notes on the design

- **Backend discovery is lazy** (`outpost_ensure_ggml_backends_loaded`). Loading
  `ggml-cuda.dll` is half a gigabyte of I/O plus CUDA context creation; doing it
  at module init would charge every Godot process that merely has the addon
  installed, including the 407-test suite, which runs on `FakeAiBackend` and
  never loads a model. It runs on the model-load worker thread instead, so the
  cost falls only on a run that actually wants inference, and never on the main
  thread.
- **Model loading and generation both run on detached worker threads**, and
  results reach GDScript through `call_deferred("emit_signal", ...)` so signal
  delivery is always on the main thread. This is the same rule as D22: a real
  turn takes hundreds of milliseconds and nothing here may block a frame.
- **The chat template is applied by hand** (see trap 5) rather than pulling a
  Jinja engine in. The proper fix, if this ever needs to serve models beyond the
  Gemma 4 family, is llama.cpp's own `minja` renderer in `common/` — which is
  excluded from this build precisely because `LLAMA_BUILD_COMMON=OFF` keeps the
  Android cross-compile small.
- **`n_batch` is capped at 2048, not set to `n_ctx`.** Batch size is how many
  tokens may be submitted in one `llama_decode`, and sizing it to the whole
  context reserves a compute buffer for a batch this game never submits. On a
  phone, where 2.43 GiB of weights already compete for ~4 GiB of available RAM
  (D5), that reservation is the constraint deciding whether the model fits.

## Known follow-ups

- **The KV cache is cleared on every call**, so each of a turn's two AI calls
  (classify, then narrate) reprocesses its whole prompt. That is cheap on CUDA
  and is most of the 4 s on a phone. D8 (prefix-caching the system prompt) is
  the named fix and is not done here.
- **iOS/Metal (D10)** — source-verified, never run, no Mac available.
- **Voice input (D18)** — shares this toolchain; the open question is whether
  whisper `small` (~466 MB) fits alongside E2B on a real phone.
