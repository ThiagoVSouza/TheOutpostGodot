extends GutTest

## The migration chain runner (M4/B3): apply every declared step newer than the version stamped
## in the save, oldest first. The tests below are mostly about the cases where that sentence
## does not apply cleanly, because those are the ones that quietly corrupt a settlement.


func _step(version: String, fn: Callable) -> SaveMigration:
	return SaveMigration.step(version, fn)


# --- version comparison ----------------------------------------------------------------

func test_versions_compare_numerically_not_as_strings() -> void:
	# The bug this exists to prevent: as strings "0.10.0" sorts *before* "0.2.0", so a string
	# comparison silently stops running migrations at the tenth release.
	assert_eq(SaveMigrator.compare_versions("0.10.0", "0.2.0"), 1, "0.10.0 is newer than 0.2.0")
	assert_eq(SaveMigrator.compare_versions("0.2.0", "0.10.0"), -1)
	assert_eq(SaveMigrator.compare_versions("1.0.0", "0.9.9"), 1)


func test_missing_components_read_as_zero() -> void:
	assert_eq(SaveMigrator.compare_versions("1", "1.0.0"), 0, "1 == 1.0.0")
	assert_eq(SaveMigrator.compare_versions("1.2", "1.2.0"), 0)
	assert_eq(SaveMigrator.compare_versions("1.2.1", "1.2"), 1)


func test_a_suffix_does_not_throw_off_the_comparison() -> void:
	assert_eq(SaveMigrator.compare_versions("1.2.0-beta", "1.2.0"), 0,
		"a pre-release suffix compares equal rather than erroring")
	assert_eq(SaveMigrator.compare_versions("2-rc1", "1.9.9"), 1)


# --- running the chain -----------------------------------------------------------------

func test_only_steps_newer_than_the_save_run() -> void:
	var ran: Array = []
	var migrations := [
		_step("0.2.0", func(d: Dictionary) -> Dictionary: ran.append("0.2.0"); return d),
		_step("0.3.0", func(d: Dictionary) -> Dictionary: ran.append("0.3.0"); return d),
		_step("0.4.0", func(d: Dictionary) -> Dictionary: ran.append("0.4.0"); return d),
	]

	var out := SaveMigrator.migrate({}, "0.2.0", "0.4.0", migrations)

	assert_true(bool(out["ok"]))
	assert_eq(ran, ["0.3.0", "0.4.0"], "the step at the saved version already happened")
	assert_eq(out["applied"], ["0.3.0", "0.4.0"], "and what ran is reported, so it is auditable")


func test_steps_run_oldest_first_regardless_of_declaration_order() -> void:
	# Each step only knows about its own change, so running them out of order corrupts the data.
	var migrations := [
		_step("0.3.0", func(d: Dictionary) -> Dictionary: d["trail"] = String(d["trail"]) + "b"; return d),
		_step("0.2.0", func(d: Dictionary) -> Dictionary: d["trail"] = String(d["trail"]) + "a"; return d),
		_step("0.10.0", func(d: Dictionary) -> Dictionary: d["trail"] = String(d["trail"]) + "c"; return d),
	]

	var out := SaveMigrator.migrate({"trail": ""}, "0.1.0", "0.10.0", migrations)

	assert_eq(String((out["data"] as Dictionary)["trail"]), "abc", "sorted numerically, oldest first")


func test_data_walks_forward_one_step_at_a_time() -> void:
	var migrations := [
		_step("0.2.0", func(d: Dictionary) -> Dictionary:
			return {"food": d.get("grain", 0)}),          # renamed the key
		_step("0.3.0", func(d: Dictionary) -> Dictionary:
			return {"resources": {"food": d.get("food", 0)}}),  # nested it
	]

	var out := SaveMigrator.migrate({"grain": 7}, "0.1.0", "0.3.0", migrations)

	assert_true(bool(out["ok"]))
	assert_eq(int(((out["data"] as Dictionary)["resources"] as Dictionary)["food"]), 7,
		"a save two versions old arrives in the present shape")


func test_a_step_declared_for_an_unreleased_version_does_not_run_early() -> void:
	var ran: Array = []
	var migrations := [
		_step("0.2.0", func(d: Dictionary) -> Dictionary: ran.append("0.2.0"); return d),
		_step("0.9.0", func(d: Dictionary) -> Dictionary: ran.append("0.9.0"); return d),
	]

	# The build is at 0.2.0; the 0.9.0 step is written but its shape change has not shipped.
	var out := SaveMigrator.migrate({}, "0.1.0", "0.2.0", migrations)

	assert_true(bool(out["ok"]))
	assert_eq(ran, ["0.2.0"], "steps above the module's own version are not run")


func test_nothing_runs_when_the_save_is_already_current() -> void:
	var ran: Array = []
	var migrations := [_step("0.2.0", func(d: Dictionary) -> Dictionary: ran.append("x"); return d)]

	var out := SaveMigrator.migrate({"a": 1}, "0.2.0", "0.2.0", migrations)

	assert_true(bool(out["ok"]))
	assert_eq(ran.size(), 0)
	assert_eq(out["applied"], [], "an up-to-date save is not touched")


func test_a_save_from_a_newer_build_of_the_module_is_refused() -> void:
	var out := SaveMigrator.migrate({"a": 1}, "0.9.0", "0.2.0", [])

	# Its data may hold shapes this build has never seen, and there is no backwards migration.
	assert_false(bool(out["ok"]))
	assert_eq(String(out["error"]), "module_from_newer_version")


func test_a_step_that_returns_garbage_stops_the_load() -> void:
	var migrations := [
		_step("0.2.0", func(d: Dictionary) -> Dictionary: d["ok"] = true; return d),
		_step("0.3.0", func(_d: Dictionary) -> Variant: return null),  # a bug in the step
		_step("0.4.0", func(d: Dictionary) -> Dictionary: d["never"] = true; return d),
	]

	var out := SaveMigrator.migrate({}, "0.1.0", "0.4.0", migrations)

	assert_false(bool(out["ok"]))
	assert_eq(String(out["error"]), "migration_failed")
	assert_eq(out["applied"], ["0.2.0"], "how far it got is reported")
	assert_eq(out["data"], {}, "half-migrated data is not handed back")


func test_the_original_data_is_not_mutated() -> void:
	var original := {"grain": 7}
	var migrations := [_step("0.2.0", func(d: Dictionary) -> Dictionary: d["grain"] = 99; return d)]

	SaveMigrator.migrate(original, "0.1.0", "0.2.0", migrations)

	assert_eq(int(original["grain"]), 7, "migrating works on a copy, so a failed load can retry")
