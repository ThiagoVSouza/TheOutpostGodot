class_name AiAvailability
extends RefCounted

## Kernel-owned AI availability state implementing the T5 recovery policy (D16
## amendment): when the production backend fails, orchestration is blocked and a
## visible unavailable state is announced — the game never fabricates a player-facing
## turn with [FakeAiBackend]. At most [constant MAX_ATTEMPTS] automatic recovery
## probes run per outage (with backoff), then the state parks at UNAVAILABLE until a
## deliberate player retry starts a new sequence. No game state changes while blocked
## (the orchestrator refuses before reaching the backend).
##
## Lives in the kernel and announces on the event bus — not in the chat UI — because
## the future workflow DSL runtime (AI-call suspension points) becomes a second
## consumer of this state.
##
## Implementation note: deliberately signal-driven with zero coroutines, so
## SceneTreeTimer callbacks can drive it directly (Godot 4.7 rejects unawaited
## coroutine calls at parse time).

signal changed(state: String, payload: Dictionary)

const EVENT_NAME := "ai_availability_changed"
const MAX_ATTEMPTS: int = 3

enum State { AVAILABLE, RECOVERING, UNAVAILABLE }

## Delay in seconds before automatic attempt N is backoff_seconds[N - 1].
## Tests shrink these to near-zero.
var backoff_seconds: Array = [2.0, 5.0, 10.0]

var _state: int = State.AVAILABLE
var _attempt: int = 0
var _outage_id: int = 0
var _events: EventBus
var _backend_provider: Callable


## [param backend_provider] returns the kernel's current [AiBackend] when called —
## a provider rather than a reference so backend swaps are tolerated mid-session.
func _init(events: EventBus, backend_provider: Callable) -> void:
	_events = events
	_backend_provider = backend_provider


func state() -> int:
	return _state


func attempt() -> int:
	return _attempt


## True while orchestration must not reach the backend (RECOVERING or UNAVAILABLE).
func is_blocked() -> bool:
	return _state != State.AVAILABLE


func state_name() -> String:
	match _state:
		State.RECOVERING:
			return "recovering"
		State.UNAVAILABLE:
			return "unavailable"
	return "available"


## The orchestrator reports a backend failure (timeout / transport / server error —
## never a cancellation). Starts the bounded automatic recovery sequence; repeated
## reports during an active outage are ignored.
func report_failure(error: String) -> void:
	if _state != State.AVAILABLE:
		return
	_begin_outage({"error": error}, _backoff_before_attempt(1))


## Deliberate player retry: allowed only from the parked UNAVAILABLE state, and the
## first probe runs immediately — the player asked; no backoff.
func retry() -> void:
	if _state != State.UNAVAILABLE:
		return
	_begin_outage({"reason": "player_retry"}, 0.0)


func _backoff_before_attempt(n: int) -> float:
	var index := n - 1
	if index < 0 or index >= backoff_seconds.size():
		return 0.0
	return float(backoff_seconds[index])


func _begin_outage(detail: Dictionary, first_delay: float) -> void:
	_outage_id += 1
	_attempt = 0
	_set_state(State.RECOVERING, detail)
	_schedule_attempt(_outage_id, first_delay)


## Timers hold only a weakref: a pending backoff must never extend this object's
## lifetime past the kernel's (the T1 leak lesson).
func _schedule_attempt(outage: int, delay: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_set_state(State.UNAVAILABLE, {"reason": "no_scene_tree"})
		return
	var wr: WeakRef = weakref(self)
	tree.create_timer(maxf(delay, 0.0)).timeout.connect(func() -> void:
		var live: AiAvailability = wr.get_ref()
		if live != null:
			live._run_attempt(outage))


func _run_attempt(outage: int) -> void:
	if outage != _outage_id or _state != State.RECOVERING:
		return
	_attempt += 1
	_emit({})
	var backend: AiBackend = _backend_provider.call()
	if backend == null:
		_attempt_finished(outage, false)
		return
	var probe := backend.attempt_recovery(_attempt)
	if probe.is_finished():
		_attempt_finished(outage, bool(probe.outcome().get("ok", false)))
		return
	var wr: WeakRef = weakref(self)
	probe.finished.connect(func(outcome: Dictionary) -> void:
		var live: AiAvailability = wr.get_ref()
		if live != null:
			live._on_probe_finished(outage, outcome),
		CONNECT_ONE_SHOT)


func _on_probe_finished(outage: int, outcome: Dictionary) -> void:
	if outage != _outage_id or _state != State.RECOVERING:
		return
	_attempt_finished(outage, bool(outcome.get("ok", false)))


func _attempt_finished(outage: int, success: bool) -> void:
	if success:
		_set_state(State.AVAILABLE, {"attempts_used": _attempt})
		return
	if _attempt >= MAX_ATTEMPTS:
		_set_state(State.UNAVAILABLE, {"attempts_used": _attempt})
		return
	_schedule_attempt(outage, _backoff_before_attempt(_attempt + 1))


func _set_state(new_state: int, detail: Dictionary) -> void:
	_state = new_state
	_emit(detail)


func _emit(detail: Dictionary) -> void:
	var payload := {"state": state_name(), "attempt": _attempt}
	payload.merge(detail)
	changed.emit(state_name(), payload)
	if _events != null:
		_events.emit(EVENT_NAME, payload)
