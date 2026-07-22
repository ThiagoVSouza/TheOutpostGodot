class_name SaveManager
extends RefCounted

## Named save slots on disk (M4/B2). One JSON file per slot under [member saves_dir], plus a
## `.bak` of that slot's previous contents.
##
## **JSON, not binary** (M4 direction review): the project is already JSON canonical form
## throughout — the DSL (D24), traces (D21), instance snapshots (§5.2) — migrations over JSON
## are far cheaper to write and test, and a save you can read in a text editor is a save you
## can debug.
##
## **There is no index file.** Each save is self-describing and [method slots] derives the list
## by scanning the directory, which removes an entire class of bug: an index that disagrees
## with the files beside it. With the handful of slots a player keeps, parsing them is cheap.
## If that ever stops being true, add a cache then — but the files stay the source of truth.
##
## **Slot ids are opaque and generated**, never derived from the player's name for the save.
## That keeps filenames out of the player's hands entirely: no sanitizing, no collision between
## two names that normalize alike, no unicode filename surprises. The name is metadata inside
## the file, and the player may rename or reuse it freely.
##
## Migrations are B3; this reads and writes [constant SAVE_VERSION] and **refuses** anything
## newer (see [method read_slot]).

## The core save format version, bumped when the envelope below changes shape. Per-module
## versions are stamped separately, from each module's own manifest.
const SAVE_VERSION: int = 1

const EXTENSION := ".json"

var saves_dir: String

## Module data from the last loaded save whose module is not loaded in this build — carried
## forward untouched so the next save does not erase it. See [method restore].
##
## Scoped to the game it came from: [method forget_carried] drops it when the player starts a
## new game, or this build would write one settlement's DLC data into another's save.
var _carried_modules: Dictionary = {}

static var _seq: int = 0


func _init(dir: String = "user://saves") -> void:
	saves_dir = dir.trim_suffix("/")


# --- writing ---------------------------------------------------------------------------

## Write a new slot named [param name]. Returns `{ok, slot_id, error}`.
func save_new(kernel: GameKernel, name: String) -> Dictionary:
	return save_slot(kernel, _new_slot_id(), name)


## Write (or overwrite) the slot [param slot_id]. Returns `{ok, slot_id, error}`.
func save_slot(kernel: GameKernel, slot_id: String, name: String) -> Dictionary:
	if kernel == null:
		return {"ok": false, "slot_id": slot_id, "error": "no_kernel"}
	if not _is_safe_slot_id(slot_id):
		return {"ok": false, "slot_id": slot_id, "error": "bad_slot_id"}
	if not _ensure_dir():
		return {"ok": false, "slot_id": slot_id, "error": "no_directory"}

	var payload := capture(kernel, slot_id, name)
	if not AtomicFile.write_text(_path_for(slot_id), JSON.stringify(payload, "\t")):
		return {"ok": false, "slot_id": slot_id, "error": "write_failed"}
	return {"ok": true, "slot_id": slot_id, "error": ""}


## The whole save, as a dictionary. Separate from the file handling so a test — or a later
## replay or cloud-sync path — can inspect exactly what would be written without touching disk.
func capture(kernel: GameKernel, slot_id: String = "", name: String = "") -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"slot": {
			"id": slot_id,
			"name": name,
			"saved_at": int(Time.get_unix_time_from_system()),
			# Denormalized for the load menu, so listing slots never needs the whole save.
			"total_days": kernel.clock.total_days if kernel.clock != null else 0,
		},
		"state": kernel.state.to_dict(),
		"globals": kernel.globals.to_dict(),
		"clock": kernel.clock.to_dict(),
		# Suspended workflows are part of the world, not a detail of it: a save without them
		# would silently drop whatever the player had been asked and not yet answered (B1).
		"workflow_instances": kernel.workflow_instances.to_dict(),
		"modules": _capture_modules(kernel),
	}


func _capture_modules(kernel: GameKernel) -> Dictionary:
	# Start from the data of modules that were in the loaded save but are not loaded now (see
	# `restore`), so saving with a DLC disabled preserves rather than erases what it owned.
	var out: Dictionary = _carried_modules.duplicate(true)
	for module: Module in kernel.modules.loaded_modules():
		out[module.module_id()] = {
			# Stamped even when a module saves nothing, because B3 migrates on this version and
			# "the module was present, at version X" is itself worth recording.
			"version": module.manifest.version if module.manifest != null else "0.0.0",
			"data": module.capture_save_data(kernel),
		}
	return out


