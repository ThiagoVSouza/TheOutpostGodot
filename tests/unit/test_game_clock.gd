extends GutTest

## GameClock emits per-day and month-boundary events as it advances.

func test_advance_emits_day_and_month_events() -> void:
	var events := EventBus.new()
	var days: Array = []
	var months: Array = []
	events.subscribe("day_passed", func(p: Dictionary) -> void: days.append(p["total_days"]))
	events.subscribe("month_ended", func(p: Dictionary) -> void: months.append(p["total_days"]))

	var clock := GameClock.new(events)
	clock.advance(GameClock.DAYS_PER_MONTH)

	assert_eq(days.size(), GameClock.DAYS_PER_MONTH, "one day_passed per day")
	assert_eq(months.size(), 1, "one month_ended at the boundary")
	assert_eq(int(months[0]), GameClock.DAYS_PER_MONTH)
	assert_eq(clock.months_elapsed(), 1)


func test_no_month_event_before_boundary() -> void:
	var events := EventBus.new()
	var months: Array = []
	events.subscribe("month_ended", func(_p: Dictionary) -> void: months.append(1))
	var clock := GameClock.new(events)
	clock.advance(GameClock.DAYS_PER_MONTH - 1)
	assert_eq(months.size(), 0, "no month_ended before the last day")
	assert_eq(clock.day_of_month(), GameClock.DAYS_PER_MONTH - 1)
