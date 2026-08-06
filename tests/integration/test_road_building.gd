extends GutTest

## Building a road, end to end: select open ground, reach Build through the band, draw, and confirm —
## and every way of abandoning it in between.
##
## The load-bearing promise is that **nothing touches the world until Confirm**. A plan is a drawing;
## the roads only change when the player says so, and cancelling has to leave no trace.


## **Roads live in the world, and the world is an autoload.** A road built in one test is still there
## in the next, which is right for the game and wrong for a test: the second one would open on ground
## it thought was bare, click it, and select a road instead of the open terrain it meant to build on.
func before_each() -> void:
	Kernel.state.set_value(RoadNetwork.STATE_KEY, [])


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	return screen


func _roads(screen: Control) -> RoadNetwork:
	return screen.get("_roads") as RoadNetwork


func _plot(screen: Control) -> Rect2i:
	var map := screen.get("_terrain_map") as TerrainMap
	return (BaseGameMap.constructions(map)[0]["cells"]) as Rect2i


## A subtile on open ground, well clear of every farm.
func _open(screen: Control, offset := Vector2i.ZERO) -> Vector2i:
	var site := BaseGameMap.outpost_site(screen.get("_terrain_map") as TerrainMap)
	return (site + Vector2i(0, 6)) * BaseGameMap.SUBTILES_PER_TILE + offset


func _on_field(screen: Control) -> Vector2i:
	return _plot(screen).position * BaseGameMap.SUBTILES_PER_TILE + Vector2i(2, 2)


## Reach build mode the way a player does: click open ground, press Build, pick the tool.
##
## The ground clicked to get here is deliberately well away from where the tests draw. Build is
## offered on open terrain and not on a road, so re-entering by clicking a square you have just paved
## would find a road selected and no Build button on the band — which is correct, and not the thing
## any of these tests is about.
func _start_building(screen: Control, tool_label: String = "Road") -> void:
	screen.call("_on_subtile_clicked", _open(screen, Vector2i(0, 12)))
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_press_action(dock, "Build")
	_press_action(dock, tool_label)


func _press_action(dock: SelectionDock, label: String) -> bool:
	for child in dock.actions.get_children():
		var button := child as SkinnedButton
		if button != null and button.label.text == label:
			button.pressed.emit()
			return true
	return false


func _action_labels(dock: SelectionDock) -> Array:
	var out: Array = []
	for child in dock.actions.get_children():
		var button := child as SkinnedButton
		if button != null:
			out.append(button.label.text)
	return out


func _paint(screen: Control, subtiles: Array) -> void:
	for at: Vector2i in subtiles:
		screen.call("_on_subtile_painted", at)


# --- getting there ------------------------------------------------------------------------------

## Only open ground can be built on, so only open ground offers the button.
func test_build_is_offered_on_open_ground_and_not_on_a_field() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock

	screen.call("_on_subtile_clicked", _open(screen))
	assert_true(_action_labels(dock).has("Build"), "open ground can be built on")

	screen.call("_on_subtile_clicked", _on_field(screen))
	assert_false(_action_labels(dock).has("Build"),
		"a field offers no Build rather than one that would refuse")


func test_choosing_a_tool_hands_the_map_over_to_drawing() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock

	screen.call("_on_subtile_clicked", _open(screen))
	_press_action(dock, "Build")
	assert_eq(_action_labels(dock), ["Road", "Demolish", "Back"])
	assert_false(view.is_paint_mode(), "picking is not yet drawing")

	_press_action(dock, "Road")
	assert_true(screen.call("is_building"))
	assert_true(view.is_paint_mode())
	assert_eq(_action_labels(dock), ["Confirm", "Cancel"])
	assert_false(view.has_selection(),
		"the square that got you here stops being the subject once you are drawing")


# --- drawing and confirming ----------------------------------------------------------------------

func test_a_drawn_run_is_only_a_plan_until_confirm() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_start_building(screen)

	var run: Array = []
	for i in 4:
		run.append(_open(screen, Vector2i(i, 0)))
	_paint(screen, run)

	assert_true(view.has_road_plan(), "the run shows as ghosts")
	assert_eq(_roads(screen).count(), 0, "and nothing is built yet")

	_press_action(dock, "Confirm")
	assert_eq(_roads(screen).count(), 4)
	for at: Vector2i in run:
		assert_true(_roads(screen).has_road(at))
	assert_false(view.has_road_plan(), "the ghosts go once they are real")
	assert_false(screen.call("is_building"), "confirming drops you back out")
	assert_false(view.is_paint_mode())


