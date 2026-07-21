extends GutTest

## OpRegistry (A2): the DSL's vocabulary and the purity invariants it refuses to break.

const Registry := preload("res://core/workflow/dsl/op_registry.gd")


func test_with_core_has_the_expected_vocabulary() -> void:
	var r := Registry.with_core()
	for op in ["read_state", "fn", "table_get", "get", "get_global",
			"set_global", "roll", "run_command", "emit", "run", "wait_game_time", "confirm"]:
		assert_true(r.has(op), "core registry should know \"%s\"" % op)
	# Grammar keywords are NOT registry ops — they are fixed machinery (D27).
	assert_false(r.has("if"), "control flow is grammar, not vocabulary")
	assert_false(r.has("let"), "let is grammar, not vocabulary")


func test_pure_ops_are_expression_position_and_effects_are_statement_position() -> void:
	var r := Registry.with_core()
	assert_true(r.get_spec("read_state").expression, "read_state is a pure expression op")
	assert_true(r.get_spec("read_state").pure)
	assert_false(r.get_spec("read_state").statement, "a pure read is not a statement")

	assert_true(r.get_spec("run_command").statement, "run_command is an effectful statement")
	assert_false(r.get_spec("run_command").pure)
	assert_false(r.get_spec("run_command").expression, "an effect may never sit in an expression")


func test_register_rejects_an_impure_expression_op() -> void:
	var r := Registry.new()
	# expression==true but pure==false violates the purity discipline; must be refused.
	var bad := Registry.OpSpec.new("sneaky", false, true, false)
	assert_false(r.register(bad), "an impure op may not be expression-usable")
	assert_false(r.has("sneaky"))


func test_register_rejects_unreachable_and_unnamed_ops() -> void:
	var r := Registry.new()
	assert_false(r.register(Registry.OpSpec.new("nowhere", true, false, false)), "op usable in no position")
	assert_false(r.register(Registry.OpSpec.new("", true, true, false)), "op with no name")


func test_op_names_are_sorted() -> void:
	var r := Registry.with_core()
	var names := r.op_names()
	var sorted := names.duplicate()
	sorted.sort()
	assert_eq(Array(names), Array(sorted), "op_names() should come back sorted")
