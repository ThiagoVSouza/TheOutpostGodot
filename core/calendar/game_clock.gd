class_name GameClock
extends RefCounted

## In-game calendar. Tracks elapsed days and emits calendar events that the [Scheduler]
## and workflows hook into. Days are advanced explicitly (turn-/action-driven), not by
## real time. Emits (via the injected [EventBus]):
##   "day_passed"   -> { "total_days": int }
##   "month_ended"  -> { "month": int, "total_days": int }

const DAYS_PER_MONTH: int = 30

var total_days: int = 0

var _events: EventBus


func _init(events: EventBus = null) -> void:
	_events = events


## Advance the calendar day by day so per-day and month-boundary events all fire.
func advance(days: int = 1) -> void:
	for _i in maxi(days, 0):
		total_days += 1
		_emit("day_passed", {"total_days": total_days})
		if total_days % DAYS_PER_MONTH == 0:
			_emit("month_ended", {"month": months_elapsed(), "total_days": total_days})


## Number of whole months elapsed.
func months_elapsed() -> int:
	return total_days / DAYS_PER_MONTH


## 1-based day within the current month (0 before any day has passed).
func day_of_month() -> int:
	if total_days == 0:
		return 0
	return ((total_days - 1) % DAYS_PER_MONTH) + 1


## Save contract, mirroring [GameState] and [GlobalStore]. Restoring sets the day directly and
## fires **no** calendar events: loading a save is not time passing, and replaying a year of
## `day_passed` on load would re-run every scheduled workflow the save already accounted for.
func to_dict() -> Dictionary:
	return {"total_days": total_days}


func from_dict(data: Dictionary) -> void:
	total_days = maxi(int(data.get("total_days", 0)), 0)


func _emit(event_name: String, payload: Dictionary) -> void:
	if _events != null:
		_events.emit(event_name, payload)
