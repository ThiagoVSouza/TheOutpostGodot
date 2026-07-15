class_name CommandRegistry
extends RefCounted

## Whitelist of commands the AI (and workflows) are allowed to produce.
##
## This is a core safety boundary. The AI never constructs a [Command] directly and never
## runs code: it emits `{name, args}`, and only a name registered here can be turned into
## a real command — via a factory the module supplied. An unknown name is rejected. This
## keeps AI-driven mutations restricted to vetted, validated commands.

var _factories: Dictionary = {}  # name: String -> Callable(args: Dictionary) -> Command


## Register a command factory. [param factory] maps an args Dictionary to a [Command].
func register(command_name: String, factory: Callable) -> void:
	_factories[command_name] = factory


func has(command_name: String) -> bool:
	return _factories.has(command_name)


func command_names() -> Array:
	return _factories.keys()


## Build a command from a whitelisted name + args, or null if the name is not allowed
## (or the factory fails to produce a [Command]).
func create(command_name: String, args: Dictionary) -> Command:
	if not _factories.has(command_name):
		return null
	var factory: Callable = _factories[command_name]
	var command := factory.call(args) as Command
	return command
