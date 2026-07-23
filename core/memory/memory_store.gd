class_name MemoryStore
extends RefCounted

## The game master's memory (M5, D37): an append-only log of things that happened, in English
## (D35), each tagged with the entities it concerns. Retrieval is entity-tag + recency — given a
## plan's (or a turn's) subjects, return the most recent memories that share one, newest first.
## One hop, no model call, deterministic; the briefing's multi-step AI drill-down is deferred
## until a measurement says one hop is not enough (D37).
##
## **Storage is an append-only JSONL file** (D34, which named this explicitly: memories want an
## append log like the trace writer, not a whole-part rewrite in every snapshot). The file lives
## in the workspace dir, so `SaveWorkspace.clear()` on a new game or a load wipes it for free —
## the "replace, never merge" rule (D34) reaches memories without extra wiring. It survives a
## normal close/reopen because the workspace file persists.
##
## A memory is a plain Dictionary:
##   { id: String, day: int, text: "<english>", subjects: [entity ids], kind: String }

var _memories: Array = []      # Array[Dictionary], in insertion (chronological) order
var _seq: int = 0
var _path: String = ""
var _persist: bool = false


## [param path] is the JSONL file; when [param persist] is true it is loaded on construction and
## appended to on every [method record]. Tests default to in-memory only (persist off) so a run
## never writes into a real dir — the same guard the trace writer and session use.
func _init(path: String = "", persist: bool = false) -> void:
	_path = path
	_persist = persist and not path.is_empty()
	if _persist:
		_load()


## Append a memory and return it. Assigns an id; fills [param day]/[param kind] as given.
func record(text: String, subjects: Array = [], day: int = 0, kind: String = "event") -> Dictionary:
	_seq += 1
	var memory := {
		"id": "m%d" % _seq,
		"day": day,
		"text": text,
		"subjects": subjects.duplicate(),
		"kind": kind,
	}
	_memories.append(memory)
	if _persist:
		_append_line(memory)
	return memory


## The [param k] most recent memories that share at least one subject with [param subjects] and
## are not from the future ([param before_day] inclusive — a tick should not see events dated
## after the day it runs). Newest first. Empty when nothing matches.
func retrieve(subjects: Array, k: int = 3, before_day: int = 0x7FFFFFFF) -> Array:
	var matches: Array = []
	for memory: Dictionary in _memories:
		if int(memory.get("day", 0)) > before_day:
			continue
		if _shares_subject(memory.get("subjects", []), subjects):
			matches.append(memory)
	# Chronological order in, so a stable "newest first" is the reverse of the tail.
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("day", 0)) > int(b.get("day", 0)))
	return matches.slice(0, k)


func count() -> int:
	return _memories.size()


func all() -> Array:
	return _memories.duplicate()


## Drop everything, in memory and on disk. Called when a new game starts or a slot is loaded over
## the current one (D34: loading replaces, never merges). `SaveWorkspace.clear()` also removes the
## file, so this stays correct whether or not the dir was already wiped.
func clear() -> void:
	_memories.clear()
	_seq = 0
	if _persist and FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _shares_subject(a: Variant, b: Array) -> bool:
	if not (a is Array):
		return false
	for subject: Variant in (a as Array):
		if b.has(subject):
			return true
	return false


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			_memories.append(parsed)
			_seq = maxi(_seq, _seq_of(parsed as Dictionary))
	f.close()


func _seq_of(memory: Dictionary) -> int:
	var id := String(memory.get("id", ""))
	return int(id.trim_prefix("m")) if id.begins_with("m") else 0


func _append_line(memory: Dictionary) -> void:
	if not _ensure_dir():
		return
	# Open for append: READ_WRITE preserves existing content (WRITE would truncate it).
	var f := FileAccess.open(_path, FileAccess.READ_WRITE) if FileAccess.file_exists(_path) \
		else FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(memory))
	f.close()


func _ensure_dir() -> bool:
	var dir := _path.get_base_dir()
	if dir.is_empty() or DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK
