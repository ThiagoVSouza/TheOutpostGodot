extends GutTest

const SUCCESS_FIXTURE := "res://tests/fixtures/ai/llama_chat_success.json"


class TestRemoteBackend:
	extends RemoteLlamaBackend

	var pending_http: HTTPRequest = null
	var captured_url: String = ""
	var captured_headers := PackedStringArray()
	var captured_method: HTTPClient.Method = HTTPClient.METHOD_GET
	var captured_body: String = ""
	var cancel_calls: int = 0
	var start_error: Error = OK

	func _start_http_request(
		http_request: HTTPRequest,
		url: String,
		headers: PackedStringArray,
		method: HTTPClient.Method,
		body: String
	) -> Error:
		pending_http = http_request
		captured_url = url
		captured_headers = headers
		captured_method = method
		captured_body = body
		return start_error

	func _cancel_http_request(_http_request: HTTPRequest) -> void:
		cancel_calls += 1

	func finish(result: int, response_code: int, body: PackedByteArray) -> void:
		pending_http.request_completed.emit(result, response_code, PackedStringArray(), body)


func test_generate_starts_post_and_does_not_complete_synchronously() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var backend := TestRemoteBackend.new(host, "http://example.test/v1/chat/completions", "key-123")
	var request := backend.generate({"message": "hello", "grammar": 'root ::= "ok"'})

	assert_false(request.is_finished(), "RemoteLlamaBackend must honor D22")
	assert_eq(backend.captured_url, "http://example.test/v1/chat/completions")
	assert_eq(backend.captured_method, HTTPClient.METHOD_POST)
	assert_has(backend.captured_headers, "Content-Type: application/json")
	assert_has(backend.captured_headers, "Authorization: Bearer key-123")
	var payload: Variant = JSON.parse_string(backend.captured_body)
	assert_true(payload is Dictionary)
	assert_eq(String((payload as Dictionary)["grammar"]), 'root ::= "ok"')

	backend.finish(HTTPRequest.RESULT_SUCCESS, 200, _success_body())
	var outcome := await request.wait()
	assert_true(bool(outcome["ok"]))
	var response: Dictionary = outcome["response"]
	assert_eq(String(response["backend"]), "remote-llama")


func test_cancel_reaches_transport_and_late_completion_loses() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var backend := TestRemoteBackend.new(host)
	var request := backend.generate({"message": "hello"})
	var http := backend.pending_http

	request.cancel()
	assert_eq(backend.cancel_calls, 1)
	assert_true(http.is_queued_for_deletion(), "cancelled HTTPRequest must be cleaned up")
	backend.finish(HTTPRequest.RESULT_SUCCESS, 200, _success_body())
	var outcome := await request.wait()
	assert_false(bool(outcome["ok"]))
	assert_true(bool(outcome["cancelled"]))


func test_transport_and_http_failures_map_through_ai_request() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var transport_backend := TestRemoteBackend.new(host)
	var transport_request := transport_backend.generate({"message": "hello"})
	transport_backend.finish(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	var transport_outcome := await transport_request.wait()
	assert_eq(String(transport_outcome["error"]), "transport_error:2")

	var http_backend := TestRemoteBackend.new(host)
	var http_request := http_backend.generate({"message": "hello"})
	http_backend.finish(HTTPRequest.RESULT_SUCCESS, 429, "rate limited".to_utf8_buffer())
	var http_outcome := await http_request.wait()
	assert_eq(String(http_outcome["error"]), "http_error:429")


func test_immediate_start_error_is_still_deferred() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var backend := TestRemoteBackend.new(host)
	backend.start_error = ERR_CANT_CONNECT
	var request := backend.generate({"message": "hello"})
	assert_false(request.is_finished(), "even immediate transport setup errors are deferred")
	var outcome := await request.wait()
	assert_false(bool(outcome["ok"]))
	assert_eq(String(outcome["error"]), "transport_start_error:%d" % ERR_CANT_CONNECT)


func test_orchestrator_owned_failure_aborts_and_cleans_transport() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var backend := TestRemoteBackend.new(host)
	var request := backend.generate({"message": "hello"})
	var http := backend.pending_http

	request.fail("timeout")
	assert_eq(backend.cancel_calls, 1, "external timeout must abort HTTP transport")
	assert_true(http.is_queued_for_deletion(), "timed-out HTTPRequest must be cleaned up")
	var outcome := await request.wait()
	assert_eq(String(outcome["error"]), "timeout")


func _success_body() -> PackedByteArray:
	return FileAccess.get_file_as_string(SUCCESS_FIXTURE).to_utf8_buffer()
