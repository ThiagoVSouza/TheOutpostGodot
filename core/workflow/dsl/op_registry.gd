class_name OpRegistry
extends RefCounted

## The DSL's *vocabulary* (D24/D27): the leaf ops a workflow may name, each declaring a
## single source of truth for its purity, where it may appear, and the shape of its fields.
## The validator reads these to enforce the purity discipline structurally, and D19 grammar
## generation will later read the same [member OpSpec.pure] flag — one flag, two consumers,
## never forked.
##
## What is NOT here: the DSL's *grammar* — the `workflow` envelope, control flow
## (`if`/`foreach`/`for`/`break`), and the binding statements `let`/`require`. That is fixed
## machinery the validator hardcodes (D27: authors get vocabulary, not grammar), so a
## component can add a `map.move_unit` command (named via `run_command`) but can never add a
## new control construct. Components extend this registry; they never extend the grammar.


## One op's contract. [member pure] is the D24 flag; [member expression]/[member statement]
## say which positions the op may legally appear in. The `*_fields` arrays tell the validator
## how to check each field without hardcoding per-op knowledge:
##   [member expr_fields]      each holds one expression        (e.g. get.key, set_global.value)
##   [member args_fields]      each holds a dict of expressions (e.g. fn.args, run_command.args)
##   [member literal_fields]   each must be a plain literal string, never a sigil/expression
##                             (e.g. fn.name — you may not compute which function to call)
##   [member local_ref_fields] each must be a "$$name" local reference (e.g. roll.as)
class OpSpec:
	extends RefCounted
	var name: String
	var pure: bool
	var expression: bool  # may appear in an expression position (as an op-object)
	var statement: bool    # may appear as a statement (an entry of a steps/then/else array)
	var required_fields: PackedStringArray
	var expr_fields: PackedStringArray
	var args_fields: PackedStringArray
	var literal_fields: PackedStringArray
	var local_ref_fields: PackedStringArray

	func _init(op_name: String, is_pure: bool, is_expression: bool, is_statement: bool,
			required: PackedStringArray = PackedStringArray()) -> void:
		name = op_name
		pure = is_pure
		expression = is_expression
		statement = is_statement
		required_fields = required


var _ops: Dictionary = {}  # name -> OpSpec


## A registry seeded with the core M3a vocabulary. Components add to it later.
static func with_core() -> OpRegistry:
	var r := OpRegistry.new()
	r._seed_core()
	return r


## Register (or, deliberately, replace) an op. Returns false on an obviously malformed
## spec so a mistaken registration fails loudly at startup, not at first execution.
func register(spec: OpSpec) -> bool:
	if spec == null or spec.name.is_empty():
		return false
	if not spec.expression and not spec.statement:
		return false  # an op reachable from nowhere is a registration bug
	if spec.expression and not spec.pure:
		return false  # the purity discipline: expression-position ops must be pure
	_ops[spec.name] = spec
	return true


func has(op_name: String) -> bool:
	return _ops.has(op_name)


func get_spec(op_name: String) -> OpSpec:
	return _ops.get(op_name, null)


func op_names() -> PackedStringArray:
	var names := PackedStringArray()
	for k in _ops:
		names.append(k)
	names.sort()
	return names


## The core vocabulary. Pure expression ops first, then effectful statement ops.
func _seed_core() -> void:
	# --- pure, expression-position ops ---
	var read_state := OpSpec.new("read_state", true, true, false, PackedStringArray(["path"]))
	# `path` is an array of expression segments — validated specially (a sigil segment
	# resolves, a bare string stays a literal key), so it is not a plain expr_field.
	register(read_state)

	var fn := OpSpec.new("fn", true, true, false, PackedStringArray(["name"]))
	fn.literal_fields = PackedStringArray(["name"])
	fn.args_fields = PackedStringArray(["args"])
	register(fn)

	var table_get := OpSpec.new("table_get", true, true, false, PackedStringArray(["table", "key"]))
	table_get.literal_fields = PackedStringArray(["table"])
	table_get.expr_fields = PackedStringArray(["key"])
	register(table_get)

	# Nested access into a dict/array value (replaces dotted sigils; A2 syntax review).
	var get := OpSpec.new("get", true, true, false, PackedStringArray(["from", "key"]))
	get.expr_fields = PackedStringArray(["from", "key"])
	register(get)

	# Read a global variable (D31): non-authoritative shared scratch; the read side is pure.
	var get_global := OpSpec.new("get_global", true, true, false, PackedStringArray(["name"]))
	get_global.literal_fields = PackedStringArray(["name"])
	register(get_global)

	# --- effectful, statement-position ops ---
	# Write a global (D31): capability-gated, recorded in the trace. Never the source of an
	# authoritative game number — that stays behind run_command (D4 intact).
	var set_global := OpSpec.new("set_global", false, false, true, PackedStringArray(["name", "value"]))
	set_global.literal_fields = PackedStringArray(["name"])
	set_global.expr_fields = PackedStringArray(["value"])
	register(set_global)

	var roll := OpSpec.new("roll", false, false, true, PackedStringArray(["dice", "as"]))
	roll.literal_fields = PackedStringArray(["dice"])
	roll.local_ref_fields = PackedStringArray(["as"])
	register(roll)

	var run_command := OpSpec.new("run_command", false, false, true, PackedStringArray(["name"]))
	run_command.literal_fields = PackedStringArray(["name"])
	run_command.args_fields = PackedStringArray(["args"])
	register(run_command)

	var emit := OpSpec.new("emit", false, false, true, PackedStringArray(["msg"]))
	emit.literal_fields = PackedStringArray(["msg"])
	emit.args_fields = PackedStringArray(["values"])
	register(emit)

	# Bounded AI narration (A5, D4 amendment #3): produces player-facing prose from decided
	# facts. `instruction`/`verbosity` are authored literals (never computed — D4); `context`
	# is a dict of expressions (the decided facts); `language` may be a literal or a param
	# (D29); `as` optionally binds the prose to a local.
	var narrate := OpSpec.new("narrate", false, false, true, PackedStringArray(["instruction"]))
	narrate.literal_fields = PackedStringArray(["instruction", "verbosity"])
	narrate.expr_fields = PackedStringArray(["language"])
	narrate.args_fields = PackedStringArray(["context"])
	narrate.local_ref_fields = PackedStringArray(["as"])
	register(narrate)

	var run := OpSpec.new("run", false, false, true, PackedStringArray(["workflow"]))
	run.literal_fields = PackedStringArray(["workflow"])
	run.args_fields = PackedStringArray(["args"])
	register(run)

	# Hand off to another workflow (M3b): a tail-call, not a return. Unlike `run` it does not
	# come back — the turn continues as a new segment (same orchestration + trace). This is the
	# phase/transition primitive; `run` stays the call/return helper primitive.
	var dispatch := OpSpec.new("dispatch", false, false, true, PackedStringArray(["workflow"]))
	dispatch.literal_fields = PackedStringArray(["workflow"])
	dispatch.args_fields = PackedStringArray(["args"])
	register(dispatch)

	# Suspension points (execution/checkpointing is A3; here they are just vocabulary). Their
	# resume_require / scope fields get light structural validation in the validator.
	var wait_game_time := OpSpec.new("wait_game_time", false, false, true, PackedStringArray(["until_day"]))
	wait_game_time.expr_fields = PackedStringArray(["until_day"])
	register(wait_game_time)

	var confirm := OpSpec.new("confirm", false, false, true, PackedStringArray(["msg", "scope"]))
	confirm.literal_fields = PackedStringArray(["msg"])
	confirm.args_fields = PackedStringArray(["values"])
	register(confirm)
