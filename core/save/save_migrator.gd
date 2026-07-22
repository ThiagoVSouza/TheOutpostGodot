class_name SaveMigrator
extends RefCounted

## Runs a module's declared [SaveMigration] chain over save data (M4/B3).
##
## The rule is one sentence: **apply every step whose `to_version` is newer than the version
## stamped in the save, oldest first.** Everything else here is about the cases where that
## sentence does not apply cleanly, and each of them fails loudly rather than guessing —
## silently loading a save you did not understand is how a player's settlement quietly loses
## half its buildings.

## Compare two "semantic-ish" version strings component by component, numerically.
## Returns -1 if [param a] < [param b], 0 if equal, 1 if greater.
##
## Numeric per component on purpose: as strings, "0.10.0" sorts *before* "0.2.0", so a
## string comparison silently stops running migrations at the tenth release. Missing
## components read as 0, so "1" == "1.0" == "1.0.0"; non-numeric components read as 0 too,
## which makes a suffix like "1.2.0-beta" compare equal to "1.2.0" rather than throwing.
static func compare_versions(a: String, b: String) -> int:
	var left := a.split(".")
	var right := b.split(".")
	var count := maxi(left.size(), right.size())
	for i in count:
		var l := _component(left, i)
		var r := _component(right, i)
		if l != r:
			return -1 if l < r else 1
	return 0


static func _component(parts: PackedStringArray, index: int) -> int:
	if index >= parts.size():
		return 0
	var raw := parts[index].strip_edges()
	# Take the leading digits so "2-beta" reads as 2; a component with no digits reads as 0.
	var digits := ""
	for c in raw:
		if c < "0" or c > "9":
			break
		digits += c
	return int(digits) if not digits.is_empty() else 0


## Migrate one module's save data from [param from_version] up to [param to_version].
##
## Returns `{ok, data, applied, error}` — `applied` lists the versions of the steps that ran,
## which is what makes a migration auditable after the fact rather than a black box.
static func migrate(data: Dictionary, from_version: String, to_version: String,
		migrations: Array, log: GameLog = null, module_id: String = "") -> Dictionary:
	# Save written by a *newer* build of this module than the one running. Its data may contain
	# shapes this build has never seen, and there is no backwards migration to undo them.
	# Refusing is the honest answer; see SaveManager's identical stance on the envelope version.
	if compare_versions(from_version, to_version) > 0:
		return {"ok": false, "data": data, "applied": [],
			"error": "module_from_newer_version"}

	var pending: Array = []
	for migration: SaveMigration in migrations:
		if migration == null or not migration.apply.is_valid():
			return {"ok": false, "data": data, "applied": [], "error": "invalid_migration"}
		# Steps at or below the saved version already happened; steps above the module's own
		# version are declared for a release that has not shipped yet and must not run early.
		if compare_versions(migration.to_version, from_version) > 0 \
				and compare_versions(migration.to_version, to_version) <= 0:
			pending.append(migration)

	pending.sort_custom(func(x: SaveMigration, y: SaveMigration) -> bool:
		return compare_versions(x.to_version, y.to_version) < 0)

	var migrated := data.duplicate(true)
	var applied: Array = []
	for migration: SaveMigration in pending:
		var out: Variant = migration.apply.call(migrated)
		# A step that returns something other than a dictionary has a bug in it. Stopping here
		# keeps the half-migrated data out of the game rather than handing it to the module.
		if not (out is Dictionary):
			return {"ok": false, "data": data, "applied": applied, "error": "migration_failed"}
		migrated = out as Dictionary
		applied.append(migration.to_version)
		if log != null:
			log.info("SaveMigrator", "Migrated %s save data to %s%s" % [
				module_id, migration.to_version,
				": %s" % migration.description if not migration.description.is_empty() else ""])

	return {"ok": true, "data": migrated, "applied": applied, "error": ""}
