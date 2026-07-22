extends GutTest

## Which slot the player is in and when it gets written (M4/B4a). `SaveManager` is the
## mechanism; this is the policy — resume-or-start, dirty tracking, the coalesced turn-boundary
## autosave, and the lifecycle save that is the only one Android actually guarantees us.

const SCRATCH_DIR := "user://test_session"


func after_each() -> void:
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
	# The suite runs with OUTPOST_TEST_RUN=1, which switches automatic writes off so a test run
	# never touches the player's real saves. These tests are *about* that machinery, so they opt
	# back in against a scratch directory.
	kernel.session.autosave_enabled = true
	return kernel


func _food(kernel: GameKernel) -> int:
	return int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


func _grant(kernel: GameKernel, amount: int) -> void:
	kernel.commands.execute(GrantResourceCommand.new("food", amount))


# --- starting a session ------------------------------------------------------------------

func test_a_first_run_starts_fresh_without_writing_anything() -> void:
	var kernel := _kernel()

	var started: Dictionary = kernel.session.continue_or_start()

	assert_true(bool(started["ok"]))
	assert_false(bool(started["continued"]), "there was nothing to continue")
	assert_false(kernel.session.has_slot(), "a slot is created on the first save, not on boot")
	assert_eq(kernel.saves.slots().size(), 0,
		"opening the game and closing it leaves no stray empty settlement")


func test_a_second_run_continues_the_newest_slot() -> void:
	var first := _kernel()
	first.session.start_new("Ironhold")
	_grant(first, 6)
	first.clock.advance(4)
	first.session.save("test")

	var second := _kernel()
	var resumed: Dictionary = second.session.continue_or_start()

	assert_true(bool(resumed["continued"]), "the settlement is resumed")
	assert_eq(second.session.slot_name, "Ironhold", "including its name")
	assert_eq(_food(second), 6)
	assert_eq(second.clock.total_days, 4)


func test_an_unlistable_save_is_skipped_and_the_player_still_gets_a_game() -> void:
	var kernel := _kernel()
	_write_raw("slot_broken", {"version": SaveManager.SAVE_VERSION + 9, "slot": {"name": "Doomed"}})

	var resumed: Dictionary = kernel.session.continue_or_start()

	# A save this build cannot even read never reaches the load menu, so continuing simply finds
	# nothing to continue. That is not an error — and because the session stays unattached, the
	# next save creates a *new* slot instead of overwriting the file nobody could read.
	assert_true(bool(resumed["ok"]))
	assert_false(bool(resumed["continued"]))
	assert_false(kernel.session.has_slot())
	kernel.session.save("manual")
	assert_true(FileAccess.file_exists("%s/slot_broken.json" % SCRATCH_DIR), "the bad file is untouched")


func test_a_save_that_lists_but_cannot_load_leaves_the_session_detached() -> void:
	var kernel := _kernel()
	# Readable envelope, so it lists — but base_game's data was written by a newer build, which
	# B3 refuses. This is the realistic version of "the newest save will not load".
	_write_raw("slot_future", {
		"version": SaveManager.SAVE_VERSION,
		"slot": {"id": "slot_future", "name": "Doomed", "saved_at": 9, "total_days": 2},
		"modules": {"base_game": {"version": "99.0.0", "data": {}}},
	})

	var resumed: Dictionary = kernel.session.continue_or_start()

	assert_false(bool(resumed["ok"]))
	assert_eq(String(resumed["error"]), "module_from_newer_version")
	# Attaching to the slot would overwrite it on the next autosave. Staying detached keeps the
	# game playable and leaves the file for the player to deal with.
	assert_false(kernel.session.has_slot(), "the session does not adopt a slot it could not read")
	kernel.session.mark_dirty()
	kernel.session.save_on_lifecycle_event("app_paused")
	var still_doomed: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/slot_future.json" % SCRATCH_DIR)) as Dictionary
	assert_eq(String((still_doomed["slot"] as Dictionary)["name"]), "Doomed", "nothing overwrote it")


func _write_raw(slot_id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var f := FileAccess.open("%s/%s.json" % [SCRATCH_DIR, slot_id], FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


# --- writing ------------------------------------------------------------------------------

func test_the_first_save_creates_the_slot_and_later_saves_reuse_it() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")

	_grant(kernel, 1)
	kernel.session.save("test")
	var created := kernel.session.slot_id
	_grant(kernel, 1)
	kernel.session.save("test")

	assert_false(created.is_empty())
	assert_eq(kernel.session.slot_id, created, "the session stays in its slot")
	assert_eq(kernel.saves.slots().size(), 1, "saving twice does not make two settlements")


func test_applying_a_command_marks_the_session_dirty() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")

	# Nothing has happened yet, so a lifecycle save has nothing to write.
	assert_false(kernel.session.save_on_lifecycle_event("app_paused"), "clean session writes nothing")

	# `command_applied` is the authoritative "the world changed" signal — every state mutation
	# goes through the command bus by design.
	_grant(kernel, 3)
	assert_true(kernel.session.save_on_lifecycle_event("app_paused"), "a changed world is written")


func test_time_passing_also_marks_the_session_dirty() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")

	kernel.clock.advance(1)

	assert_true(kernel.session.save_on_lifecycle_event("app_paused"),
		"time moving is a change even when no command ran")


func test_a_lifecycle_save_ignores_the_autosave_interval() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 1)
	kernel.session.save("test")  # resets the interval clock

	_grant(kernel, 1)
	# Android kills backgrounded apps without asking, so this is the only write we are ever
	# guaranteed. Coalescing it away would be losing the turn for the sake of a file write.
	assert_true(kernel.session.save_on_lifecycle_event("app_paused"))


func test_turn_boundary_autosaves_are_coalesced() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 1)

	assert_true(kernel.session.autosave(), "the first autosave writes")
	_grant(kernel, 1)
	assert_false(kernel.session.autosave(), "a fast player does not write a file every second")


func test_autosave_does_nothing_when_nothing_changed() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")

	assert_false(kernel.session.autosave(), "an unchanged world is not rewritten")
	assert_eq(kernel.saves.slots().size(), 0)


func test_automated_runs_never_write_to_the_real_save_directory() -> void:
	var kernel := _kernel()
	kernel.session.autosave_enabled = false  # stands in for OUTPOST_TEST_RUN
	kernel.session.start_new("Ironhold")
	_grant(kernel, 1)

	assert_false(kernel.session.autosave(), "no automatic write")
	assert_false(kernel.session.save_on_lifecycle_event("app_paused"), "not even on lifecycle")
	assert_true(bool(kernel.session.save("manual")["ok"]),
		"an explicit save still works — the guard is on automatic writes only")


func test_a_full_put_it_down_and_pick_it_up_cycle() -> void:
	# The milestone's goal in one test: play, get backgrounded, come back to the same world.
	var playing := _kernel()
	playing.session.start_new("Ironhold")
	_grant(playing, 12)
	playing.clock.advance(9)
	assert_true(playing.session.save_on_lifecycle_event("app_paused"), "the OS warned us")

	var relaunched := _kernel()
	relaunched.session.continue_or_start()

	assert_eq(_food(relaunched), 12)
	assert_eq(relaunched.clock.total_days, 9)
	assert_eq(relaunched.session.slot_name, "Ironhold")
