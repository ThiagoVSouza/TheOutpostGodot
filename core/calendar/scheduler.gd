class_name Scheduler
extends RefCounted

## Schedules workflows/callbacks against the game calendar. STUB SEAM — milestone 1.
##
## Will let systems and the AI schedule work for a future date or recurring cadence
## (e.g. an end-of-month workflow) and dispatch them as the [GameClock] advances.

## Schedule work for a given game day. Real implementation stores and dispatches these.
func schedule_on_day(_day: int, _workflow_id: String, _payload: Dictionary = {}) -> void:
	# TODO(milestone-1): persist scheduled entries and fire them from GameClock events.
	pass
