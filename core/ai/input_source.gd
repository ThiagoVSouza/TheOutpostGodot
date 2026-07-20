class_name AiInputSource
extends RefCounted

## One origin of player text for the AI pipeline (D18): typed chat today; voice and
## trace replay later.
##
## Sources are created via [method AiInputRouter.create_source] and owned by their
## caller. The source references the kernel-owned router, and the router holds no
## sources, so no RefCounted cycle forms.

var _id: String
var _router: AiInputRouter


func _init(source_id: String, router: AiInputRouter) -> void:
	_id = source_id
	_router = router


func id() -> String:
	return _id


## Send one player message into the AI pipeline. Fire-and-forget: the reply is
## broadcast on the event bus as [constant AiInputRouter.EVENT_TURN_COMPLETED],
## tagged with this source's id.
func submit(text: String, metadata: Dictionary = {}) -> void:
	_router.submit(_id, text, metadata)
