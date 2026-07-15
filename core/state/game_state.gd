class_name GameState
extends RefCounted

## Central container for mutable game state.
##
## The brief mandates that state is only ever changed through validated commands
## (see [CommandBus]). This container therefore exposes generic get/set access that
## the command layer uses; gameplay code should route mutations through commands,
## not call [method set_value] directly. Typed sub-stores can replace the backing
## dictionary later without changing the command contract.

var _values: Dictionary = {}


func has_value(key: String) -> bool:
	return _values.has(key)


func get_value(key: String, default: Variant = null) -> Variant:
	return _values.get(key, default)


## Intended to be called by the command layer after validation, not by gameplay code.
func set_value(key: String, value: Variant) -> void:
	_values[key] = value


## Snapshot of all state, e.g. for save serialization (deep-duplicated).
func to_dict() -> Dictionary:
	return _values.duplicate(true)


## Replace state wholesale, e.g. when loading a save.
func from_dict(data: Dictionary) -> void:
	_values = data.duplicate(true)
