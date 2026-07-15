class_name Scheduler
extends RefCounted

## Schedules workflows against the game calendar and dispatches them as the [GameClock]
## advances. Subscribes to the clock's [EventBus] events and runs due workflow
## definitions through the [WorkflowEngine]. Emits "workflow_ran" after each dispatch:
##   { "ok": bool, "message": String, "trigger": String }

var _events: EventBus
var _workflows: WorkflowEngine
var _kernel: GameKernel

var _monthly: Array = []      # Array[Dictionary] workflow defs run every month_ended
var _by_day: Dictionary = {}  # total_days: int -> Array[Dictionary]


func _init(events: EventBus, workflows: WorkflowEngine, kernel: GameKernel) -> void:
	_events = events
	_workflows = workflows
	_kernel = kernel
	if _events != null:
		_events.subscribe("month_ended", _on_month_ended)
		_events.subscribe("day_passed", _on_day_passed)


## Run this workflow definition at the end of every month.
func schedule_monthly(workflow_def: Dictionary) -> void:
	_monthly.append(workflow_def)


## Run this workflow definition once, when the clock reaches [param on_total_days].
func schedule_on_day(on_total_days: int, workflow_def: Dictionary) -> void:
	if not _by_day.has(on_total_days):
		_by_day[on_total_days] = []
	_by_day[on_total_days].append(workflow_def)


func pending_monthly() -> int:
	return _monthly.size()


func _on_month_ended(payload: Dictionary) -> void:
	for wf in _monthly:
		_run(wf, "month_ended")


func _on_day_passed(payload: Dictionary) -> void:
	var d := int(payload.get("total_days", 0))
	if _by_day.has(d):
		for wf in _by_day[d]:
			_run(wf, "day_passed")
		_by_day.erase(d)


func _run(workflow_def: Dictionary, trigger: String) -> void:
	var res := _workflows.execute(workflow_def, _kernel)
	if _events != null:
		_events.emit("workflow_ran", {"ok": res.success, "message": res.message, "trigger": trigger})
