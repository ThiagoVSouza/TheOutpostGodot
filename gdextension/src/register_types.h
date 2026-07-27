#ifndef OUTPOST_LLAMA_REGISTER_TYPES_H
#define OUTPOST_LLAMA_REGISTER_TYPES_H

#include <godot_cpp/core/class_db.hpp>

void initialize_outpost_llama_module(godot::ModuleInitializationLevel p_level);
void uninitialize_outpost_llama_module(godot::ModuleInitializationLevel p_level);

/// Discover and register ggml's backend plugins (CUDA, CPU, ...), at most once
/// per process. Deliberately NOT called at module init: loading ggml-cuda.dll is
/// half a gigabyte of I/O plus CUDA context creation, and every Godot process
/// that merely has this addon installed would pay it - including the test suite,
/// which runs entirely on FakeAiBackend and never loads a model. Called instead
/// from the model-load worker thread, so the cost lands only on a run that
/// actually wants inference, and never on the main thread.
void outpost_ensure_ggml_backends_loaded();

#endif // OUTPOST_LLAMA_REGISTER_TYPES_H
