extends GutTest

## Cues declared in data, played by name. Runs against the real manifest and the real audio server
## (headless uses a dummy driver), so what is asserted is what the game does — a cue is registered,
## a stream loads, `playing` is true, the buses exist.

const MANIFEST := "res://modules/base_game/assets/audio/audio.json"
const SCRATCH_MANIFEST := "user://test_audio_manifest.json"


func _manager() -> AudioManager:
	var audio := AudioManager.new()
	add_child_autofree(audio)  # _ready builds the players; free them with the test
	# Playback is off by default under the test runner (see AudioManager.enabled). These are the
	# tests of that machinery, so they are the ones that turn it back on — the same shape as the
	# save tests re-enabling autosave against a scratch directory.
	audio.enabled = true
	return audio


func after_each() -> void:
	if FileAccess.file_exists(SCRATCH_MANIFEST):
		DirAccess.remove_absolute(SCRATCH_MANIFEST)


func _write_manifest(text: String) -> String:
	var file := FileAccess.open(SCRATCH_MANIFEST, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return SCRATCH_MANIFEST


func test_it_registers_the_cues_a_module_declares() -> void:
	var audio := _manager()
	assert_true(audio.load_manifest(MANIFEST), "the base game's manifest loads")
	assert_true(audio.has_cue(AudioManager.MUSIC, "main_menu"))
	assert_true(audio.has_cue(AudioManager.SFX, "ui_click"))


func test_playing_music_by_name_starts_it() -> void:
	var audio := _manager()
	audio.load_manifest(MANIFEST)
	audio.play_music("main_menu")
	assert_eq(audio.current_music(), "main_menu")

	audio.stop_music()
	assert_eq(audio.current_music(), "", "stopping is reflected, not just requested")


func test_asking_again_for_the_track_already_playing_is_a_no_op() -> void:
	# Screens announce what should be playing without knowing what came before, so walking
	# menu -> wizard -> menu must not keep starting the theme over. A restart would go through
	# _start_music, which rewinds the stream, so a playhead that has not moved back is the tell.
	var audio := _manager()
	audio.load_manifest(MANIFEST)
	audio.play_music("main_menu")
	await wait_frames(3)
	var elapsed := audio._music.get_playback_position()

	audio.play_music("main_menu")

	assert_eq(audio.current_music(), "main_menu", "still the same track")
	assert_true(audio._music.get_playback_position() >= elapsed,
		"the playhead did not jump back to the start")


func test_an_unknown_cue_is_refused_rather_than_crashing() -> void:
	# A cue a module did not ship (a DLC that is not loaded) must cost the sound, nothing more.
	var audio := _manager()
	audio.load_manifest(MANIFEST)
	audio.play_music("no_such_track")
	audio.play_sfx("no_such_click")
	assert_eq(audio.current_music(), "", "nothing started")


func test_an_automated_run_stays_silent_unless_asked() -> void:
	# The default the suite relies on: cues still register (so wiring is testable), but nothing
	# plays, so no run loads a multi-megabyte stream or leaves a playback open at exit.
	var audio := _manager()
	audio.enabled = false
	audio.load_manifest(MANIFEST)

	audio.play_music("main_menu")

	assert_true(audio.has_cue(AudioManager.MUSIC, "main_menu"), "the cue is still registered")
	assert_eq(audio.current_music(), "", "but nothing was played")


func test_a_missing_manifest_is_reported_not_fatal() -> void:
	var audio := _manager()
	assert_false(audio.load_manifest("res://modules/base_game/assets/audio/nope.json"))


func test_a_cue_without_a_file_is_skipped() -> void:
	var audio := _manager()
	var path := _write_manifest('{"version": 1, "sfx": {"broken": {"volume": 1.0}}}')
	assert_false(audio.load_manifest(path), "a manifest whose only cue is unusable adds nothing")
	assert_false(audio.has_cue(AudioManager.SFX, "broken"))


func test_every_category_has_its_own_bus() -> void:
	# The player's volume lives on the bus, so a settings screen can move Music without touching
	# SFX. A missing bus silently collapses that into one slider.
	for category in AudioManager.CATEGORIES:
		var bus := AudioManager.bus_for(category)
		assert_ne(bus, "Master", "category '%s' has a bus of its own" % category)
		assert_true(AudioServer.get_bus_index(bus) >= 0)


func test_category_volume_round_trips_and_zero_means_silent() -> void:
	var audio := _manager()
	var was := audio.category_volume(AudioManager.MUSIC)

	audio.set_category_volume(AudioManager.MUSIC, 0.5)
	assert_almost_eq(audio.category_volume(AudioManager.MUSIC), 0.5, 0.01)
	audio.set_category_volume(AudioManager.MUSIC, 0.0)
	assert_eq(audio.category_volume(AudioManager.MUSIC), 0.0, "zero reads back as silence, not -80 dB")

	audio.set_category_volume(AudioManager.MUSIC, was)


func test_wiring_clicks_gives_every_button_a_sound_exactly_once() -> void:
	var audio := _manager()
	audio.load_manifest(MANIFEST)
	var screen := Control.new()
	add_child_autofree(screen)
	var row := HBoxContainer.new()
	screen.add_child(row)
	var button := Button.new()
	row.add_child(button)  # nested, to prove it walks the whole tree

	audio.wire_clicks(screen)
	assert_eq(button.pressed.get_connections().size(), 1, "the button makes a sound")

	# Twice must not double it: re-entering a screen would otherwise click twice, then three times.
	audio.wire_clicks(screen)
	assert_eq(button.pressed.get_connections().size(), 1, "wiring twice connects once")


func test_a_button_added_after_wiring_still_makes_a_sound() -> void:
	# Screens add controls after `_ready` (a list that fills, a row that appears). A control that is
	# silent because it arrived late is the bug this catches.
	var audio := _manager()
	audio.load_manifest(MANIFEST)
	var screen := Control.new()
	add_child_autofree(screen)
	audio.wire_clicks(screen)

	var late := Button.new()
	screen.add_child(late)

	assert_eq(late.pressed.get_connections().size(), 1)
