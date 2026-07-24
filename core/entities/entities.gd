class_name Entities
extends RefCounted

## The world's cast (M5/M7 engine block): the characters, factions and locations the game and its
## plots refer to. An entity is authoritative game state under GameState["entities"][id], mutated
## only through whitelisted commands (D4 — `create_entity`, `adjust_disposition`) and saved by B2
## with the rest of GameState. **This is the engine, not content:** no cast is authored here — a
## module or a new-game workflow creates entities through the commands. Plans and memories already
## carry `subjects: [entity ids]`; these helpers give those ids identity.
##
## An entity is a plain Dictionary:
##   { id, type: "character"|"faction"|"location", name,
##     disposition: int(-100..100, toward the player), traits: [String], status: "active" }

const CHARACTER := "character"
const FACTION := "faction"
const LOCATION := "location"
const TYPES: PackedStringArray = [CHARACTER, FACTION, LOCATION]

const DISPOSITION_MIN := -100
const DISPOSITION_MAX := 100


static func new_entity(id: String, type: String, name: String, disposition: int = 0,
		traits: Array = []) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"name": name,
		"disposition": clampi(disposition, DISPOSITION_MIN, DISPOSITION_MAX),
		"traits": traits.duplicate(),
		"status": "active",
	}


static func all(state: GameState) -> Dictionary:
	return state.get_value("entities", {})


static func exists(state: GameState, id: String) -> bool:
	return all(state).has(id)


static func get_entity(state: GameState, id: String) -> Dictionary:
	return all(state).get(id, {})


static func by_type(state: GameState, type: String) -> Array:
	var out: Array = []
	for entity: Dictionary in all(state).values():
		if String(entity.get("type", "")) == type:
			out.append(entity)
	return out


static func disposition(state: GameState, id: String) -> int:
	return int(get_entity(state, id).get("disposition", 0))


## Resolve subject ids (as carried by plans and memories) to their entities, skipping unknowns.
## The seam that gives a plan's `subjects` identity — a name, a type, a disposition — for context
## or display. Content decides how to use it; the block just makes it available.
static func resolve(state: GameState, ids: Array) -> Array:
	var out: Array = []
	var table: Dictionary = all(state)
	for id: Variant in ids:
		if table.has(id):
			out.append(table[id])
	return out


static func names(state: GameState, ids: Array) -> Array:
	var out: Array = []
	for entity: Dictionary in resolve(state, ids):
		out.append(String(entity.get("name", entity.get("id", ""))))
	return out
