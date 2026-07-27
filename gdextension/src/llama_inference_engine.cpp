#include "llama_inference_engine.h"

#include <chrono>
#include <vector>

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "register_types.h"

namespace godot {

LlamaInferenceEngine::LlamaInferenceEngine() {
}

LlamaInferenceEngine::~LlamaInferenceEngine() {
	unload_model();
}

void LlamaInferenceEngine::_bind_methods() {
	ClassDB::bind_method(D_METHOD("begin_load_model", "model_path", "n_gpu_layers", "n_ctx"), &LlamaInferenceEngine::begin_load_model);
	ClassDB::bind_method(D_METHOD("unload_model"), &LlamaInferenceEngine::unload_model);
	ClassDB::bind_method(D_METHOD("is_model_loaded"), &LlamaInferenceEngine::is_model_loaded);
	ClassDB::bind_method(D_METHOD("generate", "request"), &LlamaInferenceEngine::generate);
	ClassDB::bind_method(D_METHOD("cancel", "request_id"), &LlamaInferenceEngine::cancel);

	ADD_SIGNAL(MethodInfo("model_load_completed"));
	ADD_SIGNAL(MethodInfo("model_load_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("generation_completed",
			PropertyInfo(Variant::INT, "request_id"),
			PropertyInfo(Variant::DICTIONARY, "response")));
	ADD_SIGNAL(MethodInfo("generation_failed",
			PropertyInfo(Variant::INT, "request_id"),
			PropertyInfo(Variant::STRING, "error")));
}

void LlamaInferenceEngine::begin_load_model(const String &p_model_path, int p_n_gpu_layers, int p_n_ctx) {
	bool expected = false;
	if (!_busy.compare_exchange_strong(expected, true)) {
		call_deferred("emit_signal", "model_load_failed", "engine_busy");
		return;
	}
	Ref<LlamaInferenceEngine> self(this);
	std::thread worker([self, p_model_path, p_n_gpu_layers, p_n_ctx]() {
		self->_run_load_model(p_model_path, p_n_gpu_layers, p_n_ctx);
	});
	worker.detach();
}

void LlamaInferenceEngine::_run_load_model(String p_model_path, int p_n_gpu_layers, int p_n_ctx) {
	// First model load in this process pays for backend discovery (see the
	// comment on this function): without it llama sees no CUDA device and
	// silently places every layer on the CPU.
	outpost_ensure_ggml_backends_loaded();

	// Not unload_model(): that guards on _busy for external callers, and this
	// thread is itself the reason _busy is already true.
	if (_ctx != nullptr) {
		llama_free(_ctx);
		_ctx = nullptr;
	}
	_free_model_locked();

	llama_model_params model_params = llama_model_default_params();
	model_params.n_gpu_layers = p_n_gpu_layers;

	CharString path_utf8 = p_model_path.utf8();
	_model = llama_model_load_from_file(path_utf8.get_data(), model_params);
	if (_model == nullptr) {
		_busy.store(false);
		call_deferred("emit_signal", "model_load_failed", "model_load_failed");
		return;
	}

	_vocab = llama_model_get_vocab(_model);
	const char *tmpl = llama_model_chat_template(_model, nullptr);
	_chat_template = (tmpl != nullptr) ? std::string(tmpl) : std::string();

	llama_context_params ctx_params = llama_context_default_params();
	ctx_params.n_ctx = (uint32_t)p_n_ctx;
	ctx_params.n_batch = (uint32_t)p_n_ctx;

	_ctx = llama_init_from_model(_model, ctx_params);
	if (_ctx == nullptr) {
		_free_model_locked();
		_busy.store(false);
		call_deferred("emit_signal", "model_load_failed", "context_init_failed");
		return;
	}
	_busy.store(false);
	call_deferred("emit_signal", "model_load_completed");
}

void LlamaInferenceEngine::unload_model() {
	// Never tear down a model a worker thread is still decoding against.
	if (_busy.load()) {
		return;
	}
	if (_ctx != nullptr) {
		llama_free(_ctx);
		_ctx = nullptr;
	}
	_free_model_locked();
}

void LlamaInferenceEngine::_free_model_locked() {
	if (_model != nullptr) {
		llama_model_free(_model);
		_model = nullptr;
	}
	_vocab = nullptr;
	_chat_template.clear();
}

bool LlamaInferenceEngine::is_model_loaded() const {
	return _model != nullptr && _ctx != nullptr;
}

int64_t LlamaInferenceEngine::generate(const Dictionary &p_request) {
	int64_t request_id = _next_request_id.fetch_add(1);

	if (!is_model_loaded()) {
		_fail_deferred(request_id, "engine_not_ready");
		return request_id;
	}
	bool expected = false;
	if (!_busy.compare_exchange_strong(expected, true)) {
		_fail_deferred(request_id, "engine_busy");
		return request_id;
	}

	_cancel_requested.store(false);
	_current_request_id.store(request_id);

	// Hold a Ref in the thread's closure so the engine outlives GDScript
	// dropping its own reference mid-generation; unload_model()'s busy guard
	// still protects the underlying llama_model/context from a concurrent reload.
	Ref<LlamaInferenceEngine> self(this);
	std::thread worker([self, request_id, p_request]() {
		self->_run_generation(request_id, p_request);
	});
	worker.detach();
	return request_id;
}

void LlamaInferenceEngine::cancel(int64_t p_request_id) {
	if (_current_request_id.load() == p_request_id) {
		_cancel_requested.store(true);
	}
}

void LlamaInferenceEngine::_fail_deferred(int64_t p_request_id, const String &p_error) {
	call_deferred("emit_signal", "generation_failed", p_request_id, p_error);
}

// Runs on a detached worker thread. Owns the whole decode+sample loop for one
// turn; the KV cache is cleared up front so every call is a fresh full-context
// pass (D22's request contract already carries the whole conversation each
// turn, so there is no cross-call cache to preserve here).
void LlamaInferenceEngine::_run_generation(int64_t p_request_id, Dictionary p_request) {
	Array messages = p_request.get("messages", Array());
	if (messages.is_empty()) {
		String single = p_request.get("message", String());
		Dictionary m;
		m["role"] = "user";
		m["content"] = single;
		messages.push_back(m);
	}

	std::vector<std::string> roles;
	std::vector<std::string> contents;
	roles.reserve(messages.size());
	contents.reserve(messages.size());
	for (int i = 0; i < messages.size(); i++) {
		Dictionary msg = messages[i];
		String role = msg.get("role", "user");
		String content = msg.get("content", "");
		roles.push_back(std::string(role.utf8().get_data()));
		contents.push_back(std::string(content.utf8().get_data()));
	}

	std::vector<llama_chat_message> chat_messages;
	chat_messages.reserve(roles.size());
	size_t total_chars = 0;
	for (size_t i = 0; i < roles.size(); i++) {
		chat_messages.push_back({ roles[i].c_str(), contents[i].c_str() });
		total_chars += contents[i].size();
	}

	// llama_chat_apply_template only pattern-matches a fixed list of known
	// templates by substring (see llm_chat_detect_template) - it cannot render
	// arbitrary Jinja2. The E2B/E4B GGUFs ship a macro-heavy template with no
	// literal "<start_of_turn>" text, so detection fails (-1) even though the
	// model is a normal Gemma chat model. Fall back to the documented Gemma
	// turn format by hand rather than pulling in a Jinja engine for Phase 1.
	const char *tmpl = _chat_template.empty() ? nullptr : _chat_template.c_str();
	std::vector<char> prompt_buf(total_chars * 2 + 256);
	int32_t needed = llama_chat_apply_template(tmpl, chat_messages.data(), chat_messages.size(), true,
			prompt_buf.data(), (int32_t)prompt_buf.size());
	if (needed >= 0 && (size_t)needed > prompt_buf.size()) {
		prompt_buf.resize(needed);
		needed = llama_chat_apply_template(tmpl, chat_messages.data(), chat_messages.size(), true,
				prompt_buf.data(), (int32_t)prompt_buf.size());
	}
	std::string prompt;
	if (needed >= 0) {
		prompt.assign(prompt_buf.data(), needed);
	} else {
		for (size_t i = 0; i < roles.size(); i++) {
			const std::string &gemma_role = (roles[i] == "assistant") ? "model" : "user";
			prompt += "<start_of_turn>" + gemma_role + "\n" + contents[i] + "<end_of_turn>\n";
		}
		prompt += "<start_of_turn>model\n";
	}

	llama_memory_clear(llama_get_memory(_ctx), true);

	int32_t n_prompt_tokens = -llama_tokenize(_vocab, prompt.c_str(), (int32_t)prompt.size(),
			nullptr, 0, true, true);
	if (n_prompt_tokens <= 0) {
		_busy.store(false);
		_fail_deferred(p_request_id, "tokenize_failed");
		return;
	}
	std::vector<llama_token> tokens(n_prompt_tokens);
	if (llama_tokenize(_vocab, prompt.c_str(), (int32_t)prompt.size(),
				tokens.data(), (int32_t)tokens.size(), true, true) < 0) {
		_busy.store(false);
		_fail_deferred(p_request_id, "tokenize_failed");
		return;
	}

	llama_batch prompt_batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
	int64_t prompt_start_usec = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
										 .count();
	if (llama_decode(_ctx, prompt_batch) != 0) {
		_busy.store(false);
		_fail_deferred(p_request_id, "decode_failed");
		return;
	}
	int64_t prompt_end_usec = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
									   .count();

	llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
	llama_sampler *smpl = llama_sampler_chain_init(sparams);

	String grammar = p_request.get("grammar", String());
	CharString grammar_utf8 = grammar.utf8();
	if (!grammar.is_empty()) {
		llama_sampler_chain_add(smpl, llama_sampler_init_grammar(_vocab, grammar_utf8.get_data(), "root"));
	}

	double temperature = double(p_request.get("temperature", 0.7));
	if (temperature <= 0.0) {
		llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
	} else {
		uint32_t seed = (uint32_t)std::chrono::high_resolution_clock::now().time_since_epoch().count();
		llama_sampler_chain_add(smpl, llama_sampler_init_temp((float)temperature));
		llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed));
	}

	int max_tokens = int(p_request.get("max_tokens", 128));
	std::string output;
	String finish_reason = "length";
	int produced = 0;
	int64_t gen_start_usec = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
									  .count();

	for (int i = 0; i < max_tokens; i++) {
		if (_cancel_requested.load()) {
			finish_reason = "cancelled";
			break;
		}
		llama_token new_token = llama_sampler_sample(smpl, _ctx, -1);
		if (llama_vocab_is_eog(_vocab, new_token)) {
			finish_reason = "stop";
			break;
		}
		char piece[256];
		int32_t n = llama_token_to_piece(_vocab, new_token, piece, sizeof(piece), 0, true);
		if (n > 0) {
			output.append(piece, n);
		}
		produced++;

		llama_batch next_batch = llama_batch_get_one(&new_token, 1);
		if (llama_decode(_ctx, next_batch) != 0) {
			llama_sampler_free(smpl);
			_busy.store(false);
			_fail_deferred(p_request_id, "decode_failed");
			return;
		}
	}
	int64_t gen_end_usec = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
									.count();

	llama_sampler_free(smpl);

	if (finish_reason == "cancelled") {
		_busy.store(false);
		_fail_deferred(p_request_id, "cancelled");
		return;
	}

	String content = String::utf8(output.c_str(), (int)output.size());
	if (content.strip_edges().is_empty()) {
		_busy.store(false);
		_fail_deferred(p_request_id, "empty_content");
		return;
	}

	Dictionary timings;
	timings["prompt_n"] = (int)tokens.size();
	timings["prompt_ms"] = double(prompt_end_usec - prompt_start_usec) / 1000.0;
	timings["predicted_n"] = produced;
	timings["predicted_ms"] = double(gen_end_usec - gen_start_usec) / 1000.0;

	Dictionary response;
	response["content"] = content;
	response["narrative"] = content;
	response["tool_calls"] = Array();
	response["finish_reason"] = finish_reason;
	response["timings"] = timings;

	_busy.store(false);
	call_deferred("emit_signal", "generation_completed", p_request_id, response);
}

} //namespace godot
