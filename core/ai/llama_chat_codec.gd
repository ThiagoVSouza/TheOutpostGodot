class_name LlamaChatCodec
extends RefCounted

## Pure request/response codec for llama.cpp's OpenAI-compatible chat endpoint.
##
## Keeping JSON shaping and validation free of transport state makes malformed and
## recorded server responses testable without a live model. RemoteLlamaBackend owns
## HTTP lifecycle; this class only translates between the game's Dictionary contract
## and `/v1/chat/completions`.

const DEFAULT_TEMPERATURE: float = 0.7
const DEFAULT_MAX_TOKENS: int = 128


static func build_payload(
	request: Dictionary,
	default_temperature: float = DEFAULT_TEMPERATURE,
	default_max_tokens: int = DEFAULT_MAX_TOKENS
) -> Dictionary:
	var messages: Array = _as_array(request.get("messages", []))
	if messages.is_empty():
		var message := String(request.get("message", ""))
		messages = [{"role": "user", "content": message}]

	var temperature := float(request.get("temperature", default_temperature))
	var max_tokens := maxi(1, int(request.get("max_tokens", default_max_tokens)))
	var payload := {
		"messages": messages.duplicate(true),
		"temperature": temperature,
		"max_tokens": max_tokens,
		"cache_prompt": true,
		"stream": false,
	}

	var grammar := String(request.get("grammar", ""))
	if not grammar.is_empty():
		payload["grammar"] = grammar
	return payload


## Parse a completed HTTP response into:
##   { ok: bool, response: Dictionary, error: String }
##
## The response intentionally exposes both `content` (for M3's future constrained
## pipe parser) and `narrative` (for the current M2 orchestrator). OpenAI tool calls
## are not forwarded: D20 retired that as an AI-facing output path.
static func parse_response(response_code: int, body: PackedByteArray) -> Dictionary:
	if response_code < 200 or response_code >= 300:
		return _failure("http_error:%d" % response_code)

	var json := JSON.new()
	var parse_error := json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		return _failure("invalid_json")
	var decoded: Variant = json.data
	if not decoded is Dictionary:
		return _failure("invalid_response")

	var root := decoded as Dictionary
	var choices: Array = _as_array(root.get("choices", []))
	if choices.is_empty() or not choices[0] is Dictionary:
		return _failure("invalid_response")
	var choice := choices[0] as Dictionary
	var message: Variant = choice.get("message", null)
	if not message is Dictionary:
		return _failure("invalid_response")
	var message_dict := message as Dictionary
	var content: Variant = message_dict.get("content", null)
	if not content is String:
		return _failure("invalid_response")
	var response_text := String(content)
	if response_text.strip_edges().is_empty():
		return _failure("empty_content")

	var response := {
		"content": response_text,
		"narrative": response_text,
		"tool_calls": [] as Array,
		"finish_reason": String(choice.get("finish_reason", "")),
		"timings": _parse_timings(root.get("timings", {})),
	}
	return {"ok": true, "response": response, "error": ""}


static func transport_error(result: int) -> String:
	return "transport_error:%d" % result


static func _parse_timings(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source := value as Dictionary
	var timings := {}
	for key in ["prompt_n", "prompt_ms", "predicted_n", "predicted_ms"]:
		var timing: Variant = source.get(key, null)
		if timing is int or timing is float:
			timings[key] = timing
	return timings


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "response": {}, "error": error}
