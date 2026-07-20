extends GutTest

## WorkflowExecutor (A3): validated workflows actually run — binding scopes, evaluating
## expressions through the real kernel context, and applying effects through the vetted
## seams (CommandBus, EventBus, GlobalStore). Boots a kernel so run_command hits the real
## whitelist, exactly as v0's executor tests did.

const Executor := preload("res://core/workflow/workflow_executor.gd")
const Instance := preload("res://core/workflow/workflow_instance.gd")


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	return kernel


func _run(kernel: GameKernel, def: Dictionary, params: Dictionary = {}) -> RefCounted:
	# Validate first (the executor trusts validated input), then run.
	var validation := WorkflowValidator.new().validate(def)
	assert_true(validation.success, "test workflow should validate: %s" % validation.message)
	var inst := Instance.create(String(def["id"]), int(def["version"]), params, 12345)
	return Executor.for_kernel(kernel).run(def, inst)


func test_full_pipeline_rolls_reads_state_computes_and_mutates() -> void:
	var kernel := _kernel()
	kernel.state.set_value("config", {"base_food": 2})

	var emitted: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: emitted.append(p))

	var def := {
		"op": "workflow", "id": "forage_test", "version": 1, "params": {},
		"steps": [
			{"op": "roll", "dice": "2d6", "as": "$$roll"},
			{"op": "let", "as": "$$base", "value": {"op": "read_state", "path": ["config", "base_food"]}},
			{"op": "let", "as": "$$amount", "value": ["$$base", "+", 1]},
			{"op": "if", "cond": ["$$roll", ">=", 2],
			 "then": [
				{"op": "run_command", "name": "grant_resource",
				 "args": {"resource": "food", "amount": "$$amount"}},
				{"op": "emit", "msg": "forage.win", "values": {"amount": "$$amount"}}
			 ],
			 "else": [{"op": "emit", "msg": "forage.none"}]}
		]
	}
	var result: RefCounted = _run(kernel, def)

	assert_true(result.succeeded(), "the workflow should complete")
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 3,
		"base_food(2) + 1 granted through the command")
	assert_has(result.applied_commands, "grant_resource")
	assert_eq(emitted.size(), 1, "only the win branch emits")
	assert_eq(emitted[0]["msg"], "forage.win")
	assert_eq(int((emitted[0]["values"] as Dictionary)["amount"]), 3)


func test_fn_and_table_get_resolve_through_the_registries() -> void:
	var kernel := _kernel()
	kernel.dsl_functions.register("combat.mod", func(args: Dictionary) -> int: return int(args["a"]) + 4)
	kernel.dsl_tables.register("weapon_damage", {"sword": 8, "axe": 10})

	var captured: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: captured.append(p))

	var def := {
		"op": "workflow", "id": "lookup_test", "version": 1, "params": {},
		"steps": [
			{"op": "let", "as": "$$m", "value": {"op": "fn", "name": "combat.mod", "args": {"a": 1}}},
			{"op": "let", "as": "$$d", "value": {"op": "table_get", "table": "weapon_damage", "key": "sword"}},
			{"op": "emit", "msg": "x", "values": {"m": "$$m", "d": "$$d"}}
		]
	}
	assert_true(_run(kernel, def).succeeded())
	assert_eq(int((captured[0]["values"] as Dictionary)["m"]), 5, "fn(a=1) -> 5")
	assert_eq(int((captured[0]["values"] as Dictionary)["d"]), 8, "table_get sword -> 8")


func test_globals_and_for_loop() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "counter", "version": 1, "params": {},
		"steps": [
			{"op": "set_global", "name": "count", "value": 0},
			{"op": "for", "from": 0, "to": 3, "as": "$$i", "body": [
				{"op": "set_global", "name": "count",
				 "value": [{"op": "get_global", "name": "count"}, "+", 1]}
			]},
			{"op": "let", "as": "$$final", "value": {"op": "get_global", "name": "count"}}
		]
	}
	var result: RefCounted = _run(kernel, def)
	assert_true(result.succeeded())
	assert_eq(int(kernel.globals.get_value("count")), 3, "loop ran 3 times (half-open [0,3))")
	assert_eq(int(result.instance.locals["final"]), 3, "the global read back into a local")
	assert_false(result.instance.locals.has("i"), "the loop var is loop-scoped, gone after the loop")


func test_foreach_binds_item_and_index() -> void:
	var kernel := _kernel()
	var seen: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: seen.append(p["values"]))
	# A collection comes from a param/state/fn, never an inline array literal (arrays in an
	# expression position are always operator expressions, by design).
	var def := {
		"op": "workflow", "id": "each", "version": 1,
		"params": {"names": {"type": "list", "required": true}},
		"steps": [
			{"op": "foreach", "source": "@names", "as": "$$item", "index": "$$idx", "body": [
				{"op": "emit", "msg": "seen", "values": {"item": "$$item", "idx": "$$idx"}}
			]}
		]
	}
	assert_true(_run(kernel, def, {"names": ["a", "b"]}).succeeded())
	assert_eq(seen.size(), 2)
	assert_eq(seen[0], {"item": "a", "idx": 0})
	assert_eq(seen[1], {"item": "b", "idx": 1})


