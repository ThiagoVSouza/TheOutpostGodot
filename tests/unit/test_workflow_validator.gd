extends GutTest

## WorkflowValidator (A2): accepts the agreed canonical syntax and rejects every structural
## and purity violation it is meant to catch. The two worked examples (in the reconciled
## get-op syntax) are the positive cases; the rest are one rejection per rule.

const Validator := preload("res://core/workflow/dsl/workflow_validator.gd")


func _v() -> WorkflowValidator:
	return Validator.new()


func _json(text: String) -> Variant:
	return JSON.parse_string(text)


# --- positive cases: the worked examples ---

func test_accepts_the_melee_attack_workflow() -> void:
	var def: Variant = _json("""
	{
	  "op": "workflow", "id": "combat_melee_attack", "version": 1,
	  "params": {
	    "actor_id":  {"type": "entity_id", "required": true},
	    "target_id": {"type": "entity_id", "required": true}
	  },
	  "steps": [
	    {"op": "require",
	     "cond": {"op": "fn", "name": "combat.in_melee_range",
	              "args": {"a": "@actor_id", "b": "@target_id"}},
	     "fail_code": "precondition_failed", "fail_msg": "combat.out_of_range"},
	    {"op": "roll", "dice": "1d20", "as": "$$atk"},
	    {"op": "let", "as": "$$total",
	     "value": ["$$atk", "+", {"op": "fn", "name": "combat.attack_modifier",
	                              "args": {"actor": "@actor_id"}}]},
	    {"op": "if",
	     "cond": ["$$total", ">=", {"op": "read_state",
	                                "path": ["entities", "@target_id", "defense"]}],
	     "then": [
	        {"op": "let", "as": "$$dmg",
	         "value": {"op": "table_get", "table": "weapon_damage",
	                   "key": {"op": "read_state",
	                           "path": ["entities", "@actor_id", "weapon_class"]}}},
	        {"op": "run_command", "name": "apply_damage",
	         "args": {"target": "@target_id", "amount": "$$dmg"}},
	        {"op": "emit", "type": "dice_result", "msg": "combat.attack_hit",
	         "values": {"roll": "$$atk", "total": "$$total", "damage": "$$dmg"}}
	     ],
	     "else": [
	        {"op": "emit", "type": "dice_result", "msg": "combat.attack_miss",
	         "values": {"roll": "$$atk", "total": "$$total"}}
	     ]}
	  ]
	}
	""")
	var r := _v().validate(def)
	assert_true(r.success, "the melee example must validate: %s" % r.message)


func test_accepts_travel_with_get_op_and_suspension() -> void:
	# The reconciled travel example: "$$route.found" is now an explicit get.
	var def: Variant = _json("""
	{
	  "op": "workflow", "id": "travel_to_location", "version": 1,
	  "params": {"actor_id": {"type": "entity_id", "required": true},
	             "destination_id": {"type": "entity_id", "required": true}},
	  "steps": [
	    {"op": "let", "as": "$$route",
	     "value": {"op": "fn", "name": "travel.calculate_route",
	               "args": {"from": "@actor_id", "to": "@destination_id"}}},
	    {"op": "require",
	     "cond": [{"op": "get", "from": "$$route", "key": "found"}, "==", true],
	     "fail_code": "missing_resource", "fail_msg": "travel.no_route"},
	    {"op": "run_command", "name": "start_travel",
	     "args": {"actor": "@actor_id", "route": "$$route"}},
	    {"op": "emit", "msg": "travel.departed",
	     "values": {"mode": {"op": "get", "from": "$$route", "key": "mode"}}},
	    {"op": "wait_game_time",
	     "until_day": {"op": "get", "from": "$$route", "key": "arrival_day"}},
	    {"op": "run_command", "name": "complete_travel",
	     "args": {"actor": "@actor_id", "at": "@destination_id"}}
	  ]
	}
	""")
	var r := _v().validate(def)
	assert_true(r.success, "the travel example must validate: %s" % r.message)


func test_accepts_globals_and_loops() -> void:
	var def: Variant = _json("""
	{
	  "op": "workflow", "id": "tick", "version": 3,
	  "params": {},
	  "steps": [
	    {"op": "set_global", "name": "turn_counter",
	     "value": [{"op": "get_global", "name": "turn_counter"}, "+", 1]},
	    {"op": "for", "from": 0, "to": 3, "as": "$$i", "body": [
	       {"op": "if", "cond": ["$$i", "==", 2],
	        "then": [{"op": "break"}]}
	    ]}
	  ]
	}
	""")
	var r := _v().validate(def)
	assert_true(r.success, "globals + for-loop + break should validate: %s" % r.message)


