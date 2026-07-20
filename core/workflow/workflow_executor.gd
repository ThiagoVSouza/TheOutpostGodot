class_name WorkflowExecutor
extends RefCounted

## Runs a validated workflow definition against a [WorkflowInstance] and the kernel's seams
## (A3). It walks the op-tree with an **explicit control stack** rather than native recursion,
## precisely so a suspension's resume point can serialize as a stack of indices (D25) instead
## of an un-serializable GDScript call stack.
##
## Effects go only through the vetted seams: mutations via [CommandBus] (the D4 choke point),
## events via [EventBus], globals via [GlobalStore] (D31, recorded in the trace). Expressions
## are evaluated purely through a [WorkflowRuntimeContext]. Failure is fail-fast with a typed
## `fail_code` (§4).
##
## Scope of this build (A3.1): full execution to completion — require/let/roll/if/foreach/
## for/break/run_command/emit/set_global/run. It *detects* a suspension op (wait_game_time /
## confirm) and captures the wake + instance state, but resume-from-snapshot (the `pc_stack`
## encoding, an open §12 detail) is A3.2.

const MAX_RUN_DEPTH: int = 16

## What executing one statement asks the run loop to do next.
enum Action { CONTINUE, PUSH, BREAK, FAIL, SUSPEND }


class Frame:
	extends RefCounted
	var block: Array
	var pc: int = 0
	var loop: LoopState = null
	# How this frame was reached from its parent, so the resume point can serialize and
	# rebuild (A3.2): `sel` = "root"|"then"|"else"|"elif:N"|"body"; `at` = the parent
	# control statement's index in the parent block.
	var sel: String = "root"
	var at: int = -1

	func _init(b: Array) -> void:
		block = b


class LoopState:
	extends RefCounted
	var var_name: String
	var index_name: String  # "" when the loop has no index binding (a `for`)
	var values: Array
	var pos: int = 0


class RunResult:
	extends RefCounted
	var status: WorkflowInstance.Status
	var fail_code: String = ""
	var fail_msg: String = ""
	var emits: Array = []              # [{type, msg, values}]
	var applied_commands: Array = []
	var wake: Dictionary = {}          # set when SUSPENDED
	var instance: WorkflowInstance

	func succeeded() -> bool:
		return status == WorkflowInstance.Status.COMPLETED


var _state: GameState
var _command_registry: CommandRegistry
var _commands: CommandBus
var _events: EventBus
var _globals: GlobalStore
var _functions: DslFunctionRegistry
var _tables: DslTableRegistry
var _workflows: WorkflowRegistry


func _init(state: GameState, command_registry: CommandRegistry, commands: CommandBus,
		events: EventBus, globals: GlobalStore, functions: DslFunctionRegistry,
		tables: DslTableRegistry, workflows: WorkflowRegistry = null) -> void:
	_state = state
	_command_registry = command_registry
	_commands = commands
	_events = events
	_globals = globals
	_functions = functions
	_tables = tables
	_workflows = workflows


## Convenience constructor from a booted kernel.
static func for_kernel(kernel: GameKernel) -> WorkflowExecutor:
	return WorkflowExecutor.new(kernel.state, kernel.command_registry, kernel.commands,
		kernel.events, kernel.globals, kernel.dsl_functions, kernel.dsl_tables,
		kernel.workflow_registry)


## Run [param instance] against [param definition] (a validated `steps` tree). [param trace]
## is optional; when present each effect is recorded for A1's trace.
func run(definition: Dictionary, instance: WorkflowInstance, trace: AiTrace = null, depth: int = 0) -> RunResult:
	var result := RunResult.new()
	result.instance = instance
	if depth > MAX_RUN_DEPTH:
		return _fail(result, instance, "recursion_limit", "sub-workflow depth exceeded")
	if trace != null:
		trace.add("workflow_started", {"workflow": instance.workflow_id, "instance": instance.instance_id})
	var stack: Array = [Frame.new(definition.get("steps", []) as Array)]
	return _execute(stack, definition, instance, result, trace, depth)


## Resume a suspended instance (D25/§5.3). [param outcome] carries the wake result — for a
## confirmation, `{confirmed: bool}`. Re-proves `resume_require` against live state *first*
## (the snapshot was for planning; live state gets the last word), then rebuilds the control
## stack from `pc_stack` and continues exactly where it left off.
func resume(definition: Dictionary, instance: WorkflowInstance, outcome: Dictionary = {}, trace: AiTrace = null, depth: int = 0) -> RunResult:
	var result := RunResult.new()
	result.instance = instance

	# A declined confirmation cancels the action outright — zero further commands (the
	# destructive command sits *after* the confirm, so nothing has been applied).
	if String(instance.wake.get("type", "")) == "confirmation" and not bool(outcome.get("confirmed", true)):
		return _fail(result, instance, "cancelled", "player declined the confirmation", trace)

	var ctx := WorkflowRuntimeContext.new(instance.params, instance.locals, _state,
		_globals, _functions, _tables)
	for rr in instance.resume_require:
		var cond: Variant = (rr as Dictionary).get("cond", null)
		if not DslExpressionEvaluator.truthy(_eval(cond, ctx)):
			return _fail(result, instance, String((rr as Dictionary).get("fail_code", "stale_context")),
				"a resume precondition no longer holds", trace)

	instance.status = WorkflowInstance.Status.RUNNING
	if trace != null:
		trace.add("workflow_resumed", {"instance": instance.instance_id})
	return _execute(_rebuild_stack(definition, instance), definition, instance, result, trace, depth)


## The shared run loop, over an explicit control stack — driven fresh by [method run] or from
## a rebuilt stack by [method resume].
func _execute(stack: Array, definition: Dictionary, instance: WorkflowInstance, result: RunResult, trace: AiTrace, depth: int) -> RunResult:
	var ctx := WorkflowRuntimeContext.new(instance.params, instance.locals, _state,
		_globals, _functions, _tables)
	while not stack.is_empty():
		var frame: Frame = stack.back()
		if frame.pc >= frame.block.size():
			if frame.loop != null and _advance_loop(frame, instance):
				continue
			stack.pop_back()
			continue
		var stmt: Dictionary = frame.block[frame.pc]
		frame.pc += 1
		var outcome := _exec_statement(stmt, instance, ctx, result, trace, depth)
		match int(outcome["action"]):
			Action.CONTINUE:
				pass
			Action.PUSH:
				var pushed: Frame = outcome["frame"]
				pushed.at = frame.pc - 1  # the control statement that opened this child block
				stack.push_back(pushed)
			Action.BREAK:
				_break_loop(stack, instance)
			Action.FAIL:
				return _fail(result, instance, String(outcome["fail_code"]), String(outcome.get("fail_msg", "")), trace)
			Action.SUSPEND:
				instance.pc_stack = _capture_pc_stack(stack)
				instance.resume_require = _as_array(outcome.get("resume_require", []))
				return _suspend(result, instance, outcome["wake"], trace)

	instance.status = WorkflowInstance.Status.COMPLETED
	instance.pc_stack = []
	if trace != null:
		trace.add("workflow_completed", {"instance": instance.instance_id})
	result.status = WorkflowInstance.Status.COMPLETED
	return result


# --- statement dispatch ---

func _exec_statement(stmt: Dictionary, instance: WorkflowInstance, ctx: WorkflowRuntimeContext,
		result: RunResult, trace: AiTrace, depth: int) -> Dictionary:
	var op := String(stmt["op"])
	match op:
		"let":
			instance.locals[_local_name(stmt["as"])] = _eval(stmt.get("value", null), ctx)
			return {"action": Action.CONTINUE}
		"require":
			if not DslExpressionEvaluator.truthy(_eval(stmt.get("cond", null), ctx)):
				if trace != null:
					trace.add("workflow_require_failed", {"fail_code": stmt.get("fail_code", "")})
				return {"action": Action.FAIL, "fail_code": stmt.get("fail_code", "precondition_failed"),
					"fail_msg": stmt.get("fail_msg", "")}
			return {"action": Action.CONTINUE}
		"roll":
			instance.locals[_local_name(stmt["as"])] = _roll(String(stmt["dice"]), instance)
			return {"action": Action.CONTINUE}
		"set_global":
			var gname := String(stmt["name"])
			var gval: Variant = _eval(stmt.get("value", null), ctx)
			_globals.set_value(gname, gval)
			if trace != null:
				trace.add("workflow_global_set", {"name": gname, "value": gval})
			if _events != null:
				_events.emit("workflow_global_set", {"name": gname, "value": gval})
			return {"action": Action.CONTINUE}
		"run_command":
			return _exec_run_command(stmt, ctx, result, instance, trace)
		"emit":
			return _exec_emit(stmt, ctx, result, trace)
		"if":
			return _exec_if(stmt, ctx)
		"foreach":
			return _exec_foreach(stmt, ctx, instance)
		"for":
			return _exec_for(stmt, instance)
		"break":
			return {"action": Action.BREAK}
		"run":
			return _exec_run(stmt, ctx, result, trace, depth)
		"wait_game_time":
			return {"action": Action.SUSPEND,
				"wake": {"type": "game_time", "at_day": _eval(stmt.get("until_day", null), ctx)},
				"resume_require": stmt.get("resume_require", [])}
		"confirm":
			return {"action": Action.SUSPEND,
				"wake": {"type": "confirmation", "scope": stmt.get("scope", {}),
					"msg": stmt.get("msg", "")},
				"resume_require": stmt.get("resume_require", [])}
	return {"action": Action.FAIL, "fail_code": "unknown_op", "fail_msg": "unhandled op \"%s\"" % op}


