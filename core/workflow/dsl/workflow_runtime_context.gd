class_name WorkflowRuntimeContext
extends DslEvalContext

## The real, kernel-backed [DslEvalContext]: what an executing workflow instance reads from.
## Params and locals are the instance's own dictionaries (locals is the live one the executor
## mutates via `let`/`roll`); state, globals, functions and tables are the shared kernel
## services. Still read-only — an expression can reach all of this but mutate none of it;
## effects (`run_command`, `set_global`) are the executor's job, never the evaluator's.

var _params: Dictionary
var _locals: Dictionary
var _state: GameState
var _globals: GlobalStore
var _functions: DslFunctionRegistry
var _tables: DslTableRegistry


func _init(params: Dictionary, locals: Dictionary, state: GameState,
		globals: GlobalStore, functions: DslFunctionRegistry, tables: DslTableRegistry) -> void:
	_params = params
	_locals = locals
	_state = state
	_globals = globals
	_functions = functions
	_tables = tables


func get_param(param_name: String) -> Variant:
	return _params.get(param_name, null)


func get_local(local_name: String) -> Variant:
	return _locals.get(local_name, null)


## Walk an already-resolved path (the evaluator resolved any sigil segments) through
## [GameState]'s nested dictionaries. A segment that leaves a non-dictionary returns null.
func read_state(path: Array) -> Variant:
	if path.is_empty():
		return null
	var cur: Variant = _state.get_value(path[0], null)
	for i in range(1, path.size()):
		if cur is Dictionary:
			cur = (cur as Dictionary).get(path[i], null)
		else:
			return null
	return cur


func call_fn(fn_name: String, args: Dictionary) -> Variant:
	return _functions.call_fn(fn_name, args)


func table_get(table_name: String, key: Variant) -> Variant:
	return _tables.lookup(table_name, key)


func get_global(global_name: String) -> Variant:
	return _globals.get_value(global_name, null)
