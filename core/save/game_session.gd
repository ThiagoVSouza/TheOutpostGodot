class_name GameSession
extends RefCounted

## The game in progress: where it lives, and when it is written (M4/B4a).
##
## Two persistence layers, answering different questions:
##
##   [SaveWorkspace] — `user://current/`, the live game as separate parts. Written at every
##       turn boundary and every OS lifecycle event, but only the parts that actually changed.
##       This is what survives a crash. Losing at most the turn in progress is the contract.
##   [SaveManager]   — `user://saves/<slot>.json`, a whole snapshot the player named. Written
##       deliberately, or on a long cadence. This is what the player keeps, revisits, and one
##       day shares.
##
## The distinction matters because the two have opposite cost profiles. A snapshot is
## O(total state) and would be ruinous per turn once M5's memories exist; a checkpoint touches
## only what moved. Building the split now is cheap — retrofitting it after memories land is
## not, which is the same argument that made migrations worth doing early.
##
## **There is deliberately no autosave interval.** A checkpoint that writes nothing when
## nothing changed costs a comparison, so throttling it would only add a way to lose a turn.
## (An earlier interval-based version also hid a real bug: `Time.get_ticks_msec()` is small in
## a short-lived process, so the *first* checkpoint — the one that matters most — was skipped.)

const DEFAULT_SLOT_NAME := "The Outpost"

## How often the game snapshots itself to a slot on its own, in game days. Rare on purpose: the
## workspace already protects against a crash, so this exists to give the player a named point
## to come back to, not to protect data.
const AUTO_SNAPSHOT_DAYS: int = 360

## Errors that mean "the data is fine, this build cannot read it" — as opposed to "the data is
## damaged". The distinction decides whether it is safe to move on: damaged data can be
## abandoned for a snapshot, but data written by a *newer* build must never be discarded or
## overwritten, because the player only has to reinstall the newer build to get it back.
const REFUSALS: Array[String] = ["save_from_newer_version", "module_from_newer_version"]

signal session_changed(slot_id: String, slot_name: String)

var slot_id: String = ""
var slot_name: String = DEFAULT_SLOT_NAME

## When false, only explicit [method checkpoint] / [method snapshot] calls write. Defaults off
## under the test runner so an automated run never writes into the player's real save
## directory — the same guard the trace writer uses (A1). A *default*, not a hard gate: tests
## of this machinery point at scratch directories and set it back on.
var autosave_enabled: bool = OS.get_environment("OUTPOST_TEST_RUN") != "1"

var _kernel: GameKernel
var _last_snapshot_day: int = 0


## Note on wiring: this does **not** subscribe itself to the event bus. A [RefCounted] that
## reaches the bus through the kernel and then hands the bus a handler capturing itself is the
## `session → kernel → events → handler → session` cycle the T1 notes warn about, and it leaks.
## [GameKernel] — a Node, with an explicit lifetime — owns the subscriptions and calls in here.
func _init(kernel: GameKernel) -> void:
	_kernel = kernel


func has_slot() -> bool:
	return not slot_id.is_empty()


func workspace() -> SaveWorkspace:
	return _kernel.workspace


# --- starting a session ------------------------------------------------------------------

## Resume the game in progress, or the newest snapshot, or start fresh — in that order.
## Returns `{ok, continued, source, error}` where `source` is "workspace", "slot" or "new".
##
## The workspace wins over a slot file even when the slot is newer by wall clock: the workspace
## *is* the game the player was playing, and a slot is a copy they took of it. Preferring the
## snapshot would silently discard everything since it was taken.
func continue_or_start() -> Dictionary:
	if workspace().exists():
		var resumed := _restore_from_workspace()
		if bool(resumed["ok"]):
			return {"ok": true, "continued": true, "source": "workspace", "error": ""}
		var error := String(resumed["error"])
		if REFUSALS.has(error):
			# The live game is intact — this build is simply too old to read it (a downgrade,
			# or a sideloaded older APK). **Stop here.** Continuing would reach `start_new`,
			# which clears the workspace, and the player would lose their settlement to a
			# version mismatch without ever being asked. Their files are untouched; the choice
			# of what to do next belongs to them.
			_kernel.log.error("GameSession",
				"Refusing to open the live game: %s. Left untouched." % error)
			return {"ok": false, "continued": false, "source": "workspace_blocked", "error": error}
		# Genuinely damaged rather than merely unreadable by this build. A snapshot is exactly
		# the backup for this, so fall through to the newest one.
		_kernel.log.warn("GameSession", "Workspace unreadable (%s); trying the newest snapshot"
			% error)

	var available: Array = _kernel.saves.slots()
	if not available.is_empty():
		var newest: Dictionary = available[0]  # slots() is newest first
		var loaded := load_slot(String(newest["id"]))
		if bool(loaded["ok"]):
			return {"ok": true, "continued": true, "source": "slot", "error": ""}
		# Do not adopt a slot that would not load: staying detached means the next snapshot
		# creates a new file instead of overwriting one the player may still want.
		_kernel.log.warn("GameSession", "Could not continue slot '%s' (%s); starting detached"
			% [newest["id"], loaded["error"]])
		slot_id = ""
		return {"ok": false, "continued": false, "source": "new", "error": String(loaded["error"])}

	start_new()
	return {"ok": true, "continued": false, "source": "new", "error": ""}


## Begin a new game, discarding the workspace. Writes no slot file: one is created on the first
## snapshot, so opening the game and closing it again never leaves a stray empty settlement.
func start_new(name: String = DEFAULT_SLOT_NAME) -> void:
	workspace().clear()
	slot_id = ""
	slot_name = name
	_last_snapshot_day = 0
	session_changed.emit(slot_id, slot_name)


