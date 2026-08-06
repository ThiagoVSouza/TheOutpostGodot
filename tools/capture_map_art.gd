extends SceneTree

## Dev tool: mount the game screen and shoot the map once per state of whatever art is being judged —
## the crop cycle today, building stages when there are any.
##
## Exists for the same reason `capture_screens.gd` does, one level narrower. That tool proves every
## *screen* still renders; this one is for looking at a single painting against the real map, at a
## real zoom, with the real ground under it — which is the only place a wrong anchor, a mip halo or a
## seam actually shows. Pressing `5`–`8` in the running game does the same thing; this is the version
## that leaves files behind to compare side by side.
##
## Run: `$GODOT --path . -s res://tools/capture_map_art.gd`
## Writes `user://map_art/*.png` (override with `OUTPOST_CAPTURE_DIR`, an absolute path).
##
## Not a test — it asserts nothing. It produces evidence a human can look at.

const OUT_SUBDIR := "map_art"
const VIEWPORT_SIZE := Vector2i(1280, 800)
## Layout settles on the second frame and the map's textures load on `setup`; a few frames of margin
## costs a capture run nothing. Same reasoning as `capture_screens.gd`.
const SETTLE_FRAMES := 8

## How far to pull back from the opening frame for the wide shot, which is the one that shows whether
## a group of fields reads as a holding or as a pile of squares.
const WIDE_ZOOM_STEPS := 4
const WIDE_ZOOM_FACTOR := 0.8

var _out_dir := ""
var _host: Control = null
var _kernel: Node = null
var _saved: Array[String] = []


func _initialize() -> void:
	_out_dir = OS.get_environment("OUTPOST_CAPTURE_DIR")
	if _out_dir.is_empty():
		_out_dir = "user://".path_join(OUT_SUBDIR)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# `_initialize` runs before autoloads are ready: the kernel exists but has not booted, so its
	# subsystems are still null. One frame is what turns it into a usable kernel.
	await process_frame
	_kernel = root.get_node("Kernel")
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

	_kernel.router.goto("base_game.chat")
	await _settle()
	var screen: Node = _host.get_child(_host.get_child_count() - 1)
	var view: OverworldMapView = screen.get("_map_view")
	if view == null:
		push_warning("capture: the game screen has no map view")
		return

	# The opening frame, one shot per stage. Same camera every time, so the four are comparable and a
	# frame cut off its pitch would show as the field stepping sideways between them.
	for stage in BaseGameMap.CropStage.size():
		screen.call("_set_crop_stage", stage)
		_finish_fade(view)
		await _shoot("crop_%d_%s" % [stage,
			String(BaseGameMap.CROP_STAGE_TITLES[stage]).to_snake_case()])
	screen.call("_set_crop_stage", BaseGameMap.CropStage.GROWING)

	# The house, every state, clear and snowed. Same camera again for the same reason: sixteen frames
	# cut from one sheet have to land in exactly the same place, and a shot per state is how you see
	# that they do.
	var was_snow: bool = Buildings.snow
	for snowed: bool in [false, true]:
		Buildings.snow = snowed
		for which in Buildings.Appearance.size():
			screen.call("_set_house_appearance", which)
			_finish_fade(view)
			await _shoot("house_%s%d_%s" % ["snow_" if snowed else "", which,
				String(Buildings.APPEARANCE_TITLES[which]).to_snake_case()])
	Buildings.snow = was_snow
	screen.call("_set_house_appearance", Buildings.Appearance.FINISHED)

	# Pulled back, at the stage with the most in it: this is the shot that answers whether neighbouring
	# fields overlap into one holding or read as a grid of squares.
	screen.call("_set_crop_stage", BaseGameMap.CropStage.RIPE)
	for _step in WIDE_ZOOM_STEPS:
		view.call("_zoom_at", Vector2(VIEWPORT_SIZE) * 0.5, WIDE_ZOOM_FACTOR)
	await _shoot("crop_wide")

	# And far enough out that the art is gone and only the averaged colour is left — the fallback that
	# keeps a field a brown patch instead of vanishing into the grass.
	while view.is_terrain_textured():
		view.call("_zoom_at", Vector2(VIEWPORT_SIZE) * 0.5, 0.6)
	await _shoot("crop_flat")

	# **The one shot for judging sizes against each other.** A house, a field and a tree in one frame
	# with both grids on, close enough that all three are drawn at their painted detail — which is the
	# only way to see whether they belong to the same world.
	var map: TerrainMap = screen.get("_terrain_map")
	if map != null:
		view.set_tile_grid_visible(true)
		view.set_subgrid_visible(true)
		# **Settle first, then frame.** The view re-fits to the default frame whenever it is resized,
		# and layout is still settling for the first frames after a change — so framing a shot and
		# *then* waiting has the framing quietly undone before the picture is taken.
		await _settle()
		_focus(view, map, Vector2(BaseGameMap.outpost_site(map)) + HARMONY_FOCUS, HARMONY_SUBTILE_PX)
		# A couple of frames for the queued redraw to actually land — `queue_redraw` schedules, it does
		# not draw — but not the full settle, which is long enough for a late relayout to re-fit.
		await process_frame
		await process_frame
		await _shoot("harmony", false)

		# **The dissolve, caught at four points.** A stage change is a change to the world and the
		# world does not cut; a still cannot show that, so here is the same field at rest, a third and
		# two thirds of the way into becoming the next one, and arrived.
		screen.call("_set_crop_stage", BaseGameMap.CropStage.GROWING)
		_finish_fade(view)
		await _frame()
		await _shoot("dissolve_0_growing", false)
		screen.call("_set_crop_stage", BaseGameMap.CropStage.RIPE)
		for part: float in [0.35, 0.65]:
			await _shoot_at_fade(view, "dissolve_%d" % int(part * 100.0), part)
		_finish_fade(view)
		await _frame()
		await _shoot("dissolve_100_ripe", false)


