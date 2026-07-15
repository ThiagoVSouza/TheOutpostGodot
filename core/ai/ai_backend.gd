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

## Human-readable id for logging / AI trace (e.g. "fake", "desktop-llama").
func backend_id() -> String:
	return "abstract"


## Whether the backend is ready to serve requests (model loaded, etc.).
func is_ready() -> bool:
	return false


## Produce a structured response for a request.
##
## [param request] is a Dictionary describing the prompt/context/tools; the return is
## a Dictionary the orchestrator interprets (e.g. tool calls, narrative text). Kept as
## plain dictionaries so recorded/replayed responses serialize trivially. Abstract:
## concrete backends must override.
func generate(_request: Dictionary) -> Dictionary:
	push_error("AiBackend.generate() called on abstract base; use a concrete backend")
	return {}
