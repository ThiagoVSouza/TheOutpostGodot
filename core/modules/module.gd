class_name Module
extends RefCounted

## Base class for a module's entry point.
##
## A module registers its content with the kernel through stable interfaces instead of
## reaching into unrelated systems. The registry sets [member manifest] then calls
## [method register] once, in dependency order. Subclasses override [method register].

var manifest: ModuleManifest


## Convenience id accessor.
func module_id() -> String:
	return manifest.id if manifest != null else "<unknown>"


## Register this module's screens, systems, commands, AI tools, workflows, etc.
## Called once by the [ModuleRegistry] after dependencies are loaded.
## [param kernel] is the running [GameKernel] singleton, providing the stable seams
## (kernel.screens, kernel.commands, kernel.events, ...).
func register(_kernel: GameKernel) -> void:
	pass


## Module-owned save data (M4/B2). Anything a module keeps outside [GameState] and needs back
## on load goes here; return an empty dictionary (the default) if there is nothing. Must be
## JSON-serializable — the save file is text.
##
## The module's `manifest.version` is stamped alongside this in the save, which is what lets
## B3 migrate old module data forward.
func capture_save_data(_kernel: GameKernel) -> Dictionary:
	return {}


## Restore what [method capture_save_data] produced. [param data] is empty when the save
## predates this module — a module added since the save must cope with that rather than assume
## its keys exist.
func restore_save_data(_kernel: GameKernel, _data: Dictionary) -> void:
	pass


## Declared shape changes this module's save data has been through (M4/B3), as [SaveMigration]
## steps tagged with the `manifest.version` that introduced each. Order does not matter — the
## [SaveMigrator] sorts them — and only steps newer than the version stamped in the save run.
##
## Add a step in the same commit as the shape change that needs it, and never edit a shipped
## step: a player's save may be sitting on any past version, and rewriting history is exactly
## the case migrations exist to avoid.
func save_migrations() -> Array:
	return []
