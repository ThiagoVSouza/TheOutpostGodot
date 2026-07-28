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
## Marks settings files that have seen the fullscreen-at-launch policy. It lets us distinguish the
## former implicit Windowed default from a player deliberately choosing Windowed for a resolution.
const VIDEO_POLICY_KEY := "policy_version"
const VIDEO_POLICY_VERSION := 1

const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_BORDERLESS := "borderless"
const WINDOW_MODE_FULLSCREEN := "fullscreen"
const WINDOW_MODES := [WINDOW_MODE_WINDOWED, WINDOW_MODE_BORDERLESS, WINDOW_MODE_FULLSCREEN]

const VSYNC_OFF := "off"
const VSYNC_ON := "on"
const VSYNC_ADAPTIVE := "adaptive"
const VSYNC_MODES := [VSYNC_OFF, VSYNC_ON, VSYNC_ADAPTIVE]

const RESOLUTION_KEY := "resolution"
const MONITOR_KEY := "monitor"
const MAX_FPS_KEY := "max_fps"

## "Leave it alone." The default for both window size and monitor: it means the player's settings
## do not override the project's platform launch policy. Desktop starts fullscreen; mobile owns its
## portrait surface through the OS. Only an explicit Windowed-mode choice replaces the desktop
## launch size.
const UNSET := ""
const MONITOR_UNSET := -1

## The `override.cfg` this writes ([method write_launch_override]) carries display settings only, and
## the mode is Godot's own [enum Window.Mode] rather than this file's string names.
const OVERRIDE_SECTION := "display"
const WINDOW_MODE_SETTING_WINDOWED := 0
const WINDOW_MODE_SETTING_FULLSCREEN := 3

## 0 is Godot's own "no cap" — the default, so V-Sync stays what actually limits the frame rate
## unless the player says otherwise.
const MAX_FPS_UNCAPPED := 0

## Key rebinding lives in its own section, one entry per overridden action, keyed by action id and
## holding a raw keycode int. **Only overrides are stored** — an action the player never touched has
## no entry, so changing a *default* in [InputActions] reaches everyone who had not deliberately
## chosen otherwise, instead of being frozen into every existing config file.
const INPUT_SECTION := "input"

## "No override" — the player never touched this action, so its default applies. [constant KEY_NONE]
## is 0, which is also what a missing config entry reads as.
const NO_KEY := KEY_NONE

## "Deliberately bound to nothing", which is **not** the same as no override: an action whose key was
## taken by another action must end up with no key at all, and storing [constant NO_KEY] there would
## fall back to the default — the very key that was just taken away — and the conflict would survive.
const UNBOUND := -1

## Familiar Windowed sizes. The settings screen filters this short list against the selected
## monitor's usable desktop area rather than offering every possible resolution.
const RESOLUTIONS: Array = ["960x540", "1024x576", "1280x720", "1600x900", "1920x1080", "2560x1440"]
## A native window has borders and a title bar in addition to the client area Godot sizes. Reserve
## conservative room for them when deciding which resolution fits a desktop work area.
const WINDOWED_DECORATION_ALLOWANCE := Vector2i(32, 80)

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
		return
	_migrate_video_policy()


## Older versions wrote `windowed` even when the player had never chosen a window mode. Upgrade
## that bare legacy default once, so an existing install adopts the current fullscreen launch
## policy while a deliberate Windowed choice remains a deliberate choice.
func _migrate_video_policy() -> void:
	if int(_config.get_value(VIDEO_SECTION, VIDEO_POLICY_KEY, 0)) >= VIDEO_POLICY_VERSION:
		return
	var legacy_default := (
		String(_config.get_value(VIDEO_SECTION, WINDOW_MODE_KEY, "")) == WINDOW_MODE_WINDOWED
		and not _config.has_section_key(VIDEO_SECTION, RESOLUTION_KEY)
		and not _config.has_section_key(VIDEO_SECTION, MONITOR_KEY)
	)
	if legacy_default:
		_config.set_value(VIDEO_SECTION, WINDOW_MODE_KEY, WINDOW_MODE_FULLSCREEN)
	_config.set_value(VIDEO_SECTION, VIDEO_POLICY_KEY, VIDEO_POLICY_VERSION)
	save()


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
	var stored := String(_config.get_value(VIDEO_SECTION, WINDOW_MODE_KEY, WINDOW_MODE_FULLSCREEN))
	return stored if WINDOW_MODES.has(stored) else WINDOW_MODE_FULLSCREEN


