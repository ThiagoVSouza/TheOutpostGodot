class_name GlobalStore
extends RefCounted

## The DSL's global-variable store (D31): a writable, workflow-shared key-value scope that
## sits BESIDE authoritative game state, never over it. Non-authoritative by discipline — a
## global may hold coordination data (counters, flags, last-classified intent) but never the
## source of an authoritative game number; balance stays behind the command choke point (D4).
##
## Reads are pure (`get_global`); writes go through `set_global`, which the executor records
## in the trace and gates by capability (D30). Persisted with the save: [method to_dict] /
## [method from_dict] are the contract, mirroring [GameState].

var _values: Dictionary = {}


func has(global_name: String) -> bool:
	return _values.has(global_name)


func get_value(global_name: String, default: Variant = null) -> Variant:
	return _values.get(global_name, default)


func set_value(global_name: String, value: Variant) -> void:
	_values[global_name] = value


func to_dict() -> Dictionary:
	return _values.duplicate(true)


func from_dict(data: Dictionary) -> void:
	_values = data.duplicate(true)
