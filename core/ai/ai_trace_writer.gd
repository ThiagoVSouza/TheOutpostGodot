class_name AiTraceWriter
extends RefCounted

## The sink [AiTrace] was missing (A1, D21): one JSONL file per orchestration — one stage
## entry per line — plus a human-readable Markdown export, under [member traces_dir].
##
## D21's whole rationale: the purpose is manual verification, not query performance. JSONL
## keeps that cheap; SQLite is deferred to M5, if ever. **No retention policy** — traces
## accumulate under [member traces_dir] with no cleanup; that is M4's problem, alongside
## save/load.
##
## On by default in dev builds (construct with the one-arg form, or set [member enabled]
## directly). Tests that don't want disk writes point [member traces_dir] at a scratch
## folder (see [ModuleRegistry]'s `root` override for the same pattern) or set
## [member enabled] to false; [method write] is then a no-op.

var traces_dir: String
var enabled: bool


func _init(dir: String = "user://traces", enabled_by_default: bool = OS.is_debug_build()) -> void:
	traces_dir = dir.trim_suffix("/")
	enabled = enabled_by_default


## Write both the JSONL trace and its Markdown export for one orchestration. No-op when
## disabled, when [param trace] is null, or if the directory cannot be created. Returns
## `{"jsonl": <path>, "markdown": <path>}` on success, `{}` otherwise.
func write(trace: AiTrace) -> Dictionary:
	if not enabled or trace == null:
		return {}
	if not _ensure_dir():
		return {}
	var jsonl_path := "%s/%s.jsonl" % [traces_dir, trace.id]
	var md_path := "%s/%s.md" % [traces_dir, trace.id]
	if not _write_lines(jsonl_path, trace):
		return {}
	if not _write_text(md_path, trace.to_markdown()):
		return {}
	return {"jsonl": jsonl_path, "markdown": md_path}


func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(traces_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(traces_dir) == OK


## One JSON object per line — each an `{"stage": String, "data": Dictionary}` entry, in
## the order [AiTrace] recorded them.
func _write_lines(path: String, trace: AiTrace) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	for e in trace.entries():
		f.store_line(JSON.stringify(e))
	f.close()
	return true


func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
