class_name ScreenRouter
extends RefCounted

## Runtime screen navigation (the in-game boot flow). [ScreenRegistry] is a lookup table with one
## designated start screen; it has no notion of a *current* screen or of changing it. This is that
## layer: it owns the one mounted screen and swaps it on request, so the flow can move
## splash → loading → main menu → new game → game.
##
## Stateless infrastructure — no game state — like the registry it sits beside. The [Control] it
## mounts into (the main scene) registers itself once via [method set_host]; screens then call
## `Kernel.router.goto(id)` to advance.

var _screens: ScreenRegistry
var _host: Control = null
var _current: Node = null
var _current_id: String = ""


func _init(screens: ScreenRegistry) -> void:
	_screens = screens


## The mount point — the boot scene calls this once. All screens are added as children of it.
func set_host(host: Control) -> void:
	_host = host


func current_id() -> String:
	return _current_id


## Show the screen registered under [param id], replacing whatever is mounted. If the screen
## defines `on_enter(params)` it is called *before* the screen enters the tree, so its `_ready`
## can rely on the params. A no-op with a warning if there is no host or the id is unknown.
func goto(id: String, params: Dictionary = {}) -> void:
	if _host == null:
		push_error("ScreenRouter.goto('%s') with no host set" % id)
		return
	if not _screens.has(id):
		# A deliberate no-op, not a crash — the current screen stays put. A warning, not an error,
		# so a mistyped target is visible without taking the app (or a test) down.
		push_warning("ScreenRouter.goto('%s'): no such screen" % id)
		return
	var next := _screens.instantiate(id)
	if next == null:
		push_error("ScreenRouter.goto('%s'): failed to instantiate" % id)
		return
	if next.has_method("on_enter"):
		next.call("on_enter", params)
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = next
	_current_id = id
	_host.add_child(next)
