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
