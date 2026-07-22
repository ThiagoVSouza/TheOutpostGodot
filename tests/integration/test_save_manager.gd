extends GutTest

## Named save slots on disk (M4/B2): a settlement written to a file and read back into a
## genuinely fresh kernel, plus the failure modes a save file actually meets — a crash
## mid-write, a corrupt file, and a save from a build newer than this one.

const SCRATCH_DIR := "user://test_saves"


## A module the registry never discovered, pushed into a booted kernel so the module save-data
## hook can be exercised. base_game saves nothing yet, so without this the hook would only be
## covered by its own default.
class SpyModule extends Module:
	var restored: Dictionary = {}
	var restore_calls: int = 0

	func _init() -> void:
		manifest = ModuleManifest.new()
		manifest.id = "spy_module"
		manifest.version = "2.3.4"

	func capture_save_data(_kernel: GameKernel) -> Dictionary:
		return {"banners": 3}

	func restore_save_data(_kernel: GameKernel, data: Dictionary) -> void:
		restored = data
		restore_calls += 1


func after_each() -> void:
	_clear_scratch_dir()


func _clear_scratch_dir() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file])
	DirAccess.remove_absolute(SCRATCH_DIR)


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.saves = SaveManager.new(SCRATCH_DIR)
	return kernel


func _spy_kernel() -> Array:
	var kernel := _kernel()
	var spy := SpyModule.new()
	# The registry discovers modules from disk; there is no seam to register one at runtime,
	# so the test appends directly. Reaching into `_modules` is deliberate and confined here.
	kernel.modules._modules.append(spy)
	return [kernel, spy]


func _food(kernel: GameKernel) -> int:
	return int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


func test_a_settlement_survives_being_written_and_read_back() -> void:
	var before := _kernel()
	before.state.set_value("resources", {"food": 12, "gold": 4})
	before.globals.set_value("mood", "uneasy")
	before.clock.advance(37)

	var saved: Dictionary = before.saves.save_new(before, "First Colony")
	assert_true(bool(saved["ok"]), "the save is written")

	# A genuinely fresh kernel: nothing carried over but the file on disk.
	var after := _kernel()
	var loaded: Dictionary = after.saves.load_slot(after, String(saved["slot_id"]))

	assert_true(bool(loaded["ok"]), "and read back")
	assert_eq(_food(after), 12, "resources survive")
	assert_eq(String(after.globals.get_value("mood", "")), "uneasy", "globals survive (D31)")
	assert_eq(after.clock.total_days, 37, "the calendar survives")


func test_a_pending_question_is_part_of_the_save() -> void:
	# B1 gave suspended instances an owner; this is why that mattered. A save without them
	# would silently drop whatever the player had been asked and not yet answered.
	var before := _kernel()
	var instance := WorkflowInstance.create("burn", 1, {}, 0)
	instance.status = WorkflowInstance.Status.SUSPENDED
	instance.wake = {"type": "confirmation", "msg": "confirm.burn"}
	before.workflow_instances.remember(instance)

	var saved: Dictionary = before.saves.save_new(before, "Mid-question")
	var after := _kernel()
	after.saves.load_slot(after, String(saved["slot_id"]))

	assert_eq(after.workflow_instances.pending_confirmations().size(), 1,
		"the unanswered question comes back with the save")


func test_module_data_and_version_are_captured_and_restored() -> void:
	var pair := _spy_kernel()
	var kernel: GameKernel = pair[0]
	var spy: SpyModule = pair[1]

	var payload := kernel.saves.capture(kernel, "slot_x", "name")
	var modules: Dictionary = payload["modules"]

	assert_true(modules.has("base_game"), "every loaded module is stamped, even one that saves nothing")
	assert_eq(String((modules["spy_module"] as Dictionary)["version"]), "2.3.4",
		"the manifest version is recorded, which is what B3 will migrate on")
	assert_eq(int(((modules["spy_module"] as Dictionary)["data"] as Dictionary)["banners"]), 3)

	kernel.saves.restore(kernel, payload)
	assert_eq(spy.restore_calls, 1)
	assert_eq(int(spy.restored["banners"]), 3, "the module gets its own data back")


func test_a_module_absent_from_the_save_is_still_told_about_the_load() -> void:
	var pair := _spy_kernel()
	var kernel: GameKernel = pair[0]
	var spy: SpyModule = pair[1]

	# A save made before this module existed.
	kernel.saves.restore(kernel, {"version": 1, "modules": {"base_game": {"version": "0.1.0", "data": {}}}})

	assert_eq(spy.restore_calls, 1, "a module added since the save still hears about the load")
	assert_eq(spy.restored, {}, "with empty data, not a skipped call")


func test_loading_does_not_replay_the_calendar() -> void:
	var kernel := _kernel()
	var days: Array = []
	kernel.events.subscribe("day_passed", func(_p: Dictionary) -> void: days.append(1))

	kernel.saves.restore(kernel, {"version": 1, "clock": {"total_days": 400}})

	# Replaying a year of day_passed on load would re-run every scheduled workflow the save
	# already accounted for. Loading is not time passing.
	assert_eq(days.size(), 0, "restoring the clock fires no calendar events")
	assert_eq(kernel.clock.total_days, 400)


