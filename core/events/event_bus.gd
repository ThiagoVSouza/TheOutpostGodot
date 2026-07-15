class_name EventBus
extends RefCounted

## Decoupled publish/subscribe bus for cross-system communication.
##
## Systems emit and listen by event name so modules never need direct references
## to each other. Payloads are dictionaries to keep the bus schema-agnostic; typed
## event wrappers can be layered on top per module if desired.

var _subscribers: Dictionary = {}  # event_name: String -> Array[Callable]


## Subscribe a callable to an event name. The callable receives one Dictionary payload.
func subscribe(event_name: String, handler: Callable) -> void:
	if not _subscribers.has(event_name):
		_subscribers[event_name] = [] as Array[Callable]
	var handlers: Array[Callable] = _subscribers[event_name]
	if not handlers.has(handler):
		handlers.append(handler)


## Remove a previously subscribed handler.
func unsubscribe(event_name: String, handler: Callable) -> void:
	if not _subscribers.has(event_name):
		return
	var handlers: Array[Callable] = _subscribers[event_name]
	handlers.erase(handler)
	if handlers.is_empty():
		_subscribers.erase(event_name)


## Emit an event to all current subscribers. Iterates a copy so handlers may
## safely (un)subscribe during dispatch.
func emit(event_name: String, payload: Dictionary = {}) -> void:
	if not _subscribers.has(event_name):
		return
	var handlers: Array[Callable] = (_subscribers[event_name] as Array[Callable]).duplicate()
	for handler in handlers:
		if handler.is_valid():
			handler.call(payload)


## Number of handlers registered for an event (useful in tests).
func subscriber_count(event_name: String) -> int:
	if not _subscribers.has(event_name):
		return 0
	return (_subscribers[event_name] as Array[Callable]).size()
