extends GutTest

## The two persistence layers (M4/B4a). The workspace is the live game, written at every turn
## boundary but only where it changed — that is what survives a crash. A slot file is a whole
## snapshot the player named, written rarely. These tests are mostly about keeping the two
## honest with each other.

const SCRATCH_SAVES := "user://test_session_saves"
const SCRATCH_WORK := "user://test_session_work"


func after_each() -> void:
	for path in [SCRATCH_SAVES, SCRATCH_WORK]:
		_wipe(path)


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.saves = SaveManager.new(SCRATCH_SAVES)
	kernel.workspace = SaveWorkspace.new(SCRATCH_WORK)
	# The suite runs with OUTPOST_TEST_RUN=1, which switches automatic writes off so a test run
	# never touches the player's real game. These tests are *about* that machinery, so they opt
	# back in against scratch directories.
	kernel.session.autosave_enabled = true
	return kernel


func _food(kernel: GameKernel) -> int:
	return int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0))


func _grant(kernel: GameKernel, amount: int) -> void:
	kernel.commands.execute(GrantResourceCommand.new("food", amount))


# --- the cheap, frequent write -----------------------------------------------------------

func test_a_checkpoint_writes_the_live_game_as_separate_parts() -> void:
	var kernel := _kernel()
	_grant(kernel, 4)
	kernel.clock.advance(2)

	kernel.session.checkpoint("test")

	# Separate parts are the whole point: at M5 a settlement carrying thousands of memories
	# must not be re-serialized whole on every turn.
	assert_true(kernel.workspace.has_part(SaveWorkspace.WORLD))
	assert_true(kernel.workspace.has_part(SaveWorkspace.CLOCK))
	assert_true(kernel.workspace.has_part(SaveWorkspace.META))
	assert_eq(kernel.saves.slots().size(), 0, "and no slot file was created")


func test_only_the_parts_that_changed_are_rewritten() -> void:
	var kernel := _kernel()
	_grant(kernel, 1)
	kernel.session.checkpoint("first")

	kernel.clock.advance(1)
	var written := kernel.session.checkpoint("second")

	# Content comparison, not dirty flags: a flag someone forgets to set is a lost turn, and the
	# bug stays invisible until a player loses progress.
	assert_eq(written, 2, "only the clock moved — clock + meta (which carries the day count)")


func test_a_checkpoint_that_changes_nothing_writes_nothing() -> void:
	var kernel := _kernel()
	_grant(kernel, 1)
	kernel.session.checkpoint("first")

	assert_eq(kernel.session.checkpoint("again"), 0,
		"an unchanged world costs a comparison and no I/O — which is why there is no interval")


func test_the_live_game_survives_a_crash_without_any_slot_file() -> void:
	# The contract: lose at most the turn in progress, with no snapshot involved at all.
	var playing := _kernel()
	_grant(playing, 12)
	playing.clock.advance(9)
	playing.session.checkpoint("turn")

	var relaunched := _kernel()
	var resumed: Dictionary = relaunched.session.continue_or_start()

	assert_true(bool(resumed["continued"]))
	assert_eq(String(resumed["source"]), "workspace")
	assert_eq(_food(relaunched), 12)
	assert_eq(relaunched.clock.total_days, 9)
	assert_eq(relaunched.saves.slots().size(), 0, "no snapshot was ever taken")


func test_resuming_writes_nothing() -> void:
	var playing := _kernel()
	_grant(playing, 3)
	playing.clock.advance(2)
	playing.session.checkpoint("turn")

	var relaunched := _kernel()
	relaunched.session.continue_or_start()

	# Found in the live run: without recording read parts as current, the first checkpoint after
	# a resume rewrote all six identically — doubling the I/O of every launch, which is exactly
	# the write amplification this split exists to avoid.
	assert_eq(relaunched.session.checkpoint("turn"), 0, "a resumed game rewrites nothing")
	assert_false(FileAccess.file_exists("%s/world.json.bak" % SCRATCH_WORK),
		"and nothing was rewritten during the resume itself")