func set_window_mode(mode: String) -> void:
	if WINDOW_MODES.has(mode):
		_config.set_value(VIDEO_SECTION, WINDOW_MODE_KEY, mode)
		_config.set_value(VIDEO_SECTION, VIDEO_POLICY_KEY, VIDEO_POLICY_VERSION)


func vsync_mode() -> String:
	var stored := String(_config.get_value(VIDEO_SECTION, VSYNC_KEY, VSYNC_ON))
	return stored if VSYNC_MODES.has(stored) else VSYNC_ON


func set_vsync_mode(mode: String) -> void:
	if VSYNC_MODES.has(mode):
		_config.set_value(VIDEO_SECTION, VSYNC_KEY, mode)


## The window size the player picked, as `"WxH"`, or [constant UNSET] for "leave it alone".
func resolution() -> String:
	var stored := String(_config.get_value(VIDEO_SECTION, RESOLUTION_KEY, UNSET))
	return stored if RESOLUTIONS.has(stored) else UNSET


func set_resolution(value: String) -> void:
	if value == UNSET or RESOLUTIONS.has(value):
		_config.set_value(VIDEO_SECTION, RESOLUTION_KEY, value)


## The fixed choices that fit within a monitor's usable work area, with room for normal window
## decorations. Kept pure so the screen picker and the boot-time application use the same rule.
static func suitable_resolutions(usable: Rect2i) -> Array[String]:
	var suitable: Array[String] = []
	for value: String in RESOLUTIONS:
		var size := resolution_size(value)
		if (size.x + WINDOWED_DECORATION_ALLOWANCE.x <= usable.size.x
				and size.y + WINDOWED_DECORATION_ALLOWANCE.y <= usable.size.y):
			suitable.append(value)
	return suitable


## A stored size remains meaningful when the player returns to its larger monitor. Until then,
## select the largest fitting choice instead of opening an oversized, unreachable window.
static func effective_windowed_resolution(stored: String, usable: Rect2i) -> String:
	var suitable := suitable_resolutions(usable)
	if suitable.has(stored):
		return stored
	return String(suitable.back()) if not suitable.is_empty() else UNSET


static func resolution_size(value: String) -> Vector2i:
	var parts := value.split("x")
	return Vector2i(int(parts[0]), int(parts[1]))


## The monitor index the player picked, or [constant MONITOR_UNSET]. Not validated against the
## current screen count here — a laptop that stored "monitor 2" at the desk should get its choice
## back when it is docked again, not have it erased by one undocked run ([method apply_video]
## simply skips it while it is out of range).
func monitor() -> int:
	return int(_config.get_value(VIDEO_SECTION, MONITOR_KEY, MONITOR_UNSET))


func set_monitor(index: int) -> void:
	_config.set_value(VIDEO_SECTION, MONITOR_KEY, maxi(index, MONITOR_UNSET))


func max_fps() -> int:
	return maxi(int(_config.get_value(VIDEO_SECTION, MAX_FPS_KEY, MAX_FPS_UNCAPPED)), 0)


func set_max_fps(value: int) -> void:
	_config.set_value(VIDEO_SECTION, MAX_FPS_KEY, maxi(value, 0))


## The player's override for [param action], or [constant NO_KEY] if they never changed it.
func key_binding(action: String) -> int:
	return int(_config.get_value(INPUT_SECTION, action, NO_KEY))


func set_key_binding(action: String, keycode: int) -> void:
	_config.set_value(INPUT_SECTION, action, maxi(keycode, UNBOUND))


## Drop one override, so the action goes back to its default.
func clear_key_binding(action: String) -> void:
	if _config.has_section_key(INPUT_SECTION, action):
		_config.erase_section_key(INPUT_SECTION, action)


## Drop every override at once — the Controls tab's "reset bindings", which must not disturb the
## audio, video or gameplay sections the way [method reset_to_defaults] would.
func clear_all_key_bindings() -> void:
	if _config.has_section(INPUT_SECTION):
		_config.erase_section(INPUT_SECTION)


## Push the stored window mode + V-Sync onto the real window. Called at boot and whenever the
## settings screen changes one. A headless run (tests, CI) has no real window to call into —
## `DisplayServer.get_name() == "headless"` is the standing guard for that, same shape as the
## test-runner guards on the trace writer, audio and this file's own [member persist].
func apply_video() -> void:
	# Not a display-server call, and meaningful on a phone (where it is a battery setting more than
	# a smoothness one), so it is applied before the headless guard rather than after it.
	Engine.max_fps = max_fps()
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

	# Monitor before size: moving a window to another screen can resize it, so picking the screen
	# first and the size second is the only order that ends up with both.
	var screen := monitor()
	if screen >= 0 and screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(screen)

	# **Windowed only, desktop only.** Fullscreen and borderless take their size from the screen, and
	# on a phone the OS owns the window outright — in either case forcing a size either does nothing
	# or fights whoever actually owns it.
	var launch_size := Vector2i.ZERO
	if window_mode() == WINDOW_MODE_WINDOWED and can_resize_window():
		var usable := _window_usable_rect()
		var selected := effective_windowed_resolution(resolution(), usable)
		if selected != UNSET:
			launch_size = resolution_size(selected)
			DisplayServer.window_set_size(launch_size)
		_center_window(usable)

	write_launch_override(launch_size)