# --- envelope rejections ---

func test_rejects_non_dictionary_and_wrong_top_op() -> void:
	assert_false(_v().validate([]).success, "a non-dictionary is not a workflow")
	assert_false(_v().validate({"op": "mechanic", "id": "x", "version": 1, "steps": []}).success,
		"top op must be workflow")


func test_rejects_missing_id_and_bad_version() -> void:
	assert_false(_v().validate({"op": "workflow", "version": 1, "steps": []}).success, "no id")
	assert_false(_v().validate({"op": "workflow", "id": "x", "version": 0, "steps": []}).success, "version < 1")
	assert_false(_v().validate({"op": "workflow", "id": "x", "version": "1", "steps": []}).success, "version not int")


# --- the purity rule (the headline) ---

func test_rejects_effectful_op_in_an_expression_position() -> void:
	# run_command is an effect; putting it where a value belongs is the core violation.
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "let", "as": "$$y",
		 "value": {"op": "run_command", "name": "apply_damage", "args": {}}}
	]}
	var r := _v().validate(def)
	assert_false(r.success, "an effect may never appear in an expression")
	assert_string_contains(r.message, "expression position")


func test_rejects_pure_op_used_as_a_statement() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "read_state", "path": ["resources"]}
	]}
	assert_false(_v().validate(def).success, "read_state is not a statement")


# --- statement / field rejections ---

func test_rejects_unknown_op() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "delete_disk"}
	]}
	assert_false(_v().validate(def).success)


func test_rejects_missing_required_field() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "run_command", "args": {}}  # no "name"
	]}
	var r := _v().validate(def)
	assert_false(r.success)
	assert_string_contains(r.message, "name")


func test_rejects_computed_literal_field() -> void:
	# You may not compute which function to call; fn.name must be a plain literal.
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "let", "as": "$$v", "value": {"op": "fn", "name": "@which_fn", "args": {}}}
	]}
	assert_false(_v().validate(def).success, "fn.name may not be a reference")


func test_rejects_bad_local_ref_on_let() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "let", "as": "@nope", "value": 1}  # "as" must be a $$ local
	]}
	assert_false(_v().validate(def).success)


func test_rejects_require_without_fail_code() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "require", "cond": true}
	]}
	assert_false(_v().validate(def).success)


# --- expression rejections ---

func test_rejects_malformed_reference() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "let", "as": "$$y", "value": "$$"}  # empty local name
	]}
	assert_false(_v().validate(def).success)


func test_rejects_non_operator_array_expression() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "let", "as": "$$y", "value": [1, 2, 3]}  # middle is not an operator
	]}
	assert_false(_v().validate(def).success, "a bare array is not a valid expression")


# --- control-flow rejections ---

func test_rejects_break_outside_a_loop() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "break"}
	]}
	assert_false(_v().validate(def).success)
	# but valid inside a loop body
	var ok := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "for", "from": 0, "to": 1, "as": "$$i", "body": [{"op": "break"}]}
	]}
	assert_true(_v().validate(ok).success)


func test_rejects_for_with_non_constant_bounds() -> void:
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [
		{"op": "for", "from": 0, "to": "$$n", "as": "$$i", "body": []}
	]}
	assert_false(_v().validate(def).success, "for bounds must be integer literals")


# --- budget ---

func test_rejects_over_the_step_budget() -> void:
	var steps: Array = []
	for _i in Validator.MAX_STEPS + 1:
		steps.append({"op": "emit", "msg": "x"})
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": steps}
	assert_false(_v().validate(def).success, "exceeding MAX_STEPS is rejected")


func test_rejects_over_the_depth_bound() -> void:
	# Nest ifs past MAX_DEPTH.
	var inner: Dictionary = {"op": "emit", "msg": "deep"}
	for _i in Validator.MAX_DEPTH + 2:
		inner = {"op": "if", "cond": true, "then": [inner]}
	var def := {"op": "workflow", "id": "x", "version": 1, "params": {}, "steps": [inner]}
	assert_false(_v().validate(def).success, "exceeding MAX_DEPTH is rejected")
