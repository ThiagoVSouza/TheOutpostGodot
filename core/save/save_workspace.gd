class_name SaveWorkspace
extends RefCounted

## The game currently being played, on disk as **separate parts** under [member dir] (M4/B4a).
##
## This is the live source of truth between launches. A slot file ([SaveManager]) is a
## *snapshot* of it — something the player made deliberately, or the game made on a long
## cadence — and the two answer different questions:
##
##   workspace : "what is happening right now, survive a crash"   — written often, cheaply
##   slot file : "a settlement I can keep, name, and come back to" — written rarely, wholly
##
## **Why parts rather than one file.** Rewriting the whole world on every turn costs
## O(total state) per turn. Today that is a couple of KB and would not matter; at M5 (memory
## and retrieval) a settlement carrying thousands of memories re-serialized every turn is real
## cost, and on mobile flash it is wear as well. Splitting now is cheap; splitting after
## memories exist is not — the same argument that made migrations worth doing early.
##
## **Unchanged parts are not written at all.** [method checkpoint_part] compares the serialized
## part against what it last wrote and skips identical content. That is deliberately content
## comparison rather than dirty flags: a dirty flag someone forgets to set is a lost turn, and
## the bug is invisible until a player loses progress. The parts are small enough that
## comparing them is cheaper than being wrong.
##
## Note this is *not* where large append-heavy data should go when it arrives. Memories want an
## append-only log (JSONL, as the trace writer already does), not a whole-part rewrite.

const WORLD := "world"
const GLOBALS := "globals"
const CLOCK := "clock"
const INSTANCES := "instances"
const META := "meta"

## The parts the kernel itself owns. Modules add their own under `module_<id>`.
const CORE_PARTS: Array[String] = [WORLD, GLOBALS, CLOCK, INSTANCES, META]

var dir: String

## part name -> the exact text last written, so an unchanged part is never rewritten.
var _written: Dictionary = {}


func _init(workspace_dir: String = "user://current") -> void:
	dir = workspace_dir.trim_suffix("/")


func exists() -> bool:
	return FileAccess.file_exists(_path(META))


func path_for(part: String) -> String:
	return _path(part)


# --- writing -------------------------------------------------------------------------------

## Write one part, but only if its content actually changed. Returns true if it wrote.
func checkpoint_part(part: String, data: Dictionary) -> bool:
	var text := JSON.stringify(data)
	if _written.get(part, null) == text:
		return false
	if not _ensure_dir():
		return false
	if not AtomicFile.write_text(_path(part), text):
		return false
	_written[part] = text
	return true


# --- reading -------------------------------------------------------------------------------

## Read one part. Returns an empty dictionary when the part is absent or unreadable — a missing
## part means "this game never had one", which is the normal case for a module that saves
## nothing, so it is not an error the caller has to branch on.
func read_part(part: String) -> Dictionary:
	var read := AtomicFile.read_json(_path(part))
	if not bool(read["ok"]):
		return {}
	var data: Dictionary = read["data"]
	# A part we just read is by definition current, so record it as written. Without this the
	# first checkpoint after a resume rewrites every part identically — doubling the I/O of
	# every launch, which is exactly the write amplification this split exists to avoid.
	_written[part] = JSON.stringify(data)
	return data


func has_part(part: String) -> bool:
	return FileAccess.file_exists(_path(part))


## Every `module_<id>` part currently on disk, as `id -> data`.
func module_parts() -> Dictionary:
	var out: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for file in d.get_files():
		if not file.ends_with(".json") or not file.begins_with("module_"):
			continue  # also skips .bak and .tmp
		var id := file.trim_suffix(".json").trim_prefix("module_")
		out[id] = read_part(module_part_name(id))
	return out


static func module_part_name(module_id: String) -> String:
	return "module_%s" % module_id


# --- lifecycle -----------------------------------------------------------------------------

## Delete the workspace. Used when starting a new game or loading a slot over the current one —
## both of which replace the live game wholesale, so a leftover part from the previous one would
## be read back as if it belonged.
func clear() -> void:
	_written.clear()
	if not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute("%s/%s" % [dir, file])


func _path(part: String) -> String:
	return "%s/%s.json" % [dir, part]


func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK
