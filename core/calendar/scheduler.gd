class_name Scheduler
extends RefCounted

## Schedules workflows against the game calendar and dispatches them as the [GameClock]
## advances. Subscribes to the clock's [EventBus] events and runs due workflow definitions
## on the A3 kernel — validated once when scheduled ([WorkflowValidator]), then run as a
## fresh [WorkflowInstance] through [WorkflowExecutor]. Emits "workflow_ran" after each
## dispatch: { "ok": bool, "message": String, "trigger": String }.
##
## Suspension note: a scheduled workflow is expected to run to completion (the month-end
## report does). If one suspends (a `wait_*`/`confirm`), it reports `ok: false` here and is
## not yet re-armed — game-time wake re-arming (§5.2) is future work, not part of this
## migration.

var _events: EventBus
var _kernel: GameKernel
var _validator: WorkflowValidator

var _monthly: Array = []      # Array[Dictionary] validated workflow defs run every month_ended
var _by_day: Dictionary = {}  # total_days: int -> Array[Dictionary]
var _seq: int = 0


func _init(events: EventBus, kernel: GameKernel) -> void:
	_events = events
	_kernel = kernel
	_validator = WorkflowValidator.new()
	if _events != null:
		_events.subscribe("month_ended", _on_month_ended)
		_events.subscribe("day_passed", _on_day_passed)


## Run this workflow definition at the end of every month. Rejected (with a log warning) if
## it does not validate, so an ill-formed definition never reaches a trigger.
func schedule_monthly(workflow_def: Dictionary) -> void:
	if _validate(workflow_def, "monthly"):
		_monthly.append(workflow_def)


## Run this workflow definition once, when the clock reaches [param on_total_days].
func schedule_on_day(on_total_days: int, workflow_def: Dictionary) -> void:
	if not _validate(workflow_def, "on_day"):
		return
	if not _by_day.has(on_total_days):
		_by_day[on_total_days] = []
	_by_day[on_total_days].append(workflow_def)


func pending_monthly() -> int:
	return _monthly.size()


func _validate(workflow_def: Dictionary, when: String) -> bool:
	var result := _validator.validate(workflow_def)
	if not result.success:
		if _kernel != null and _kernel.log != null:
			_kernel.log.warn("Scheduler", "Rejected %s workflow: %s" % [when, result.message])
		return false
	return true


func _on_month_ended(_payload: Dictionary) -> void:
	for wf in _monthly:
		_run(wf, "month_ended")


func _on_day_passed(payload: Dictionary) -> void:
	var d := int(payload.get("total_days", 0))
	if _by_day.has(d):
		for wf in _by_day[d]:
			_run(wf, "day_passed")
		_by_day.erase(d)


func _run(workflow_def: Dictionary, trigger: String) -> void:
	_seq += 1
	var instance := WorkflowInstance.create(
		String(workflow_def.get("id", "scheduled")),
		int(workflow_def.get("version", 1)),
		{},
		hash("%d:%d" % [Time.get_ticks_usec(), _seq]))
	var result := WorkflowExecutor.for_kernel(_kernel).run(workflow_def, instance)
	if _events != null:
		_events.emit("workflow_ran", {
			"ok": result.succeeded(),
			"message": result.fail_msg,
			"trigger": trigger,
		})
