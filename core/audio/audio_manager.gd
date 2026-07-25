class_name AudioManager
extends Node

## Plays the game's music and sound effects, from cues that modules declare in data.
##
## A module ships an `audio.json` and registers it ([method load_manifest]); everything after that
## refers to a cue by **name** — `play_music("main_menu")`, `play_sfx("ui_click")`. No screen ever
## names a file, so re-scoring the game is a data change, and a cue a module did not ship is a
## warning rather than a crash (a DLC's sound is simply absent when the DLC is not loaded).
##
## Streams are loaded **on first play, then cached**. Music files are the largest assets in the
## project — preloading every declared cue at boot would spend that on the splash screen, and on
## every headless test run.
##
## Volume lives in two places on purpose: a cue's `volume` in the manifest is the mix decision (this
## click is quieter than that one) and belongs to whoever authored the sound; a category's level is
## the *player's* decision and lives on the bus, where a settings screen can move it without
## touching the content. See `default_bus_layout.tres`.

## Manifest categories, which are also the bus names. A category with no bus falls back to Master
## rather than refusing to play — a missing bus should cost the player volume control, not the sound.
const MUSIC := "music"
const SFX := "sfx"
const AMBIENCE := "ambience"
const CATEGORIES: Array[String] = [MUSIC, SFX, AMBIENCE]

## How many effects can overlap before the oldest is cut off. Effects are fire-and-forget, so they
## need somewhere to land that is not "the one player, interrupting whatever is on it" — two buttons
## pressed in quick succession should sound like two presses.
const SFX_VOICES := 8

## Seconds to fade the outgoing and incoming track over when music changes. Short enough not to feel
## like a wait, long enough that the cut is not audible as a click.
const MUSIC_FADE := 0.6

## Silence, in dB. Godot treats anything at or below -80 as inaudible.
const SILENT_DB := -80.0

## Marks a button whose press has already been given a sound, and separately a root already being
## watched for late arrivals. Markers rather than `pressed.is_connected(play_sfx.bind(cue))`: each
## `bind` builds a fresh [Callable], and relying on two of them comparing equal is how a button ends
## up connected twice and clicks twice.
const WIRED_FLAG := "_audio_click_wired"
const WATCHED_FLAG := "_audio_click_watched"

## When false, cues are registered but nothing is ever played. Defaults off under the test runner —
## the same guard the trace writer and the memory store use: an automated run has no one to hear it,
## and playing anyway costs a multi-megabyte stream load per suite and leaves a live playback open at
## exit (which the engine then reports as a leak, drowning out real ones). A *default*, not a hard
## gate: the tests of this class turn it back on.
var enabled: bool = OS.get_environment("OUTPOST_TEST_RUN") != "1"

var _cues: Dictionary = {}  # category -> { id -> {path, loop, volume_db} }
var _streams: Dictionary = {}  # resource path -> AudioStream (cache; null marks a failed load)
var _music: AudioStreamPlayer = null
var _sfx_voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _music_cue: String = ""
var _log: GameLog = null
var _fade: Tween = null


func _init(log: GameLog = null) -> void:
	_log = log
	name = "AudioManager"


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = bus_for(MUSIC)
	add_child(_music)
	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = bus_for(SFX)
		add_child(voice)
		_sfx_voices.append(voice)


