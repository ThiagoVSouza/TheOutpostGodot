extends GutTest

## Phase 4's clock driver is deliberately deterministic here: tests feed elapsed seconds directly
## rather than relying on engine frames, while production reaches the same method through _process.

var _gated := false
var _clock: GameClock
var _driver: TimeDriver


func before_each() -> void:
	_clock = GameClock.new()
	_driver = TimeDriver.new(_clock, func() -> bool: return _gated)
	add_child_autofree(_driver)
	_driver.set_active(true)


func test_one_x_advances_one_day_per_configured_interval() -> void:
	_driver.set_speed(TimeDriver.Speed.SPEED_1)
	_driver.advance_elapsed(TimeDriver.SECONDS_PER_DAY - 0.01)
	assert_eq(_clock.total_days, 0)
	_driver.advance_elapsed(0.01)
	assert_eq(_clock.total_days, 1)


func test_faster_speeds_scale_the_same_clock() -> void:
	_driver.set_speed(TimeDriver.Speed.SPEED_3)
	_driver.advance_elapsed(TimeDriver.SECONDS_PER_DAY / 4.0)
	assert_eq(_clock.total_days, 1, "3x uses the 4x multiplier without changing GameClock")


func test_pause_restores_the_previous_speed() -> void:
	_driver.set_speed(TimeDriver.Speed.SPEED_2)
	_driver.toggle_pause()
	assert_true(_driver.is_paused())
	_driver.advance_elapsed(TimeDriver.SECONDS_PER_DAY * 5.0)
	assert_eq(_clock.total_days, 0, "paused time does not accumulate")
	_driver.toggle_pause()
	assert_eq(_driver.speed(), TimeDriver.Speed.SPEED_2)


func test_the_gate_stops_time_without_a_backlog() -> void:
	_driver.set_speed(TimeDriver.Speed.SPEED_1)
	_gated = true
	_driver.advance_elapsed(TimeDriver.SECONDS_PER_DAY * 3.0)
	assert_eq(_clock.total_days, 0)
	_gated = false
	_driver.advance_elapsed(0.0)
	assert_eq(_clock.total_days, 0, "event time is discarded, never caught up")
	_driver.advance_elapsed(TimeDriver.SECONDS_PER_DAY)
	assert_eq(_clock.total_days, 1)


func test_loading_always_starts_paused() -> void:
	_driver.set_speed(TimeDriver.Speed.SPEED_3)
	_driver.loaded_game()
	assert_true(_driver.is_paused())
	_driver.toggle_pause()
	assert_eq(_driver.speed(), TimeDriver.Speed.SPEED_1, "load does not retain an old speed")


func test_kernel_world_gate_reads_pending_confirmations() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	assert_false(kernel.is_world_time_gated())
	var pending := WorkflowInstance.create("test_confirm", 1, {}, 0)
	pending.status = WorkflowInstance.Status.SUSPENDED
	pending.wake = {"type": "confirmation"}
	kernel.workflow_instances.remember(pending)
	assert_true(kernel.is_world_time_gated(), "the driver can stop for a confirm without knowing UI state")
