class_name AiTrace
extends RefCounted

## Ordered record of an orchestration run: each stage, tool call, validation result and
## command. The brief requires the game to display an internal AI trace during development
## showing each orchestration stage; the chat screen renders this, and tests assert on it.
##
## [member id] names this orchestration for [AiTraceWriter] (D21): one JSONL file plus one
## Markdown export per orchestration, filed as `<id>.jsonl` / `<id>.md`.

static var _next_seq: int = 0

## Stable, sortable, unique-per-process. Not a security token — just a filename.
var id: String = ""

var _entries: Array = []  # Array[Dictionary] of { "stage": String, "data": Dictionary }


func _init() -> void:
	AiTrace._next_seq += 1
	id = "orch_%d_%04d" % [int(Time.get_unix_time_from_system()), AiTrace._next_seq]


## Append a stage entry. [param data] is JSON-serializable detail for that stage.
func add(stage: String, data: Dictionary = {}) -> void:
	_entries.append({"stage": stage, "data": data.duplicate(true)})


func entries() -> Array:
	return _entries


func stages() -> Array:
	var out: Array = []
	for e in _entries:
		out.append(e["stage"])
	return out


func has_stage(stage: String) -> bool:
	return stages().has(stage)


## Every entry recorded for one stage, in order, as their data dictionaries. `has_stage` answers
## "did this happen"; this answers "with what" — which is the question a D4 audit actually asks.
func entries_for(stage: String) -> Array:
	var out: Array = []
	for e in _entries:
		if e["stage"] == stage:
			out.append(e["data"])
	return out


## Human-readable multiline dump for the dev trace panel / logs.
func to_text() -> String:
	var lines: Array = []
	for e in _entries:
		lines.append("• %s  %s" % [e["stage"], JSON.stringify(e["data"])])
	return "\n".join(lines)


## Human-readable Markdown export (D21 §19.4 / A1): readable without external tooling —
## one heading per stage, its data as a fenced JSON block, in order.
func to_markdown() -> String:
	var lines: Array = []
	lines.append("# Orchestration trace `%s`" % id)
	lines.append("")
	lines.append("%d stage(s)." % _entries.size())
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		lines.append("")
		lines.append("## %d. %s" % [i + 1, e["stage"]])
		lines.append("")
		lines.append("```json")
		lines.append(JSON.stringify(e["data"], "  "))
		lines.append("```")
	return "\n".join(lines) + "\n"
