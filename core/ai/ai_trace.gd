class_name AiTrace
extends RefCounted

## Ordered record of an orchestration run: each stage, tool call, validation result and
## command. The brief requires the game to display an internal AI trace during development
## showing each orchestration stage; the chat screen renders this, and tests assert on it.

var _entries: Array = []  # Array[Dictionary] of { "stage": String, "data": Dictionary }


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


## Human-readable multiline dump for the dev trace panel / logs.
func to_text() -> String:
	var lines: Array = []
	for e in _entries:
		lines.append("• %s  %s" % [e["stage"], JSON.stringify(e["data"])])
	return "\n".join(lines)
