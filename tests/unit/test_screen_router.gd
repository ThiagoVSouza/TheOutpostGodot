extends GutTest

## The ScreenRouter (in-game boot flow): it swaps the one mounted screen and delivers on_enter
## params. Uses a fresh ScreenRegistry + runtime-packed scenes, so no booted kernel is needed.

const PROBE := preload("res://tests/fixtures/router_probe.gd")

var _registry: ScreenRegistry
var _host: Control
var _router: ScreenRouter


func before_each() -> void:
	_registry = ScreenRegistry.new()
	_registry.register("a", _plain_scene())
	_registry.register("b", _plain_scene())
	_registry.register("probe", _probe_scene())
	_host = Control.new()
	add_child_autofree(_host)
	_router = ScreenRouter.new(_registry)
	_router.set_host(_host)


func _plain_scene() -> PackedScene:
	return _pack(Control.new())


func _probe_scene() -> PackedScene:
	return _pack(PROBE.new())


func _pack(node: Node) -> PackedScene:
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()  # the scene keeps its own copy; free the source so it is not left orphaned
	return scene


func test_goto_mounts_the_screen() -> void:
	_router.goto("a")
	assert_eq(_host.get_child_count(), 1, "the screen is mounted under the host")
	assert_eq(_router.current_id(), "a")


func test_goto_swaps_the_current_screen() -> void:
	_router.goto("a")
	var first := _host.get_child(0)
	_router.goto("b")
	assert_eq(_router.current_id(), "b")
	await get_tree().process_frame  # queue_free lands next frame
	assert_false(is_instance_valid(first), "the previous screen was freed")
	assert_eq(_host.get_child_count(), 1, "exactly one screen is ever mounted")


func test_on_enter_delivers_params_before_mount() -> void:
	_router.goto("probe", {"next": "core.main_menu"})
	var mounted := _host.get_child(_host.get_child_count() - 1)
	assert_eq(mounted.entered_params, {"next": "core.main_menu"})


func test_goto_unknown_id_is_a_safe_no_op() -> void:
	_router.goto("a")
	_router.goto("does_not_exist")
	assert_eq(_router.current_id(), "a", "an unknown target leaves the current screen in place")
	assert_eq(_host.get_child_count(), 1)
