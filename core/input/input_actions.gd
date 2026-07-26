class_name InputActions
extends RefCounted

## The game's input actions, and the one place that knows their default keys.
##
## Everything the player can trigger with a key goes through Godot's [InputMap] rather than a
## screen matching keycodes itself — that indirection *is* rebinding: a screen asks "was this the
## `pass_day` action?" and never learns which key that is.
##
## **Only actions with something behind them live here.** The settings screen's Controls tab lists
## more than this (roster, chronicle, quick-load, screenshot, map panning by key) — those are the
## intended set and stay marked `planned`, because an action bound to a feature that does not exist
## is a binding the player can change and then watch do nothing, which is the failure the whole
## `planned` discipline exists to prevent. Move an entry here when its feature lands, not before.
##
## Defaults come from the same list the Controls tab was written against (`docs/Remember.md`'s
## promise that every binding is changeable); overrides live in [AppSettings] and are re-applied
## over these at boot.

const FOCUS_INPUT := "focus_input"
const PASS_DAY := "pass_day"
const OPEN_MAP := "open_map"
const MAP_ZOOM_IN := "map_zoom_in"
const MAP_ZOOM_OUT := "map_zoom_out"
const QUICK_SAVE := "quick_save"
const OPEN_SETTINGS := "open_settings"
const BACK_CLOSE := "back_close"

## `group` matches the Controls tab's own headings, so the tab can be built from this list instead
## of keeping a parallel one that drifts.
const ACTIONS := [
	{"id": FOCUS_INPUT, "label": "Focus the input", "group": "Conversation", "default": KEY_T},
	{"id": PASS_DAY, "label": "Let a day pass", "group": "The world", "default": KEY_SPACE},
	{"id": OPEN_MAP, "label": "Open the map", "group": "The world", "default": KEY_M},
	{"id": MAP_ZOOM_IN, "label": "Zoom in", "group": "Map", "default": KEY_EQUAL},
	{"id": MAP_ZOOM_OUT, "label": "Zoom out", "group": "Map", "default": KEY_MINUS},
	{"id": OPEN_SETTINGS, "label": "Settings", "group": "System", "default": KEY_F1},
	{"id": QUICK_SAVE, "label": "Quick save", "group": "System", "default": KEY_F5},
	{"id": BACK_CLOSE, "label": "Back / close", "group": "System", "default": KEY_ESCAPE},
]


static func ids() -> Array:
	var out: Array = []
	for action: Dictionary in ACTIONS:
		out.append(String(action["id"]))
	return out


static func definition(id: String) -> Dictionary:
	for action: Dictionary in ACTIONS:
		if String(action["id"]) == id:
			return action
	return {}


static func default_keycode(id: String) -> int:
	return int(definition(id).get("default", KEY_NONE))


## Register every action on the [InputMap] and bind it, preferring the player's stored override.
## Called once at boot and again whenever a binding changes — it rebuilds from scratch, so there is
## no path where a stale event is left attached.
static func install(settings: AppSettings) -> void:
	for action: Dictionary in ACTIONS:
		var id := String(action["id"])
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id)
		var keycode := keycode_for(id, settings)
		# An action can legitimately have no key — the loser of a conflict. It stays *registered*
		# so `event.is_action()` calls against it keep working (and answering false), rather than
		# every caller having to check whether the action exists.
		if keycode != KEY_NONE:
			InputMap.action_add_event(id, _key_event(keycode))


## The keycode actually in force: the player's override if they set one, else the default.
## [constant AppSettings.UNBOUND] reports as [constant KEY_NONE] — deliberately no key, which is
## different from having no override and so must not fall through to the default.
static func keycode_for(id: String, settings: AppSettings) -> int:
	if settings != null:
		var override := settings.key_binding(id)
		if override == AppSettings.UNBOUND:
			return KEY_NONE
		if override != AppSettings.NO_KEY:
			return override
	return default_keycode(id)


## The action currently bound to [param keycode], or "" — what conflict detection asks. A key may
## only drive one action: two actions on one key is not a preference, it is a bug the player set.
static func action_using(keycode: int, settings: AppSettings, except: String = "") -> String:
	if keycode == KEY_NONE:
		return ""  # "no key" is not a clash; any number of actions may be unbound at once
	for id: String in ids():
		if id != except and keycode_for(id, settings) == keycode:
			return id
	return ""


## A key's display name ("Space", "F5", "Escape"). [method OS.get_keycode_string] is the engine's
## own naming, so it matches what the player sees elsewhere and is localized for their layout.
static func key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode != KEY_NONE else "Unbound"


## Logical `keycode`, not `physical_keycode`: these are named keys and letters the player picked by
## the label on the cap, and [method key_name] reports them the same way. Physical codes would be
## the right choice for a WASD-shaped movement cluster, and are worth revisiting if map panning by
## key ever lands.
static func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	return event
