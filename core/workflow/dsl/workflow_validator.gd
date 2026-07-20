class_name WorkflowValidator
extends RefCounted

## The registration-time strict validator (A2, D24): proves a workflow definition is
## structurally sound and obeys the purity discipline BEFORE it can ever run. A definition
## that fails here is never admitted to the registry, so the executor (A3) can trust its
## shape and never has to re-check it.
##
## It enforces, structurally:
##   - the `workflow` envelope (id, version, params, steps);
##   - that every statement is a known statement op (registry vocabulary or fixed grammar);
##   - **the purity rule** — effectful ops appear only at statement level; an expression
##     position accepts pure ops only (an effectful op there is the headline rejection);
##   - control-flow shape (`if`/`foreach`/`for`/`break`), with `for` bounds constant and
##     `break` only inside a loop;
##   - well-formed sigil references and one-operator-per-array expressions;
##   - a total step budget and a nesting-depth bound.
##
## It is side-effect free: it reads the definition and the [OpRegistry], nothing else. What
## it does NOT check (A2 scope): cross-workflow call-graph acyclicity for `run` (needs the
## whole registry — a later step), rule-table key existence, and unknown-optional-field
## rejection (extra keys are tolerated for now).

const MAX_STEPS: int = 512
const MAX_DEPTH: int = 32

## Control-flow and binding statements the grammar owns (never registry-extensible, D27).
const GRAMMAR_STATEMENTS := ["let", "require", "if", "foreach", "for", "break"]

var _ops: OpRegistry
var _step_count: int


func _init(ops: OpRegistry = null) -> void:
	_ops = ops if ops != null else OpRegistry.with_core()


## Validate a whole definition. Returns CommandResult.ok() or a fail carrying a message that
## names the offending location (e.g. "steps[2].then[0].cond").
func validate(definition: Variant) -> CommandResult:
	_step_count = 0
	if not (definition is Dictionary):
		return _fail("workflow", "definition must be a dictionary")
	var def := definition as Dictionary
	if String(def.get("op", "")) != "workflow":
		return _fail("workflow", "top-level op must be \"workflow\"")
	if String(def.get("id", "")).is_empty():
		return _fail("workflow", "workflow needs a non-empty \"id\"")
	if not _is_int_like(def.get("version", null)) or float(def["version"]) < 1.0:
		return _fail("workflow", "workflow needs an integer \"version\" >= 1")

	var params_result := _validate_params(def.get("params", {}))
	if not params_result.success:
		return params_result

	if not (def.get("steps", null) is Array):
		return _fail("workflow", "workflow needs a \"steps\" array")
	return _validate_block(def["steps"] as Array, "steps", 0, false)


# --- envelope ---

func _validate_params(params_v: Variant) -> CommandResult:
	if not (params_v is Dictionary):
		return _fail("params", "\"params\" must be a dictionary")
	for pname in (params_v as Dictionary):
		var spec: Variant = (params_v as Dictionary)[pname]
		if not (spec is Dictionary):
			return _fail("params.%s" % pname, "each param must declare {type, required, default?}")
		if String((spec as Dictionary).get("type", "")).is_empty():
			return _fail("params.%s" % pname, "param needs a \"type\"")
	return CommandResult.ok()


# --- statements ---

func _validate_block(block: Array, path: String, depth: int, in_loop: bool) -> CommandResult:
	if depth > MAX_DEPTH:
		return _fail(path, "nesting exceeds MAX_DEPTH (%d)" % MAX_DEPTH)
	for i in block.size():
		var r := _validate_statement(block[i], "%s[%d]" % [path, i], depth, in_loop)
		if not r.success:
			return r
	return CommandResult.ok()


func _validate_statement(node: Variant, path: String, depth: int, in_loop: bool) -> CommandResult:
	if not (node is Dictionary):
		return _fail(path, "statement must be a dictionary")
	var stmt := node as Dictionary
	var op := String(stmt.get("op", ""))
	if op.is_empty():
		return _fail(path, "statement has no \"op\"")

	_step_count += 1
	if _step_count > MAX_STEPS:
		return _fail(path, "workflow exceeds MAX_STEPS (%d)" % MAX_STEPS)

	if GRAMMAR_STATEMENTS.has(op):
		return _validate_grammar_statement(op, stmt, path, depth, in_loop)

	var spec := _ops.get_spec(op)
	if spec == null:
		return _fail(path, "unknown op \"%s\"" % op)
	if not spec.statement:
		# e.g. a pure expression op like read_state used where a statement belongs.
		return _fail(path, "op \"%s\" is not valid as a statement" % op)
	return _validate_registry_op_fields(spec, stmt, path, depth)


