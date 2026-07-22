class_name AiOrchestrator
extends RefCounted

## The ribosome (D30): fixed, trusted machinery that runs **one authored entry workflow** per
## player turn. It does not decide what a turn does — the entry workflow does (guardrails →
## classify → dispatch → narrate). The only hardcoded thing here is the entry workflow's id.
##
## What stays code (the safety surface): the availability gate (T5), the one-turn-at-a-time
## busy guard, and handing the finished trace to its sink (A1). Everything else — how a turn
## is shaped, which workflow resolves an intent, what the AI is asked — is authored content the
## executor runs. The AI is reached only through the executor's `ai`/`narrate` ops, at points an
## author chose (D4/D30), never by this orchestrator directly.
##
## Concurrency (D22): [method handle_message] is a coroutine — callers await it. A turn runs
## one at a time (busy guard). Per-call timeout and cancel of an in-flight model call live in
## the AI runner/narrator seams and wire in with the real `AiBackend`; they are not this
## orchestrator's job anymore.
##
## Returns: { ok: bool, narrative: String, trace: AiTrace, applied_commands: Array, error: String }

## The one fixed point (D30): the id of the entry workflow. Content registers it; classification
## and dispatch downstream are authored, breaking the bootstrap (classification picks the
## workflow, but classification is itself a step in this workflow).
const ENTRY_WORKFLOW_ID := "orchestration_entry"
const MAX_MESSAGE_LEN: int = 2000

var _kernel: GameKernel
var _busy: bool = false


func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func is_busy() -> bool:
	return _busy


## Cancel is a no-op for now: cancelling an in-flight model call belongs to the AI runner/
## narrator seams (wired with the real backend). Kept so callers and an idle cancel are safe.
func cancel() -> void:
	pass


## Handle one player message (coroutine — await it).
func handle_message(message: String, context: Dictionary = {}) -> Dictionary:
	# T5 gate: while the backend is in an outage, refuse before anything runs — no state
	# change, and never a fabricated reply.
	var availability := _kernel.ai_availability
	if availability != null and availability.is_blocked():
		var t := AiTrace.new()
		t.add("unavailable", {"state": availability.state_name(), "attempt": availability.attempt()})
		var msg := "The game master is unavailable. Use Retry to reconnect."
		if availability.state() == AiAvailability.State.RECOVERING:
			msg = "The game master is reconnecting. Please wait."
		return _result(false, msg, t, [], "unavailable")
	if _busy:
		return _result(false, "The game master is still thinking.", AiTrace.new(), [], "busy")
	_busy = true
	var out: Dictionary = await _run_turn(message, context)
	_busy = false
	return out


func _run_turn(message: String, context: Dictionary) -> Dictionary:
	var trace := AiTrace.new()
	trace.add("turn_started", {"source": String(context.get("source", "")), "message_length": message.length()})
	# Cheap degenerate-input pre-checks; the entry workflow does the real guardrails (D30).
	if message.strip_edges().is_empty():
		trace.add("guardrails", {"ok": false, "reason": "empty"})
		return _result(false, "Say something first.", trace, [], "empty_message")
	if message.length() > MAX_MESSAGE_LEN:
		trace.add("guardrails", {"ok": false, "reason": "too_long"})
		return _result(false, "That message is too long.", trace, [], "guardrails")

	var entry: Variant = _kernel.workflow_registry.get_definition(ENTRY_WORKFLOW_ID)
	if not (entry is Dictionary):
		trace.add("no_entry_workflow", {"id": ENTRY_WORKFLOW_ID})
		return _result(false, "The game master is not configured.", trace, [], "no_entry_workflow")

	var def := entry as Dictionary
	var params := {"message": message, "source": String(context.get("source", ""))}
	var instance := WorkflowInstance.create(ENTRY_WORKFLOW_ID, int(def.get("version", 1)), params, _seed(message))
	var result := await WorkflowExecutor.for_kernel(_kernel).run(def, instance, trace)
	return _finish(result, trace)


