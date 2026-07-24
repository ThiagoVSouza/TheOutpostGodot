class_name CreatePlanCommand
extends Command

## Bring a background plan into being (M5, D36/D37). The whitelisted, only way a plan first enters
## `GameState["plans"]` — until now nothing did in production (apply_plan_transition can only modify
## an existing plan, and mutation only spawns a follow-up from a ticking one). A new-game seed or a
## world event creates the initial plot through this; once present, `PlanTicker` picks it up on the
## next `day_passed`. Refuses a blank or duplicate id so a seed can't quietly clobber a live plot.

var id: String
var template: String
var tick_workflow: String
var subjects: Array
var situation: String
var next_wake: int
var intensity: int
var band: String


func _init(plan_id: String = "", plan_template: String = "", workflow_id: String = "plan_tick",
		plan_subjects: Array = [], plan_situation: String = "", wake_day: int = 30,
		starting_intensity: int = 40, starting_band: String = "tense") -> void:
	id = plan_id
	template = plan_template
	tick_workflow = workflow_id
	subjects = plan_subjects
	situation = plan_situation
	next_wake = wake_day
	intensity = starting_intensity
	band = starting_band


func command_name() -> String:
	return "create_plan"


func validate(state: GameState) -> CommandResult:
	if id.strip_edges().is_empty():
		return CommandResult.fail("plan id is required")
	if (state.get_value("plans", {}) as Dictionary).has(id):
		return CommandResult.fail("plan '%s' already exists" % id)
	return CommandResult.ok()


func apply(state: GameState) -> CommandResult:
	var plans: Dictionary = state.get_value("plans", {})
	plans[id] = Plans.new_plan(id, template, tick_workflow, subjects, situation, next_wake,
		intensity, band)
	state.set_value("plans", plans)
	return CommandResult.ok("created plan '%s'" % id, {"id": id, "template": template})


static func from_args(args: Dictionary) -> Command:
	var subjects_v: Variant = args.get("subjects", [])
	return CreatePlanCommand.new(
		String(args.get("id", "")),
		String(args.get("template", "")),
		String(args.get("tick_workflow", "plan_tick")),
		subjects_v if subjects_v is Array else [],
		String(args.get("situation", "")),
		int(args.get("next_wake", 30)),
		int(args.get("intensity", 40)),
		String(args.get("band", "tense")))