func test_a_lifecycle_event_takes_the_same_cheap_checkpoint() -> void:
	# Android kills backgrounded apps without asking, so this is the last guaranteed moment —
	# and because it only writes what moved, it is cheap enough to always take.
	var kernel := _kernel()
	_grant(kernel, 3)

	assert_true(kernel.session.save_on_lifecycle_event("app_paused") > 0)
	assert_eq(kernel.session.save_on_lifecycle_event("app_paused"), 0, "and again writes nothing")


# --- the rare, whole write ----------------------------------------------------------------

func test_a_snapshot_creates_a_named_slot_and_reuses_it() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 1)

	kernel.session.snapshot("manual")
	var created := kernel.session.slot_id
	_grant(kernel, 1)
	kernel.session.snapshot("manual")

	assert_false(created.is_empty())
	assert_eq(kernel.session.slot_id, created, "the session stays in its slot")
	assert_eq(kernel.saves.slots().size(), 1, "saving twice does not make two settlements")
	assert_eq(String((kernel.saves.slots()[0] as Dictionary)["name"]), "Ironhold")


func test_opening_and_closing_without_playing_leaves_no_settlement_behind() -> void:
	var kernel := _kernel()

	var started: Dictionary = kernel.session.continue_or_start()

	assert_true(bool(started["ok"]))
	assert_false(bool(started["continued"]))
	assert_eq(kernel.saves.slots().size(), 0, "a slot is created on the first snapshot, not on boot")


# --- which layer wins ----------------------------------------------------------------------

func test_the_live_game_wins_over_an_older_snapshot() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 5)
	kernel.session.snapshot("manual")   # snapshot holds 5
	_grant(kernel, 7)
	kernel.session.checkpoint("turn")   # workspace holds 12

	var relaunched := _kernel()
	var resumed: Dictionary = relaunched.session.continue_or_start()

	# The workspace *is* the game the player was playing; a slot is a copy they took of it.
	# Preferring the snapshot would silently discard everything since it was taken.
	assert_eq(String(resumed["source"]), "workspace")
	assert_eq(_food(relaunched), 12, "nothing since the snapshot is lost")


func test_an_unreadable_live_game_falls_back_to_the_newest_snapshot() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 5)
	kernel.session.snapshot("manual")
	_grant(kernel, 7)
	kernel.session.checkpoint("turn")
	# Corrupt the live game's world part *and* its backup, as a bad shutdown might.
	for suffix in ["", ".bak"]:
		var f := FileAccess.open("%s/meta.json%s" % [SCRATCH_WORK, suffix], FileAccess.WRITE)
		f.store_string("{ truncated")
		f.close()

	var relaunched := _kernel()
	var resumed: Dictionary = relaunched.session.continue_or_start()

	assert_true(bool(resumed["continued"]), "a snapshot is exactly the backup for this")
	assert_eq(String(resumed["source"]), "slot")
	assert_eq(_food(relaunched), 5, "the player loses what came after the snapshot, not the game")


func test_loading_a_slot_replaces_the_live_game_wholesale() -> void:
	var kernel := _kernel()
	kernel.session.start_new("Ironhold")
	_grant(kernel, 5)
	kernel.session.snapshot("manual")
	var slot := kernel.session.slot_id
	kernel.globals.set_value("mood", "from the later game")
	_grant(kernel, 7)
	kernel.session.checkpoint("turn")

	kernel.session.load_slot(slot)

	assert_eq(_food(kernel), 5, "the slot's world is in place")
	# A leftover part from the previous game would otherwise be read back as if it belonged.
	var relaunched := _kernel()
	relaunched.session.continue_or_start()
	assert_eq(_food(relaunched), 5)
	assert_null(relaunched.globals.get_value("mood", null), "no leftover from the replaced game")


