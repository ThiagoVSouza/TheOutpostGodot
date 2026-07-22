class_name GameSession
extends RefCounted

## Which slot the player is currently in, and when it gets written (M4/B4a).
##
## [SaveManager] knows *how* to read and write a slot; this knows *which one* and *when* — the
## policy half, deliberately separate so the mechanism stays testable without a running session.
##
## The autosave policy is built around one fact: **on Android the OS can kill a backgrounded
## app without warning, and it never asks first.** So the only write that is genuinely
## guaranteed is the one made when the app is *told* it is going to the background. Everything
## else — the per-turn autosave — is an optimization that limits how much a hard kill can cost.
##
## Turn-boundary autosaves are coalesced by [constant AUTOSAVE_INTERVAL] so a fast player does
## not write a file every second; a lifecycle save always writes immediately and ignores it.

## Minimum seconds between turn-boundary autosaves. Lifecycle saves bypass this entirely.
const AUTOSAVE_INTERVAL: float = 20.0

const DEFAULT_SLOT_NAME := "The Outpost"

## Emitted after a load, a new game, or any successful save, so UI can reflect the slot.
signal session_changed(slot_id: String, slot_name: String)

var slot_id: String = ""
var slot_name: String = DEFAULT_SLOT_NAME

## When false, only explicit [method save] calls write. Defaults to off under the test runner
## so an automated run never writes into the player's real save directory — the same guard the
## trace writer uses (A1). A *default*, not a hard gate: tests of this machinery point at a
## scratch directory and set it back on.
var autosave_enabled: bool = OS.get_environment("OUTPOST_TEST_RUN") != "1"

var _kernel: GameKernel
## -1 means "not saved yet this session". A plain 0 would compare against a process that has
## only been alive a few seconds and wrongly conclude the interval had not elapsed — so the
## very first autosave of a short session would be skipped, which is the one that matters most.
var _last_autosave_msec: int = -1
var _dirty: bool = false


## Note on wiring: this does **not** subscribe itself to the event bus. A [RefCounted] that
## reaches the bus through the kernel and then hands the bus a handler capturing itself is the
## `session → kernel → events → handler → session` cycle the T1 notes warn about, and it leaks.
## [GameKernel] — a Node, with an explicit lifetime — owns the subscriptions and calls in here.
func _init(kernel: GameKernel) -> void:
	_kernel = kernel


## True once this session is attached to a slot on disk.
func has_slot() -> bool:
	return not slot_id.is_empty()


# --- starting a session ------------------------------------------------------------------

## Resume the most recently saved slot, or start a fresh session if there is none.
## Returns `{ok, continued, slot_id, error}` — `continued` distinguishes "loaded a save" from
## "there was nothing to load", which is not an error and callers usually render differently.
func continue_or_start() -> Dictionary:
	var available: Array = _kernel.saves.slots()
	if available.is_empty():
		start_new()
		return {"ok": true, "continued": false, "slot_id": slot_id, "error": ""}

	var newest: Dictionary = available[0]  # slots() is newest first
	var loaded := load_slot(String(newest["id"]))
	if not bool(loaded["ok"]):
		# A corrupt or unreadable newest save must not wedge the player out of their game.
		# Starting fresh here would *overwrite* it on the next autosave, so the session stays
		# detached from any slot: the game is playable and the bad file is left alone for the
		# player (or a support conversation) to deal with.
		_kernel.log.warn("GameSession", "Could not continue slot '%s' (%s); starting detached"
			% [newest["id"], loaded["error"]])
		slot_id = ""
		slot_name = String(newest.get("name", DEFAULT_SLOT_NAME))
		return {"ok": false, "continued": false, "slot_id": "", "error": String(loaded["error"])}
	return {"ok": true, "continued": true, "slot_id": slot_id, "error": ""}


## Begin a new session. Does not write anything: a slot is created on the first save, so
## opening the game and closing it again never leaves a stray empty settlement behind.
func start_new(name: String = DEFAULT_SLOT_NAME) -> void:
	slot_id = ""
	slot_name = name
	_dirty = false
	session_changed.emit(slot_id, slot_name)


func load_slot(id: String) -> Dictionary:
	var loaded: Dictionary = _kernel.saves.load_slot(_kernel, id)
	if not bool(loaded["ok"]):
		return loaded
	slot_id = id
	var meta: Dictionary = (loaded["data"] as Dictionary).get("slot", {}) as Dictionary
	slot_name = String(meta.get("name", DEFAULT_SLOT_NAME))
	_dirty = false
	_last_autosave_msec = Time.get_ticks_msec()
	session_changed.emit(slot_id, slot_name)
	return loaded


# --- writing -----------------------------------------------------------------------------

## Write the session now, creating its slot on first save. [param reason] is recorded in the
## log so a trace of when saves happened is readable after the fact.
func save(reason: String = "manual") -> Dictionary:
	var result: Dictionary
	if has_slot():
		result = _kernel.saves.save_slot(_kernel, slot_id, slot_name)
	else:
		result = _kernel.saves.save_new(_kernel, slot_name)
	if not bool(result["ok"]):
		_kernel.log.error("GameSession", "Save failed (%s): %s" % [reason, result["error"]])
		return result
	slot_id = String(result["slot_id"])
	_dirty = false
	_last_autosave_msec = Time.get_ticks_msec()
	_kernel.log.info("GameSession", "Saved '%s' (%s)" % [slot_name, reason])
	session_changed.emit(slot_id, slot_name)
	return result


## Mark that something happened worth persisting. Cheap and safe to call often — the decision
## about whether to actually write belongs to [method autosave].
func mark_dirty() -> void:
	_dirty = true


## A turn-boundary autosave: writes only if something changed and the interval has elapsed.
## Returns true if it wrote.
func autosave() -> bool:
	if not _autosave_allowed() or not _dirty:
		return false
	if _last_autosave_msec >= 0 \
			and Time.get_ticks_msec() - _last_autosave_msec < int(AUTOSAVE_INTERVAL * 1000.0):
		return false
	return bool(save("autosave")["ok"])


## The save that actually matters. Called when the OS tells us the app is leaving the
## foreground, or is closing — the last moment we are guaranteed to run code. Ignores the
## interval and writes whenever there is anything to write, because there may be no next
## chance: Android kills backgrounded apps without asking.
func save_on_lifecycle_event(reason: String) -> bool:
	if not _autosave_allowed() or not _dirty:
		return false
	return bool(save(reason)["ok"])


func _autosave_allowed() -> bool:
	return autosave_enabled
