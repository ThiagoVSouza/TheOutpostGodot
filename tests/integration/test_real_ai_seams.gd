extends GutTest

## The real AI seams (M3b): LlamaAiRunner (grammar-constrained classification) and
## LlamaNarrator (bounded prose), plus the shared LlamaAiCall (timeout + T5 reporting). Driven
## against a recording backend double so the request shaping, grammar, parsing and failure
## handling are all verified without a live model. The live E2B run is a separate manual check.


## Captures the request and returns a scripted completion — deferred, per the D22 rule that a
## backend never finishes in-call.
class RecordingBackend:
	extends AiBackend
	var last_request: Dictionary = {}
	var scripted_content: String = "forage"
	var should_fail: bool = false

	func backend_id() -> String:
		return "recording"

	func is_ready() -> bool:
		return true

	func generate(request: Dictionary) -> AiRequest:
		last_request = request
		var req := AiRequest.new()
		var content := scripted_content
		var fail := should_fail
		(func() -> void:
			if fail:
				req.fail("connection_refused")
			else:
				req.complete({"content": content, "narrative": content})).call_deferred()
		return req


func _kernel_with(backend: AiBackend) -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boots with the fake; we swap the backend below
	kernel.ai = backend         # the seams read kernel.ai at call time
	return kernel


func _family() -> PromptFamily:
	return PromptFamily.new("classify_intent", PackedStringArray(["forage", "general"]))


func test_gbnf_grammar_admits_exactly_the_options() -> void:
	assert_eq(LlamaAiRunner.gbnf_for_options(PackedStringArray(["forage", "general"])),
		"root ::= \"forage\" | \"general\"", "a closed set becomes an alternation grammar (D19)")


func test_llama_runner_classifies_and_shapes_the_request() -> void:
	var backend := RecordingBackend.new()
	backend.scripted_content = "forage"
	var kernel := _kernel_with(backend)
	var runner := LlamaAiRunner.new(kernel)

	var value: String = await runner.classify(_family(), {"message": "I forage the hills"})

	assert_eq(value, "forage", "returns the constrained label")
	assert_string_contains(String(backend.last_request["grammar"]), "forage", "the request carries the grammar")
	assert_eq(float(backend.last_request["temperature"]), 0.0, "classification is deterministic (temp 0)")
	assert_string_contains(String((backend.last_request["messages"] as Array)[1]["content"]), "I forage the hills",
		"the player's message reaches the prompt")


func test_a_families_label_descriptions_reach_the_prompt() -> void:
	# Found live, not in tests: with bare labels E2B classified "I sing to the goats" as `forage`
	# (goats → animals → food) because nothing told it `general` was the decline option. Adding
	# the meanings moved it to `general`. The grammar bounds the answer; this is what makes the
	# answer sensible, so it is worth pinning.
	var backend := RecordingBackend.new()
	backend.scripted_content = "general"
	var kernel := _kernel_with(backend)
	var runner := LlamaAiRunner.new(kernel)
	var family := PromptFamily.new("classify_intent", PackedStringArray(["forage", "general"]),
		{"forage": "gathering food from the land", "general": "anything else, including whimsy"})

	var value: String = await runner.classify(family, {"message": "I sing to the goats"})

	assert_eq(value, "general")
	var prompt := String((backend.last_request["messages"] as Array)[1]["content"])
	assert_string_contains(prompt, "gathering food from the land", "each label's meaning is in the prompt")
	assert_string_contains(prompt, "anything else, including whimsy", "including the catch-all's")


func test_a_family_without_descriptions_still_lists_its_labels() -> void:
	var backend := RecordingBackend.new()
	backend.scripted_content = "forage"
	var kernel := _kernel_with(backend)
	var runner := LlamaAiRunner.new(kernel)

	await runner.classify(_family(), {"message": "I forage the hills"})

	var prompt := String((backend.last_request["messages"] as Array)[1]["content"])
	assert_string_contains(prompt, "forage, general", "descriptions are optional, not required")


func test_llama_runner_guards_an_out_of_set_answer() -> void:
	var backend := RecordingBackend.new()
	backend.scripted_content = "nonsense"  # the grammar would forbid this; the guard still catches it
	var kernel := _kernel_with(backend)
	var runner := LlamaAiRunner.new(kernel)
	var value: String = await runner.classify(_family(), {})
	assert_eq(value, "", "an out-of-set answer is rejected, not bound")


func test_llama_runner_failure_opens_the_t5_outage() -> void:
	var backend := RecordingBackend.new()
	backend.should_fail = true
	var kernel := _kernel_with(backend)
	var runner := LlamaAiRunner.new(kernel)
	var value: String = await runner.classify(_family(), {})
	assert_eq(value, "", "a failed classification returns empty")
	assert_true(kernel.ai_availability.is_blocked(), "a backend failure re-opens the T5 outage at the seam")


func test_llama_narrator_produces_prose_from_decided_facts() -> void:
	var backend := RecordingBackend.new()
	backend.scripted_content = "The scouts return laden with grain."
	var kernel := _kernel_with(backend)
	var narrator := LlamaNarrator.new(kernel)

	var prose: String = await narrator.narrate("the foraging succeeded", {"amount": 5}, "short", "en")

	assert_eq(prose, "The scouts return laden with grain.")
	var user_msg := String((backend.last_request["messages"] as Array)[1]["content"])
	assert_string_contains(user_msg, "amount", "the decided facts reach the narrator")
	assert_string_contains(user_msg, "en", "the output language is passed through (D29)")


func test_llama_narrator_failure_does_not_lose_the_turn() -> void:
	var backend := RecordingBackend.new()
	backend.should_fail = true
	var kernel := _kernel_with(backend)
	var narrator := LlamaNarrator.new(kernel)
	var prose: String = await narrator.narrate("something happened", {}, "short", "en")
	assert_false(prose.strip_edges().is_empty(), "a failed narration still returns a usable line")