func test_a_snapshot_that_will_not_load_leaves_the_session_detached() -> void:
	var kernel := _kernel()
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)
	var f := FileAccess.open("%s/slot_future.json" % SCRATCH_SAVES, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": SaveManager.SAVE_VERSION,
		"slot": {"id": "slot_future", "name": "Doomed", "saved_at": 9, "total_days": 2},
		"modules": {"base_game": {"version": "99.0.0", "data": {}}},
	}))
	f.close()

	var resumed: Dictionary = kernel.session.continue_or_start()

	assert_false(bool(resumed["ok"]))
	assert_eq(String(resumed["error"]), "module_from_newer_version")
	# Adopting the slot would let the next snapshot overwrite a file the player may still want.
	assert_false(kernel.session.has_slot())


func test_automated_runs_never_write_the_players_game() -> void:
	var kernel := _kernel()
	kernel.session.autosave_enabled = false  # stands in for OUTPOST_TEST_RUN
	_grant(kernel, 1)

	assert_eq(kernel.session.checkpoint("turn"), 0, "no automatic write")
	assert_eq(kernel.session.save_on_lifecycle_event("app_paused"), 0, "not even on lifecycle")
	assert_true(bool(kernel.session.snapshot("manual")["ok"]),
		"an explicit snapshot still works — the guard is on automatic writes only")


func test_a_live_game_from_a_newer_build_is_refused_and_left_completely_alone() -> void:
	# The downgrade case, and the most dangerous one in this whole system: an older build must
	# never treat "I cannot read this" as "there is nothing here". Falling through to a fresh
	# start would clear the workspace and destroy a settlement over a version mismatch.
	var kernel := _kernel()
	DirAccess.make_dir_recursive_absolute(SCRATCH_WORK)
	_write(SCRATCH_WORK, "meta", {"version": SaveManager.SAVE_VERSION,
		"slot": {"id": "", "name": "Ironhold", "saved_at": 5, "total_days": 3}})
	_write(SCRATCH_WORK, "world", {"resources": {"food": 4}})
	_write(SCRATCH_WORK, "module_base_game", {"version": "99.0.0", "data": {}})

	var resumed: Dictionary = kernel.session.continue_or_start()

	assert_false(bool(resumed["ok"]))
	assert_eq(String(resumed["error"]), "module_from_newer_version")
	assert_eq(String(resumed["source"]), "workspace_blocked", "it stops rather than moving on")
	assert_push_error("Left untouched", "and says loudly why, rather than failing quietly")
	# The player only has to reinstall the newer build to get their game back — but only if we
	# did not delete it first.
	assert_true(FileAccess.file_exists("%s/world.json" % SCRATCH_WORK), "the live game is intact")
	var world: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/world.json" % SCRATCH_WORK)) as Dictionary
	assert_eq(int((world["resources"] as Dictionary)["food"]), 4, "and unmodified")


func test_a_workspace_is_migrated_on_resume_like_any_save() -> void:
	# A workspace can be as old as any slot file if the player left the game closed across an
	# update, so it goes through B3's migrations too — which it does by reassembling into the
	# same envelope SaveManager.restore already understands.
	var kernel := _kernel()
	DirAccess.make_dir_recursive_absolute(SCRATCH_WORK)
	_write(SCRATCH_WORK, "meta", {"version": SaveManager.SAVE_VERSION,
		"slot": {"id": "", "name": "Ironhold", "saved_at": 5, "total_days": 3}})
	_write(SCRATCH_WORK, "world", {"resources": {"food": 4}})
	_write(SCRATCH_WORK, "clock", {"total_days": 3})
	_write(SCRATCH_WORK, "module_base_game", {"version": "0.0.1", "data": {}})

	var resumed: Dictionary = kernel.session.continue_or_start()

	assert_true(bool(resumed["ok"]), "an older live game opens normally")
	assert_eq(String(resumed["source"]), "workspace")
	assert_eq(_food(kernel), 4)
	assert_eq(kernel.clock.total_days, 3)


func _write(dir: String, part: String, data: Dictionary) -> void:
	var f := FileAccess.open("%s/%s.json" % [dir, part], FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
