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

	settings.reset_to_defaults()

	assert_almost_eq(settings.audio_volume(AudioManager.MUSIC),
		float(AppSettings.DEFAULTS[AudioManager.MUSIC]), 0.001)
	assert_eq(settings.narration_level(), NarrationSettings.LEVEL_NORMAL)
