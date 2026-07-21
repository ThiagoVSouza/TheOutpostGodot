class_name WorkflowRegistry
extends RefCounted

## Validated workflow definitions, keyed by id (and version). Nothing enters here until the
## [WorkflowValidator] has accepted it, so every consumer — the executor's `run` op, the
## scheduler, resume — can trust the shape of what it pulls out. This is also where the
## cross-workflow call-graph would be checked for acyclicity (a later step; single-definition
## validation cannot see the whole graph).

var _validator: WorkflowValidator
var _by_id: Dictionary = {}          # id -> latest definition
var _by_id_version: Dictionary = {}  # "id@version" -> definition


func _init(validator: WorkflowValidator = null) -> void:
	_validator = validator if validator != null else WorkflowValidator.new()


## Validate and register a definition. Returns the validation result; on failure nothing is
## stored (a definition that cannot be proven sound is never admitted).
func register(definition: Variant) -> CommandResult:
	var result := _validator.validate(definition)
	if not result.success:
		return result
	var def := definition as Dictionary
	var id := String(def["id"])
	var version := int(def["version"])
	_by_id[id] = def
	_by_id_version["%s@%d" % [id, version]] = def
	return CommandResult.ok("registered", {"id": id, "version": version})


func has(id: String) -> bool:
	return _by_id.has(id)


## Look up by "id" (latest) or "id@version". Returns null if absent.
func get_definition(id_or_ref: String) -> Variant:
	if _by_id_version.has(id_or_ref):
		return _by_id_version[id_or_ref]
	return _by_id.get(id_or_ref, null)
