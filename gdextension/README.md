# outpost_llama — in-process llama.cpp binding (M6)

Binds `libllama` **in-process** through a GDExtension, instead of M2's
subprocess + HTTP transport. That transport works on desktop and **cannot ship on
mobile**: iOS forbids spawning subprocesses and Android blocks exec from app
data. This is the M6 prerequisite named in `docs/plan.md`.

Phase 1 is **Windows only** and proves the architecture. Android (NDK, arm64 CPU
per D9) and iOS (Metal, D10) are follow-on work; the C++ here is already
platform-agnostic — only `ModelProfile.gpu_layers` and the build config change.

## Build

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_gdextension.ps1
```

Nothing under `thirdparty/`, `build_tmp/` or `addons/outpost_llama/bin/` is
tracked — that folder alone is ~1.1 GiB of llama.cpp and CUDA runtime DLLs, all
of it reproducible. The tracked source is `src/`, `SConstruct`, and the
`.gdextension` descriptor beside the addon.

## Run

```
$env:OUTPOST_AI_BACKEND = "in-process-llama"
$env:OUTPOST_MODEL_PROFILE = "gemma_e2b_desktop_cuda"
```

`InProcessLlamaBackend` (`core/ai/in_process_llama_backend.gd`) implements the
existing `AiBackend` seam, so nothing above the backend layer — orchestrator,
D22 request contract, T5 availability policy — changed to accommodate it.

## Measured (2026-07-27, RTX 4070 Laptop, Gemma 4 E2B Q4_K_XL)

| | CPU-only | CUDA |
|---|---|---|
| Raw generation, warm | 3854 ms | **123 ms** |
| Full orchestrator turn (classify → dispatch → forage → narrate) | 34313 ms | **423–513 ms** |

For reference, the M2 subprocess+HTTP baseline was 0.80–0.85 s warm, so the
in-process path is *faster* than the transport it replaces, on top of being the
one that can ship on a phone.

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
- **The chat template is applied by hand for Gemma.**
  `llama_chat_apply_template` only substring-matches a fixed list of known
  templates; it cannot render Jinja2. The E2B/E4B GGUFs carry a macro-heavy
  template containing no literal `<start_of_turn>`, so detection returns -1 even
  though the model is an ordinary Gemma chat model. Rather than pull in a Jinja
  engine for Phase 1, the documented Gemma turn format is emitted directly when
  detection fails.