func _exec_run_command(stmt: Dictionary, ctx: WorkflowRuntimeContext, result: RunResult,
		instance: WorkflowInstance, trace: AiTrace) -> Dictionary:
	var name := String(stmt["name"])
	var args := _eval_args(stmt.get("args", {}), ctx)
	if not _command_registry.has(name):
		return {"action": Action.FAIL, "fail_code": "unknown_command",
			"fail_msg": "workflow named a non-whitelisted command \"%s\"" % name}
	var command := _command_registry.create(name, args)
	if command == null:
		return {"action": Action.FAIL, "fail_code": "unknown_command",
			"fail_msg": "command factory returned null for \"%s\"" % name}
	var res := _commands.execute(command)
	var ledger := {"name": name, "status": "ok" if res.success else "failed"}
	instance.applied_commands.append(ledger)
	result.applied_commands.append(name)
	if trace != null:
		trace.add("workflow_command", {"command": name, "ok": res.success, "message": res.message})
	if not res.success:
		return {"action": Action.FAIL, "fail_code": "command_failed", "fail_msg": res.message}
	return {"action": Action.CONTINUE}


func _exec_emit(stmt: Dictionary, ctx: WorkflowRuntimeContext, result: RunResult, trace: AiTrace) -> Dictionary:
	var record := {"type": String(stmt.get("type", "")), "msg": String(stmt["msg"]),
		"values": _eval_args(stmt.get("values", {}), ctx)}
	result.emits.append(record)
	if _events != null:
		_events.emit("workflow_emit", record)
	if trace != null:
		trace.add("workflow_emit", record)
	return {"action": Action.CONTINUE}


func _exec_if(stmt: Dictionary, ctx: WorkflowRuntimeContext) -> Dictionary:
	if DslExpressionEvaluator.truthy(_eval(stmt.get("cond", null), ctx)):
		return {"action": Action.PUSH, "frame": _branch_frame(stmt.get("then", []) as Array, "then")}
	var branches := _as_array(stmt.get("elif", []))
	for k in branches.size():
		if DslExpressionEvaluator.truthy(_eval((branches[k] as Dictionary).get("cond", null), ctx)):
			return {"action": Action.PUSH,
				"frame": _branch_frame((branches[k] as Dictionary).get("then", []) as Array, "elif:%d" % k)}
	if stmt.has("else"):
		return {"action": Action.PUSH, "frame": _branch_frame(stmt["else"] as Array, "else")}
	return {"action": Action.CONTINUE}


func _branch_frame(block: Array, sel: String) -> Frame:
	var f := Frame.new(block)
	f.sel = sel
	return f


func _exec_foreach(stmt: Dictionary, ctx: WorkflowRuntimeContext, instance: WorkflowInstance) -> Dictionary:
	var src: Variant = _eval(stmt.get("source", null), ctx)
	var values: Array = []
	if src is Array:
		values = (src as Array).duplicate()
	elif src is Dictionary:
		values = (src as Dictionary).keys()
	else:
		return {"action": Action.FAIL, "fail_code": "not_iterable", "fail_msg": "foreach source is not a collection"}
	if values.is_empty():
		return {"action": Action.CONTINUE}
	return _start_loop(stmt.get("body", []) as Array, _local_name(stmt["as"]),
		_local_name(stmt.get("index", "")), values, instance)


