extends AiTool

## "roll_die" — a controlled dice-rolling tool the AI may call.
##
## Deterministic when given a seed (used by tests and recorded/replay mode). Returns data
## only; it never mutates game state. Args: { sides:int=6, count:int=1, seed?:int }.

const MAX_DICE: int = 100


func tool_name() -> String:
	return "roll_die"


func params_schema() -> Dictionary:
	return {
		"sides": {"type": "int", "default": 6, "min": 1},
		"count": {"type": "int", "default": 1, "min": 1, "max": MAX_DICE},
		"seed": {"type": "int", "optional": true},
	}


func execute(args: Dictionary, _kernel: GameKernel) -> Dictionary:
	var sides := maxi(int(args.get("sides", 6)), 1)
	var count := clampi(int(args.get("count", 1)), 1, MAX_DICE)
	var rng := RandomNumberGenerator.new()
	if args.has("seed"):
		rng.seed = int(args["seed"])
	else:
		rng.randomize()

	var rolls: Array = []
	var total := 0
	for _i in count:
		var r := rng.randi_range(1, sides)
		rolls.append(r)
		total += r
	return {"sides": sides, "count": count, "rolls": rolls, "total": total}
