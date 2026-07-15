class_name AiOrchestrator
extends RefCounted

## Drives the AI pipeline for a player message, end to end.
##
## Implements a realistic two-turn tool-use loop against the abstract [AiBackend]:
##   guardrails -> classify intent -> build request -> ai.generate (turn 1)
##   -> if the AI asks for tools, run them via [ToolRegistry] and re-call with results
##   (turn 2) -> apply any returned commands through the whitelisted [CommandRegistry] +
##   [CommandBus] -> optionally schedule workflows -> return the narrative.
##
## Safety: the AI never runs code and never mutates state directly. It only names tools
## and commands; unknown/non-whitelisted names are rejected and recorded in the [AiTrace].
##
## Request  -> backend: { message, intent, scope, context, tools[], tool_results[]? }
## Response <- backend: { narrative, tool_calls[], commands[], schedule[]? }

const MAX_MESSAGE_LEN: int = 2000

var _kernel: GameKernel


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


## Handle one player message. Returns:
##   { ok: bool, narrative: String, trace: AiTrace, applied_commands: Array, error: String }
func handle_message(message: String, context: Dictionary = {}) -> Dictionary:
	var trace := AiTrace.new()
	var applied: Array = []

	# 1. Guardrails.
	var guard := _check_guardrails(message)
	trace.add("guardrails", {"ok": guard.success, "message": guard.message})
	if not guard.success:
		return _result(false, guard.message, trace, applied, "guardrails")

	# 2. Intent classification (minimal, deterministic).
	var intent := _classify(message)
	trace.add("classify_intent", {"intent": intent})

	# 3. Build the request for the backend.
	var request := {
		"message": message,
		"intent": intent,
		"scope": _as_dict(context.get("scope", {})),
		"context": _as_dict(context.get("context", {})),
		"tools": _kernel.tools.schemas(),
	}
	trace.add("build_request", {"tools": _kernel.tools.tool_names()})

	# 4. Turn 1.
	var response := _kernel.ai.generate(request)
	trace.add("ai_response", {"turn": 1, "response": response})
	if typeof(response) != TYPE_DICTIONARY or response.is_empty():
		return _result(false, "The game master is silent.", trace, applied, "empty_response")

	# 5. If the AI requested tools, run them and take a second turn with the results.
	var tool_calls: Array = _as_array(response.get("tool_calls", []))
	if not tool_calls.is_empty():
		request["tool_results"] = _run_tools(tool_calls, trace)
		response = _kernel.ai.generate(request)
		trace.add("ai_response", {"turn": 2, "response": response})
		if typeof(response) != TYPE_DICTIONARY:
			return _result(false, "The game master faltered.", trace, applied, "malformed_response")

	# 6. Apply any commands through the whitelist + command bus.
	for c in _as_array(response.get("commands", [])):
		if _apply_command(c, trace):
			applied.append(_as_dict(c).get("name", "?"))

	# 7. Optionally schedule workflows the AI proposed.
	for s in _as_array(response.get("schedule", [])):
		_handle_schedule(s, trace)

	# 8. Narrative.
	var narrative := String(_as_dict(response).get("narrative", ""))
	if narrative.strip_edges().is_empty():
		narrative = "(The world is quiet.)"
	trace.add("narrative", {"text": narrative})

	return _result(true, narrative, trace, applied, "")


# --- pipeline helpers ---

func _check_guardrails(message: String) -> CommandResult:
	if message.strip_edges().is_empty():
		return CommandResult.fail("Say something first.")
	if message.length() > MAX_MESSAGE_LEN:
		return CommandResult.fail("That message is too long.")
	return CommandResult.ok()


## Minimal deterministic intent classifier. Real backends will do this with the model;
## for now a keyword map keeps tests deterministic and selects the FakeAiBackend response.
func _classify(message: String) -> String:
	var lower := message.to_lower()
	for kw in ["forage", "scout", "hunt", "gather", "food"]:
		if lower.contains(kw):
			return "forage"
	return "general"


func _run_tools(tool_calls: Array, trace: AiTrace) -> Array:
	var results: Array = []
	for call_v in tool_calls:
		var call := _as_dict(call_v)
		var name := String(call.get("name", ""))
		var args := _as_dict(call.get("args", {}))
		if not _kernel.tools.has(name):
			trace.add("tool_rejected", {"tool": name, "reason": "unknown tool"})
			continue
		var tool := _kernel.tools.get_tool(name)
		var result := tool.execute(args, _kernel)
		trace.add("tool_executed", {"tool": name, "args": args, "result": result})
		results.append({"name": name, "result": result})
	return results


func _apply_command(command_data: Variant, trace: AiTrace) -> bool:
	var c := _as_dict(command_data)
	var name := String(c.get("name", ""))
	var args := _as_dict(c.get("args", {}))
	if not _kernel.command_registry.has(name):
		trace.add("command_rejected", {"command": name, "reason": "not whitelisted"})
		return false
	var command := _kernel.command_registry.create(name, args)
	if command == null:
		trace.add("command_rejected", {"command": name, "reason": "factory returned null"})
		return false
	var res := _kernel.commands.execute(command)
	trace.add("command_result", {"command": name, "ok": res.success, "message": res.message})
	return res.success


func _handle_schedule(schedule_data: Variant, trace: AiTrace) -> void:
	var s := _as_dict(schedule_data)
	var when := String(s.get("when", ""))
	var wf: Variant = s.get("workflow", null)
	if when != "month_end" or not (wf is Dictionary):
		trace.add("workflow_rejected", {"reason": "unsupported schedule", "when": when})
		return
	var validation := _kernel.workflows.validate_definition(wf, _kernel.workflows.default_capabilities())
	if not validation.success:
		trace.add("workflow_rejected", {"reason": validation.message})
		return
	_kernel.scheduler.schedule_monthly(wf)
	trace.add("workflow_scheduled", {"when": when})


# --- small typed accessors so malformed AI output never crashes the pipeline ---

func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []


func _result(ok: bool, narrative: String, trace: AiTrace, applied: Array, error: String) -> Dictionary:
	return {
		"ok": ok,
		"narrative": narrative,
		"trace": trace,
		"applied_commands": applied,
		"error": error,
	}