func _exec_for(stmt: Dictionary, instance: WorkflowInstance) -> Dictionary:
	# Half-open [from, to): `for from 0 to 3` binds 0, 1, 2 — matches array/index semantics.
	var lo := int(stmt["from"])
	var hi := int(stmt["to"])
	var values: Array = []
	for n in range(lo, hi):
		values.append(n)
	if values.is_empty():
		return {"action": Action.CONTINUE}
	return _start_loop(stmt.get("body", []) as Array, _local_name(stmt["as"]), "", values, instance)


func _exec_run(stmt: Dictionary, ctx: WorkflowRuntimeContext, result: RunResult, trace: AiTrace, depth: int) -> Dictionary:
	if _workflows == null:
		return {"action": Action.FAIL, "fail_code": "no_registry", "fail_msg": "no workflow registry for `run`"}
	var ref := String(stmt["workflow"])
	var child_def: Variant = _workflows.get_definition(ref)
	if not (child_def is Dictionary):
		return {"action": Action.FAIL, "fail_code": "unknown_workflow", "fail_msg": "no workflow \"%s\"" % ref}
	var def := child_def as Dictionary
	var child := WorkflowInstance.create(String(def["id"]), int(def["version"]),
		_eval_args(stmt.get("args", {}), ctx), _child_seed(ctx))
	var child_result := run(def, child, trace, depth + 1)
	# Merge the child's observable effects into the parent's tally.
	for c in child_result.applied_commands:
		result.applied_commands.append(c)
	for e in child_result.emits:
		result.emits.append(e)
	match child_result.status:
		WorkflowInstance.Status.COMPLETED:
			return {"action": Action.CONTINUE}
		WorkflowInstance.Status.SUSPENDED:
			# Nested suspension makes the parent suspend too — that lands with resume (A3.2).
			return {"action": Action.FAIL, "fail_code": "nested_suspension_unsupported",
				"fail_msg": "sub-workflow \"%s\" suspended" % ref}
	return {"action": Action.FAIL, "fail_code": child_result.fail_code, "fail_msg": child_result.fail_msg}


# --- loop plumbing ---

func _start_loop(body: Array, var_name: String, index_name: String, values: Array, instance: WorkflowInstance) -> Dictionary:
	var loop := LoopState.new()
	loop.var_name = var_name
	loop.index_name = index_name
	loop.values = values
	loop.pos = 0
	var frame := Frame.new(body)
	frame.sel = "body"
	frame.loop = loop
	_bind_loop(loop, instance)
	return {"action": Action.PUSH, "frame": frame}


func _advance_loop(frame: Frame, instance: WorkflowInstance) -> bool:
	frame.loop.pos += 1
	if frame.loop.pos < frame.loop.values.size():
		frame.pc = 0
		_bind_loop(frame.loop, instance)
		return true
	_unbind_loop(frame.loop, instance)
	return false


func _bind_loop(loop: LoopState, instance: WorkflowInstance) -> void:
	instance.locals[loop.var_name] = loop.values[loop.pos]
	if not loop.index_name.is_empty():
		instance.locals[loop.index_name] = loop.pos


## Loop item/index are loop-scoped (§4): drop them when the loop ends so they don't linger
## in the flat locals after the loop.
func _unbind_loop(loop: LoopState, instance: WorkflowInstance) -> void:
	instance.locals.erase(loop.var_name)
	if not loop.index_name.is_empty():
		instance.locals.erase(loop.index_name)


# --- suspend/resume: serialize and rebuild the control stack (A3.2) ---

## Serialize the live control stack into the structured pc_stack (one descriptor per frame,
## outermost first). Loop frames carry their remaining values + position so a resumed loop
## advances deterministically without re-evaluating its source against changed state.
func _capture_pc_stack(stack: Array) -> Array:
	var out: Array = []
	for f in stack:
		var frame: Frame = f
		var d: Dictionary = {"sel": frame.sel, "at": frame.at, "pc": frame.pc}
		if frame.loop != null:
			d["loop"] = {"var": frame.loop.var_name, "index": frame.loop.index_name,
				"values": frame.loop.values.duplicate(true), "pos": frame.loop.pos}
		out.append(d)
	return out


