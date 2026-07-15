class_name Command
extends RefCounted

## Base class for all validated state mutations.
##
## Per the brief, neither the AI nor the UI may change important game state directly.
## Instead they produce Command instances (e.g. GrantResourceCommand,
## ChangeRelationshipCommand) which the [CommandBus] validates before applying. This
## makes actions testable, reproducible and compatible with saves and AI trace replay.
##
## Subclasses override [method validate] and [method apply]. They must not mutate
## state inside [method validate] — validation is side-effect free.

## Stable identifier for logging / trace replay. Override in subclasses.
func command_name() -> String:
	return "Command"


## Check whether this command may be applied to the given state.
## Must be side-effect free. Return CommandResult.ok() or CommandResult.fail(reason).
func validate(_state: GameState) -> CommandResult:
	return CommandResult.ok()


## Apply the mutation to state. Only called by the CommandBus after [method validate]
## has succeeded. Return a result describing the outcome.
func apply(_state: GameState) -> CommandResult:
	return CommandResult.fail("Command.apply() not implemented")
