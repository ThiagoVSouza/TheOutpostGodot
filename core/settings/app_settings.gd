class_name AppSettings
extends RefCounted

## The player's app-level preferences, persisted outside any save.
##
## Distinct from the per-game choices in `GameState["profile"]`, and the distinction is the point:
## how loud the music is belongs to the *person*, not to a settlement. Loading a different save must
## not change the volume, and starting a new game must not reset it.
##
## Deliberately narrow. It stores only the settings that are actually **wired to something** — today
## the audio levels. The settings screen shows a great deal more than this, all of it marked as not
## yet implemented; adding a key here before the thing it controls exists would mean persisting a
## value nothing reads, which is worse than an obviously-empty section because it looks finished.
##
## Written as a Godot [ConfigFile] (an ini) rather than JSON: it is the one file a player may
## reasonably want to open and edit by hand when something has gone wrong.

const PATH := "user://settings.cfg"

const AUDIO_SECTION := "audio"
const GAMEPLAY_SECTION := "gameplay"
const NARRATION_KEY := "narration_level"
const VIDEO_SECTION := "video"
const WINDOW_MODE_KEY := "window_mode"
const VSYNC_KEY := "vsync_mode"

const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_BORDERLESS := "borderless"
const WINDOW_MODE_FULLSCREEN := "fullscreen"
const WINDOW_MODES := [WINDOW_MODE_WINDOWED, WINDOW_MODE_BORDERLESS, WINDOW_MODE_FULLSCREEN]

const VSYNC_OFF := "off"
const VSYNC_ON := "on"
const VSYNC_ADAPTIVE := "adaptive"
const VSYNC_MODES := [VSYNC_OFF, VSYNC_ON, VSYNC_ADAPTIVE]

## Default levels, 0..1 linear. Music sits below effects so narration and UI stay legible over it.
const DEFAULTS := {
	AudioManager.MASTER: 1.0,
	AudioManager.MUSIC: 0.7,
	AudioManager.SFX: 0.9,
	AudioManager.AMBIENCE: 0.8,
}

## When false, [method save] does nothing. Off under the test runner so an automated run never writes
## into the player's real config — the same guard the trace writer, memory store and audio use.
var persist: bool = OS.get_environment("OUTPOST_TEST_RUN") != "1"

var _path: String
var _config := ConfigFile.new()


func _init(path: String = PATH) -> void:
	_path = path


## Read the config from disk. A missing or damaged file is not an error: the defaults are a complete,
## playable configuration, so the honest response is to use them rather than to refuse to start.
func load_from_disk() -> void:
	if _config.load(_path) != OK:
		_config.clear()


## Write the config, if persistence is on. Returns whether anything was written.
func save() -> bool:
	if not persist:
		return false
	return _config.save(_path) == OK


## A category's stored level, 0..1, falling back to its default.
func audio_volume(category: String) -> float:
	var fallback: float = float(DEFAULTS.get(category, 1.0))
	return clampf(float(_config.get_value(AUDIO_SECTION, category, fallback)), 0.0, 1.0)


func set_audio_volume(category: String, linear: float) -> void:
	_config.set_value(AUDIO_SECTION, category, clampf(linear, 0.0, 1.0))


## Push the stored levels onto the mixer. Called at boot and whenever the settings screen changes
## one, so the bus is always the single place a level actually lives at runtime.
func apply_audio(audio: AudioManager) -> void:
	if audio == null:
		return
	for category in AudioManager.MIXER_LEVELS:
		audio.set_category_volume(category, audio_volume(category))


## The narration length a **new game** starts with — the wizard's Settings step pre-selects it, and
## the player can still choose differently for that game.
##
## Two layers, each with one job: this is the person's usual preference, and the per-game value in
## `GameState["profile"]` is what actually governs a game once it exists (see
## [method GameKernel.apply_player_preferences]). Without the app-level layer the wizard would open on
## a hardcoded default forever, no matter how many times the player changed it.
func narration_level() -> String:
	var stored := String(_config.get_value(GAMEPLAY_SECTION, NARRATION_KEY,
		NarrationSettings.LEVEL_NORMAL))
	return stored if NarrationSettings.is_level(stored) else NarrationSettings.LEVEL_NORMAL


func set_narration_level(level: String) -> void:
	if NarrationSettings.is_level(level):
		_config.set_value(GAMEPLAY_SECTION, NARRATION_KEY, level)


func window_mode() -> String:
	var stored := String(_config.get_value(VIDEO_SECTION, WINDOW_MODE_KEY, WINDOW_MODE_WINDOWED))
	return stored if WINDOW_MODES.has(stored) else WINDOW_MODE_WINDOWED


func set_window_mode(mode: String) -> void:
	if WINDOW_MODES.has(mode):
		_config.set_value(VIDEO_SECTION, WINDOW_MODE_KEY, mode)


func vsync_mode() -> String:
	var stored := String(_config.get_value(VIDEO_SECTION, VSYNC_KEY, VSYNC_ON))
	return stored if VSYNC_MODES.has(stored) else VSYNC_ON


func set_vsync_mode(mode: String) -> void:
	if VSYNC_MODES.has(mode):
		_config.set_value(VIDEO_SECTION, VSYNC_KEY, mode)


## Push the stored window mode + V-Sync onto the real window. Called at boot and whenever the
## settings screen changes one. A headless run (tests, CI) has no real window to call into —
## `DisplayServer.get_name() == "headless"` is the standing guard for that, same shape as the
## test-runner guards on the trace writer, audio and this file's own [member persist].
func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match window_mode():
		WINDOW_MODE_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	const VSYNC_SERVER_MODES := {
		VSYNC_OFF: DisplayServer.VSYNC_DISABLED,
		VSYNC_ON: DisplayServer.VSYNC_ENABLED,
		VSYNC_ADAPTIVE: DisplayServer.VSYNC_ADAPTIVE,
	}
	DisplayServer.window_set_vsync_mode(VSYNC_SERVER_MODES[vsync_mode()])


## Put every stored value back to its default. Does not write — the caller decides when to commit, so
## a settings screen can offer "reset" and still let the player back out.
func reset_to_defaults() -> void:
	_config.clear()
