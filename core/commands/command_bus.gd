class_name CommandBus
extends RefCounted

## Validates and applies [Command]s against [GameState].
##
## This is the single choke point for state mutation. It validates first and only
## applies on success, emitting events so other systems (UI, AI trace, save) can react.
## Emitted events (via [EventBus], if provided):
##   "command_applied"  -> { "command": String, "result": CommandResult }
##   "command_rejected" -> { "command": String, "result": CommandResult }

var _state: GameState
var _events: EventBus
var _log: GameLog


func _init(state: GameState, events: EventBus = null, log: GameLog = null) -> void:
	_state = state
	_events = events
	_log = log


## Validate then apply. Returns the apply result, or the validation failure if invalid.
func execute(command: Command) -> CommandResult:
	var name := command.command_name()
	var validation := command.validate(_state)
	if not validation.success:
		if _log != null:
			_log.warn("CommandBus", "Rejected %s: %s" % [name, validation.message])
		if _events != null:
			_events.emit("command_rejected", {"command": name, "result": validation})
		return validation

	var result := command.apply(_state)
	if _log != null:
		if result.success:
			_log.debug("CommandBus", "Applied %s" % name)
		else:
			_log.error("CommandBus", "Apply failed for %s: %s" % [name, result.message])
	if _events != null:
		var event_name := "command_applied" if result.success else "command_rejected"
		_events.emit(event_name, {"command": name, "result": result})
	return result
