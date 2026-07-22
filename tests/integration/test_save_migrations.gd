extends GutTest

## Module-declared migrations running through a real load (M4/B3), plus the two module-lifecycle
## cases a save outlives: a module added since the save was written, and a module that was in
## the save but is not loaded now.

const SCRATCH_DIR := "user://test_save_migrations"


## A module at v0.3.0 whose save data has been through two shape changes.
class EvolvedModule extends Module:
	var restored: Dictionary = {}

	func _init(version: String = "0.3.0") -> void:
		manifest = ModuleManifest.new()
		manifest.id = "evolved"
		manifest.version = version

	func capture_save_data(_kernel: GameKernel) -> Dictionary:
		return {"resources": {"food": 5}}

	func restore_save_data(_kernel: GameKernel, data: Dictionary) -> void:
		restored = data

	func save_migrations() -> Array:
		return [
			SaveMigration.step("0.2.0", func(d: Dictionary) -> Dictionary:
				return {"food": d.get("grain", 0)}, "renamed grain to food"),
			SaveMigration.step("0.3.0", func(d: Dictionary) -> Dictionary:
				return {"resources": {"food": d.get("food", 0)}}, "nested resources"),
		]


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file])
	DirAccess.remove_absolute(SCRATCH_DIR)


func _kernel_with(module: Module) -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.saves = SaveManager.new(SCRATCH_DIR)
	if module != null:
		# No runtime seam registers a module; the registry discovers them from disk. Reaching
		# into `_modules` is deliberate and confined to these tests.
		kernel.modules._modules.append(module)
		kernel.modules._loaded_ids[module.module_id()] = true
	return kernel


## A save written by the old build: module data in its v0.1.0 shape.
func _old_save() -> Dictionary:
	return {
		"version": SaveManager.SAVE_VERSION,
		"slot": {"id": "slot_old", "name": "Old Colony", "saved_at": 1, "total_days": 3},
		"state": {"resources": {"food": 1}},
		"modules": {"evolved": {"version": "0.1.0", "data": {"grain": 7}}},
	}


func test_an_old_save_is_migrated_forward_before_the_module_sees_it() -> void:
	var module := EvolvedModule.new()
	var kernel := _kernel_with(module)

	var loaded: Dictionary = kernel.saves.restore(kernel, _old_save())

	assert_true(bool(loaded["ok"]))
	assert_eq(int((module.restored["resources"] as Dictionary)["food"]), 7,
		"grain 7 walked through both steps into the present shape")
	assert_eq((loaded["migrations"] as Dictionary)["evolved"], ["0.2.0", "0.3.0"],
		"and what ran is reported")


func test_a_current_save_is_handed_over_untouched() -> void:
	var module := EvolvedModule.new()
	var kernel := _kernel_with(module)

	var loaded: Dictionary = kernel.saves.restore(kernel, {
		"version": SaveManager.SAVE_VERSION,
		"modules": {"evolved": {"version": "0.3.0", "data": {"resources": {"food": 42}}}},
	})

	assert_eq(int((module.restored["resources"] as Dictionary)["food"]), 42)
	assert_eq((loaded["migrations"] as Dictionary).size(), 0, "nothing to migrate")


func test_a_failed_migration_leaves_the_world_untouched() -> void:
	var module := EvolvedModule.new("0.1.0")  # build is OLDER than the save
	var kernel := _kernel_with(module)
	kernel.state.set_value("resources", {"food": 999})

	var loaded: Dictionary = kernel.saves.restore(kernel, {
		"version": SaveManager.SAVE_VERSION,
		"state": {"resources": {"food": 1}},
		"modules": {"evolved": {"version": "0.9.0", "data": {}}},
	})

	assert_false(bool(loaded["ok"]))
	assert_eq(String(loaded["error"]), "module_from_newer_version")
	# Migrations run before anything is applied, so a load either happens completely or not at
	# all. Migrating as each module restored would leave the world half-loaded.
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary)["food"]), 999,
		"the running game is not half-overwritten by a load that could not finish")
	assert_eq(module.restored, {}, "and the module was never handed anything")


func test_a_module_added_since_the_save_does_not_replay_its_history() -> void:
	var module := EvolvedModule.new()
	var kernel := _kernel_with(module)

	# The save has no stamp for this module at all — it predates the module entirely.
	var loaded: Dictionary = kernel.saves.restore(kernel, {
		"version": SaveManager.SAVE_VERSION, "modules": {"base_game": {"version": "0.1.0", "data": {}}},
	})

	assert_true(bool(loaded["ok"]))
	# Guessing "0.0.0" would replay the whole chain over empty data and hand the module
	# {"resources": {"food": 0}} as if it had once held grain.
	assert_eq(module.restored, {}, "no stamp means nothing to migrate, not migrate from zero")


func test_data_of_a_module_that_is_not_loaded_survives_a_save_cycle() -> void:
	# Disabling a DLC, saving, then re-enabling it must not erase what it owned. Losing content
	# by turning something off is not a choice a player knowingly makes.
	var kernel := _kernel_with(null)  # the "dlc" module is NOT loaded in this build
	kernel.saves.restore(kernel, {
		"version": SaveManager.SAVE_VERSION,
		"modules": {"dlc_module": {"version": "1.4.0", "data": {"relics": ["spear", "urn"]}}},
	})

	var payload := kernel.saves.capture(kernel, "slot_x", "Colony")

	var dlc: Dictionary = (payload["modules"] as Dictionary)["dlc_module"]
	assert_eq(String(dlc["version"]), "1.4.0", "carried forward at the version that wrote it")
	assert_eq((dlc["data"] as Dictionary)["relics"], ["spear", "urn"], "with its data intact")
	# Deliberately unmigrated: this build cannot know what those shapes mean, so it carries the
	# bytes and lets the owning module migrate them when it comes back.


func test_migrations_survive_an_actual_round_trip_through_disk() -> void:
	var writer := _kernel_with(null)
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var f := FileAccess.open("%s/slot_old.json" % SCRATCH_DIR, FileAccess.WRITE)
	f.store_string(JSON.stringify(_old_save()))
	f.close()

	var module := EvolvedModule.new()
	var reader := _kernel_with(module)
	var loaded: Dictionary = reader.saves.load_slot(reader, "slot_old")

	assert_true(bool(loaded["ok"]), "error: %s" % loaded.get("error", ""))
	assert_eq(int((module.restored["resources"] as Dictionary)["food"]), 7,
		"a file written by the old build loads into the new one")
	assert_eq(int((reader.state.get_value("resources", {}) as Dictionary)["food"]), 1,
		"and the rest of the save applied normally")
