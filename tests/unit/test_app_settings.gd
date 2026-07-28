extends GutTest

## App-level preferences: the ones that belong to the player rather than to a save.

const SCRATCH := "user://test_settings.cfg"


func _settings() -> AppSettings:
	var settings := AppSettings.new(SCRATCH)
	settings.persist = true  # off by default under the test runner; this test owns a scratch file
	return settings


func after_each() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_defaults_are_a_complete_configuration() -> void:
	# Nothing stored yet: every level still has to answer, because the defaults are what a first run
	# plays with.
	var settings := AppSettings.new(SCRATCH)
	for category in AudioManager.MIXER_LEVELS:
		var level := settings.audio_volume(category)
		assert_true(level > 0.0 and level <= 1.0, "'%s' has an audible default" % category)
	assert_true(NarrationSettings.is_level(settings.narration_level()))


func test_a_level_survives_a_restart() -> void:
	var settings := _settings()
	settings.set_audio_volume(AudioManager.MUSIC, 0.25)
	assert_true(settings.save(), "written to disk")

	var reopened := AppSettings.new(SCRATCH)
	reopened.load_from_disk()
	assert_almost_eq(reopened.audio_volume(AudioManager.MUSIC), 0.25, 0.001)


func test_a_missing_file_is_not_an_error() -> void:
	# A first run, or a config the player deleted. The defaults are playable, so refusing to start
	# would be the wrong answer.
	var settings := AppSettings.new("user://test_settings_absent.cfg")
	settings.load_from_disk()
	assert_almost_eq(settings.audio_volume(AudioManager.MASTER),
		float(AppSettings.DEFAULTS[AudioManager.MASTER]), 0.001)


func test_a_damaged_file_falls_back_to_defaults() -> void:
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("this is not an ini [[[")
	file.close()

	var settings := AppSettings.new(SCRATCH)
	settings.load_from_disk()

	assert_almost_eq(settings.audio_volume(AudioManager.MUSIC),
		float(AppSettings.DEFAULTS[AudioManager.MUSIC]), 0.001,
		"a damaged config reads as unset, not as silence")


func test_levels_are_clamped_rather_than_trusted() -> void:
	var settings := _settings()
	settings.set_audio_volume(AudioManager.MUSIC, 4.0)
	settings.set_audio_volume(AudioManager.SFX, -1.0)
	assert_eq(settings.audio_volume(AudioManager.MUSIC), 1.0)
	assert_eq(settings.audio_volume(AudioManager.SFX), 0.0)


func test_an_unreadable_narration_level_is_refused() -> void:
	var settings := _settings()
	var before := settings.narration_level()
	settings.set_narration_level("operatic")
	assert_eq(settings.narration_level(), before, "the stored level stays a known one")


func test_window_mode_and_vsync_default_to_a_playable_configuration() -> void:
	var settings := AppSettings.new(SCRATCH)
	assert_eq(settings.window_mode(), AppSettings.WINDOW_MODE_FULLSCREEN)
	assert_eq(settings.vsync_mode(), AppSettings.VSYNC_ON)


func test_window_mode_and_vsync_survive_a_restart() -> void:
	var settings := _settings()
	settings.set_window_mode(AppSettings.WINDOW_MODE_WINDOWED)
	settings.set_vsync_mode(AppSettings.VSYNC_OFF)
	assert_true(settings.save())

	var reopened := AppSettings.new(SCRATCH)
	reopened.load_from_disk()
	assert_eq(reopened.window_mode(), AppSettings.WINDOW_MODE_WINDOWED)
	assert_eq(reopened.vsync_mode(), AppSettings.VSYNC_OFF)


func test_a_bare_legacy_windowed_default_migrates_to_fullscreen() -> void:
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("[video]\nwindow_mode=\"windowed\"\n")
	file.close()

	var settings := _settings()
	settings.load_from_disk()
	assert_eq(settings.window_mode(), AppSettings.WINDOW_MODE_FULLSCREEN)

	var reopened := _settings()
	reopened.load_from_disk()
	assert_eq(reopened.window_mode(), AppSettings.WINDOW_MODE_FULLSCREEN,
		"the migration is saved, so it runs only once")


func test_an_unknown_window_mode_or_vsync_value_is_refused() -> void:
	var settings := _settings()
	var before_mode := settings.window_mode()
	var before_vsync := settings.vsync_mode()
	settings.set_window_mode("holographic")
	settings.set_vsync_mode("triple-buffered")
	assert_eq(settings.window_mode(), before_mode, "the stored mode stays a known one")
	assert_eq(settings.vsync_mode(), before_vsync, "the stored vsync mode stays a known one")


func test_resolution_monitor_and_fps_default_to_leaving_things_alone() -> void:
	# A first run uses the project's platform launch policy instead of a stored user override, and
	# must not cap the frame rate behind V-Sync's back.
	var settings := AppSettings.new(SCRATCH)
	assert_eq(settings.resolution(), AppSettings.UNSET)
	assert_eq(settings.monitor(), AppSettings.MONITOR_UNSET)
	assert_eq(settings.max_fps(), AppSettings.MAX_FPS_UNCAPPED)


func test_video_choices_survive_a_restart() -> void:
	var settings := _settings()
	settings.set_resolution(String(AppSettings.RESOLUTIONS[0]))
	settings.set_monitor(1)
	settings.set_max_fps(60)
	assert_true(settings.save())

	var reopened := AppSettings.new(SCRATCH)
	reopened.load_from_disk()
	assert_eq(reopened.resolution(), String(AppSettings.RESOLUTIONS[0]))
	assert_eq(reopened.monitor(), 1)
	assert_eq(reopened.max_fps(), 60)


