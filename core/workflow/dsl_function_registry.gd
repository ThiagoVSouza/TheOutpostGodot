class_name DslFunctionRegistry
extends RefCounted

## The names callable from a workflow's `fn` op — registered **pure** query functions (D27's
## "query ops"): `combat.attack_modifier`, `travel.calculate_route`, etc. A component
## contributes functions here; the DSL calls them by name and can never invent one (the
## validator forbids a computed `fn.name`). Purity is the registrant's contract: a function
## must be deterministic and side-effect free, because it runs in expression position.

var _fns: Dictionary = {}  # name -> Callable(args: Dictionary) -> Variant


func register(fn_name: String, fn: Callable) -> void:
	_fns[fn_name] = fn


func has(fn_name: String) -> bool:
	return _fns.has(fn_name)


## Call a registered function. Returns null for an unregistered name — the validator has
## already ensured names are literals, but a name unknown at runtime degrades to null rather
## than crashing the instance mid-flight.
func call_fn(fn_name: String, args: Dictionary) -> Variant:
	if not _fns.has(fn_name):
		push_error("DSL fn: no registered function \"%s\"" % fn_name)
		return null
	return (_fns[fn_name] as Callable).call(args)
