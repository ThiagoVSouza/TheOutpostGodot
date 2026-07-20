class_name DslExpressionEvaluator
extends RefCounted

## Evaluates a DSL expression node to a value (D24, §4). Pure by construction: it only ever
## *reads* through a [DslEvalContext] — nothing an expression reaches can mutate state. It is
## a total tree-walker: given input the validator has accepted it never crashes; given
## malformed input it returns null (and pushes an error) rather than throwing.
##
## An expression node is one of:
##   literal        int / float / bool / null / a non-sigil string
##   reference      "@param" / "$$local"  (atomic names; "\..." escapes to a literal)
##   binary expr    [left, "<op>", right]     — exactly one operator per array, no precedence
##   unary expr     ["not", operand]
##   op-object      {"op": "read_state"|"fn"|"table_get"|"get"|"get_global", ...}
##
## Arrays in an expression position are ALWAYS operator expressions (a literal list is not
## expressible as a bare array — that is what keeps [1,2,3] from being mistaken for a triple).

const BINARY_OPS := ["==", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "%",
	"and", "or", "in", "contains"]
const UNARY_OPS := ["not"]


static func evaluate(node: Variant, ctx: DslEvalContext) -> Variant:
	match typeof(node):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return node
		TYPE_STRING, TYPE_STRING_NAME:
			return _resolve_ref(String(node), ctx)
		TYPE_ARRAY:
			return _eval_array(node as Array, ctx)
		TYPE_DICTIONARY:
			return _eval_op_object(node as Dictionary, ctx)
	push_error("DSL expr: unevaluable node type %d" % typeof(node))
	return null


# --- references ---

static func _resolve_ref(s: String, ctx: DslEvalContext) -> Variant:
	var c := DslRef.classify(s)
	match int(c["kind"]):
		DslRef.Kind.LITERAL:
			return c["value"]
		DslRef.Kind.PARAM:
			return ctx.get_param(String(c["name"]))
		DslRef.Kind.LOCAL:
			return ctx.get_local(String(c["name"]))
	return null


# --- operator expressions ---

static func _eval_array(arr: Array, ctx: DslEvalContext) -> Variant:
	if arr.size() == 3 and arr[1] is String and BINARY_OPS.has(arr[1]):
		return _eval_binary(String(arr[1]), arr[0], arr[2], ctx)
	if arr.size() == 2 and arr[0] is String and UNARY_OPS.has(arr[0]):
		return _eval_unary(String(arr[0]), arr[1], ctx)
	push_error("DSL expr: array is not a valid triple or unary expression")
	return null


static func _eval_binary(op: String, left_node: Variant, right_node: Variant, ctx: DslEvalContext) -> Variant:
	# Short-circuit boolean ops evaluate the right side only when needed.
	if op == "and":
		return false if not _truthy(evaluate(left_node, ctx)) else _truthy(evaluate(right_node, ctx))
	if op == "or":
		return true if _truthy(evaluate(left_node, ctx)) else _truthy(evaluate(right_node, ctx))

	var l: Variant = evaluate(left_node, ctx)
	var r: Variant = evaluate(right_node, ctx)
	match op:
		"==": return _eq(l, r)
		"!=": return not _eq(l, r)
		"<", "<=", ">", ">=": return _compare(op, l, r)
		"+": return _add(l, r)
		"-": return _arith(l, r, "-")
		"*": return _arith(l, r, "*")
		"/": return _arith(l, r, "/")
		"%": return _arith(l, r, "%")
		"in": return _membership(l, r)
		"contains": return _membership(r, l)
	return null


static func _eval_unary(op: String, operand_node: Variant, ctx: DslEvalContext) -> Variant:
	if op == "not":
		return not _truthy(evaluate(operand_node, ctx))
	return null


# --- op-objects ---