func test_an_unknown_resolution_is_refused() -> void:
	var settings := _settings()
	settings.set_resolution("1x1")
	assert_eq(settings.resolution(), AppSettings.UNSET, "a size not on the list is not stored")


func test_a_stored_monitor_is_kept_even_while_it_is_out_of_range() -> void:
	# A laptop that stored "monitor 2" at the desk should get that choice back when it is docked
	# again, rather than have one undocked run erase it. apply_video() skips it while out of range.
	var settings := _settings()
	settings.set_monitor(7)
	assert_eq(settings.monitor(), 7)


func test_a_negative_frame_cap_reads_as_uncapped() -> void:
	var settings := _settings()
	settings.set_max_fps(-30)
	assert_eq(settings.max_fps(), AppSettings.MAX_FPS_UNCAPPED)


func test_applying_video_sets_the_engine_frame_cap_even_headless() -> void:
	# max_fps is not a display-server call, so it applies on any platform — including the test
	# runner, which is what lets this be asserted at all.
	var before := Engine.max_fps
	var settings := _settings()
	settings.set_max_fps(45)

	settings.apply_video()

	assert_eq(Engine.max_fps, 45)
	Engine.max_fps = before  # shared engine state; leave it as we found it


func test_applying_video_does_not_crash_headless() -> void:
	# The test runner has no real window (DisplayServer.get_name() == "headless"); apply_video()
	# must no-op rather than call into a display server that is not there.
	assert_eq(DisplayServer.get_name(), "headless", "this test's premise")
	var settings := _settings()
	settings.apply_video()
	assert_true(true, "apply_video() returned instead of calling into a display server that is not there")


func test_suitable_resolutions_only_include_sizes_that_leave_room_for_window_chrome() -> void:
	var usable := Rect2i(Vector2i(1920, 0), Vector2i(1920, 1040))
	assert_eq(AppSettings.suitable_resolutions(usable),
		["960x540", "1024x576", "1280x720", "1600x900"])
	assert_eq(AppSettings.effective_windowed_resolution("1920x1080", usable), "1600x900")


func test_centered_window_position_ignores_the_previous_offscreen_coordinate() -> void:
	var usable := Rect2i(Vector2i(1920, 0), Vector2i(1920, 1040))
	var centered := AppSettings.centered_window_position(Vector2i(1312, 980), usable)
	assert_eq(centered, Vector2i(2224, 30), "the full native window is centered on monitor two")
	assert_eq(AppSettings.client_position_for_centered_window(
		Vector2i(1312, 980), Vector2i(8, 32), usable), Vector2i(2232, 62),
		"the client position accounts for the title bar above it")


func test_centered_window_position_keeps_an_oversized_window_movable() -> void:
	var usable := Rect2i(Vector2i(0, 0), Vector2i(1280, 720))
	var centered := AppSettings.centered_window_position(Vector2i(1920, 1080), usable)
	assert_eq(centered, Vector2i.ZERO, "oversized windows start at the visible top-left")


func test_applying_puts_the_levels_on_the_buses() -> void:
	var audio := AudioManager.new()
	add_child_autofree(audio)
	var settings := _settings()
	settings.set_audio_volume(AudioManager.MUSIC, 0.4)

	settings.apply_audio(audio)

	assert_almost_eq(audio.category_volume(AudioManager.MUSIC), 0.4, 0.01)
	settings.set_audio_volume(AudioManager.MUSIC, 1.0)
	settings.apply_audio(audio)  # leave the shared mixer as we found it


func test_an_automated_run_does_not_write_the_players_config() -> void:
	# The same guard the trace writer and audio use: a suite must never touch the real user://.
	var settings := AppSettings.new(SCRATCH)
	assert_false(settings.persist, "persistence is off under the test runner")
	settings.set_audio_volume(AudioManager.MUSIC, 0.1)
	assert_false(settings.save())
	assert_false(FileAccess.file_exists(SCRATCH), "nothing was written")


func test_reset_returns_every_value_to_its_default() -> void:
	var settings := _settings()
	settings.set_audio_volume(AudioManager.MUSIC, 0.1)
	settings.set_narration_level(NarrationSettings.LEVEL_TOPICS)
	settings.set_window_mode(AppSettings.WINDOW_MODE_FULLSCREEN)
	settings.set_vsync_mode(AppSettings.VSYNC_OFF)
	settings.set_resolution(String(AppSettings.RESOLUTIONS[0]))
	settings.set_monitor(1)
	settings.set_max_fps(30)

	settings.reset_to_defaults()

	assert_almost_eq(settings.audio_volume(AudioManager.MUSIC),
		float(AppSettings.DEFAULTS[AudioManager.MUSIC]), 0.001)
	assert_eq(settings.narration_level(), NarrationSettings.LEVEL_NORMAL)
	assert_eq(settings.window_mode(), AppSettings.WINDOW_MODE_FULLSCREEN)
	assert_eq(settings.vsync_mode(), AppSettings.VSYNC_ON)
	assert_eq(settings.resolution(), AppSettings.UNSET)
	assert_eq(settings.monitor(), AppSettings.MONITOR_UNSET)
	assert_eq(settings.max_fps(), AppSettings.MAX_FPS_UNCAPPED)