func test_break_exits_the_loop() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "brk", "version": 1, "params": {},
		"steps": [
			{"op": "set_global", "name": "n", "value": 0},
			{"op": "for", "from": 0, "to": 10, "as": "$$i", "body": [
				{"op": "if", "cond": ["$$i", "==", 3], "then": [{"op": "break"}]},
				{"op": "set_global", "name": "n", "value": [{"op": "get_global", "name": "n"}, "+", 1]}
			]}
		]
	}
	assert_true(_run(kernel, def).succeeded())
	assert_eq(int(kernel.globals.get_value("n")), 3, "counted 0,1,2 then broke at i==3")


func test_require_failure_halts_before_the_command() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "guard", "version": 1, "params": {},
		"steps": [
			{"op": "require", "cond": false, "fail_code": "precondition_failed", "fail_msg": "nope"},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 5}}
		]
	}
	var result: RefCounted = _run(kernel, def)
	assert_eq(result.status, Instance.Status.FAILED)
	assert_eq(result.fail_code, "precondition_failed")
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 0,
		"fail-fast: the command after the failed require never ran")


func test_non_whitelisted_command_fails_the_instance() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "bad", "version": 1, "params": {},
		"steps": [{"op": "run_command", "name": "delete_everything", "args": {}}]
	}
	var result: RefCounted = _run(kernel, def)
	assert_eq(result.status, Instance.Status.FAILED)
	assert_eq(result.fail_code, "unknown_command")


func test_wait_game_time_suspends_and_captures_state() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "trip", "version": 2, "params": {},
		"steps": [
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 1}},
			{"op": "wait_game_time", "until_day": 214},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 100}}
		]
	}
	var result: RefCounted = _run(kernel, def)
	assert_eq(result.status, Instance.Status.SUSPENDED, "hitting wait_game_time suspends")
	assert_eq(result.wake["type"], "game_time")
	assert_eq(int(result.wake["at_day"]), 214)
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 1,
		"the command after the suspension point did not run")

	# The suspended instance serializes to the save-file contract (§5.2) and round-trips.
	var snap: Dictionary = result.instance.to_dict()
	assert_eq(snap["status"], "suspended")
	assert_eq(snap["workflow"], "trip@2")
	var restored := Instance.from_dict(snap)
	assert_eq(restored.workflow_id, "trip")
	assert_eq(restored.workflow_version, 2)
	assert_eq(restored.wake["type"], "game_time")


func test_seeded_rolls_are_deterministic() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "dice", "version": 1, "params": {},
		"steps": [
			{"op": "roll", "dice": "3d6", "as": "$$a"},
			{"op": "roll", "dice": "3d6", "as": "$$b"},
			{"op": "let", "as": "$$sum", "value": ["$$a", "+", "$$b"]}
		]
	}
	var a := Instance.create("dice", 1, {}, 999)
	var b := Instance.create("dice", 1, {}, 999)
	Executor.for_kernel(kernel).run(def, a)
	Executor.for_kernel(kernel).run(def, b)
	assert_eq(a.locals["sum"], b.locals["sum"], "same seed -> same roll sequence")
	assert_between(int(a.locals["a"]), 3, 18, "3d6 is in range")


func _food(kernel: GameKernel) -> int:
	return int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


func test_resume_after_wait_continues_from_where_it_suspended() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "trip", "version": 1, "params": {},
		"steps": [
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 1}},
			{"op": "wait_game_time", "until_day": 5},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 10}}
		]
	}
	var inst := Instance.create("trip", 1, {}, 1)
	var suspended: RefCounted = Executor.for_kernel(kernel).run(def, inst)
	assert_eq(suspended.status, Instance.Status.SUSPENDED)
	assert_eq(_food(kernel), 1, "only the pre-wait command ran")

	var resumed: RefCounted = Executor.for_kernel(kernel).resume(def, inst)
	assert_true(resumed.succeeded(), "resume runs to completion")
	assert_eq(_food(kernel), 11, "the post-wait command ran on resume")


func test_suspended_instance_survives_a_serialization_round_trip() -> void:
	# The M3a exit criterion: a suspended instance survives a restart. We serialize through
	# JSON (proving nothing unserializable is captured), rebuild, and resume with a fresh
	# executor against the live world.
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "trip", "version": 1, "params": {},
		"steps": [
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 2}},
			{"op": "wait_game_time", "until_day": 9},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 5}}
		]
	}
	var inst := Instance.create("trip", 1, {}, 1)
	Executor.for_kernel(kernel).run(def, inst)

	var json := JSON.stringify(inst.to_dict())
	var reloaded := Instance.from_dict(JSON.parse_string(json))
	assert_eq(reloaded.status, Instance.Status.SUSPENDED)

	var resumed: RefCounted = Executor.for_kernel(kernel).resume(def, reloaded)
	assert_true(resumed.succeeded(), "the reloaded instance resumes and completes")
	assert_eq(_food(kernel), 7, "2 before the restart + 5 after")


