class_name RemoteLlamaBackend
extends AiBackend

## Non-blocking HTTP client for llama.cpp's `/v1/chat/completions` endpoint.
##
## T2 deliberately buffers complete responses through HTTPRequest. Token streaming can
## later replace the transport without changing AiRequest or the orchestrator. The
## orchestrator owns timeouts; this backend owns request cancellation and Node cleanup.

const DEFAULT_ENDPOINT := "http://127.0.0.1:8099/v1/chat/completions"
const RESPONSE_BODY_LIMIT: int = 2 * 1024 * 1024

var endpoint_url: String
var api_key: String
var temperature: float
var max_tokens: int

var _host: Node


func _init(
	host: Node,
	endpoint: String = DEFAULT_ENDPOINT,
	key: String = "",
	default_temperature: float = LlamaChatCodec.DEFAULT_TEMPERATURE,
	default_max_tokens: int = LlamaChatCodec.DEFAULT_MAX_TOKENS
) -> void:
	_host = host
	endpoint_url = endpoint
	api_key = key
	temperature = default_temperature
	max_tokens = default_max_tokens


func backend_id() -> String:
	return "remote-llama"


func is_ready() -> bool:
	return is_instance_valid(_host) and _host.is_inside_tree() and not endpoint_url.is_empty()


func generate(request: Dictionary) -> AiRequest:
	var ai_request := AiRequest.new()
	if not is_ready():
		_defer_failure(ai_request, "backend_not_ready")
		return ai_request

	var http_request := HTTPRequest.new()
	http_request.body_size_limit = RESPONSE_BODY_LIMIT
	_host.add_child(http_request)

	http_request.request_completed.connect(
		func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			_on_http_completed(ai_request, http_request, result, response_code, headers, body),
		CONNECT_ONE_SHOT
	)
	ai_request.set_cancel_hook(func() -> void: _cancel_and_free(http_request))
	# The orchestrator owns timeouts and expresses them by failing AiRequest directly.
	# Observe every external failure as well as explicit cancel(), so the HTTP transport
	# never survives a terminal request.
	ai_request.failed.connect(func(_error: String) -> void: _cancel_and_free(http_request))

	var headers := PackedStringArray(["Content-Type: application/json"])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer %s" % api_key)
	var payload := LlamaChatCodec.build_payload(request, temperature, max_tokens)
	var body := JSON.stringify(payload)
	var start_error := _start_http_request(
		http_request, endpoint_url, headers, HTTPClient.METHOD_POST, body
	)
	if start_error != OK:
		_free_http_request(http_request)
		_defer_failure(ai_request, "transport_start_error:%d" % start_error)
	return ai_request


## Overridable seams used by tests to drive completion and observe cancellation without
## opening a socket. Production always delegates to HTTPRequest.
func _start_http_request(
	http_request: HTTPRequest,
	url: String,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	body: String
) -> Error:
	return http_request.request(url, headers, method, body)


func _cancel_http_request(http_request: HTTPRequest) -> void:
	http_request.cancel_request()


func _on_http_completed(
	ai_request: AiRequest,
	http_request: HTTPRequest,
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_free_http_request(http_request)
	if ai_request.is_finished():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		ai_request.fail(LlamaChatCodec.transport_error(result))
		return

	var parsed := LlamaChatCodec.parse_response(response_code, body)
	if not bool(parsed.get("ok", false)):
		ai_request.fail(String(parsed.get("error", "invalid_response")))
		return
	var response: Dictionary = parsed.get("response", {})
	response["backend"] = backend_id()
	ai_request.complete(response)


func _cancel_and_free(http_request: HTTPRequest) -> void:
	if not is_instance_valid(http_request) or http_request.is_queued_for_deletion():
		return
	_cancel_http_request(http_request)
	_free_http_request(http_request)


func _free_http_request(http_request: HTTPRequest) -> void:
	if is_instance_valid(http_request) and not http_request.is_queued_for_deletion():
		http_request.queue_free()


func _defer_failure(ai_request: AiRequest, error: String) -> void:
	(func() -> void: ai_request.fail(error)).call_deferred()