## Where the house row, the nearest field and open ground for the trees all fall within one frame, as
## tiles from the outpost's own cell — and how big a subtile is drawn while looking at them.
##
## **In canvas units, not saved-image pixels.** The project designs against a 720x1280 viewport and
## stretches `canvas_items` to the window, so at a 1280x800 window a control unit is 0.625 of a
## physical pixel and everything in the PNG comes out smaller than the number asked for. Ninety here
## is about 56 pixels in the file — a house you can read — and thirteen subtiles of view height, which
## is just enough to hold the house row and the nearest field in one frame.
const HARMONY_FOCUS := Vector2(0.4, -1.7)
const HARMONY_SUBTILE_PX := 90.0


## Put [param at] (in tiles) in the middle of the view at a chosen subtile size. Reaches past the
## view's public surface deliberately: framing a shot is not something the game does, so there is no
## public call for it and inventing one would be API for a screenshot's benefit.
func _focus(view: OverworldMapView, map: TerrainMap, at: Vector2, subtile_px: float) -> void:
	# **The view re-frames itself whenever it is resized** (`resized.connect(fit)` in its `_ready`),
	# and a shell relayout can land several frames after everything looks settled — which silently puts
	# the camera back to the default frame between the framing and the shutter. Let go of that here;
	# this script's window never changes size again anyway.
	if view.resized.is_connected(view.fit):
		view.resized.disconnect(view.fit)
	var zoom := subtile_px * float(OverworldMapView.SUBGRID_DIVISIONS) / float(map.tile_size_px)
	view.set("_zoom", clampf(zoom, OverworldMapView.MIN_ZOOM, OverworldMapView.MAX_ZOOM))
	# The view's **own** size, which is in canvas units and is not the window's size — see
	# [constant HARMONY_SUBTILE_PX]. Centring on the window's pixel size puts the camera somewhere else
	# entirely, and the error is a plausible-looking offset rather than an obvious one.
	view.set("_origin", at * float(map.tile_size_px)
		- (view.size * 0.5) / (view.get("_zoom") as float))
	view.call("_clamp_origin")
	view.call("_refresh")


## Run the cross-dissolve to its end without waiting for it. The captures are stills of *states*, and
## a shot taken while the map is still halfway between two of them is a picture of neither.
func _finish_fade(view: OverworldMapView) -> void:
	view.call("_process", OverworldMapView.STANDING_FADE_SECONDS)


## Hold the dissolve at [param part] and photograph it. Processing goes off first: the fade advances
## itself every frame, so a value set and then waited on is never the value photographed.
func _shoot_at_fade(view: OverworldMapView, name: String, part: float) -> void:
	view.set_process(false)
	view.set("_standing_fade", part)
	view.queue_redraw()
	await _frame()
	await _shoot(name, false)


func _frame() -> void:
	await process_frame
	await process_frame


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## Grab the rendered viewport. `frame_post_draw` is the only point at which the texture holds this
## frame rather than the previous one.
func _shoot(name: String, settle: bool = true) -> void:
	if settle:
		await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name + ".png")
	if image.save_png(path) == OK:
		_saved.append(name + ".png")
	else:
		push_warning("capture: could not write %s" % path)
