class_name DslTableRegistry
extends RefCounted

## Rule tables for the `table_get` op (D24): the tunable numbers of the game live here, not
## in code, so balance is data a designer edits without a rebuild — the mechanism the D4
## amendment's difficulty bands will use. A2 does single-key lookup; **range-row bands**
## (e.g. a dice total mapping to an outcome band) are deferred to M3b when the difficulty
## tables are actually authored.

var _tables: Dictionary = {}  # name -> Dictionary(key -> value)


func register(table_name: String, table: Dictionary) -> void:
	_tables[table_name] = table


func has(table_name: String) -> bool:
	return _tables.has(table_name)


## Look up a key in a named table. Returns null for a missing table or key — a workflow that
## needs to treat a miss as a failure does so with an explicit `require`, keeping the policy
## in the authored content rather than buried here.
func lookup(table_name: String, key: Variant) -> Variant:
	if not _tables.has(table_name):
		push_error("DSL table_get: no registered table \"%s\"" % table_name)
		return null
	return (_tables[table_name] as Dictionary).get(key, null)
