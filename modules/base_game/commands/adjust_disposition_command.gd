class_name AdjustDispositionCommand
extends Command

## Move an entity's disposition toward the player (M5/M7) — the core relationship mechanic the
## briefing leans on (the steward's feeling toward the hero colours the five-year assessment). The
## whitelisted, only way that number changes (D4): a plot, an event or a resolved turn proposes a
## delta, code clamps and applies it. The engine block; who likes whom, and by how much, is content.

var id: String
var delta: int


func _init(entity_id: String = "", disposition_delta: int = 0) -> void:
	id = entity_id
	delta = disposition_delta


func command_name() -> String:
	return "adjust_disposition"


func validate(state: GameState) -> CommandResult:
	if not Entities.exists(state, id):
		return CommandResult.fail("no entity '%s'" % id)
	return CommandResult.ok()


func apply(state: GameState) -> CommandResult:
	var entities: Dictionary = Entities.all(state)
	var entity: Dictionary = entities[id]
	var updated := clampi(int(entity.get("disposition", 0)) + delta,
		Entities.DISPOSITION_MIN, Entities.DISPOSITION_MAX)
	entity["disposition"] = updated
	entities[id] = entity
	state.set_value("entities", entities)
	return CommandResult.ok("%s disposition -> %d" % [id, updated], {"id": id, "disposition": updated})


static func from_args(args: Dictionary) -> Command:
	return AdjustDispositionCommand.new(String(args.get("id", "")), int(args.get("delta", 0)))
