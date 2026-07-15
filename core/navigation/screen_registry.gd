class_name ScreenRegistry
extends RefCounted

## Registry of screens that modules contribute.
##
## Modules register screens by id through this seam (per the brief's "Screen and
## navigation registration" core responsibility) rather than instancing scenes into
## the tree themselves. The boot flow / navigation reads it back to display a screen.

var _screens: Dictionary = {}  # id: String -> PackedScene
var _start_screen_id: String = ""


## Register a screen. The first screen registered with [param is_start] = true becomes
## the initial screen shown after boot.
func register(id: String, scene: PackedScene, is_start: bool = false) -> void:
	_screens[id] = scene
	if is_start and _start_screen_id.is_empty():
		_start_screen_id = id


func has(id: String) -> bool:
	return _screens.has(id)


func get_scene(id: String) -> PackedScene:
	return _screens.get(id, null)


func start_screen_id() -> String:
	return _start_screen_id


func screen_ids() -> Array:
	return _screens.keys()


## Instantiate a registered screen, or null if unknown.
func instantiate(id: String) -> Node:
	var scene: PackedScene = _screens.get(id, null)
	if scene == null:
		return null
	return scene.instantiate()