## Record the window this call just produced, so the *next* launch opens at that size instead of the
## project default and then jumping.
##
## The engine builds the window from `project.godot` before a single script runs, so nothing here can
## affect the window this process already has — by the time [method apply_video] is reached, roughly a
## second of a wrong-sized window has already been shown. `override.cfg` is the one hook Godot reads
## *before* window creation, so the fix has to be written now for next time.
##
## Best effort by design. A read-only install directory simply means the file is not written and the
## launch behaves as it does today; that is a cosmetic loss, not a failure worth reporting.
func write_launch_override(windowed_size: Vector2i) -> void:
	if not persist or DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var config := ConfigFile.new()
	match window_mode():
		WINDOW_MODE_FULLSCREEN:
			config.set_value(OVERRIDE_SECTION, "window/size/mode", WINDOW_MODE_SETTING_FULLSCREEN)
		WINDOW_MODE_BORDERLESS:
			config.set_value(OVERRIDE_SECTION, "window/size/mode", WINDOW_MODE_SETTING_WINDOWED)
			config.set_value(OVERRIDE_SECTION, "window/size/borderless", true)
		_:
			config.set_value(OVERRIDE_SECTION, "window/size/mode", WINDOW_MODE_SETTING_WINDOWED)
			config.set_value(OVERRIDE_SECTION, "window/size/borderless", false)
			if windowed_size.x > 0 and windowed_size.y > 0:
				config.set_value(OVERRIDE_SECTION, "window/size/window_width_override",
					windowed_size.x)
				config.set_value(OVERRIDE_SECTION, "window/size/window_height_override",
					windowed_size.y)
	var path := launch_override_path()
	# Rewriting an identical file on every launch is pointless disk churn, and this runs at boot.
	var existing := ConfigFile.new()
	if existing.load(path) == OK and existing.encode_to_text() == config.encode_to_text():
		return
	config.save(path)


## Where Godot looks for `override.cfg`: the project folder when running from source, and beside the
## executable in an exported game — where `res://` is a read-only pack and cannot be written at all.
static func launch_override_path() -> String:
	if OS.has_feature("editor"):
		return "res://override.cfg"
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")


## Find the current desktop work area after a requested monitor change, so size filtering and
## placement both use the display the player chose.
func _window_usable_rect() -> Rect2i:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = 0
	return DisplayServer.screen_get_usable_rect(screen)


func _center_window(usable: Rect2i) -> void:
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	# Godot sets the *client-area* position, while the desired visual center is the decorated native
	# window. Add the title-bar/border offset back before setting the client-area coordinate.
	var decoration_offset := (
		DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations())
	DisplayServer.window_set_position(client_position_for_centered_window(
		DisplayServer.window_get_size_with_decorations(), decoration_offset, usable))


## Pure so multi-monitor placement stays testable without a real DisplayServer. An oversized window
## begins at the usable top-left, keeping its title bar available to move it.
static func centered_window_position(window_size: Vector2i, usable: Rect2i) -> Vector2i:
	return usable.position + Vector2i(
		maxi(0, int((usable.size.x - window_size.x) / 2)),
		maxi(0, int((usable.size.y - window_size.y) / 2)))


## `window_set_position` uses the client area, not the decorated outer window. Keep that platform
## detail in one small conversion so all callers center what the player can actually see.
static func client_position_for_centered_window(decorated_size: Vector2i, decoration_offset: Vector2i,
		usable: Rect2i) -> Vector2i:
	return centered_window_position(decorated_size, usable) + decoration_offset


## Whether a window size the player picks can actually be honoured: a desktop window the app owns,
## not a phone's OS-owned surface. The settings screen greys the control out when this is false, so
## the reason is visible rather than the setting silently doing nothing.
static func can_resize_window() -> bool:
	return not OS.has_feature("mobile") and DisplayServer.get_name() != "headless"


## Put every stored value back to its default. Does not write — the caller decides when to commit, so
## a settings screen can offer "reset" and still let the player back out.
func reset_to_defaults() -> void:
	_config.clear()
