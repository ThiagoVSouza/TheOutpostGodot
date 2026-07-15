class_name WorkflowEngine
extends RefCounted

## Validates and executes the controlled workflow DSL.
##
## Per the brief, the AI may propose workflows but must NEVER run arbitrary GDScript.
## Workflows are JSON-serializable dictionaries with a "steps" array; every step's "op"
## must be in the allowed capability set, and the step count is bounded. Execution
## interprets a small, fixed op set — it cannot call into anything not vetted here, and
## state changes still go through whitelisted commands.
##
## Definition shape:
##   { "id"?, "version"?, "origin"?, "steps": [ {op, ...}, ... ] }
## Ops: read_state {key, as?}, narrate {text}, roll {sides, count, seed?, as?},
##      run_command {name, args?}

const MAX_STEPS: int = 256
const MAX_LOOP_ITERATIONS: int = 1000


## The op set this engine can interpret — used as the default capability whitelist.
func default_capabilities() -> PackedStringArray:
	return PackedStringArray(["read_state", "narrate", "roll", "run_command"])


## Structure + capability + budget check. Side-effect free.
func validate_definition(definition: Variant, allowed_capabilities: PackedStringArray) -> CommandResult:
	if not (definition is Dictionary):
		return CommandResult.fail("workflow must be a dictionary")
	if not definition.has("steps"):
		return CommandResult.fail("workflow has no 'steps'")
	var steps: Variant = definition["steps"]
	if not (steps is Array):
		return CommandResult.fail("'steps' must be an array")
	if steps.size() > MAX_STEPS:
		return CommandResult.fail("workflow exceeds MAX_STEPS (%d)" % MAX_STEPS)
	var allowed: Dictionary = {}
	for cap in allowed_capabilities:
		allowed[cap] = true
	for i in steps.size():
		var step: Variant = steps[i]
		if not (step is Dictionary):
			return CommandResult.fail("step %d is not a dictionary" % i)
		var op := String(step.get("op", ""))
		if op.is_empty():
			return CommandResult.fail("step %d has no 'op'" % i)
		if not allowed.has(op):
			return CommandResult.fail("step %d op '%s' not in allowed capabilities" % [i, op])
	return CommandResult.ok("valid", {"steps": steps.size()})


## Validate (against default capabilities) then interpret the steps. Never runs code.
## On success, result.data carries { narrative, applied_commands, vars }.
func execute(definition: Variant, kernel: GameKernel) -> CommandResult:
	var validation := validate_definition(definition, default_capabilities())
	if not validation.success:
		return validation

	var steps: Array = (definition as Dictionary)["steps"]
	var vars: Dictionary = {}
	var narrative_parts: Array = []
	var applied: Array = []
	var executed := 0

	for step_v in steps:
		if executed >= MAX_STEPS:
			break
		executed += 1
		var step := step_v as Dictionary
		var op := String(step.get("op", ""))
		match op:
			"read_state":
				var key := String(step.get("key", ""))
				var alias := String(step.get("as", key))
				var value: Variant = _read_path(kernel.state, key)
				if value == null and step.has("default"):
					value = step["default"]
				vars[alias] = value
			"narrate":
				var text := _interpolate(String(step.get("text", "")), vars)
				narrative_parts.append(text)
				if kernel.events != null:
					kernel.events.emit("workflow_narrative", {"text": text})
			"roll":
				var sides := maxi(int(step.get("sides", 6)), 1)
				var count := int(step.get("count", 1))
				var rng := RandomNumberGenerator.new()
				if step.has("seed"):
					rng.seed = int(step["seed"])
				var total := 0
				for _r in mini(count, MAX_LOOP_ITERATIONS):
					total += rng.randi_range(1, sides)
				vars[String(step.get("as", "roll"))] = total
			"run_command":
				var cmd_name := String(step.get("name", ""))
				var cmd_args: Variant = step.get("args", {})
				if not (cmd_args is Dictionary):
					cmd_args = {}
				if kernel.command_registry.has(cmd_name):
					var cmd := kernel.command_registry.create(cmd_name, cmd_args)
					if cmd != null and kernel.commands.execute(cmd).success:
						applied.append(cmd_name)

	return CommandResult.ok("workflow executed", {
		"narrative": "\n".join(narrative_parts),
		"applied_commands": applied,
		"vars": vars,
	})


# --- helpers ---

## Read a dotted path (e.g. "resources.food") out of [GameState]'s nested dictionaries.
func _read_path(state: GameState, path: String) -> Variant:
	var parts := path.split(".")
	if parts.is_empty():
		return null
	var current: Variant = state.get_value(parts[0], null)
	for i in range(1, parts.size()):
		if current is Dictionary:
			current = current.get(parts[i], null)
		else:
			return null
	return current


## Replace ${name} tokens in [param text] with values from [param vars].
func _interpolate(text: String, vars: Dictionary) -> String:
	var out := text
	for k in vars:
		out = out.replace("${%s}" % k, str(vars[k]))
	return out
