#ifndef OUTPOST_LLAMA_INFERENCE_ENGINE_H
#define OUTPOST_LLAMA_INFERENCE_ENGINE_H

#include <atomic>
#include <string>
#include <thread>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "llama.h"

namespace godot {

// In-process llama.cpp binding for M6 (GDExtension binds libllama directly;
// M2's subprocess+HTTP transport cannot ship on mobile). One model/context per
// instance, one generation in flight at a time (mirrors the orchestrator's own
// busy guard). generate() returns immediately with a request id; the actual
// decode runs on a detached worker thread and reports back via
// generation_completed/generation_failed, emitted through call_deferred so
// Godot signal delivery always happens on the main thread.
class LlamaInferenceEngine : public RefCounted {
	GDCLASS(LlamaInferenceEngine, RefCounted)

public:
	LlamaInferenceEngine();
	~LlamaInferenceEngine() override;

	// Model loading is a multi-second cold-start cost (weights I/O + KV buffer
	// reservation) and must never block Godot's main thread, matching the
	// same D22 "nothing here may block" rule generate() follows. Runs on a
	// detached worker thread; reports back via model_load_completed/failed.
	void begin_load_model(const String &p_model_path, int p_n_gpu_layers, int p_n_ctx);
	void unload_model();
	bool is_model_loaded() const;

	// request: { messages: Array[Dictionary{role,content}] (or message: String),
	//            temperature: float, max_tokens: int, grammar: String (GBNF, optional) }
	// Returns a request id (>= 1) always; failures are reported async via
	// generation_failed so callers never branch on the return value itself.
	int64_t generate(const Dictionary &p_request);
	void cancel(int64_t p_request_id);

protected:
	static void _bind_methods();

private:
	llama_model *_model = nullptr;
	llama_context *_ctx = nullptr;
	const llama_vocab *_vocab = nullptr;
	std::string _chat_template;

	std::atomic<bool> _busy{ false };
	std::atomic<bool> _cancel_requested{ false };
	std::atomic<int64_t> _current_request_id{ 0 };
	std::atomic<int64_t> _next_request_id{ 1 };

	void _run_generation(int64_t p_request_id, Dictionary p_request);
	void _run_load_model(String p_model_path, int p_n_gpu_layers, int p_n_ctx);
	bool _is_single_token(const char *p_text) const;
	void _fail_deferred(int64_t p_request_id, const String &p_error);
	void _free_model_locked();
};

} //namespace godot

#endif // OUTPOST_LLAMA_INFERENCE_ENGINE_H