func _validate_grammar_statement(op: String, stmt: Dictionary, path: String, depth: int, in_loop: bool) -> CommandResult:
	match op:
		"let":
			var as_r := _require_local_ref(stmt.get("as", null), "%s.as" % path)
			if not as_r.success:
				return as_r
			return _validate_expr(stmt.get("value", null), "%s.value" % path, depth)
		"require":
			if String(stmt.get("fail_code", "")).is_empty():
				return _fail(path, "\"require\" needs a non-empty \"fail_code\"")
			return _validate_expr(stmt.get("cond", null), "%s.cond" % path, depth)
		"if":
			return _validate_if(stmt, path, depth, in_loop)
		"foreach":
			var as_r := _require_local_ref(stmt.get("as", null), "%s.as" % path)
			if not as_r.success:
				return as_r
			if stmt.has("index"):
				var idx_r := _require_local_ref(stmt.get("index", null), "%s.index" % path)
				if not idx_r.success:
					return idx_r
			var src_r := _validate_expr(stmt.get("source", null), "%s.source" % path, depth)
			if not src_r.success:
				return src_r
			return _validate_loop_body(stmt.get("body", null), "%s.body" % path, depth)
		"for":
			# Constant bounds (§4): from/to are integer literals so termination is provable.
			# JSON has no int type, so an integral float (0, 3) counts; "$$n" does not.
			if not _is_int_like(stmt.get("from", null)) or not _is_int_like(stmt.get("to", null)):
				return _fail(path, "\"for\" needs integer-literal \"from\" and \"to\" bounds")
			var as_r := _require_local_ref(stmt.get("as", null), "%s.as" % path)
			if not as_r.success:
				return as_r
			return _validate_loop_body(stmt.get("body", null), "%s.body" % path, depth)
		"break":
			if not in_loop:
				return _fail(path, "\"break\" is only valid inside a loop body")
			return CommandResult.ok()
	return _fail(path, "unhandled grammar statement \"%s\"" % op)


func _validate_if(stmt: Dictionary, path: String, depth: int, in_loop: bool) -> CommandResult:
	var cond_r := _validate_expr(stmt.get("cond", null), "%s.cond" % path, depth)
	if not cond_r.success:
		return cond_r
	if not (stmt.get("then", null) is Array):
		return _fail(path, "\"if\" needs a \"then\" block")
	var then_r := _validate_block(stmt["then"] as Array, "%s.then" % path, depth + 1, in_loop)
	if not then_r.success:
		return then_r
	if stmt.has("elif"):
		if not (stmt["elif"] is Array):
			return _fail(path, "\"elif\" must be an array of {cond, then}")
		for j in (stmt["elif"] as Array).size():
			var branch: Variant = (stmt["elif"] as Array)[j]
			var bpath := "%s.elif[%d]" % [path, j]
			if not (branch is Dictionary):
				return _fail(bpath, "each elif branch must be a dictionary")
			var bcond := _validate_expr((branch as Dictionary).get("cond", null), "%s.cond" % bpath, depth)
			if not bcond.success:
				return bcond
			if not ((branch as Dictionary).get("then", null) is Array):
				return _fail(bpath, "elif branch needs a \"then\" block")
			var bthen := _validate_block((branch as Dictionary)["then"] as Array, "%s.then" % bpath, depth + 1, in_loop)
			if not bthen.success:
				return bthen
	if stmt.has("else"):
		if not (stmt["else"] is Array):
			return _fail(path, "\"else\" must be a block")
		return _validate_block(stmt["else"] as Array, "%s.else" % path, depth + 1, in_loop)
	return CommandResult.ok()


func _validate_loop_body(body_v: Variant, path: String, depth: int) -> CommandResult:
	if not (body_v is Array):
		return _fail(path, "loop needs a \"body\" block")
	return _validate_block(body_v as Array, path, depth + 1, true)


