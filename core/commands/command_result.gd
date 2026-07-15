class_name CommandResult
extends RefCounted

## Outcome of validating and/or applying a [Command].
##
## Commands never throw; they return a result so the AI orchestrator, UI and tests
## can inspect success/failure uniformly and so failures are reproducible in traces.

var success: bool
var message: String
var data: Dictionary


func _init(is_success: bool, msg: String = "", result_data: Dictionary = {}) -> void:
	success = is_success
	message = msg
	data = result_data


static func ok(msg: String = "", result_data: Dictionary = {}) -> CommandResult:
	return CommandResult.new(true, msg, result_data)


static func fail(msg: String, result_data: Dictionary = {}) -> CommandResult:
	return CommandResult.new(false, msg, result_data)
