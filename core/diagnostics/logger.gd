class_name GameLog
extends RefCounted

## Minimal diagnostics sink for the kernel and modules.
## (Named GameLog because Godot 4 has a built-in `Logger` class.)
##
## Kept deliberately small: it just tags messages with a level and source so the
## AI trace / benchmark tooling described in the brief can hook a richer sink here
## later without changing call sites.

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.DEBUG


func _init(minimum: Level = Level.DEBUG) -> void:
	min_level = minimum


func debug(source: String, message: String) -> void:
	_emit(Level.DEBUG, source, message)


func info(source: String, message: String) -> void:
	_emit(Level.INFO, source, message)


func warn(source: String, message: String) -> void:
	_emit(Level.WARN, source, message)


func error(source: String, message: String) -> void:
	_emit(Level.ERROR, source, message)


func _emit(level: Level, source: String, message: String) -> void:
	if level < min_level:
		return
	var line := "[%s] %s: %s" % [_level_name(level), source, message]
	if level == Level.WARN:
		push_warning(line)
	elif level == Level.ERROR:
		push_error(line)
	print(line)


func _level_name(level: Level) -> String:
	match level:
		Level.DEBUG: return "DEBUG"
		Level.INFO: return "INFO"
		Level.WARN: return "WARN"
		Level.ERROR: return "ERROR"
	return "?"
