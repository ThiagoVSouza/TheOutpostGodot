class_name GameClock
extends RefCounted

## In-game calendar. STUB SEAM — filled in milestone 1.
##
## Will track the game date and advance it (day/month/turn), emitting calendar events
## (e.g. "month_ended") that the [Scheduler] and workflows hook into. For now it only
## holds a day counter so the seam and its type exist.

var day: int = 0


## Advance the calendar by [param days]. Real implementation will emit date events.
func advance(days: int = 1) -> void:
	# TODO(milestone-1): emit "day_passed"/"month_ended" via EventBus and drive Scheduler.
	day += days