## Shape the executor's result into the turn contract. The reply is the workflow's narration.
func _finish(result: RefCounted, trace: AiTrace) -> Dictionary:
	var narrative := String(result.get("narration"))
	if narrative.strip_edges().is_empty():
		narrative = "(The world is quiet.)"
	var applied: Array = result.get("applied_commands")
	match int(result.get("status")):
		WorkflowInstance.Status.COMPLETED:
			return _result(true, narrative, trace, applied, "")
		WorkflowInstance.Status.SUSPENDED:
			# A confirm-pending turn. The instance goes to the store, which owns it until
			# something wakes it (M4/B1) — before this it was dropped, so a workflow that
			# suspended could never be resumed or saved. The reply still stands: the player
			# reads the question the workflow asked, and answers via `resume`.
			var suspended: WorkflowInstance = result.get("instance")
			_kernel.workflow_instances.remember(suspended)
			return _result(true, narrative, trace, applied, "pending_confirmation",
				suspended.instance_id if suspended != null else "")
		_:
			return _result(false, narrative, trace, applied, String(result.get("fail_code")))


## Answer a pending question and resume its instance (M4/B1 — coroutine, await it).
## [param outcome] carries the wake result; for a confirmation, `{confirmed: bool}`.
##
## Goes through the same busy guard and the same `_finish` contract as a fresh turn, because it
## *is* a turn: it applies commands and narrates. The instance is forgotten before it runs, so a
## failed resume cannot leave a question the player has already answered sitting in the store —
## and if the workflow suspends again, `_finish` remembers it anew with a new pending handle.
func resume(instance_id: String, outcome: Dictionary = {}) -> Dictionary:
	if _busy:
		return _result(false, "The game master is still thinking.", AiTrace.new(), [], "busy")

	var instance := _kernel.workflow_instances.get_instance(instance_id)
	if instance == null:
		var missing := AiTrace.new()
		missing.add("resume_unknown_instance", {"instance": instance_id})
		return _result(false, "There is nothing waiting on an answer.", missing, [], "unknown_instance")

	var entry: Variant = _kernel.workflow_registry.get_definition(instance.workflow_id)
	if not (entry is Dictionary):
		# The workflow the save was made against is gone (a module removed or renamed it).
		# Drop the instance rather than stranding an unanswerable question in every future save.
		_kernel.workflow_instances.forget(instance_id)
		var gone := AiTrace.new()
		gone.add("resume_unknown_workflow", {"workflow": instance.workflow_id, "instance": instance_id})
		return _result(false, "That course of action is no longer available.", gone, [], "unknown_workflow")

	_busy = true
	var trace := AiTrace.new()
	trace.add("turn_resumed", {"instance": instance_id, "workflow": instance.workflow_id,
		"wake": instance.wake.duplicate(true), "outcome": outcome.duplicate(true)})
	_kernel.workflow_instances.forget(instance_id)
	var result := await WorkflowExecutor.for_kernel(_kernel).resume(
		entry as Dictionary, instance, outcome, trace)
	var out: Dictionary = _finish(result, trace)
	_busy = false
	return out


func _seed(message: String) -> int:
	return hash(message)


## Every return path funnels through here, so this is the one place that hands the finished
## trace to its sink (A1, D21). No-op when the kernel has no writer, or the writer is disabled.
func _result(ok: bool, narrative: String, trace: AiTrace, applied: Array, error: String,
		pending_instance: String = "") -> Dictionary:
	if _kernel != null and _kernel.trace_writer != null:
		_kernel.trace_writer.write(trace)
	return {
		"ok": ok,
		"narrative": narrative,
		"trace": trace,
		"applied_commands": applied,
		"error": error,
		# The handle a caller answers a pending question with; empty on every other turn.
		"pending_instance": pending_instance,
	}
