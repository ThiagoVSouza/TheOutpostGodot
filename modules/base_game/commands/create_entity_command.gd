class_name CreateEntityCommand
extends Command

## Add an entity to the world's cast (M5/M7). The whitelisted way a module, a new-game workflow or
## a plot brings a character, faction or location into being (D4/D30) — the engine block, not a
## specific cast. Refuses a duplicate id, an unknown type, or a blank id, so a bad create fails at
## the choke point instead of quietly overwriting an existing entity.

var id: String
var type: String
var entity_name: String
var disposition: int
var traits: Array


func _init(entity_id: String = "", entity_type: String = "", name: String = "",
		starting_disposition: int = 0, entity_traits: Array = []) -> void:
	id = entity_id
	type = entity_type
	entity_name = name
	disposition = starting_disposition
	traits = entity_traits


func command_name() -> String:
	return "create_entity"


func validate(state: GameState) -> CommandResult:
	if id.strip_edges().is_empty():
		return CommandResult.fail("entity id is required")
	if not Entities.TYPES.has(type):
		return CommandResult.fail("unknown entity type '%s'" % type)
	if Entities.exists(state, id):
		return CommandResult.fail("entity '%s' already exists" % id)
	return CommandResult.ok()


func apply(state: GameState) -> CommandResult:
	var entities: Dictionary = Entities.all(state)
	entities[id] = Entities.new_entity(id, type, entity_name, disposition, traits)
	state.set_value("entities", entities)
	return CommandResult.ok("created %s '%s'" % [type, id], {"id": id, "type": type})


static func from_args(args: Dictionary) -> Command:
	var traits_v: Variant = args.get("traits", [])
	return CreateEntityCommand.new(
		String(args.get("id", "")),
		String(args.get("type", "")),
		String(args.get("name", "")),
		int(args.get("disposition", 0)),
		traits_v if traits_v is Array else [])