## Rebuild the control stack from a pc_stack by re-walking the definition tree, descending
## into the recorded child block at each level. Loop frames restore their iteration state; the
## loop variable itself is already in `instance.locals` (persisted in the snapshot).
func _rebuild_stack(definition: Dictionary, instance: WorkflowInstance) -> Array:
	var stack: Array = []
	var block: Array = definition.get("steps", []) as Array
	for k in instance.pc_stack.size():
		var d: Dictionary = instance.pc_stack[k]
		var frame: Frame
		if k == 0:
			frame = Frame.new(block)
		else:
			var ctrl: Dictionary = block[int(d["at"])]
			block = _select_block(ctrl, String(d["sel"]))
			frame = Frame.new(block)
			frame.sel = String(d["sel"])
			frame.at = int(d["at"])
			if d.has("loop"):
				var ld: Dictionary = d["loop"]
				var loop := LoopState.new()
				loop.var_name = String(ld["var"])
				loop.index_name = String(ld["index"])
				loop.values = ld["values"] as Array
				loop.pos = int(ld["pos"])
				frame.loop = loop
		frame.pc = int(d["pc"])
		stack.append(frame)
	return stack


## The child block a control statement exposes under a given selector.
func _select_block(ctrl: Dictionary, sel: String) -> Array:
	if sel == "then":
		return ctrl.get("then", []) as Array
	if sel == "else":
		return ctrl.get("else", []) as Array
	if sel == "body":
		return ctrl.get("body", []) as Array
	if sel.begins_with("elif:"):
		var n := int(sel.substr(5))
		return ((ctrl["elif"] as Array)[n] as Dictionary).get("then", []) as Array
	return []


## `break`: pop inner frames up to and including the nearest enclosing loop, unbinding it.
func _break_loop(stack: Array, instance: WorkflowInstance) -> void:
	while not stack.is_empty():
		var frame: Frame = stack.back()
		stack.pop_back()
		if frame.loop != null:
			_unbind_loop(frame.loop, instance)
			return


# --- helpers ---

func _eval(node: Variant, ctx: WorkflowRuntimeContext) -> Variant:
	return DslExpressionEvaluator.evaluate(node, ctx)


func _eval_args(args_v: Variant, ctx: WorkflowRuntimeContext) -> Dictionary:
	var out: Dictionary = {}
	if args_v is Dictionary:
		for k in (args_v as Dictionary):
			out[k] = _eval((args_v as Dictionary)[k], ctx)
	return out


## A `$$name` reference reduced to its bare name. Loop `index` may be absent -> "".
func _local_name(ref_v: Variant) -> String:
	var s := String(ref_v)
	if s.is_empty():
		return ""
	var c := DslRef.classify(s)
	return String(c.get("name", ""))


func _roll(dice: String, instance: WorkflowInstance) -> int:
	var parts := dice.to_lower().split("d")
	var count := int(parts[0]) if parts.size() > 0 and not parts[0].is_empty() else 1
	var sides := int(parts[1]) if parts.size() > 1 else 6
	if sides < 1:
		sides = 1
	# The k-th roll derives from (seed, roll_count): deterministic, and resume-safe because
	# only roll_count needs storing — no RNG state blob.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d" % [instance.seed, instance.roll_count])
	instance.roll_count += 1
	var total := 0
	for _i in maxi(count, 0):
		total += rng.randi_range(1, sides)
	return total


func _child_seed(_ctx: WorkflowRuntimeContext) -> int:
	return int(Time.get_ticks_usec())


func _as_array(v: Variant) -> Array:
	return v as Array if v is Array else []


func _fail(result: RunResult, instance: WorkflowInstance, code: String, msg: String, trace: AiTrace = null) -> RunResult:
	instance.status = WorkflowInstance.Status.FAILED
	instance.fail_code = code
	result.status = WorkflowInstance.Status.FAILED
	result.fail_code = code
	result.fail_msg = msg
	if trace != null:
		trace.add("workflow_failed", {"instance": instance.instance_id, "fail_code": code, "message": msg})
	return result


func _suspend(result: RunResult, instance: WorkflowInstance, wake: Variant, trace: AiTrace) -> RunResult:
	instance.status = WorkflowInstance.Status.SUSPENDED
	instance.wake = wake as Dictionary
	result.status = WorkflowInstance.Status.SUSPENDED
	result.wake = wake as Dictionary
	if trace != null:
		trace.add("workflow_suspended", {"instance": instance.instance_id, "wake": wake})
	return result
