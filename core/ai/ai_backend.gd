class_name AiBackend
extends RefCounted

## Abstract interface every AI inference backend implements.
##
## The game depends on this interface, never on a concrete model. Per the brief:
##   AiBackend
##   ├── FakeAiBackend            (mandatory; no model, for gameplay/tests)
##   ├── DesktopLlamaBackend      (llama.cpp on desktop)
##   ├── AndroidLlamaBackend      (native mobile inference)
##   └── FutureAlternativeBackend
##
## Keeping this seam abstract is what lets orchestration and gameplay be developed
## and tested without loading a real model. Concrete backends override [method generate].
##
## Concurrency contract (D22): [method generate] returns an [AiRequest] immediately and
## must NEVER finish it synchronously inside the call — even a backend with an instant
## answer (the fake) defers completion, so reentrancy and cancellation bugs surface in
## tests instead of first appearing against a real model. Backends own their transport
## (HTTP, worker thread) behind the request's cancel hook; the orchestrator owns
## timeouts. A real turn takes 0.85–4 s — nothing here may block the main thread.

## Human-readable id for logging / AI trace (e.g. "fake", "desktop-llama").
func backend_id() -> String:
	return "abstract"


## Whether the backend is ready to serve requests (model loaded, etc.).
func is_ready() -> bool:
	return false


## Start generating a structured response for a request.
##
## [param request] is a Dictionary describing the prompt/context/tools; the eventual
## response is a Dictionary the orchestrator interprets (e.g. tool calls, narrative
## text). Kept as plain dictionaries so recorded/replayed responses serialize trivially.
## Abstract: concrete backends must override and return a live [AiRequest].
func generate(_request: Dictionary) -> AiRequest:
	push_error("AiBackend.generate() called on abstract base; use a concrete backend")
	return AiRequest.make_failed("abstract backend")


## One recovery probe for the T5 availability policy. [param attempt] is 1-based
## within one outage; [AiAvailability] calls this at most three times per outage.
## Same async rule as [method generate]: never finish the request in-call. The base
## implementation reports healthy — correct for [FakeAiBackend], which cannot fail.
func attempt_recovery(_attempt: int) -> AiRequest:
	var probe := AiRequest.new()
	(func() -> void: probe.complete({})).call_deferred()
	return probe
