extends GutTest

const FIXTURE_DIR := "res://tests/fixtures/ai/"


func test_payload_contains_chat_sampling_and_cache_fields() -> void:
	var payload := LlamaChatCodec.build_payload({
		"messages": [
			{"role": "system", "content": "Be concise."},
			{"role": "user", "content": "Hello"},
		],
		"temperature": 0.25,
		"max_tokens": 64,
	})
	assert_eq(float(payload["temperature"]), 0.25)
	assert_eq(int(payload["max_tokens"]), 64)
	assert_true(bool(payload["cache_prompt"]))
	assert_false(bool(payload["stream"]))
	assert_eq((payload["messages"] as Array).size(), 2)


func test_payload_includes_nonempty_per_request_grammar() -> void:
	var grammar := 'root ::= "P1|INTENT|UNKNOWN|LOW"'
	var payload := LlamaChatCodec.build_payload({"message": "?", "grammar": grammar})
	assert_eq(String(payload["grammar"]), grammar)


func test_payload_omits_empty_grammar() -> void:
	var payload := LlamaChatCodec.build_payload({"message": "hello", "grammar": ""})
	assert_false(payload.has("grammar"))


func test_payload_falls_back_to_a_user_message() -> void:
	var payload := LlamaChatCodec.build_payload({"message": "hello"})
	var messages: Array = payload["messages"]
	assert_eq(messages, [{"role": "user", "content": "hello"}])


func test_parses_content_finish_reason_and_selected_timings() -> void:
	var parsed := LlamaChatCodec.parse_response(200, _fixture("llama_chat_success.json"))
	assert_true(bool(parsed["ok"]))
	var response: Dictionary = parsed["response"]
	assert_eq(
		String(response["narrative"]),
		"Salt wind crosses the outpost as the watch changes at dusk."
	)
	assert_eq(String(response["content"]), String(response["narrative"]))
	assert_eq(String(response["finish_reason"]), "stop")
	var timings: Dictionary = response["timings"]
	assert_eq(int(timings["prompt_n"]), 37)
	assert_eq(float(timings["prompt_ms"]), 12.5)
	assert_eq(int(timings["predicted_n"]), 15)
	assert_eq(float(timings["predicted_ms"]), 145.75)
	assert_false(timings.has("predicted_per_second"), "only the T2 timing contract is copied")


func test_maps_http_statuses_without_exposing_response_body() -> void:
	for code in [401, 429, 500]:
		var parsed := LlamaChatCodec.parse_response(code, '{"secret":"do not expose"}'.to_utf8_buffer())
		assert_false(bool(parsed["ok"]))
		assert_eq(String(parsed["error"]), "http_error:%d" % code)


func test_rejects_malformed_json() -> void:
	var parsed := LlamaChatCodec.parse_response(200, _fixture("llama_chat_malformed.json"))
	assert_false(bool(parsed["ok"]))
	assert_eq(String(parsed["error"]), "invalid_json")


func test_rejects_missing_choices_and_wrong_content_type() -> void:
	var missing := LlamaChatCodec.parse_response(200, '{"choices":[]}'.to_utf8_buffer())
	assert_eq(String(missing["error"]), "invalid_response")
	var wrong_type := LlamaChatCodec.parse_response(
		200, '{"choices":[{"message":{"content":42}}]}'.to_utf8_buffer()
	)
	assert_eq(String(wrong_type["error"]), "invalid_response")


func test_rejects_reasoning_only_empty_content() -> void:
	var parsed := LlamaChatCodec.parse_response(200, _fixture("llama_chat_empty_content.json"))
	assert_false(bool(parsed["ok"]))
	assert_eq(String(parsed["error"]), "empty_content")


func test_transport_error_is_stable_and_machine_readable() -> void:
	assert_eq(LlamaChatCodec.transport_error(HTTPRequest.RESULT_CANT_CONNECT), "transport_error:2")


func _fixture(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_string(FIXTURE_DIR + name).to_utf8_buffer()
