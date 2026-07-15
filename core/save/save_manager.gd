class_name SaveManager
extends RefCounted

## Save/load and migrations. STUB SEAM — filled in milestone 1.
##
## Will serialize [GameState] plus module save-data (with version tags) and run
## migrations on load. For now it only exposes the seam so callers and tests can
## reference the type; the real format/versioning is deferred.

const SAVE_VERSION: int = 1


## Serialize game state to a dictionary. Real implementation adds module data + version.
func capture(state: GameState) -> Dictionary:
	# TODO(milestone-1): include per-module save-data and a migration version.
	return {"version": SAVE_VERSION, "state": state.to_dict()}


## Restore game state from a captured dictionary, running migrations as needed.
func restore(state: GameState, data: Dictionary) -> void:
	# TODO(milestone-1): run migrations from data["version"] to SAVE_VERSION.
	state.from_dict(data.get("state", {}))
