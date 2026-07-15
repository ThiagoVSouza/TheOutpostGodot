class_name AiTool
extends RefCounted

## Base class for a typed tool the AI may call (e.g. rolling dice, querying state).
##
## Tools are the ONLY way the AI reaches into the game during planning, and they are
## deliberately narrow: a tool returns data, it does not mutate game state. State changes
## happen exclusively through validated commands (see [CommandBus] / [CommandRegistry]).
## Modules register concrete tools with the kernel's [ToolRegistry].

## Unique tool id the AI references (e.g. "roll_die"). Override in subclasses.
func tool_name() -> String:
	return "abstract_tool"


## JSON-serializable description of the accepted arguments, surfaced to the backend so a
## real model knows how to call the tool. Kept as a plain Dictionary. Override.
func params_schema() -> Dictionary:
	return {}


## Execute the tool with validated-ish args and return a JSON-serializable result.
## [param kernel] gives read access to game systems; tools must not mutate state here.
## Override in subclasses.
func execute(_args: Dictionary, _kernel: GameKernel) -> Dictionary:
	push_error("AiTool.execute() called on abstract base")
	return {}
