extends SceneTree

## Dev tool: mount each screen in a real window, render it, and save a PNG.
##
## Exists because "verified headless only" is how UI regressions get in: GUT proves the wiring,
## and proves nothing about what the screen *looks* like. This drives the real registered scenes
## through the real kernel (fake AI backend), so the captures show what a player would see.
##
## Run: `$GODOT --path . -s res://tools/capture_screens.gd`
## Writes `user://screens/*.png` (override with `OUTPOST_CAPTURE_DIR`, an absolute path).
##
## Not a test — it asserts nothing. It produces evidence a human (or an agent) can look at.

const OUT_SUBDIR := "screens"
const VIEWPORT_SIZE := Vector2i(1280, 800)
## The project's own default portrait viewport (project.godot) — below `HudShell`'s mobile
## breakpoint, so the M8 shell captures show the mobile re-flow rather than a cramped desktop one.
const MOBILE_VIEWPORT_SIZE := Vector2i(720, 1280)
const WIZARD_STEPS := ["background", "location", "identity", "settings"]

## Frames to render before grabbing the image. One is not enough: layout settles on the second, a
## `FlagView`'s shader needs its material pushed to the renderer, and the map's biome textures are
## loaded on `setup`. A few frames of margin costs a capture run nothing.
const SETTLE_FRAMES := 6

var _out_dir := ""
var _host: Control = null
var _kernel: Node = null
var _saved: Array[String] = []


func _initialize() -> void:
	_out_dir = OS.get_environment("OUTPOST_CAPTURE_DIR")
	if _out_dir.is_empty():
		_out_dir = "user://".path_join(OUT_SUBDIR)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# `_initialize` runs before autoloads are ready, so the kernel exists but has not booted yet
	# (its subsystems are still null). One frame is what turns it into a usable kernel.
	await process_frame
	# The autoload identifier also does not resolve at compile time in a `-s` SceneTree script.
	_kernel = root.get_node("Kernel")
	DisplayServer.window_set_size(VIEWPORT_SIZE)
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

	# The pre-menu screens advance on their own (a timer, a tap, a finished load), so they are shot
	# on the frame they mount rather than left to run. `core.loading` is given the target it would
	# normally be handed; it is captured mid-flight, before it navigates on.
	await _capture_screen("core.splash", "00a_splash")
	await _capture_screen("core.loading", "00b_loading", {"next": "core.main_menu"})
	await _capture_screen("core.main_menu", "01_main_menu")

	# The exit-confirm dialog (M8 Phase 2 "done when": the real Theme reaches it too, ux_plan.md
	# §2.4) — kernel-owned, not screen-owned, so it is reached through the kernel rather than a
	# screen's own private state.
	var exit_dialog: ConfirmationDialog = _kernel.call("_ensure_exit_confirm")
	exit_dialog.popup_centered()
	await _shoot("01z_exit_confirm")
	exit_dialog.hide()

	# Every settings tab, not just the one that opens: most of the screen is placeholders whose whole
	# job is to be looked at, and a tab nobody captures is a tab nobody checks.
	var settings := await _mount("core.settings")
	if settings != null:
		var tabs := _find_tabs(settings)
		if tabs != null:
			for i in tabs.get_tab_count():
				tabs.current_tab = i
				await _shoot("01%s_settings_%s" % [char("a".unicode_at(0) + i),
					tabs.get_tab_title(i).to_lower()])

	# The wizard's four steps. `goto` mounts it; stepping is what a player's Next does, so drive
	# the same private helper the Next button drives rather than faking four separate screens.
	var wizard := await _mount("core.new_game")
	if wizard != null:
		for step in WIZARD_STEPS.size():
			wizard.call("_goto_step", step)
			await _shoot("%02d_wizard_%d_%s" % [step + 2, step + 1, WIZARD_STEPS[step]])

	# The game itself, over a freshly seeded world — the wizard's own output, so the captures show
	# the choices actually landing (flag, narration length) rather than defaults. The map is the
	# base layer now (ux_plan.md §2.1) — it is already in this capture, not a separate overlay.
	_kernel.session.begin_new_game(_new_game_fields())
	var chat := await _mount("base_game.chat")
	await _shoot("06_chat_new_game")

	# Both breakpoints of the M8 HUD shell (ux_plan.md Phase 1 "done when"). Desktop first: expand
	# the chat dock, then open Main Menu alongside it — page + chat both at half height, the
	# draggable split (rules 1-2).
	if chat != null:
		var shell := chat.get("_shell") as HudShell
		shell.set_chat_expanded(true)
		await _shoot("06b_chat_expanded")
		chat.call("_open_main_menu")
		await _shoot("06c_chat_and_menu_split")

		# Narrow the window without remounting — crossing the breakpoint with both panels open
		# should collapse to whichever opened more recently (rule 5), not leave both on screen.
		DisplayServer.window_set_size(MOBILE_VIEWPORT_SIZE)
		await _settle()
		await _shoot("06d_mobile_exclusive")
		DisplayServer.window_set_size(VIEWPORT_SIZE)
		await _settle()

	await _capture_scene("res://modules/base_game/ui/flag_preview.tscn", "07_flag_preview")


## The choices a player would make, deliberately not the defaults: a distinctive flag and the
## longest narration, so a capture where they did not apply is obvious at a glance.
func _new_game_fields() -> Dictionary:
	return {
		"hero_name": "Marcus",
		"sex": "male",
		"outpost_name": "Ravenwatch",
		"background": "knight",
		"outpost_location": "valley",
		"outpost_flag": {"shapeColor": "#2f5fc0", "texture": "pattern07",
			"textureColor": "#f3c43f", "emblem": "emblem04", "emblemColor": "#f7f7f2"},
		"verbosity": "long",
	}


func _capture_screen(screen_id: String, name: String, params: Dictionary = {}) -> void:
	if await _mount(screen_id, params) == null:
		return
	await _shoot(name)


func _mount(screen_id: String, params: Dictionary = {}) -> Node:
	if not _kernel.screens.has(screen_id):
		push_warning("capture: no screen '%s'" % screen_id)
		return null
	_kernel.router.goto(screen_id, params)
	await _settle()
	# `goto` appends the new screen and queue_free()s the old one, so the freeing sibling may
	# still be a child this frame: the newest child is the mounted screen.
	return _host.get_child(_host.get_child_count() - 1)


## The first [TabContainer] anywhere under [param node], so the capture does not depend on how deeply
## a screen happens to nest it.
func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child in node.get_children():
		var found := _find_tabs(child)
		if found != null:
			return found
	return null


func _capture_scene(path: String, name: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("capture: no scene '%s'" % path)
		return
	var scene: PackedScene = load(path)
	var node: Node = scene.instantiate()
	_host.add_child(node)
	await _shoot(name)
	node.queue_free()


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## Grab the rendered viewport. `frame_post_draw` is the only point at which the texture holds
## this frame rather than the previous one.
func _shoot(name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name + ".png")
	if image.save_png(path) == OK:
		_saved.append(name + ".png")
	else:
		push_error("capture: could not write %s" % path)
