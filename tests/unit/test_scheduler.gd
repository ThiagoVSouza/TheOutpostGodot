extends GutTest

## Scheduler dispatches the month-end workflow when the clock crosses a month boundary.

func test_monthly_workflow_runs_at_month_end() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # base_game schedules a monthly workflow on boot

	assert_gt(kernel.scheduler.pending_monthly(), 0, "base_game should schedule a monthly workflow")

	var ran: Array = []
	kernel.events.subscribe("workflow_ran", func(p: Dictionary) -> void: ran.append(p))

	kernel.clock.advance(GameClock.DAYS_PER_MONTH)

	assert_gt(ran.size(), 0, "monthly workflow runs at month end")
	assert_true(ran[0]["ok"], "workflow executes successfully")
	# The month-end workflow grants 1 gold.
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("gold", 0)), 1)


func test_scheduled_on_day_runs_once() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	var ran: Array = []
	kernel.events.subscribe("workflow_ran", func(_p: Dictionary) -> void: ran.append(1))

	kernel.scheduler.schedule_on_day(3, {
		"op": "workflow", "id": "day_three", "version": 1, "params": {},
		"steps": [{"op": "emit", "msg": "test.day_three"}]
	})
	kernel.clock.advance(5)
	assert_eq(ran.size(), 1, "day-scheduled workflow runs exactly once")
