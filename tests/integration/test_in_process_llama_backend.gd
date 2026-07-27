extends GutTest

## M6: the in-process llama binding's GDScript seam.
##
## Deliberately model-free. Loading real weights is a 2.4 GiB, multi-second
## operation and belongs in a hands-on run, not the suite; what matters here is
## that the backend honours the same contracts every other AiBackend does, and
## that a broken or missing native build is caught by the suite rather than
## first appearing in front of a player.


func test_the_native_extension_is_built_and_registers_its_class() -> void:
	# Fails loudly when gdextension/ has not been built (or failed to load, which
	# on Windows surfaces only as a terse "Error 1114" during boot). Without this,
	# a broken build looks like a backend that simply never becomes ready.
	assert_true(ClassDB.class_exists("LlamaInferenceEngine"),
		"run tools/setup_gdextension.ps1 — the outpost_llama extension is not loaded")


func test_it_identifies_itself_for_traces() -> void:
	var backend := InProcessLlamaBackend.new(null)
	assert_eq(backend.backend_id(), "in-process-llama")


func test_it_is_not_ready_before_a_model_is_loaded() -> void:
	var backend := InProcessLlamaBackend.new(null)
	assert_false(backend.is_ready())


func test_generate_without_a_profile_fails_asynchronously() -> void:
	# D22: a backend must NEVER finish a request inside generate(), even when it
	# already knows the answer is failure. Completing in-call is what hides
	# reentrancy and cancellation bugs until a real model is attached.
	var backend := InProcessLlamaBackend.new(null)
	var request := backend.generate({"message": "hello"})

	assert_false(request.is_finished(), "the request must still be open when generate() returns")

	var outcome: Dictionary = await request.wait()
	assert_false(bool(outcome["ok"]))
	assert_eq(String(outcome["error"]), "model_profile_unavailable")
