class_name AiInputRouter
extends RefCounted

## Routes player text from any [AiInputSource] into the AI orchestrator (D18).
##
## The chat screen, future voice capture, and future trace replay are all just
## sources: they submit text here, the router drives one orchestration, and the
## outcome — success, busy rejection, or failure — is broadcast on the event bus as
## [constant EVENT_TURN_COMPLETED] with the originating source id. UI renders
## replies from that event, so no input path is coupled to the orchestrator.

const EVENT_TURN_COMPLETED := "ai_turn_completed"

var _kernel: GameKernel


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func create_source(source_id: String) -> AiInputSource:
	return AiInputSource.new(source_id, self)


## Submit one message on behalf of a source. The orchestration runs as its own
## coroutine; 4.7 rejects an unawaited coroutine call, so the lambda-call pattern
## makes the fire-and-forget explicit.
func submit(source_id: String, text: String, metadata: Dictionary = {}) -> void:
	var context := metadata.duplicate()
	context["source"] = source_id
	var run := func() -> void:
		var result: Dictionary = await _kernel.ai_orchestrator.handle_message(text, context)
		_kernel.events.emit(EVENT_TURN_COMPLETED, {
			"source_id": source_id,
			"text": text,
			"result": result,
		})
	run.call()