# --- reading ---------------------------------------------------------------------------

## Read a slot and apply it to [param kernel]. Returns `{ok, error, data}`.
func load_slot(kernel: GameKernel, slot_id: String) -> Dictionary:
	var read := read_slot(slot_id)
	if not bool(read["ok"]):
		return read
	return restore(kernel, read["data"] as Dictionary)


## Read and validate a slot without applying it. Falls back to the `.bak` when the main file is
## missing or unreadable — the case a crash mid-save leaves behind.
func read_slot(slot_id: String) -> Dictionary:
	if not _is_safe_slot_id(slot_id):
		return {"ok": false, "error": "bad_slot_id", "data": {}}
	# Falls back to the `.bak` when the main file is unreadable — the case a crash mid-save
	# leaves behind.
	var parsed := AtomicFile.read_json(_path_for(slot_id))
	if not bool(parsed["ok"]):
		return {"ok": false, "error": String(parsed["error"]), "data": {}}
	var data: Dictionary = parsed["data"]
	# Refuse a save written by a newer build rather than guessing at fields we do not know.
	# Loading it anyway would quietly discard whatever that version added.
	if int(data.get("version", 0)) > SAVE_VERSION:
		return {"ok": false, "error": "save_from_newer_version", "data": {}}
	return {"ok": true, "error": "", "data": data}


## Apply an already-read save to the kernel. Returns `{ok, error, data, migrations}`.
##
## **Migrations run before anything is applied** (M4/B3). They are pure — data in, data out —
## so running them all up front means a load either happens completely or not at all; migrating
## as each module is restored would leave the world half-loaded when step three of five failed.
##
## Then order matters: the world first, then the workflows suspended inside it, so an instance
## that re-proves its `resume_require` on wake (§5.3) checks the state it actually belongs to.
func restore(kernel: GameKernel, data: Dictionary) -> Dictionary:
	if kernel == null:
		return {"ok": false, "error": "no_kernel", "data": {}, "migrations": {}}
	if int(data.get("version", 0)) > SAVE_VERSION:
		return {"ok": false, "error": "save_from_newer_version", "data": {}, "migrations": {}}

	var saved_modules: Dictionary = data.get("modules", {}) as Dictionary
	var migrated := _migrate_modules(kernel, saved_modules)
	if not bool(migrated["ok"]):
		return {"ok": false, "error": String(migrated["error"]), "data": {},
			"migrations": migrated["applied"]}

	# Every store that holds game state is *replaced*, never merged, and anything armed by the
	# previous game is dropped. Partial resets are how a load quietly inherits the last session:
	# an event fires that belongs to a game the player is no longer in, and nobody can explain
	# it. If you add a kernel service that holds game state, add it here — and
	# `test_load_isolation.gd` will fail until you have classified it either way.
	kernel.state.from_dict(data.get("state", {}) as Dictionary)
	kernel.globals.from_dict(data.get("globals", {}) as Dictionary)
	kernel.clock.from_dict(data.get("clock", {}) as Dictionary)
	kernel.workflow_instances.from_dict(data.get("workflow_instances", {}) as Dictionary)
	kernel.scheduler.reset_scheduled_by_play()

	var module_data: Dictionary = migrated["data"]
	for module: Module in kernel.modules.loaded_modules():
		# A module absent from the save gets an empty dictionary rather than being skipped: a
		# module added since the save still needs to hear about the load to set itself up.
		module.restore_save_data(kernel, module_data.get(module.module_id(), {}) as Dictionary)

	# Hold on to data belonging to modules that are not loaded right now, so the next save
	# writes it back untouched. Without this, disabling a DLC and saving would erase everything
	# that DLC owned — the player would lose it by turning something off, which is not a choice
	# anyone knowingly makes. Unmigrated on purpose: this build cannot know what those shapes
	# mean, so it carries the bytes and lets the owning module migrate them when it returns.
	_carried_modules = _orphan_modules(kernel, saved_modules)

	if kernel.events != null:
		kernel.events.emit("game_loaded", {"slot": data.get("slot", {})})
	return {"ok": true, "error": "", "data": data, "migrations": migrated["applied"]}


