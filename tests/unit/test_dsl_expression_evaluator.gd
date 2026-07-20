extends GutTest

## DslExpressionEvaluator (A2): the agreed canonical syntax, evaluated.
## References (@param/$$local, atomic + escape), fully-parenthesized operator expressions,
## and the pure op-objects read_state/fn/table_get/get/get_global (D24, D31).

const Eval := preload("res://core/workflow/dsl/expression_evaluator.gd")


## A trivial in-memory context so the evaluator is tested with no kernel dependency.
class Ctx:
	extends DslEvalContext
	var params: Dictionary = {}
	var locals: Dictionary = {}
	var state: Dictionary = {}
	var globals: Dictionary = {}
	var tables: Dictionary = {}
	var fns: Dictionary = {}  # name -> Callable(args: Dictionary) -> Variant

	func get_param(param_name: String) -> Variant:
		return params.get(param_name, null)

	func get_local(local_name: String) -> Variant:
		return locals.get(local_name, null)

	func read_state(path: Array) -> Variant:
		var cur: Variant = state
		for seg in path:
			if cur is Dictionary and (cur as Dictionary).has(seg):
				cur = (cur as Dictionary)[seg]
			else:
				return null
		return cur

	func call_fn(fn_name: String, args: Dictionary) -> Variant:
		if fns.has(fn_name):
			return (fns[fn_name] as Callable).call(args)
		return null

	func table_get(table_name: String, key: Variant) -> Variant:
		return (tables.get(table_name, {}) as Dictionary).get(key, null)

	func get_global(global_name: String) -> Variant:
		return globals.get(global_name, null)


func _ctx() -> Ctx:
	return Ctx.new()


# --- literals & references ---

func test_literals_pass_through() -> void:
	var c := _ctx()
	assert_eq(Eval.evaluate(10, c), 10)
	assert_eq(Eval.evaluate(2.5, c), 2.5)
	assert_eq(Eval.evaluate(true, c), true)
	assert_eq(Eval.evaluate("plain string", c), "plain string")
	assert_eq(Eval.evaluate(null, c), null)


func test_param_and_local_references_resolve() -> void:
	var c := _ctx()
	c.params["actor_id"] = "player_01"
	c.locals["atk"] = 17
	assert_eq(Eval.evaluate("@actor_id", c), "player_01")
	assert_eq(Eval.evaluate("$$atk", c), 17)


func test_backslash_escapes_a_literal_sigil() -> void:
	var c := _ctx()
	assert_eq(Eval.evaluate("\\@actor_id", c), "@actor_id", "leading backslash escapes the sigil")
	assert_eq(Eval.evaluate("\\\\path", c), "\\path", "doubled backslash yields one literal backslash")


# --- operator expressions ---

func test_arithmetic_and_nesting_no_precedence() -> void:
	var c := _ctx()
	c.locals["a"] = 3
	assert_eq(Eval.evaluate([2, "+", 3], c), 5)
	# (a + 1) * 2 must be written nested; there is no precedence to rely on.
	assert_eq(Eval.evaluate([["$$a", "+", 1], "*", 2], c), 8)


func test_string_concatenation_builds_a_computed_key() -> void:
	var c := _ctx()
	c.locals["index"] = 1
	# The soldier_N case from the syntax review: "+" concatenates when a side is a string.
	assert_eq(Eval.evaluate(["soldier_", "+", "$$index"], c), "soldier_1")


func test_comparisons() -> void:
	var c := _ctx()
	c.locals["total"] = 17
	assert_true(Eval.evaluate(["$$total", ">=", 15], c))
	assert_false(Eval.evaluate(["$$total", "<", 10], c))
	assert_true(Eval.evaluate([1, "==", 1.0], c), "1 == 1.0 is true")
	assert_false(Eval.evaluate(["1", "==", 1], c), "a string never equals a number")


func test_boolean_ops_short_circuit() -> void:
	var c := _ctx()
	assert_true(Eval.evaluate([[2, ">", 1], "and", [3, ">", 1]], c))
	assert_false(Eval.evaluate([[2, ">", 1], "and", [1, ">", 3]], c))
	assert_true(Eval.evaluate([[1, ">", 3], "or", [3, ">", 1]], c))
	assert_true(Eval.evaluate(["not", [1, ">", 3]], c))


func test_membership_in_and_contains() -> void:
	var c := _ctx()
	c.locals["list"] = ["a", "b", "c"]
	assert_true(Eval.evaluate(["b", "in", "$$list"], c))
	assert_false(Eval.evaluate(["z", "in", "$$list"], c))
	assert_true(Eval.evaluate(["$$list", "contains", "a"], c))


# --- op-objects ---

func test_read_state_resolves_sigil_segments_but_keeps_literals() -> void:
	var c := _ctx()
	c.params["target_id"] = "goblin_7"
	c.state = {"entities": {"goblin_7": {"defense": 12}}}
	# path ["entities", "@target_id", "defense"] -> literal, resolved, literal.
	var node := {"op": "read_state", "path": ["entities", "@target_id", "defense"]}
	assert_eq(Eval.evaluate(node, c), 12)


func test_fn_evaluates_its_args() -> void:
	var c := _ctx()
	c.locals["a"] = 4
	c.fns["combat.sum"] = func(args: Dictionary) -> int: return int(args["x"]) + int(args["y"])
	var node := {"op": "fn", "name": "combat.sum", "args": {"x": "$$a", "y": 6}}
	assert_eq(Eval.evaluate(node, c), 10)


func test_table_get_with_a_computed_key() -> void:
	var c := _ctx()
	c.locals["weapon"] = "sword"
	c.tables["weapon_damage"] = {"sword": 8, "axe": 10}
	var node := {"op": "table_get", "table": "weapon_damage", "key": "$$weapon"}
	assert_eq(Eval.evaluate(node, c), 8)


func test_get_indexes_a_dict_including_a_computed_key() -> void:
	var c := _ctx()
	c.locals["index"] = 1
	c.locals["squad"] = {"soldier_1": {"hp": 5}, "soldier_2": {"hp": 9}}
	# get from $$squad by the computed key "soldier_" + $$index -> the soldier dict.
	var soldier := {"op": "get", "from": "$$squad", "key": ["soldier_", "+", "$$index"]}
	assert_eq(Eval.evaluate(soldier, c), {"hp": 5})
	# and a chained get for the hp.
	var hp := {"op": "get", "from": soldier, "key": "hp"}
	assert_eq(Eval.evaluate(hp, c), 5)


func test_get_global_reads_the_global_store() -> void:
	var c := _ctx()
	c.globals["turn_counter"] = 7
	assert_eq(Eval.evaluate({"op": "get_global", "name": "turn_counter"}, c), 7)
	assert_null(Eval.evaluate({"op": "get_global", "name": "missing"}, c))
