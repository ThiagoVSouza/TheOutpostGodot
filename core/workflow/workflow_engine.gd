class_name WorkflowEngine
extends RefCounted

## Parses, validates and executes the controlled workflow DSL. STUB SEAM — milestone 1.
##
## Per the brief, the AI may propose workflows but must NEVER create or run arbitrary
## GDScript. Generated workflows must be parsed, schema-validated, checked against
## allowed capabilities, bounded by max steps/loops, stored with origin/version, and
## only activated after successful validation. This stub reserves the seam and the
## safety contract; the parser/validator/executor are implemented in milestone 1.

const MAX_STEPS: int = 256
const MAX_LOOP_ITERATIONS: int = 1000


## Validate a workflow definition against the schema and capability whitelist.
## Returns [CommandResult]-style ok/fail. Real implementation does the full check.
func validate_definition(_definition: Dictionary, _allowed_capabilities: PackedStringArray) -> CommandResult:
	# TODO(milestone-1): schema validation + capability whitelist + step/loop limits.
	return CommandResult.fail("WorkflowEngine not implemented yet")


## Execute a previously validated workflow. Never executes arbitrary GDScript.
func execute(_definition: Dictionary, _kernel: GameKernel) -> CommandResult:
	# TODO(milestone-1): interpret validated DSL ops (read state, roll, tool, branch,
	# command, schedule, narrate) with step/loop budgets.
	return CommandResult.fail("WorkflowEngine not implemented yet")