## Read a module's `audio.json` and register the cues it declares. Cue `file` paths are relative to
## the manifest, so a module's audio moves with the module. Called from [method Module.register].
##
## Shape: `{"version": 1, "<category>": {"<cue id>": {"file", "loop", "volume"}}}`, where `volume`
## is a 0..1 linear level (what a mixer shows) rather than dB (what the engine wants).
func load_manifest(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_warn("no audio manifest at %s" % path)
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not (parser.data is Dictionary):
		_warn("audio manifest %s is not readable JSON" % path)
		return false
	var manifest: Dictionary = parser.data
	var base_dir := path.get_base_dir()
	var added := 0
	for category in CATEGORIES:
		var entries: Dictionary = manifest.get(category, {}) as Dictionary
		for id in entries:
			var entry: Dictionary = entries[id] as Dictionary
			var file := String(entry.get("file", ""))
			if file.is_empty():
				_warn("audio cue '%s/%s' declares no file" % [category, id])
				continue
			if not _cues.has(category):
				_cues[category] = {}
			(_cues[category] as Dictionary)[String(id)] = {
				"path": base_dir.path_join(file),
				"loop": bool(entry.get("loop", category == MUSIC)),
				"volume_db": linear_to_db(clampf(float(entry.get("volume", 1.0)), 0.0, 1.0)),
			}
			added += 1
	if _log != null:
		_log.info("Audio", "Loaded %d cue(s) from %s" % [added, path])
	return added > 0


func has_cue(category: String, id: String) -> bool:
	return (_cues.get(category, {}) as Dictionary).has(id)


## Start a music cue, crossfading from whatever is playing. Re-requesting the cue already playing is
## a **no-op**, not a restart: screens announce what should be playing without knowing what came
## before, so walking menu → wizard → menu must not keep restarting the same track.
func play_music(id: String) -> void:
	if not enabled or _music == null or (_music_cue == id and _music.playing):
		return
	var cue: Dictionary = _cue(MUSIC, id)
	if cue.is_empty():
		return
	var stream := _stream(String(cue["path"]), bool(cue["loop"]))
	if stream == null:
		return
	_music_cue = id
	var target := float(cue["volume_db"])
	if _music.playing:
		# Fade the outgoing track out, swap, fade the new one in. One player rather than two: with a
		# single track in the game there is nothing to hear *underneath* the fade, and two players
		# would need their own lifetime management for a difference nobody can hear yet.
		_tween_music(SILENT_DB, func() -> void: _start_music(stream, target))
		return
	_start_music(stream, target)


## Stop the music, fading out. Safe to call when nothing is playing. Pass `fade = false` to cut it
## dead — on the way out of the app there is no next frame for a fade to run in, and a playback left
## open is what the engine reports as a leaked instance.
func stop_music(fade: bool = true) -> void:
	if _music == null or not _music.playing:
		_music_cue = ""
		return
	_music_cue = ""
	if not fade:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_music.stop()
		return
	_tween_music(SILENT_DB, func() -> void: _music.stop())


## The music cue currently playing, or "" — the honest answer to "what is playing", which is what a
## test can assert without an audio device.
func current_music() -> String:
	return _music_cue if _music != null and _music.playing else ""


## Fire a sound effect. Overlapping calls take the next free voice, so rapid presses stack instead
## of cutting each other off.
func play_sfx(id: String) -> void:
	if not enabled:
		return
	var cue: Dictionary = _cue(SFX, id)
	if cue.is_empty() or _sfx_voices.is_empty():
		return
	var stream := _stream(String(cue["path"]), false)
	if stream == null:
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = float(cue["volume_db"])
	voice.play()


## Give every button under [param root] the click sound, including ones added later. One call per
## screen, rather than a line at every button: a UI sound that some controls make and others do not
## reads as a bug, and that is exactly what hand-wiring drifts into.
func wire_clicks(root: Node, cue: String = "ui_click") -> void:
	if not has_cue(SFX, cue):
		return
	_wire_clicks_below(root, cue)
	# Screens build themselves in `_ready`, and some add controls afterwards (a list that fills, a
	# row that appears). Catching later arrivals here is what keeps those silent controls from
	# being the exception nobody notices until the sound is missing.
	if not root.has_meta(WATCHED_FLAG):
		root.set_meta(WATCHED_FLAG, true)
		root.child_entered_tree.connect(_on_child_entered.bind(cue))


func _wire_clicks_below(node: Node, cue: String) -> void:
	if node is BaseButton and not node.has_meta(WIRED_FLAG):
		node.set_meta(WIRED_FLAG, true)
		(node as BaseButton).pressed.connect(play_sfx.bind(cue))
	for child in node.get_children():
		_wire_clicks_below(child, cue)


func _on_child_entered(node: Node, cue: String) -> void:
	_wire_clicks_below(node, cue)


## Set a category's level as the player sees it: 0..1 linear, 0 being silent. This is the knob a
## settings screen turns.
func set_category_volume(category: String, linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_for(category))
	if bus < 0:
		return
	var level := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus, SILENT_DB if is_zero_approx(level) else linear_to_db(level))
	AudioServer.set_bus_mute(bus, is_zero_approx(level))


func category_volume(category: String) -> float:
	var bus := AudioServer.get_bus_index(bus_for(category))
	if bus < 0:
		return 1.0
	if AudioServer.is_bus_mute(bus):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus))


func _start_music(stream: AudioStream, target_db: float) -> void:
	_music.stream = stream
	_music.volume_db = SILENT_DB
	_music.play()
	_tween_music(target_db)


## One tween at a time: a fade started while another is running must replace it, or the two fight
## over `volume_db` and the track lands at whichever finishes last.
func _tween_music(to_db: float, on_done: Callable = Callable()) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not is_inside_tree():
		# No tree, no tweens (a headless kernel built directly in a test). Apply the end state so
		# behaviour still matches what a faded transition would have left.
		_music.volume_db = to_db
		if on_done.is_valid():
			on_done.call()
		return
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", to_db, MUSIC_FADE)
	if on_done.is_valid():
		_fade.tween_callback(on_done)


func _free_voice() -> AudioStreamPlayer:
	for voice in _sfx_voices:
		if not voice.playing:
			return voice
	# All busy: reuse them in order, so the sound that gets cut is the oldest rather than an
	# arbitrary one.
	var voice := _sfx_voices[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx_voices.size()
	return voice


func _cue(category: String, id: String) -> Dictionary:
	var entries: Dictionary = _cues.get(category, {}) as Dictionary
	if not entries.has(id):
		_warn("no %s cue '%s'" % [category, id])
		return {}
	return entries[id] as Dictionary


## Load and cache a stream. A failed load is cached as null so a missing file is reported once
## rather than on every press.
func _stream(path: String, loop: bool) -> AudioStream:
	if not _streams.has(path):
		var loaded: AudioStream = null
		if ResourceLoader.exists(path):
			loaded = load(path) as AudioStream
		if loaded == null:
			_warn("could not load audio '%s'" % path)
		elif loop and "loop" in loaded:
			# The import step decides this for a .ogg; setting it here means a manifest that says
			# `loop` gets a loop regardless of how the asset was imported.
			loaded.set("loop", true)
		_streams[path] = loaded
	return _streams[path] as AudioStream


## A category's bus, or Master when the layout does not define one. Public because a settings screen
## needs the bus name to show a level for it.
static func bus_for(category: String) -> String:
	var bus := category.capitalize() if category != SFX else "SFX"
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"


func _warn(message: String) -> void:
	if _log != null:
		_log.warn("Audio", message)
