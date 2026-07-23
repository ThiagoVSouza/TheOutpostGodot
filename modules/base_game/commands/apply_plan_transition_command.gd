class_name ApplyPlanTransitionCommand
extends Command

## The only sanctioned way a plan's direction changes (D4/D30, D36). A tick workflow classifies a
## transition; this command owns what it does — the bounded intensity nudge, the hysteresis band,
## the code-owned plot mutation, the next wake — all via pure [Plans] logic, then writes the result
## back under GameState["plans"]. The model never supplies an amount here; it only chose which
## transition, from a grammar-constrained closed set.

var plan_id: String
var transition: String
var today: int


func _init(id: String = "", transition_label: String = "", on_day: int = 0) -> void:
	plan_id = id
	transition = transition_label
	today = on_day


func command_name() -> String:
	return "apply_plan_transition"


func validate(state: GameState) -> CommandResult:
	if plan_id.strip_edges().is_empty():
		return CommandResult.fail("plan_id is required")
	if not Plans.TRANSITIONS.has(transition):
		return CommandResult.fail("unknown transition '%s'" % transition)
	var plans: Dictionary = state.get_value("plans", {})
	if not plans.has(plan_id):
		return CommandResult.fail("no plan '%s'" % plan_id)
	return CommandResult.ok()


func apply(state: GameState) -> CommandResult:
	var plans: Dictionary = state.get_value("plans", {})
	var result: Dictionary = Plans.apply_transition(plans[plan_id], transition, today)
	plans[plan_id] = result["plan"]
	for spawned: Dictionary in result["spawned"]:
		plans[String(spawned["id"])] = spawned
	state.set_value("plans", plans)
	var direction: Dictionary = (result["plan"] as Dictionary).get("direction", {})
	return CommandResult.ok(
		"plan %s -> %s" % [plan_id, transition],
		{"plan_id": plan_id, "transition": transition,
		 "band": direction.get("band", ""), "intensity": direction.get("intensity", 0),
		 "spawned": (result["spawned"] as Array).size()})


## Factory for the CommandRegistry: builds a command from workflow-supplied args.
static func from_args(args: Dictionary) -> Command:
	return ApplyPlanTransitionCommand.new(
		String(args.get("plan_id", "")),
		String(args.get("transition", "")),
		int(args.get("today", 0)))
