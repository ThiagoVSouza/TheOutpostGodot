class_name TimeDriver
extends Node

## Turns real elapsed time into authoritative one-day advances. It owns neither calendar state nor
## the reason time may be blocked: [GameClock] remains the calendar authority and the injected
## gate belongs to the kernel, so an event/UI never becomes a dependency of world simulation.

signal speed_changed(speed: int)

enum Speed { PAUSED, SPEED_1, SPEED_2, SPEED_3 }

## Initial pacing for Phase 4: a day takes five real seconds at 1x, then 2.5 and 1.25 at 2x/3x.
const SECONDS_PER_DAY := 5.0
const MULTIPLIERS := {Speed.PAUSED: 0.0, Speed.SPEED_1: 1.0, Speed.SPEED_2: 2.0, Speed.SPEED_3: 4.0}

var _clock: GameClock
var _is_gated: Callable
var _enabled: bool
var _active: bool = false
var _speed: int = Speed.PAUSED
var _previous_speed: int = Speed.SPEED_1
var _elapsed: float = 0.0


func _init(clock: GameClock, is_gated: Callable, enabled: bool = true) -> void:
	_clock = clock
	_is_gated = is_gated
	_enabled = enabled


func _process(delta: float) -> void:
	advance_elapsed(delta)


func advance_elapsed(delta: float) -> void:
	if not _enabled or not _active or _speed == Speed.PAUSED:
		return
	# A gate means time is stopped, not merely delayed. Discard elapsed wall time so resolving a
	# question never causes the world to fast-forward by however long the player spent reading it.
	if _is_gated.call():
		_elapsed = 0.0
		return
	_elapsed += maxf(delta, 0.0) * float(MULTIPLIERS[_speed])
	while _elapsed >= SECONDS_PER_DAY:
		if _is_gated.call():
			_elapsed = 0.0
			return
		_elapsed -= SECONDS_PER_DAY
		_clock.advance(1)


func set_active(active: bool) -> void:
	_active = active


func is_active() -> bool:
	return _active


func speed() -> int:
	return _speed


func is_paused() -> bool:
	return _speed == Speed.PAUSED


func set_speed(speed: int) -> void:
	var next := clampi(speed, Speed.PAUSED, Speed.SPEED_3)
	if next == _speed:
		return
	_speed = next
	if next != Speed.PAUSED:
		_previous_speed = next
	speed_changed.emit(_speed)


## Space preserves the speed the player was using rather than always returning to 1x.
func toggle_pause() -> void:
	if _speed == Speed.PAUSED:
		set_speed(_previous_speed)
	else:
		_previous_speed = _speed
		set_speed(Speed.PAUSED)


func start_new_game() -> void:
	_elapsed = 0.0
	_previous_speed = Speed.SPEED_1
	set_speed(Speed.SPEED_1)


## Speed is deliberately not save data. Loading always gives the player a paused world.
func loaded_game() -> void:
	_elapsed = 0.0
	_previous_speed = Speed.SPEED_1
	set_speed(Speed.PAUSED)