## Run every loaded module's declared chain. Returns `{ok, data, applied, error}` where `data`
## maps module id -> migrated save data, and `applied` maps module id -> the versions that ran.
func _migrate_modules(kernel: GameKernel, saved_modules: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var applied: Dictionary = {}
	for module: Module in kernel.modules.loaded_modules():
		var id := module.module_id()
		var entry: Dictionary = saved_modules.get(id, {}) as Dictionary
		var module_data: Dictionary = entry.get("data", {}) as Dictionary
		var current := module.manifest.version if module.manifest != null else "0.0.0"
		# No stamp means the save predates this module; there is nothing to migrate forward, and
		# guessing at "0.0.0" would replay the module's whole history over empty data.
		if not entry.has("version"):
			out[id] = module_data
			continue
		var result := SaveMigrator.migrate(module_data, String(entry["version"]), current,
			module.save_migrations(), kernel.log, id)
		if not bool(result["ok"]):
			if kernel.log != null:
				kernel.log.warn("SaveManager", "Cannot load save: module '%s' %s (save %s, build %s)"
					% [id, result["error"], entry["version"], current])
			return {"ok": false, "data": {}, "applied": applied, "error": String(result["error"])}
		out[id] = result["data"]
		if not (result["applied"] as Array).is_empty():
			applied[id] = result["applied"]
	return {"ok": true, "data": out, "applied": applied, "error": ""}


## Drop carried-over module data. Called when a new game starts: the data belongs to the
## settlement it was loaded from, and carrying it into an unrelated game would attribute one
## player's DLC content to another of their saves.
func forget_carried() -> void:
	_carried_modules.clear()


## Entries in the save belonging to modules this build has not loaded.
func _orphan_modules(kernel: GameKernel, saved_modules: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id: String in saved_modules:
		if not kernel.modules.is_loaded(id):
			out[id] = (saved_modules[id] as Dictionary).duplicate(true)
	return out


# --- listing and deleting --------------------------------------------------------------

## Every readable slot's metadata, newest first: `{id, name, saved_at, total_days, version}`.
## Unreadable files are skipped rather than failing the listing — one corrupt save must not
## make the load menu unusable.
func slots() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(saves_dir):
		return out
	var dir := DirAccess.open(saves_dir)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(EXTENSION):  # skips .bak and .tmp
			continue
		var slot_id := file.trim_suffix(EXTENSION)
		var read := read_slot(slot_id)
		if not bool(read["ok"]):
			continue
		var data: Dictionary = read["data"]
		var meta: Dictionary = (data.get("slot", {}) as Dictionary).duplicate(true)
		meta["id"] = slot_id  # the filename wins — it is what load_slot will be called with
		meta["version"] = int(data.get("version", 0))
		# JSON has no integer type, so every number parses back as a float (the standing A2
		# gotcha). Coerced here rather than at each call site, or a load menu shows "Day 11.0".
		meta["saved_at"] = int(meta.get("saved_at", 0))
		meta["total_days"] = int(meta.get("total_days", 0))
		out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


func has_slot(slot_id: String) -> bool:
	return _is_safe_slot_id(slot_id) and FileAccess.file_exists(_path_for(slot_id))


## Delete a slot and its backup. Deleting a slot that is not there succeeds — the caller's
## intent (that slot should not exist) is satisfied either way.
func delete_slot(slot_id: String) -> bool:
	if not _is_safe_slot_id(slot_id):
		return false
	AtomicFile.remove_all(_path_for(slot_id))
	return true


# --- disk plumbing ---------------------------------------------------------------------

func _path_for(slot_id: String) -> String:
	return "%s/%s%s" % [saves_dir, slot_id, EXTENSION]


func _new_slot_id() -> String:
	SaveManager._seq += 1
	return "slot_%d_%04d" % [int(Time.get_unix_time_from_system()), SaveManager._seq]


## Ids are generated, so this guards against a caller passing something else through — most
## importantly a path traversal (`../../secrets`) that would read or write outside the saves
## directory. Dots are refused outright, which also keeps `.bak`/`.tmp` unaddressable as slots.
func _is_safe_slot_id(slot_id: String) -> bool:
	if slot_id.is_empty() or slot_id.length() > 64:
		return false
	return slot_id.is_valid_filename() and not slot_id.contains(".")


func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(saves_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(saves_dir) == OK
