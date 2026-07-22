class_name WorkflowInstanceStore
extends RefCounted

## Owns every suspended [WorkflowInstance] (M4/B1). D25 made instances resumable and A3 proved
## a suspended one survives a JSON round-trip — but until now nothing *held* one: the executor
## returned it and [AiOrchestrator] dropped it on the floor, so the capability had no owner and
## nothing to persist. This is that owner.
##
## Deliberately dumb: it remembers, finds and forgets instances, and serializes them. It never
## runs anything — resuming is the orchestrator's job (a player confirmation) or the scheduler's
## (a game-time wake), because both need the executor and a trace, and a store that could run
## workflows would be a second, quieter orchestrator.
##
## [method to_dict] / [method from_dict] are the save contract, mirroring [GameState] and
## [GlobalStore]. An instance's own snapshot is already the contract (§5.2); this only adds the
## collection around it.

## Insertion order is preserved (Godot dictionaries are ordered), so the oldest pending
## question is the first one a UI should ask.
var _suspended: Dictionary = {}  # instance_id -> WorkflowInstance


## Take ownership of a suspended instance. Ignores anything not actually suspended — a
## completed or failed instance has nothing to resume, and storing one would leak a save entry
## that can never be woken.
func remember(instance: WorkflowInstance) -> void:
	if instance == null or instance.status != WorkflowInstance.Status.SUSPENDED:
		return
	_suspended[instance.instance_id] = instance


## Drop an instance once it has been resumed (or abandoned). Safe to call twice.
func forget(instance_id: String) -> void:
	_suspended.erase(instance_id)


func has(instance_id: String) -> bool:
	return _suspended.has(instance_id)


func get_instance(instance_id: String) -> WorkflowInstance:
	return _suspended.get(instance_id, null)


func count() -> int:
	return _suspended.size()


## Every suspended instance, oldest first.
func pending() -> Array:
	return _suspended.values()


## Suspended instances waiting on a player answer — what a UI re-presents after a load.
func pending_confirmations() -> Array:
	return _with_wake_type("confirmation")


## Suspended instances waiting for the calendar to reach a day, at or before [param total_days].
## The scheduler's game-time wake reads this; re-arming itself is still future work (A4's note).
func due_at_day(total_days: int) -> Array:
	var out: Array = []
	for instance: WorkflowInstance in _suspended.values():
		if String(instance.wake.get("type", "")) == "game_time" \
				and int(instance.wake.get("at_day", 0)) <= total_days:
			out.append(instance)
	return out


func _with_wake_type(wake_type: String) -> Array:
	var out: Array = []
	for instance: WorkflowInstance in _suspended.values():
		if String(instance.wake.get("type", "")) == wake_type:
			out.append(instance)
	return out


func to_dict() -> Dictionary:
	var out: Array = []
	for instance: WorkflowInstance in _suspended.values():
		out.append(instance.to_dict())
	return {"suspended": out}


## Replace the store wholesale from a save. Entries that do not deserialize into a suspended
## instance are skipped rather than trusted: a save is an input like any other, and a corrupt
## entry should cost one pending action, not the whole load.
func from_dict(data: Dictionary) -> void:
	_suspended.clear()
	for entry: Variant in data.get("suspended", []):
		if not (entry is Dictionary):
			continue
		var instance := WorkflowInstance.from_dict(entry as Dictionary)
		if instance.instance_id.is_empty() or instance.status != WorkflowInstance.Status.SUSPENDED:
			continue
		_suspended[instance.instance_id] = instance