static func _eval_op_object(obj: Dictionary, ctx: DslEvalContext) -> Variant:
	var op := String(obj.get("op", ""))
	match op:
		"read_state":
			return ctx.read_state(_resolve_path(obj.get("path", []), ctx))
		"fn":
			return ctx.call_fn(String(obj.get("name", "")), _eval_args(obj.get("args", {}), ctx))
		"table_get":
			return ctx.table_get(String(obj.get("table", "")), evaluate(obj.get("key", null), ctx))
		"get":
			return _index(evaluate(obj.get("from", null), ctx), evaluate(obj.get("key", null), ctx))
		"get_global":
			return ctx.get_global(String(obj.get("name", "")))
	push_error("DSL expr: '%s' is not a pure op usable in an expression" % op)
	return null


## A read_state path: each segment resolved as an expression, so "@target_id" becomes the
## param's value used as a key while a bare "entities" stays the literal key (A2 decision).
static func _resolve_path(path_v: Variant, ctx: DslEvalContext) -> Array:
	var out: Array = []
	if path_v is Array:
		for seg in path_v:
			out.append(evaluate(seg, ctx))
	return out


static func _eval_args(args_v: Variant, ctx: DslEvalContext) -> Dictionary:
	var out: Dictionary = {}
	if args_v is Dictionary:
		for k in args_v:
			out[k] = evaluate(args_v[k], ctx)
	return out


# --- value operations (total; type mismatches degrade instead of crashing) ---

static func _index(from: Variant, key: Variant) -> Variant:
	if from is Dictionary:
		return (from as Dictionary).get(key, null)
	if from is Array:
		var i := int(key)
		var a := from as Array
		return a[i] if i >= 0 and i < a.size() else null
	return null


static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL: return false
		TYPE_BOOL: return v
		TYPE_INT, TYPE_FLOAT: return v != 0
		TYPE_STRING, TYPE_STRING_NAME: return not String(v).is_empty()
		TYPE_ARRAY: return not (v as Array).is_empty()
		TYPE_DICTIONARY: return not (v as Dictionary).is_empty()
	return v != null


static func _eq(l: Variant, r: Variant) -> bool:
	# GDScript's Variant "==" *raises* on incomparable types (e.g. String vs int) rather
	# than returning false, so guard before using it: same type or both-numeric compare
	# natively (1 == 1.0 is true); any other cross-type pair is simply unequal.
	if typeof(l) == typeof(r):
		return l == r
	var l_num := l is int or l is float
	var r_num := r is int or r is float
	if l_num and r_num:
		return l == r
	return false


static func _compare(op: String, l: Variant, r: Variant) -> bool:
	# Only numbers and strings order; a mismatch is false rather than an error.
	var l_num := l is int or l is float
	var r_num := r is int or r is float
	if not ((l_num and r_num) or (l is String and r is String)):
		return false
	match op:
		"<": return l < r
		"<=": return l <= r
		">": return l > r
		">=": return l >= r
	return false


static func _add(l: Variant, r: Variant) -> Variant:
	# "+" concatenates when either side is a string, otherwise adds numerically.
	if l is String or l is StringName or r is String or r is StringName:
		return str(l) + str(r)
	if (l is int or l is float) and (r is int or r is float):
		return l + r
	push_error("DSL expr: '+' on unsupported operand types")
	return null


static func _arith(l: Variant, r: Variant, op: String) -> Variant:
	if not ((l is int or l is float) and (r is int or r is float)):
		push_error("DSL expr: '%s' requires numeric operands" % op)
		return null
	match op:
		"-": return l - r
		"*": return l * r
		"/":
			if r == 0:
				push_error("DSL expr: division by zero")
				return null
			return l / r  # int/int stays int (GDScript), float if either is float
		"%":
			if int(r) == 0:
				push_error("DSL expr: modulo by zero")
				return null
			return l % r if l is int and r is int else fmod(l, r)
	return null


static func _membership(needle: Variant, haystack: Variant) -> bool:
	if haystack is Array:
		return (haystack as Array).has(needle)
	if haystack is Dictionary:
		return (haystack as Dictionary).has(needle)
	if haystack is String:
		return (haystack as String).contains(str(needle))
	return false
