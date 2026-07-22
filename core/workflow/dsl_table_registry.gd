class_name DslTableRegistry
extends RefCounted

## Rule tables for the `table_get` op (D24): the tunable numbers of the game live here, not
## in code, so balance is data a designer edits without a rebuild — the mechanism the D4
## amendment's difficulty bands uses.
##
## Two shapes, both read through the same `table_get`:
##
## - **Key tables** ([method register]) map an exact key to a value.
## - **Range tables** ([method register_ranges]) map a *number* to the value of the band it
##   falls in — the shape a dice total needs. Bands are half-open `[from, to)`, matching the
##   DSL's `for` (A3), so adjacent rows share an edge without overlapping and a threshold is
##   written once. This is what keeps a raw d20 out of both the workflow and the narrator:
##   the workflow asks the table what *kind* of outcome the roll was and branches on that
##   word, so the number never becomes authored content or player-facing prose.

var _tables: Dictionary = {}  # name -> Dictionary(key -> value)
var _ranges: Dictionary = {}  # name -> Array[Dictionary] of normalized {from, to, value} rows


func register(table_name: String, table: Dictionary) -> void:
	_tables[table_name] = table


## Register a band table. Each row is `{"from": num, "to": num, "value": v}` with `from`
## inclusive and `to` exclusive; omit `from` for an open bottom and `to` for an open top.
## Rows must be ordered ascending and must not overlap — an author who writes an overlapping
## table has made a balance mistake, and silently taking the first match would hide it.
func register_ranges(table_name: String, rows: Array) -> void:
	var normalized: Array = []
	var previous_to: Variant = null  # the running upper edge, to catch overlap and disorder
	for i in rows.size():
		if not (rows[i] is Dictionary):
			push_error("DSL table_get: range table \"%s\" row %d is not a dictionary" % [table_name, i])
			return
		var row: Dictionary = rows[i]
		if not row.has("value"):
			push_error("DSL table_get: range table \"%s\" row %d has no \"value\"" % [table_name, i])
			return
		# INF/-INF stand in for the open ends so lookup needs no null branches.
		var from: float = float(row["from"]) if row.get("from", null) != null else -INF
		var to: float = float(row["to"]) if row.get("to", null) != null else INF
		if from >= to:
			push_error("DSL table_get: range table \"%s\" row %d is empty (from >= to)" % [table_name, i])
			return
		if previous_to != null and from < float(previous_to):
			push_error("DSL table_get: range table \"%s\" row %d overlaps or precedes the row before it"
				% [table_name, i])
			return
		previous_to = to
		normalized.append({"from": from, "to": to, "value": row["value"]})
	_ranges[table_name] = normalized


func has(table_name: String) -> bool:
	return _tables.has(table_name) or _ranges.has(table_name)


## Look up a key in a named table. Returns null for a missing table, a missing key, or a
## number outside every band — a workflow that needs to treat a miss as a failure does so with
## an explicit `require`, keeping the policy in the authored content rather than buried here.
func lookup(table_name: String, key: Variant) -> Variant:
	if _ranges.has(table_name):
		return _lookup_range(table_name, key)
	if not _tables.has(table_name):
		push_error("DSL table_get: no registered table \"%s\"" % table_name)
		return null
	return (_tables[table_name] as Dictionary).get(key, null)


func _lookup_range(table_name: String, key: Variant) -> Variant:
	# Guarded rather than coerced: `float("forage")` is 0.0, which would silently land in
	# whichever band contains zero instead of reporting the author's mistake.
	if not (key is int or key is float):
		push_error("DSL table_get: range table \"%s\" needs a number, got %s"
			% [table_name, type_string(typeof(key))])
		return null
	var value := float(key)
	for row: Dictionary in _ranges[table_name]:
		if value >= float(row["from"]) and value < float(row["to"]):
			return row["value"]
	return null
