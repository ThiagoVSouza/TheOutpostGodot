extends SceneTree

## Dev tool: mount the game screen and photograph the conversation's painted scene, at a desktop
## width and at a phone's.
##
## **Both are the point, not one of them.** The scene is fitted by its height and crops at the sides
## ([method ChatScene.band_height]), so the two breakpoints show genuinely different amounts of the
## same painting — and whether the narrow one still frames something worth looking at is a judgement
## no assertion can make.
##
## Run: `$GODOT --path . -s res://tools/capture_chat_scene.gd`
## Writes `user://chat_scene/*.png` (override with `OUTPOST_CAPTURE_DIR`, an absolute path).

const OUT_SUBDIR := "chat_scene"
const DESKTOP := Vector2i(1280, 800)
## Below `HudShell`'s mobile breakpoint, so the rail goes and the board runs the full width.
const PHONE := Vector2i(720, 1280)
const SETTLE_FRAMES := 10

var _out_dir := ""
var _host: Control = null
var _kernel: Node = null
var _saved: Array[String] = []


func _initialize() -> void:
	_out_dir = OS.get_environment("OUTPOST_CAPTURE_DIR")
	if _out_dir.is_empty():
		_out_dir = "user://".path_join(OUT_SUBDIR)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	await process_frame
	_kernel = root.get_node("Kernel")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(DESKTOP)
	await _run()
	print("\nWrote %d capture(s) to %s" % [_saved.size(), ProjectSettings.globalize_path(_out_dir)])
	for name in _saved:
		print("  - ", name)
	quit()


func _run() -> void:
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_host)
	_kernel.router.set_host(_host)
	_kernel.router.goto("base_game.chat")
	await _settle()
	var screen: Node = _host.get_child(_host.get_child_count() - 1)
	var shell: HudShell = screen.get("_shell")

	shell.set_chat_expanded(true)
	screen.call("_show_chat_scene", 0)
	await _shoot("desktop_throne_room")
	# One figure, then a pair. One first because a single portrait is where a wrong anchor, or a
	# shadow drawn on the wrong side of the person, is easiest to see.
	for step: int in [1, 2]:
		screen.set("_chat_characters", step)
		screen.call("_show_chat_scene", 0)
		await _shoot("desktop_characters_%d" % step)
	# The full layered stack, one capture per authored hairstyle. Brown is neutral enough to expose
	# alignment and alpha problems without hiding the grayscale shading.
	for style in ChatScenes.HAIR_STYLES.size():
		screen.set("_chat_hair_style", style)
		screen.set("_chat_hair_color", ChatScenes.DEFAULT_HAIR_COLOR)
		screen.call("_show_chat_scene", 0)
		await _shoot("desktop_hair_%s" % String(ChatScenes.HAIR_STYLES[style]["id"]))

	# Every skin tone at one hairstyle: the tone is a multiply over the painting, so what matters is
	# whether the shading survives it at both ends of the range.
	screen.set("_chat_hair_style", ChatScenes.DEFAULT_HAIR_STYLE)
	for tone in ChatScenes.SKIN_TONES.size():
		screen.set("_chat_skin_tone", tone)
		screen.call("_show_chat_scene", 0)
		await _shoot("desktop_skin_%s" % String(ChatScenes.SKIN_TONES[tone]["id"]))
	screen.set("_chat_skin_tone", ChatScenes.DEFAULT_SKIN_TONE)
	# Each age, at one hairstyle and tone: what tells them apart is the face, so the crop wants to be
	# tight and the rest of the stack wants to be identical.
	for age in ChatScenes.AGES.size():
		screen.set("_chat_age", age)
		screen.call("_show_chat_scene", 0)
		await _shoot("desktop_age_%s" % String(ChatScenes.AGES[age]["id"]))
	screen.set("_chat_age", ChatScenes.DEFAULT_AGE)
	screen.call("_show_chat_scene", 0)

	DisplayServer.window_set_size(PHONE)
	await _settle()
	await _settle()
	await _shoot("phone_hair_%s" % String(ChatScenes.HAIR_STYLES[screen.get("_chat_hair_style")]["id"]))
	screen.set("_chat_characters", 0)
	screen.call("_show_chat_scene", 0)
	await _shoot("phone_no_cast")


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _shoot(name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name + ".png")
	if image.save_png(path) == OK:
		_saved.append(name + ".png")
	else:
		push_warning("capture: could not write %s" % path)
