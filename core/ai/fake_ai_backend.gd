class_name FakeAiBackend
extends AiBackend

## Deterministic AI backend that returns predetermined structured responses.
##
## Mandatory per the brief: it lets gameplay development, automated tests and Android
## UI testing run the full orchestration flow without loading a model. Responses can be
## seeded per-intent; an unseeded request falls back to a canned echo response.

var _canned: Dictionary = {}  # intent/key: String -> response: Dictionary


func backend_id() -> String:
	return "fake"


func is_ready() -> bool:
	return true


## Seed a canned response for a given key (e.g. an intent name the test expects).
func set_response(key: String, response: Dictionary) -> void:
	_canned[key] = response


func generate(request: Dictionary) -> Dictionary:
	var key := String(request.get("intent", ""))
	if _canned.has(key):
		return (_canned[key] as Dictionary).duplicate(true)
	# Default deterministic fallback so orchestration has something well-formed to consume.
	return {
		"backend": backend_id(),
		"intent": key,
		"tool_calls": [] as Array,
		"narrative": "The world is quiet. (fake response)",
		"echo": request.duplicate(true),
	}