## Load a slot snapshot over the current game. The workspace is replaced wholesale — a leftover
## part from the previous game would otherwise be read back as if it belonged to this one.
func load_slot(id: String) -> Dictionary:
	var loaded: Dictionary = _kernel.saves.load_slot(_kernel, id)
	if not bool(loaded["ok"]):
		return loaded
	var meta: Dictionary = (loaded["data"] as Dictionary).get("slot", {}) as Dictionary
	slot_id = id
	slot_name = String(meta.get("name", DEFAULT_SLOT_NAME))
	_last_snapshot_day = _kernel.clock.total_days
	workspace().clear()
	_write_all_parts()
	session_changed.emit(slot_id, slot_name)
	return loaded


# --- writing -----------------------------------------------------------------------------

## Write the live game to the workspace, touching only the parts that changed. This is the
## cheap, frequent write: called at every turn boundary and every OS lifecycle event.
## Returns the number of parts written.
func checkpoint(reason: String = "turn") -> int:
	if not autosave_enabled:
		return 0
	var written := _write_all_parts()
	if written > 0:
		_kernel.log.debug("GameSession", "Checkpointed %d part(s) (%s)" % [written, reason])
	_maybe_auto_snapshot()
	return written


## Write a whole snapshot to the slot, creating one on first use. This is the rare, expensive
## write — the thing the player thinks of as "saving".
func snapshot(reason: String = "manual") -> Dictionary:
	var result: Dictionary
	if has_slot():
		result = _kernel.saves.save_slot(_kernel, slot_id, slot_name)
	else:
		result = _kernel.saves.save_new(_kernel, slot_name)
	if not bool(result["ok"]):
		_kernel.log.error("GameSession", "Snapshot failed (%s): %s" % [reason, result["error"]])
		return result
	slot_id = String(result["slot_id"])
	_last_snapshot_day = _kernel.clock.total_days
	_kernel.log.info("GameSession", "Saved '%s' (%s)" % [slot_name, reason])
	session_changed.emit(slot_id, slot_name)
	return result


## The write that actually matters on mobile. Android can kill a backgrounded app without
## warning and never asks first, so this is the last moment we are guaranteed to run code —
## and because a checkpoint only writes what moved, it is cheap enough to always take.
func save_on_lifecycle_event(reason: String) -> int:
	return checkpoint(reason)


## Snapshot on a long game-time cadence so the player has named points to come back to. The
## workspace already covers crash safety, so this is a convenience, not a durability measure.
func _maybe_auto_snapshot() -> void:
	if not has_slot() and _kernel.clock.total_days == 0:
		return  # nothing has happened yet; do not create a settlement out of an empty game
	if _kernel.clock.total_days - _last_snapshot_day < AUTO_SNAPSHOT_DAYS:
		return
	snapshot("auto")


# --- parts <-> kernel ----------------------------------------------------------------------

## Serialize the live game and hand each part to the workspace, which skips the ones whose
## content has not changed. Assembling through [method SaveManager.capture] keeps one mapping
## between the kernel and the save shape, shared with snapshots.
func _write_all_parts() -> int:
	var payload := _kernel.saves.capture(_kernel, slot_id, slot_name)
	var ws := workspace()
	var written := 0
	var parts := {
		SaveWorkspace.WORLD: payload["state"],
		SaveWorkspace.GLOBALS: payload["globals"],
		SaveWorkspace.CLOCK: payload["clock"],
		SaveWorkspace.INSTANCES: payload["workflow_instances"],
		SaveWorkspace.META: {
			"version": payload["version"],
			"slot": payload["slot"],
		},
	}
	for part: String in parts:
		if ws.checkpoint_part(part, parts[part] as Dictionary):
			written += 1
	for id: String in (payload["modules"] as Dictionary):
		if ws.checkpoint_part(SaveWorkspace.module_part_name(id),
				(payload["modules"] as Dictionary)[id] as Dictionary):
			written += 1
	return written


## Reassemble the workspace parts into the save envelope and apply it. Going back through
## [method SaveManager.restore] is what gives the workspace B3's migrations for free — a
## workspace can be as old as any slot file if the player left the game closed across an update.
func _restore_from_workspace() -> Dictionary:
	var ws := workspace()
	var meta := ws.read_part(SaveWorkspace.META)
	if meta.is_empty():
		return {"ok": false, "error": "workspace_unreadable", "data": {}}
	var payload := {
		"version": meta.get("version", SaveManager.SAVE_VERSION),
		"slot": meta.get("slot", {}),
		"state": ws.read_part(SaveWorkspace.WORLD),
		"globals": ws.read_part(SaveWorkspace.GLOBALS),
		"clock": ws.read_part(SaveWorkspace.CLOCK),
		"workflow_instances": ws.read_part(SaveWorkspace.INSTANCES),
		"modules": ws.module_parts(),
	}
	var restored: Dictionary = _kernel.saves.restore(_kernel, payload)
	if not bool(restored["ok"]):
		return restored
	var slot: Dictionary = payload["slot"] as Dictionary
	slot_id = String(slot.get("id", ""))
	slot_name = String(slot.get("name", DEFAULT_SLOT_NAME))
	_last_snapshot_day = _kernel.clock.total_days
	# Reconciles anything the read did not cover (a part the save had but this build assembles
	# differently). Normally writes nothing: the workspace records what it reads as current.
	_write_all_parts()
	session_changed.emit(slot_id, slot_name)
	return restored
