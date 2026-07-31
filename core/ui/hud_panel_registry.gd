class_name HudPanelRegistry
extends RefCounted

## Module-contributed destinations for the in-game HUD. Core owns the seam and ordering; modules
## declare the pages they own. A builder receives a ready HudPanel and current GameKernel. A refresh
## callback runs immediately before the persistent panel is shown, so it reflects the current game.

var _pages: Dictionary = {} # id: String -> {label, title, build, refresh, icon}
var _order: Array[String] = []


## [param icon] is the destination's plate on the rail — a whole painted button, art and border
## together, which is why it is the module's to declare rather than the skin's to look up by id. A
## page registered without one is drawn as a lettered plate instead.
func register(id: String, label: String, title: String, build: Callable = Callable(),
		refresh: Callable = Callable(), icon: Texture2D = null) -> void:
	if id.is_empty():
		push_error("HudPanelRegistry.register requires a non-empty id")
		return
	if not _pages.has(id):
		_order.append(id)
	_pages[id] = {"label": label, "title": title, "build": build, "refresh": refresh, "icon": icon}


func has(id: String) -> bool:
	return _pages.has(id)


func page_ids() -> Array[String]:
	return _order.duplicate()


func definition(id: String) -> Dictionary:
	var page: Dictionary = _pages.get(id, {})
	return page.duplicate()


func build(id: String, panel: HudPanel, kernel: GameKernel) -> void:
	var page: Dictionary = _pages.get(id, {})
	var builder: Callable = page.get("build", Callable())
	if builder.is_valid():
		builder.call(panel, kernel)


func refresh(id: String, panel: HudPanel, kernel: GameKernel) -> void:
	var page: Dictionary = _pages.get(id, {})
	var refresher: Callable = page.get("refresh", Callable())
	if refresher.is_valid():
		refresher.call(panel, kernel)