func test_cancelling_leaves_no_trace_of_the_plan() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_start_building(screen)
	_paint(screen, [_open(screen), _open(screen, Vector2i(1, 0))])

	_press_action(dock, "Cancel")
	assert_eq(_roads(screen).count(), 0)
	assert_false(view.has_road_plan())
	assert_false(screen.call("is_building"))
	assert_false(view.is_paint_mode(), "the drag goes back to moving the map")


## Esc reaches the plan before anything the shell owns — the shell's own first move would be to hide
## the band, which is where Cancel lives.
func test_escape_abandons_the_plan_before_anything_underneath_it() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var view := screen.get("_map_view") as OverworldMapView
	_start_building(screen)
	_paint(screen, [_open(screen)])

	assert_true(screen.call("on_hardware_back"))
	assert_false(screen.call("is_building"))
	assert_eq(_roads(screen).count(), 0)
	assert_false(view.has_road_plan())


## Sweeping across a farm gives the road either side of it, which is what the player was drawing.
func test_confirm_builds_the_valid_pieces_and_drops_the_refused_ones() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_start_building(screen)

	var good := _open(screen)
	var bad := _on_field(screen)
	_paint(screen, [good, bad])

	_press_action(dock, "Confirm")
	assert_true(_roads(screen).has_road(good))
	assert_false(_roads(screen).has_road(bad), "the field is still a field")
	assert_eq(_roads(screen).count(), 1)


## A plan of nothing but refusals would apply nothing, and a Confirm that did nothing would look
## broken rather than disallowed.
func test_confirm_is_dead_until_there_is_something_it_could_build() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_start_building(screen)

	var confirm := screen.get("_confirm_button") as SkinnedButton
	assert_true(confirm.button.disabled, "nothing drawn yet")
	_paint(screen, [_on_field(screen)])
	assert_true(confirm.button.disabled, "a plan of only refusals is still nothing to build")
	_paint(screen, [_open(screen)])
	assert_false(confirm.button.disabled)
	_press_action(dock, "Cancel")


# --- demolishing ---------------------------------------------------------------------------------

func test_demolish_takes_roads_away_and_leaves_everything_else() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := (screen.get("_shell") as HudShell).get("_selection_dock") as SelectionDock
	_start_building(screen)
	var run := [_open(screen), _open(screen, Vector2i(1, 0)), _open(screen, Vector2i(2, 0))]
	_paint(screen, run)
	_press_action(dock, "Confirm")
	assert_eq(_roads(screen).count(), 3)

	_start_building(screen, "Demolish")
	# Drag across one road and a stretch of bare ground beyond it.
	_paint(screen, [run[1], _open(screen, Vector2i(8, 0))])
	_press_action(dock, "Confirm")

	assert_eq(_roads(screen).count(), 2, "one road removed, and the bare ground was never anything")
	assert_false(_roads(screen).has_road(run[1] as Vector2i))
	assert_true(_roads(screen).has_road(run[0] as Vector2i))


# --- the world ------------------------------------------------------------------------------------

func test_a_built_road_is_written_to_the_world_and_can_be_selected() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var shell := screen.get("_shell") as HudShell
	var dock := shell.get("_selection_dock") as SelectionDock
	_start_building(screen)
	var at := _open(screen)
	_paint(screen, [at])
	_press_action(dock, "Confirm")

	# It went into state, which is what makes it survive a save.
	var stored: Variant = Kernel.state.get_value(RoadNetwork.STATE_KEY, [])
	assert_true(stored is Array and (stored as Array).size() >= 2)

	screen.call("_on_subtile_clicked", at)
	assert_true(shell.is_selection_visible())
	assert_eq((dock.get("_title_label") as Label).text, "Road")
	var view := screen.get("_map_view") as OverworldMapView
	assert_eq(view.selection(), [Rect2i(at, Vector2i.ONE)] as Array[Rect2i],
		"one piece, not the run it belongs to")
