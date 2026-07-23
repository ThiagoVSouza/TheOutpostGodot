class_name PlanTicker
extends RefCounted

## Runs due background plans off the game clock (M5, D36). It is a runner, not part of the
## [Scheduler]: the scheduler dispatches param-less workflow definitions, but a plan tick has to
## know *which* plan it is about, so it needs the plan's id as context — the same division of
## labour as [WorkflowInstanceStore] and the runners that resume its instances. It holds no state
## of its own: plans live in GameState (saved by B2), so this is stateless infrastructure.
##
## Each day the clock advances, it snapshots the plans that are due and runs each one's tick
## workflow — an authored `ai classify -> run_command apply_plan_transition` — passing the plan's
## fields as workflow params. The model sees the situation and the band *word*, never the raw
## intensity (D33). The command owns every number (D4).

var _kernel: GameKernel

# A tick suspends at its `ai` step, but `clock.advance(n)` emits `day_passed` n times in a row.
# Without serialization the overlapping handlers all read the same pre-tick state and a plan due
# once ticks several times. So only one drain runs at a time; days that arrive while it is in
# flight collapse to the latest — a plan due at any day up to `today` is still due at `today`, and
# a ticked plan has already re-armed past it, so processing the newest day once is correct.
var _draining: bool = false
var _pending_day: int = -1


func _init(kernel: GameKernel) -> void:
	_kernel = kernel
	if _kernel.events != null:
		_kernel.events.subscribe("day_passed", _on_day_passed)


func _on_day_passed(payload: Dictionary) -> void:
	var today := int(payload.get("total_days", 0))
	if _draining:
		_pending_day = maxi(_pending_day, today)
		return
	_draining = true
	await tick_due(today)
	while _pending_day >= 0:
		var next_day := _pending_day
		_pending_day = -1
		await tick_due(next_day)
	_draining = false


## Run every plan whose wake has arrived. Awaitable so a test can drive it deterministically
## rather than pumping frames after a clock advance. Due plans are snapshotted up front (a plan
## spawned by one tick has a future wake and is not run in the same pass).
func tick_due(today: int) -> void:
	var plans: Dictionary = _kernel.state.get_value("plans", {})
	for plan_id: Variant in Plans.due(plans, today):
		await _tick_one(String(plan_id), today)


func _tick_one(plan_id: String, today: int) -> void:
	# Re-read: an earlier tick in this pass may have rewritten the plans dict.
	var plans: Dictionary = _kernel.state.get_value("plans", {})
	if not plans.has(plan_id):
		return
	var plan: Dictionary = plans[plan_id]
	if String(plan.get("status", "active")) != "active":
		return
	var workflow_id := String(plan.get("tick_workflow", ""))
	var def: Variant = _kernel.workflow_registry.get_definition(workflow_id)
	if not (def is Dictionary):
		_kernel.log.warn("PlanTicker", "plan '%s' has no tick workflow '%s'" % [plan_id, workflow_id])
		return

	var direction: Dictionary = plan.get("direction", {})
	var params := {
		"plan_id": plan_id,
		"situation": String(plan.get("situation", "")),
		"direction": String(direction.get("band", "calm")),  # the band word, never the raw number (D33)
		"latest": _latest_development(plan, today),
		"today": today,
	}
	var instance := WorkflowInstance.create(
		String((def as Dictionary).get("id", "plan_tick")),
		int((def as Dictionary).get("version", 1)),
		params,
		hash("%s:%d" % [plan_id, today]))
	await WorkflowExecutor.for_kernel(_kernel).run(def as Dictionary, instance)


## The development the tick shows the model: the most recent memory about this plan's subjects,
## retrieved by entity-tag + recency (D37). Falls back to a neutral line when nothing is on record
## yet — a plan can tick before anything about it has been remembered.
func _latest_development(plan: Dictionary, today: int) -> String:
	var recent: Array = _kernel.memories.retrieve(plan.get("subjects", []), 1, today)
	if recent.is_empty():
		return "nothing new has reached the outpost about this"
	return String((recent[0] as Dictionary).get("text", ""))
