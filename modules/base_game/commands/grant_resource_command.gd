class_name GrantResourceCommand
extends Command

## Grants an amount of a settlement resource (food, gold, ...). Example of the brief's
## GrantResourceCommand: the only sanctioned way for AI/workflow outcomes to change
## resource state. Resources live under the "resources" key of [GameState] as a
## { resource_name: amount } dictionary.

var resource: String
var amount: int


func _init(resource_name: String = "", grant_amount: int = 0) -> void:
	resource = resource_name
	amount = grant_amount


func command_name() -> String:
	return "grant_resource"


func validate(_state: GameState) -> CommandResult:
	if resource.strip_edges().is_empty():
		return CommandResult.fail("resource name is required")
	if amount <= 0:
		return CommandResult.fail("amount must be positive (got %d)" % amount)
	return CommandResult.ok()


func apply(state: GameState) -> CommandResult:
	var resources: Dictionary = state.get_value("resources", {})
	var current := int(resources.get(resource, 0))
	var updated := current + amount
	resources[resource] = updated
	state.set_value("resources", resources)
	return CommandResult.ok(
		"granted %d %s" % [amount, resource],
		{"resource": resource, "amount": amount, "total": updated}
	)


## Factory for the CommandRegistry: builds a command from AI/workflow-supplied args.
static func from_args(args: Dictionary) -> Command:
	return GrantResourceCommand.new(
		String(args.get("resource", "")),
		int(args.get("amount", 0))
	)
