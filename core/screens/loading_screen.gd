extends Control

## App-shell loading screen (placeholder). Generic and reused: `on_enter({next, params})` says where
## to go once "loading" finishes. Today it is cosmetic — a short filling bar — but this is where real
## asset loading and AI-model warm-up (D8 prefix-cache ingest) will hook in. If no `next` is given it
## falls back to the main menu.

const FILL_SECONDS := 0.8

var _next: String = "core.main_menu"
var _params: Dictionary = {}
var _bar: SkinnedProgressBar = null


func on_enter(params: Dictionary) -> void:
	_next = String(params.get("next", _next))
	_params = params.get("params", {}) as Dictionary


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	# The first screen the game mounts, so the shell's theme starts here. Every screen between this
	# and the game asks for the same cue, and asking for what is already playing does nothing, so
	# there is no restart at each hop.
	Kernel.audio.play_music(AppShell.SHELL_MUSIC)
	var tween := create_tween()
	tween.tween_property(_bar, "ratio", 1.0, FILL_SECONDS)
	tween.tween_callback(func() -> void: Kernel.router.goto(_next, _params))


## Hardware/gesture back is swallowed here (Android UX pass): a transition already in flight has
## nowhere sensible to go and nothing to confirm exiting out of.
func on_hardware_back() -> bool:
	return true


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Same art as the menu it hands off to, so the two do not read as different places.
	ShellPalette.paint_shell(self, ShellPalette.BACKGROUND_LOADING)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	# The bar is bottom-aligned, so it has to clear anything the display reserves.
	margin.add_theme_constant_override("margin_bottom", 40 + SafeArea.bottom(get_viewport()))
	add_child(margin)

	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(bottom)

	# The art is shown undimmed, so the label carries its own contrast rather than relying on a scrim:
	# white text over sunlit grass is what this sat on otherwise. The bar brings its own frame.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	bottom.add_child(col)

	var label := Label.new()
	label.text = "Loading…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	col.add_child(label)

	_bar = SkinnedProgressBar.new()
	col.add_child(_bar)