## Field-driven validation for a registry statement op, using its OpSpec metadata.
func _validate_registry_op_fields(spec: OpRegistry.OpSpec, node: Dictionary, path: String, depth: int) -> CommandResult:
	for f in spec.required_fields:
		if not node.has(f):
			return _fail(path, "op \"%s\" is missing required field \"%s\"" % [spec.name, f])
	for f in spec.literal_fields:
		if node.has(f) and not _is_plain_literal_string(node[f]):
			return _fail("%s.%s" % [path, f], "field \"%s\" must be a plain literal string" % f)
	for f in spec.local_ref_fields:
		if node.has(f):
			var r := _require_local_ref(node[f], "%s.%s" % [path, f])
			if not r.success:
				return r
	for f in spec.expr_fields:
		if node.has(f):
			var r := _validate_expr(node[f], "%s.%s" % [path, f], depth)
			if not r.success:
				return r
	for f in spec.args_fields:
		if node.has(f):
			var r := _validate_args(node[f], "%s.%s" % [path, f], depth)
			if not r.success:
				return r
	return CommandResult.ok()


# --- expressions ---

func _validate_expr(node: Variant, path: String, depth: int) -> CommandResult:
	if depth > MAX_DEPTH:
		return _fail(path, "expression nesting exceeds MAX_DEPTH (%d)" % MAX_DEPTH)
	match typeof(node):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return CommandResult.ok()
		TYPE_STRING, TYPE_STRING_NAME:
			if DslRef.is_reference(String(node)) and not DslRef.is_well_formed(String(node)):
				return _fail(path, "malformed reference \"%s\"" % node)
			return CommandResult.ok()
		TYPE_ARRAY:
			return _validate_operator_expr(node as Array, path, depth)
		TYPE_DICTIONARY:
			return _validate_expr_op_object(node as Dictionary, path, depth)
	return _fail(path, "value of type %d is not a valid expression" % typeof(node))


func _validate_operator_expr(arr: Array, path: String, depth: int) -> CommandResult:
	if arr.size() == 3 and arr[1] is String and DslExpressionEvaluator.BINARY_OPS.has(arr[1]):
		var l := _validate_expr(arr[0], "%s[0]" % path, depth + 1)
		if not l.success:
			return l
		return _validate_expr(arr[2], "%s[2]" % path, depth + 1)
	if arr.size() == 2 and arr[0] is String and DslExpressionEvaluator.UNARY_OPS.has(arr[0]):
		return _validate_expr(arr[1], "%s[1]" % path, depth + 1)
	return _fail(path, "array is not a valid [left, op, right] or [op, operand] expression")


func _validate_expr_op_object(obj: Dictionary, path: String, depth: int) -> CommandResult:
	var op := String(obj.get("op", ""))
	if op.is_empty():
		return _fail(path, "expression object has no \"op\"")
	var spec := _ops.get_spec(op)
	if spec == null:
		return _fail(path, "unknown op \"%s\" in expression" % op)
	if not spec.expression:
		# The headline purity rejection: an effectful op used where a value is required.
		return _fail(path, "effectful op \"%s\" is not allowed in an expression position" % op)
	# read_state.path is an array of expression segments — validate each.
	if op == "read_state":
		if not (obj.get("path", null) is Array):
			return _fail("%s.path" % path, "\"read_state\" needs a \"path\" array")
		var segs := obj["path"] as Array
		for i in segs.size():
			var r := _validate_expr(segs[i], "%s.path[%d]" % [path, i], depth + 1)
			if not r.success:
				return r
	return _validate_registry_op_fields(spec, obj, path, depth + 1)


func _validate_args(args_v: Variant, path: String, depth: int) -> CommandResult:
	if not (args_v is Dictionary):
		return _fail(path, "must be a dictionary of expressions")
	for k in (args_v as Dictionary):
		var r := _validate_expr((args_v as Dictionary)[k], "%s.%s" % [path, k], depth + 1)
		if not r.success:
			return r
	return CommandResult.ok()


# --- helpers ---

func _require_local_ref(v: Variant, path: String) -> CommandResult:
	if not (v is String) or not String(v).begins_with("$$") or not DslRef.is_well_formed(String(v)):
		return _fail(path, "must be a \"$$local\" reference")
	return CommandResult.ok()


## A plain literal string carries no reference sigil (so it cannot be computed at runtime).
func _is_plain_literal_string(v: Variant) -> bool:
	return v is String and not DslRef.is_reference(String(v))


## An integer, or a JSON-parsed integral float (JSON.parse turns 1 into 1.0). The canonical
## form is JSON, so integer-valued fields legitimately arrive as floats.
func _is_int_like(v: Variant) -> bool:
	if v is int:
		return true
	return v is float and floor(v) == v


func _fail(path: String, message: String) -> CommandResult:
	return CommandResult.fail("%s: %s" % [path, message], {"path": path})
