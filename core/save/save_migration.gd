class_name SaveMigration
extends RefCounted

## One declared step in a module's save-data migration chain (M4/B3).
##
## A module declares the shape changes its own save data has been through, each tagged with the
## module version that introduced it. On load, [SaveMigrator] runs every step newer than the
## version stamped in the save, oldest first, so a save from any past version walks forward to
## the present one step at a time. Each step therefore only ever has to know about *its own*
## change — never the whole history — which is what keeps migrations writable years later.
##
## [member apply] takes the module's save data and returns the migrated data. It must be pure
## and total: no kernel access, no failing on unexpected input. It is handed data written by an
## older build, which may be missing keys it never had, and returning something sensible for
## garbage is part of the job.

## The module version this step brings the data up to, e.g. "0.2.0". Compared numerically per
## component (so 0.10.0 correctly sorts after 0.2.0), not as a string.
var to_version: String

## `func(data: Dictionary) -> Dictionary`
var apply: Callable

## Optional one-line note about what changed; surfaced in logs when the step runs.
var description: String


static func step(version: String, migration: Callable, note: String = "") -> SaveMigration:
	var m := SaveMigration.new()
	m.to_version = version
	m.apply = migration
	m.description = note
	return m
