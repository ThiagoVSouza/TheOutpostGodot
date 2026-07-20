class_name DslEvalContext
extends RefCounted

## What an expression needs from the outside world to evaluate: param/local scopes, game
## state reads, pure-function calls, and rule-table lookups. Kept behind this seam so
## [DslExpressionEvaluator] stays a pure tree-walker with no kernel dependency — tests
## supply a trivial in-memory context, and A3/A4 supply the real kernel-backed one.
##
## Every method here is a *read*. Expressions are pure by construction (D24): nothing an
## expression can reach may mutate state. Effects happen only at statement level, which is
## the executor's job (A3), not this evaluator's.

## Resolve a workflow param by its atomic name, e.g. "route" for "@route". Nested access
## (into the returned value) is a separate `get` op, never a dotted sigil.
func get_param(param_name: String) -> Variant:
	return null


## Resolve an instance-local by its atomic name, e.g. "route" for "$$route".
func get_local(local_name: String) -> Variant:
	return null


## Read game state at an already-resolved path (sigil segments resolved by the evaluator).
func read_state(path: Array) -> Variant:
	return null


## Call a registered pure function by name with a resolved args dict.
func call_fn(fn_name: String, args: Dictionary) -> Variant:
	return null


## Look up a resolved key in a named rule table (single-key; range rows deferred, A2).
func table_get(table_name: String, key: Variant) -> Variant:
	return null


## Read a global variable by name (D31). Reading is pure; only `set_global` (a statement
## the executor runs, not this evaluator) mutates the global store.
func get_global(global_name: String) -> Variant:
	return null
