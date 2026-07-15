class_name ModuleManifest
extends Resource

## Declarative description of a game module (base game or a DLC).
##
## Manifests are the ONLY module-discovery mechanism — there is no hardcoded module
## list. They are authored as `.tres` resources so Godot's type system validates them
## and they are inspectable in the editor. The [ModuleRegistry] scans for these,
## resolves dependency order, then instantiates [member entry_script].

## Unique module id (e.g. "base_game"). Used for dependency references and logging.
@export var id: String = ""

## Human-readable name shown in UI / logs.
@export var display_name: String = ""

## Semantic-ish version string for save migrations and diagnostics.
@export var version: String = "0.0.0"

## Ids of other modules that must load before this one.
@export var dependencies: Array[String] = []

## Script extending [Module] that is instantiated and given a chance to register
## screens, systems, commands, AI tools, workflows, etc.
@export var entry_script: Script

## Allows shipping a module but leaving it inactive.
@export var enabled: bool = true


## Basic self-check used by tooling (tools/validate.ps1) and the registry.
## Returns an array of human-readable problems; empty means valid.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.strip_edges().is_empty():
		errors.append("manifest has empty id")
	if entry_script == null:
		errors.append("manifest '%s' has no entry_script" % id)
	return errors
