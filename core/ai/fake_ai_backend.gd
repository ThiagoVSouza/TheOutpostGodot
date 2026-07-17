class_name FakeAiBackend
extends AiBackend

## Deterministic AI backend that returns predetermined structured responses.
##
## Mandatory per the brief: it lets gameplay development, automated tests and Android
## UI testing run the full orchestration flow without loading a model. Responses can be
## seeded per-intent; an unseeded request falls back to a canned echo response.

var _canned: Dictionary = {}   # key: String -> response: Dictionary
var _queues: Dictionary = {}   # key: String -> Array[Dictionary] returned in order


func backend_id() -> String:
	return "fake"


func is_ready() -> bool:
	return true


## Seed a single canned response for a key (e.g. a classified intent).
func set_response(key: String, response: Dictionary) -> void:
	_canned[key] = response


## Seed an ordered sequence of responses for a key, returned one per [method generate]
## call with that key. This models a multi-turn tool-use exchange (turn 1 asks to call a
## tool, turn 2 returns commands + narrative) without a real model.
func queue_responses(key: String, responses: Array) -> void:
	_queues[key] = responses.duplicate(true)


## Deferred completion per the D22 contract: the response is decided synchronously
## (deterministic for tests) but delivered on the next main-loop iteration, so the
## fake exercises the same await/cancel paths a real backend does.
func generate(request: Dictionary) -> AiRequest:
	var req := AiRequest.new()
	var response := _build_response(request)
	(func() -> void: req.complete(response)).call_deferred()
	return req


func _build_response(request: Dictionary) -> Dictionary:
	var key := String(request.get("intent", ""))
	# Queued sequence takes precedence so scripted multi-turn exchanges play in order.
	var queue: Array = _queues.get(key, [])
	if not queue.is_empty():
		return (queue.pop_front() as Dictionary).duplicate(true)
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