func test_named_slots_are_listed_newest_first() -> void:
	var kernel := _kernel()
	var older: Dictionary = kernel.saves.save_new(kernel, "Old Colony")
	var newer: Dictionary = kernel.saves.save_new(kernel, "New Colony")
	# Both land in the same second, so make the ordering deterministic rather than racy.
	_backdate(String(older["slot_id"]), 1000)

	var listed: Array = kernel.saves.slots()

	assert_eq(listed.size(), 2)
	assert_eq(String((listed[0] as Dictionary)["id"]), String(newer["slot_id"]), "newest first")
	assert_eq(String((listed[1] as Dictionary)["name"]), "Old Colony", "the player's name is metadata")
	# Found in the live run: JSON has no integer type, so these come back as floats and a load
	# menu would render "Day 11.0". Coerced once, in slots(), rather than at every call site.
	assert_true((listed[0] as Dictionary)["total_days"] is int, "total_days is listed as an int")
	assert_true((listed[0] as Dictionary)["saved_at"] is int, "and so is saved_at")


func test_saving_the_same_slot_twice_overwrites_and_keeps_a_backup() -> void:
	var kernel := _kernel()
	kernel.state.set_value("resources", {"food": 1})
	var saved: Dictionary = kernel.saves.save_new(kernel, "Colony")
	var slot_id := String(saved["slot_id"])

	kernel.state.set_value("resources", {"food": 99})
	kernel.saves.save_slot(kernel, slot_id, "Colony")

	assert_eq(kernel.saves.slots().size(), 1, "overwriting a slot does not create a second one")
	var fresh := _kernel()
	fresh.saves.load_slot(fresh, slot_id)
	assert_eq(_food(fresh), 99, "the newer save wins")
	assert_true(FileAccess.file_exists("%s/%s.json.bak" % [SCRATCH_DIR, slot_id]),
		"the previous contents are kept as a backup")


func test_a_corrupt_save_falls_back_to_its_backup() -> void:
	var kernel := _kernel()
	kernel.state.set_value("resources", {"food": 7})
	var saved: Dictionary = kernel.saves.save_new(kernel, "Colony")
	var slot_id := String(saved["slot_id"])
	kernel.state.set_value("resources", {"food": 8})
	kernel.saves.save_slot(kernel, slot_id, "Colony")  # now there is a .bak holding food: 7

	# A crash mid-write, or a truncated file after a power cut.
	var f := FileAccess.open("%s/%s.json" % [SCRATCH_DIR, slot_id], FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"state\": {\"resou")
	f.close()

	var fresh := _kernel()
	var loaded: Dictionary = fresh.saves.load_slot(fresh, slot_id)

	assert_true(bool(loaded["ok"]), "the backup carries the load")
	assert_eq(_food(fresh), 7, "one save is lost; the slot is not")


func test_a_corrupt_save_with_no_backup_fails_clearly() -> void:
	var kernel := _kernel()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var f := FileAccess.open("%s/slot_broken.json" % SCRATCH_DIR, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()

	var loaded: Dictionary = kernel.saves.load_slot(kernel, "slot_broken")

	assert_false(bool(loaded["ok"]))
	assert_eq(String(loaded["error"]), "corrupt_save")
	assert_eq(kernel.saves.slots().size(), 0,
		"and one corrupt file does not make the whole load menu unusable")


func test_a_save_from_a_newer_build_is_refused_not_guessed_at() -> void:
	var kernel := _kernel()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var f := FileAccess.open("%s/slot_future.json" % SCRATCH_DIR, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": SaveManager.SAVE_VERSION + 1, "state": {"resources": {"food": 5}}}))
	f.close()

	var loaded: Dictionary = kernel.saves.load_slot(kernel, "slot_future")

	# Loading it anyway would quietly discard whatever that version added.
	assert_false(bool(loaded["ok"]))
	assert_eq(String(loaded["error"]), "save_from_newer_version")
	assert_eq(_food(kernel), 0, "nothing was applied")


func test_deleting_a_slot_removes_it_and_its_backup() -> void:
	var kernel := _kernel()
	var saved: Dictionary = kernel.saves.save_new(kernel, "Colony")
	var slot_id := String(saved["slot_id"])
	kernel.saves.save_slot(kernel, slot_id, "Colony")  # create a .bak too

	assert_true(kernel.saves.delete_slot(slot_id))

	assert_false(kernel.saves.has_slot(slot_id))
	assert_eq(kernel.saves.slots().size(), 0)
	assert_false(FileAccess.file_exists("%s/%s.json.bak" % [SCRATCH_DIR, slot_id]), "no orphan backup")
	assert_true(kernel.saves.delete_slot(slot_id), "deleting what is already gone still succeeds")


func test_a_slot_id_cannot_escape_the_saves_directory() -> void:
	var kernel := _kernel()

	var escaped: Dictionary = kernel.saves.save_slot(kernel, "../../evil", "Colony")

	assert_false(bool(escaped["ok"]))
	assert_eq(String(escaped["error"]), "bad_slot_id")
	assert_false(bool(kernel.saves.read_slot("../../evil")["ok"]), "and it cannot be read either")


func test_listing_ignores_backups_and_temp_files() -> void:
	var kernel := _kernel()
	kernel.saves.save_new(kernel, "Colony")
	var f := FileAccess.open("%s/slot_stray.json.tmp" % SCRATCH_DIR, FileAccess.WRITE)
	f.store_string("{}")
	f.close()

	assert_eq(kernel.saves.slots().size(), 1, "only real slot files are offered to the player")


func _backdate(slot_id: String, seconds: int) -> void:
	var path := "%s/%s.json" % [SCRATCH_DIR, slot_id]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	(data["slot"] as Dictionary)["saved_at"] = int(data["slot"]["saved_at"]) - seconds
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
