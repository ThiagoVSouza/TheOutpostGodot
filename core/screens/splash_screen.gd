extends Control

## App-shell splash: the company logo on black for a beat, then the loading screen. Any key or click
## skips ahead. An animated reveal is still to come; the mark itself is now the real one.

const HOLD_SECONDS := 1.5

const LOGO := preload("res://core/assets/pangea_logo.png")

## The logo's drawn width; its own aspect gives the height. Sized as a share of the viewport so it
## holds its proportion of the screen on a phone and on a desktop rather than being a fixed
## rectangle that is either lost or overwhelming.
const LOGO_WIDTH_RATIO := 0.22
const LOGO_MIN_WIDTH := 160.0

## Black, not [constant ShellPalette.BACKGROUND_SPLASH]: the mark is white with a transparent
## surround, and a true black field is what a logo reveal is supposed to sit on.
const BACKDROP := Color.BLACK

var _advanced := false
var _logo: TextureRect = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	# The theme starts on the logo and carries through the whole shell — every screen between here
	# and the game asks for the same cue, and asking for what is already playing does nothing, so
	# there is no restart at each hop and no gap over the loading screen.
	Kernel.audio.play_music(AppShell.SHELL_MUSIC)
	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_advance)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	# Its own ColorRect rather than ShellPalette.paint(): this one has to *catch* the tap that
	# skips the splash, where a background otherwise lets clicks through.
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_input)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_logo = TextureRect.new()
	_logo.texture = LOGO
	# Keep the mark's own proportions whatever box it is given, and let it scale smoothly: the source
	# is 255px wide, so on a large window it is being enlarged, where nearest-neighbour would show
	# its edges as stair-steps.
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	center.add_child(_logo)
	_size_logo()
	# The splash is the first thing drawn, before layout has given this screen its real size, so the
	# ratio has to be re-applied when that size arrives (and again if the window is resized).
	resized.connect(_size_logo)


## Scale the logo to its share of the viewport, in its own aspect.
func _size_logo() -> void:
	if _logo == null:
		return
	var width := maxf(size.x * LOGO_WIDTH_RATIO, LOGO_MIN_WIDTH)
	var texture_size := LOGO.get_size()
	_logo.custom_minimum_size = Vector2(width, width * texture_size.y / maxf(texture_size.x, 1.0))


func _on_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_advance()


func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	Kernel.router.goto("core.loading", {"next": "core.main_menu"})
