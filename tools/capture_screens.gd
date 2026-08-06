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
const WIZARD_STEPS := ["background", "location", "hero", "banner", "settings"]

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
	# Captures deliberately exercise both desktop and mobile breakpoints in one known-size window;
	# the player's normal launch policy is fullscreen.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
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

	# The pre-menu screens advance on their own (a timer, a finished load), so they are shot on the
	# frame they mount rather than left to run. `core.loading` is given the target it would normally
	# be handed; it is captured mid-flight, before it navigates on. There is no splash capture: the
	# splash is the engine's boot splash, which no scene can mount and no screenshot here can reach.
	await _capture_screen("core.loading", "00b_loading", {"next": "core.main_menu"})
	await _capture_screen("core.main_menu", "01_main_menu")

	# The exit-confirm dialog (M8 Phase 2 "done when": the real Theme reaches it too, ux_plan.md
	# §2.4) — kernel-owned, not screen-owned, so it is reached through the kernel rather than a
	# screen's own private state.
	var exit_dialog: ModalDialog = _kernel.call("_ensure_exit_confirm")
	exit_dialog.open()
	await _shoot("01z_exit_confirm")
	exit_dialog.close()

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
			# Gameplay is taller than one viewport. Its working language picker lives below the first
			# fold, so record that end of the page too rather than proving only that it exists in code.
			tabs.current_tab = 0
			await _settle()
			var gameplay_scroll := tabs.get_child(0) as ScrollContainer
			var settings_language := settings.find_child("LanguagePicker", true, false) as Control
			if gameplay_scroll != null and settings_language != null:
				gameplay_scroll.ensure_control_visible(settings_language)
				await _shoot("01aa_settings_language")

	# The wizard's five steps. `goto` mounts it; stepping is what a player's Next does, so drive
	# the same private helper the Next button drives rather than faking five separate screens.
	var wizard := await _mount("core.new_game")
	if wizard != null:
		for step in WIZARD_STEPS.size():
			wizard.call("_goto_step", step)
			await _shoot("%02d_wizard_%d_%s" % [step + 2, step + 1, WIZARD_STEPS[step]])
		wizard.call("_goto_step", 4)
		var language_picker := wizard.find_child("LanguagePicker", true, false) as LanguagePicker
		if language_picker != null:
			language_picker.open_picker()
			await _shoot("06a_wizard_5_language_picker")
			language_picker.close_picker()
		# The banner is the one wizard step whose layout deliberately changes at the phone breakpoint.
		# Its five compact rows open focused editors; capture both the main reflow and the two kinds of
		# modal so none of that interaction is accepted from headless assertions alone.
		wizard.call("_goto_step", 3)
		wizard.call("_open_color_picker", "Cloth colour", "shape_color")
		await _shoot("05b_wizard_4_banner_custom_colour")
		wizard.call("on_hardware_back")
		DisplayServer.window_set_size(MOBILE_VIEWPORT_SIZE)
		await _settle()
		wizard.call("_goto_step", 4)
		language_picker.open_picker()
		await _shoot("06f_wizard_5_language_picker_mobile")
		var language_modal := language_picker.active_modal()
		var language_scroll := language_modal.get("_scroll") as ScrollContainer
		if language_scroll != null:
			language_scroll.scroll_vertical = int(language_scroll.get_v_scroll_bar().max_value)
			await _shoot("06g_wizard_5_language_picker_mobile_cjk")
		language_picker.close_picker()
		wizard.call("_goto_step", 3)
		await _shoot("06b_wizard_4_banner_mobile")
		wizard.call("_open_shape_picker", "Choose a pattern", "pattern", 14)
		await _shoot("06c_wizard_4_banner_mobile_patterns")
		wizard.call("on_hardware_back")
		wizard.call("_open_shape_picker", "Choose an emblem", "emblem", 13)
		await _shoot("06d_wizard_4_banner_mobile_emblems")
		wizard.call("on_hardware_back")
		wizard.call("_open_color_picker", "Cloth colour", "shape_color")
		await _shoot("06e_wizard_4_banner_mobile_custom_colour")
		wizard.call("on_hardware_back")
		DisplayServer.window_set_size(VIEWPORT_SIZE)
		await _settle()

	# The game itself, over a freshly seeded world — the wizard's own output, so the captures show
	# the choices actually landing (flag, narration length) rather than defaults. The map is the
	# base layer now (ux_plan.md §2.1) — it is already in this capture, not a separate overlay.
	_kernel.session.begin_new_game(_new_game_fields())
	var chat := await _mount("base_game.chat")
	await _shoot("07_chat_new_game")

	# Both breakpoints of the M8 HUD shell (ux_plan.md Phase 1 "done when"). Desktop first: expand
	# the chat dock, then open Main Menu alongside it — page + chat both at half height, the
	# draggable split (rules 1-2).
	if chat != null:
		var shell := chat.get("_shell") as HudShell
		shell.set_chat_expanded(true)
		await _shoot("07b_chat_expanded")
		# Phase 3's key acceptance capture: drive a real workflow through the dock and wait for
		# its completion event, so the resulting timeline visibly includes the rules-owned roll.
		chat.call("_on_submit", "I send scouts to forage the hills")
		while not (chat.get("_input") as LineEdit).editable:
			await process_frame
		await _shoot("07bb_chat_turn_with_timeline")
		# Phase 4 event state: a pending confirmation forces the chat to fill the stage and prevents
		# the panel stack from covering it. Drive the existing debug confirmation, then clear it so
		# later captures continue through the normal menu path.
		await chat.call("_on_dev_ask")
		await _shoot("07bc_chat_active_event")
		await chat.call("_answer", false)
		chat.call("_open_main_menu")
		await _shoot("07c_chat_and_menu_split")
		chat.call("_open_destination", "domain")
		await _shoot("07ca_domain_panel")
		chat.call("_open_destination", "map_layers")
		await _shoot("07cb_map_layers_panel")
		# The desktop path to the same layers: the shortcut's own column, over the map it changes.
		# Shot with the page closed, because that is the only state the shortcut exists in.
		shell.hide_page()
		shell.set_chat_expanded(false)
		(shell.get("_map_layers_button") as SkinnedButton).button.button_pressed = true
		shell.call("_toggle_map_layers")
		await _shoot("07cc_map_layers_flyout")
		# A layer names itself on the same plate the shortcut does, unrolling out from under the
		# column. Worth a capture of its own: it is the one part of the flyout whose overlap with the
		# chrome is a judgement about legibility rather than something a test can assert.
		var grid_plate: SkinnedButton = chat.get("_grid_layer_plate")
		shell.call("_show_map_layers_label", "Grid", grid_plate)
		await _shoot("07cd_map_layers_flyout_label")
		shell.call("_hide_map_layers_label")
		shell.call("_set_map_layers_open", false, false)

		# The terrain at both sides of `MIN_TEXTURED_TILE_PX`: the ground as authored, and the flat
		# average it falls back to once a tile is too small to read. The pair is the whole point of
		# the threshold — if the two shots disagree on colour, the fallback is wrong.
		var map_view: OverworldMapView = chat.get("_map_view")
		await _shoot("07da_map_terrain_close")

		# Selection, both ends of the ladder. These are the captures worth having: whether the
		# outline reads as an enclosure over ploughed earth, and whether a band cut from the
		# conversation's own parchment really sits on it as one surface, are judgements about the
		# art that no assertion about offsets can make.
		var plot := (BaseGameMap.constructions(chat.get("_terrain_map"))[0]["cells"]) as Rect2i
		chat.call("_on_subtile_clicked",
			plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2))
		await _shoot("07dc_map_selection_field")
		# The outpost's own cell, which no plot covers — dead centre of the frame, so the finest tier
		# is judged where it is easiest to see rather than somewhere near the edge.
		var site := BaseGameMap.outpost_site(chat.get("_terrain_map"))
		chat.call("_on_subtile_clicked",
			site * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2))
		await _shoot("07dd_map_selection_ground")
		shell.set_selection_visible(false)

		# Building a road. Three shots, because three separate judgements live here and none of them
		# can be asserted: whether the ghost reads as a plan rather than as a road, whether the
		# refusal colour is obviously a refusal, and whether the autotiled junctions actually join.
		var start := site * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 8)
		chat.call("_on_subtile_clicked", start)
		chat.call("_show_build_tools")
		await _shoot("07df_build_tools")
		chat.call("_enter_build_mode", BaseGameMap.TOOL_ROAD)
		# A run east, a turn north, and a branch — enough shapes that a wrong entry in the mask table
		# shows up as a junction facing the wrong way.
		for i in 14:
			chat.call("_on_subtile_painted", start + Vector2i(i, 0))
		for i in range(1, 9):
			chat.call("_on_subtile_painted", start + Vector2i(7, -i))
		for i in range(1, 6):
			chat.call("_on_subtile_painted", start + Vector2i(7 + i, -8))
		# And a stretch straight across a ploughed field, which may not be built on.
		for i in 8:
			chat.call("_on_subtile_painted",
				plot.position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(i, 4))
		await _shoot("07dg_build_road_plan")
		chat.call("_confirm_build")
		await _shoot("07dh_build_road_done")

		# The map stripped back to bare ground: the Terrain plate takes the fields and everything
		# standing on them away together, which is the one shot that shows the layer really reaching
		# the map rather than only latching.
		var terrain_plate: SkinnedButton = chat.get("_terrain_layer_plate")
		terrain_plate.button.button_pressed = true
		await _shoot("07de_map_terrain_only")
		terrain_plate.button.button_pressed = false

		while map_view.is_terrain_textured():
			map_view.call("_zoom_at", map_view.size * 0.5, 0.5)
		await _shoot("07db_map_terrain_far")

		# Narrow the window without remounting — crossing the breakpoint with both panels open
		# should collapse to whichever opened more recently (rule 5), not leave both on screen.
		DisplayServer.window_set_size(MOBILE_VIEWPORT_SIZE)
		await _settle()
		await _shoot("07d_mobile_exclusive")
		shell.call("_toggle_mobile_menu")
		await _shoot("07e_mobile_destinations")
		DisplayServer.window_set_size(VIEWPORT_SIZE)
		await _settle()

	await _capture_scene("res://modules/base_game/ui/flag_preview.tscn", "08_flag_preview")


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
		"language": "pt-BR",
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