func test_resume_require_failure_fails_the_instance() -> void:
	var kernel := _kernel()
	kernel.state.set_value("still_valid", true)
	kernel.dsl_functions.register("test.still_valid",
		func(_a: Dictionary) -> bool: return bool(kernel.state.get_value("still_valid", false)))
	var def := {
		"op": "workflow", "id": "guarded_trip", "version": 1, "params": {},
		"steps": [
			{"op": "wait_game_time", "until_day": 3,
			 "resume_require": [{"cond": {"op": "fn", "name": "test.still_valid", "args": {}},
								 "fail_code": "stale_context"}]},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 9}}
		]
	}
	var inst := Instance.create("guarded_trip", 1, {}, 1)
	Executor.for_kernel(kernel).run(def, inst)

	# The world moved while suspended: the precondition no longer holds.
	kernel.state.set_value("still_valid", false)
	var resumed: RefCounted = Executor.for_kernel(kernel).resume(def, inst)
	assert_eq(resumed.status, Instance.Status.FAILED)
	assert_eq(resumed.fail_code, "stale_context", "resume re-checks and fails cleanly")
	assert_eq(_food(kernel), 0, "no state changed on a stale resume")


func test_confirm_decline_cancels_and_confirm_accept_continues() -> void:
	var kernel := _kernel()
	var def := {
		"op": "workflow", "id": "destroy", "version": 1, "params": {},
		"steps": [
			{"op": "confirm", "msg": "confirm.destroy",
			 "scope": {"action": "destroy", "target": "x"}},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 4}}
		]
	}
	# Declined: the destructive command (after the confirm) never runs.
	var declined_inst := Instance.create("destroy", 1, {}, 1)
	Executor.for_kernel(kernel).run(def, declined_inst)
	var declined: RefCounted = Executor.for_kernel(kernel).resume(def, declined_inst, {"confirmed": false})
	assert_eq(declined.fail_code, "cancelled")
	assert_eq(_food(kernel), 0, "a declined confirmation applies nothing")

	# Accepted: it continues.
	var ok_inst := Instance.create("destroy", 1, {}, 1)
	Executor.for_kernel(kernel).run(def, ok_inst)
	var accepted: RefCounted = Executor.for_kernel(kernel).resume(def, ok_inst, {"confirmed": true})
	assert_true(accepted.succeeded())
	assert_eq(_food(kernel), 4)


func test_suspension_nested_in_if_and_loop_resumes_correctly() -> void:
	# The hard case the structured pc_stack exists for: suspend deep inside a loop body's
	# if-branch, then resume and finish both the loop and the trailing step.
	var kernel := _kernel()
	var seen: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: seen.append(p["values"]["i"]))
	var def := {
		"op": "workflow", "id": "loopwait", "version": 1,
		"params": {"items": {"type": "list", "required": true}},
		"steps": [
			{"op": "foreach", "source": "@items", "as": "$$x", "index": "$$i", "body": [
				{"op": "emit", "msg": "seen", "values": {"i": "$$i"}},
				{"op": "if", "cond": ["$$i", "==", 0], "then": [
					{"op": "wait_game_time", "until_day": 5}
				]}
			]},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "food", "amount": 1}}
		]
	}
	var inst := Instance.create("loopwait", 1, {"items": ["a", "b"]}, 1)
	var suspended: RefCounted = Executor.for_kernel(kernel).run(def, inst)
	assert_eq(suspended.status, Instance.Status.SUSPENDED, "suspends on iteration 0")
	assert_eq(seen, [0], "only the first iteration's emit happened before suspending")
	assert_eq(_food(kernel), 0, "the trailing command has not run")

	# Round-trip through JSON to prove the nested/loop resume point serializes.
	var reloaded := Instance.from_dict(JSON.parse_string(JSON.stringify(inst.to_dict())))
	var resumed: RefCounted = Executor.for_kernel(kernel).resume(def, reloaded)
	assert_true(resumed.succeeded())
	assert_eq(seen, [0, 1], "the loop finished its second iteration after resume")
	assert_eq(_food(kernel), 1, "the trailing command ran after the loop completed")


func test_run_invokes_a_registered_sub_workflow() -> void:
	var kernel := _kernel()
	var child := {
		"op": "workflow", "id": "grant_child", "version": 1,
		"params": {"amount": {"type": "int", "required": true}},
		"steps": [
			{"op": "run_command", "name": "grant_resource",
			 "args": {"resource": "wood", "amount": "@amount"}}
		]
	}
	assert_true(kernel.workflow_registry.register(child).success, "child registers")

	var parent := {
		"op": "workflow", "id": "parent", "version": 1, "params": {},
		"steps": [{"op": "run", "workflow": "grant_child", "args": {"amount": 7}}]
	}
	var result: RefCounted = _run(kernel, parent)
	assert_true(result.succeeded())
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("wood", 0)), 7,
		"the sub-workflow's command applied, param passed through")
	assert_has(result.applied_commands, "grant_resource")
