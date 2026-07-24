extends Module

## Entry point for the base-game module.
##
## Registers the base game's content with the kernel through stable seams: the AI dice
## tool, the whitelisted grant_resource command, the chat screen (start screen), and the
## end-of-month workflow. Systems, more tools/commands and screens are added here (or in
## sub-registrars) in later milestones.

const CHAT_SCREEN := preload("res://modules/base_game/screens/chat_screen.tscn")
const PLAYGROUND_SCREEN := preload("res://modules/base_game/screens/playground_screen.tscn")
const DiceTool := preload("res://modules/base_game/ai_tools/dice_tool.gd")

const SCREEN_ID := "base_game.chat"
const PLAYGROUND_ID := "base_game.playground"


func register(kernel: GameKernel) -> void:
	# AI tool the game master may call.
	kernel.tools.register(DiceTool.new())

	# Whitelist the only resource-mutating command the AI/workflows may produce.
	kernel.command_registry.register("grant_resource", GrantResourceCommand.from_args)
	# The only sanctioned way a background plan's direction changes (M5, D36) — it owns the
	# intensity nudge, the hysteresis band and the code-owned plot mutation via pure Plans logic.
	kernel.command_registry.register("apply_plan_transition", ApplyPlanTransitionCommand.from_args)
	# The world's cast engine (M5/M7): bring an entity into being, and move its disposition toward
	# the player. The whitelisted mechanisms; the actual cast is content authored later.
	kernel.command_registry.register("create_entity", CreateEntityCommand.from_args)
	kernel.command_registry.register("adjust_disposition", AdjustDispositionCommand.from_args)

	# Start screen: the plain chat, or the dev playground (chat + live trace breakdown) when
	# OUTPOST_PLAYGROUND=1. The first screen registered as start wins.
	var use_playground := OS.get_environment("OUTPOST_PLAYGROUND") == "1"
	kernel.screens.register(PLAYGROUND_ID, PLAYGROUND_SCREEN, use_playground)
	kernel.screens.register(SCREEN_ID, CHAT_SCREEN, not use_playground)

	# Run a short chronicle workflow at the end of every month.
	kernel.scheduler.schedule_monthly(_end_of_month_workflow())

	# --- M3b: the orchestration a player turn runs through (the ribosome, D30) ---
	# The closed intent set the model classifies into (grammar-constrained, D19). Five labels
	# plus the catch-all: two of them are gathering actions that differ only in their balance
	# data, one resolves with no roll at all, and one is refused by its own preconditions —
	# deliberately different workflow *shapes*, so the skeleton proves the routing rather than
	# one lucky path. `general` is the honest home for anything out of set.
	# The labels carry their meaning with them: the grammar decides what the model *may* answer,
	# these decide whether it answers sensibly. `general` in particular has to say out loud that
	# it is the decline option, or every message gets forced into an action that resolves.
	kernel.prompt_families.register(PromptFamily.new("classify_intent",
		PackedStringArray(["forage", "hunt", "rest", "build", "general"]),
		{
			"forage": "gathering plants, berries, roots or other food from the land",
			"hunt": "pursuing and killing animals for meat",
			"rest": "the settlement pauses, works less, sleeps or recovers",
			"build": "constructing, repairing or extending a building or structure",
			"general": "anything else, including idle talk, questions, feelings and whimsy — "
				+ "choose this whenever the message is not clearly one of the actions above",
		}))
	# The closed transition set a background plan advances by (M5, D36, Fork 2). One universal set
	# for every plan — `mutate` is deliberately absent, because the plan-tick measurement showed a
	# 2B never picks "the plot changes character" from a description; that is code's job, in the
	# command's template logic. The descriptions matter for the same reason as the intent set (D33):
	# `hold`, `de_escalate` and `resolve` all look like "nothing much happened" without a meaning.
	kernel.prompt_families.register(PromptFamily.new("classify_plan_transition",
		Plans.TRANSITIONS,
		{
			"escalate": "the situation intensifies — those involved push harder, raise the stakes, "
				+ "or move toward open conflict",
			"hold": "nothing decisive changed; the situation continues roughly as it was",
			"de_escalate": "tension eases — those involved back down, are appeased, or the threat recedes",
			"resolve": "the situation has reached its end — settled, concluded, or no longer active",
		}))
	_register_tables(kernel)
	# The entry workflow (the one hardcoded id) and the intent workflows it dispatches to.
	kernel.workflow_registry.register(_entry_workflow())
	kernel.workflow_registry.register(_gather_workflow("forage"))
	kernel.workflow_registry.register(_gather_workflow("hunt"))
	kernel.workflow_registry.register(_rest_workflow())
	kernel.workflow_registry.register(_build_workflow())
	# The tick every background plan runs (M5, D36): classify the transition from the closed set,
	# then let the command own the numbers. One workflow serves every template because plot
	# mutation lives in the command, not here (Fork 2).
	kernel.workflow_registry.register(_plan_tick_workflow())
	# Verification scaffolding, not game content: a workflow that stops to ask, so the
	# confirm → suspend → resume path is drivable in the running app until authored content
	# uses `confirm` for real. Registered **at boot** rather than on demand — a suspended
	# instance names its workflow by id, so one registered lazily cannot be resumed after a
	# restart, and the player's pending question becomes unanswerable.
	if OS.is_debug_build():
		kernel.workflow_registry.register(_dev_confirm_workflow())

	kernel.log.info(
		"BaseGame",
		"Registered dice tool, grant_resource command, chat screen, month-end + orchestration workflows"
	)


## Dev-only (see `register`): stops to ask, then grants if the player agrees.
func _dev_confirm_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "dev_confirm", "version": 1, "origin": "base_game", "params": {},
		"steps": [
			{"op": "confirm", "msg": "dev.confirm_grant", "scope": {"resource": "food", "amount": 2}},
			{"op": "run_command", "name": "grant_resource",
			 "args": {"resource": "food", "amount": 2}},
			{"op": "narrate", "instruction": "the stores are quietly topped up",
			 "context": {"outcome": "two units of food were added"},
			 "verbosity": "short", "language": "en"},
		]
	}


## Balance data (D24): every number a turn can produce lives here, editable without a rebuild.
##
## The `*_outcome` tables are **range tables** — a d20 total maps to the *band* it falls in.
## That is what keeps the raw die out of the game: the workflow branches on the band's name and
## hands the narrator that word, so no step downstream of the roll ever sees `19`. It also puts
## the success threshold in the data instead of a magic number in an authored `if`.
func _register_tables(kernel: GameKernel) -> void:
	# Foraging is the safe option: it succeeds more often than not, and pays modestly.
	kernel.dsl_tables.register_ranges("forage_outcome", [
		{"to": 8, "value": "meagre"},
		{"from": 8, "to": 16, "value": "steady"},
		{"from": 16, "value": "bountiful"},
	])
	kernel.dsl_tables.register("forage_yield", {"meagre": 0, "steady": 3, "bountiful": 5})

	# Hunting is the gamble: it fails half the time and pays roughly double when it lands.
	kernel.dsl_tables.register_ranges("hunt_outcome", [
		{"to": 11, "value": "meagre"},
		{"from": 11, "to": 18, "value": "steady"},
		{"from": 18, "value": "bountiful"},
	])
	kernel.dsl_tables.register("hunt_yield", {"meagre": 0, "steady": 6, "bountiful": 11})

	# What the outpost must have in store before a work crew can be fed off the job.
	kernel.dsl_tables.register("build_cost", {"food": 10})


## The ribosome's entry workflow (D30): real guardrails, then classify the intent from a closed
## set, then hand off to the intent's workflow. Routing is an explicit authored chain rather
## than "dispatch to whatever the model said" — `dispatch.workflow` is a literal by design, so
## the set of reachable workflows is auditable here and the model only picks among them.
## An unrecognized intent is acknowledged in prose rather than resolved — the "I sing to the
## goats" case has no mechanical stake.
func _entry_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "orchestration_entry", "version": 1, "origin": "base_game",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "require", "cond": ["@message", "!=", ""],
			 "fail_code": "empty_message", "fail_msg": "guardrails.empty"},
			{"op": "ai", "family": "classify_intent", "facts": {"message": "@message"}, "as": "$$intent"},
			{"op": "if", "cond": ["$$intent", "==", "forage"],
			 "then": [{"op": "dispatch", "workflow": "forage", "args": {"message": "@message"}}],
			 "elif": [
				{"cond": ["$$intent", "==", "hunt"],
				 "then": [{"op": "dispatch", "workflow": "hunt", "args": {"message": "@message"}}]},
				{"cond": ["$$intent", "==", "rest"],
				 "then": [{"op": "dispatch", "workflow": "rest", "args": {"message": "@message"}}]},
				{"cond": ["$$intent", "==", "build"],
				 "then": [{"op": "dispatch", "workflow": "build", "args": {"message": "@message"}}]},
			 ],
			 # The catch-all. The instruction states what *happened* — the words were heard and
			 # nothing was set in motion — rather than instructing the narrator to "acknowledge",
			 # which it will otherwise repeat back as the event itself (worst at `topics`). The
			 # unresolved state is also a decided fact in the context, so the model has something
			 # true to say instead of inventing an outcome nobody adjudicated.
			 "else": [{"op": "narrate",
					   "instruction": "the outpost hears the player's words and nothing is set in motion",
					   "context": {"message": "@message", "outcome": "nothing was resolved this turn"},
					   "verbosity": "short", "language": "en"}]}
		]
	}


## The gathering intents (economy anchor), one workflow per intent from one shape: a seeded roll
## picks an outcome *band* from a rule table, the band picks the reward from another table (never
## the model), the command owns the state change, and the model only narrates the decided result
## (D4). `forage` and `hunt` differ purely in the data their tables hold.
func _gather_workflow(intent: String) -> Dictionary:
	return {
		"op": "workflow", "id": intent, "version": 1, "origin": "base_game",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "roll", "dice": "1d20", "as": "$$roll"},
			# The die becomes a word here and stays a word from here on.
			{"op": "let", "as": "$$outcome",
			 "value": {"op": "table_get", "table": "%s_outcome" % intent, "key": "$$roll"}},
			{"op": "let", "as": "$$amount",
			 "value": {"op": "table_get", "table": "%s_yield" % intent, "key": "$$outcome"}},
			{"op": "if", "cond": ["$$amount", ">", 0],
			 "then": [
				{"op": "run_command", "name": "grant_resource",
				 "args": {"resource": "food", "amount": "$$amount"}},
				{"op": "narrate", "instruction": _gather_success_instruction(intent),
				 "context": {"amount": "$$amount", "outcome": "$$outcome"},
				 "verbosity": "short", "language": "en"}
			 ],
			 "else": [
				{"op": "narrate", "instruction": _gather_failure_instruction(intent),
				 "context": {"outcome": "$$outcome"}, "verbosity": "short", "language": "en"}
			 ]}
		]
	}


func _gather_success_instruction(intent: String) -> String:
	if intent == "hunt":
		return "the hunting party returns to the outpost carrying meat"
	return "the foraging party returns to the outpost carrying food"


func _gather_failure_instruction(intent: String) -> String:
	if intent == "hunt":
		return "the hunting party returns to the outpost having killed nothing"
	return "the foraging party returns to the outpost empty-handed"


## Resting: a turn that resolves with no roll at all. The plan calls for workflows whose shape
## decides what happens — "a seeded roll if the action warrants one, or none at all" — and this
## is the one that warrants none. Nothing is granted; the day simply passes.
func _rest_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "rest", "version": 1, "origin": "base_game",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "narrate", "instruction": "the outpost spends the day at rest and nothing befalls it",
			 "context": {"outcome": "the day passes quietly"},
			 "verbosity": "short", "language": "en"}
		]
	}


## Building: a turn a precondition can refuse. The refusal is fiction the player reads, not a
## `require` failure — an outcome the rules declined is still an outcome, and the narrator is
## told plainly that the work did not begin so it cannot imply that it did.
func _build_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "build", "version": 1, "origin": "base_game",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "let", "as": "$$stored",
			 "value": {"op": "read_state", "path": ["resources", "food"]}},
			{"op": "let", "as": "$$needed",
			 "value": {"op": "table_get", "table": "build_cost", "key": "food"}},
			{"op": "if", "cond": ["$$stored", ">=", "$$needed"],
			 "then": [
				{"op": "narrate", "instruction": "a work crew is assembled and building begins",
				 "context": {"outcome": "the work begins"}, "verbosity": "short", "language": "en"}
			 ],
			 "else": [
				{"op": "narrate",
				 "instruction": "there is too little food stored to feed a work crew, so the building does not begin",
				 # Only the verdict, not the numbers: an outpost with no food entry at all reads
				 # `$$stored` as null (comparison treats that as "not enough", correctly), and a
				 # literal null has no business reaching a prompt.
				 "context": {"outcome": "the work does not begin"},
				 "verbosity": "short", "language": "en"}
			 ]}
		]
	}


## A background plan's tick (M5, D36). The ticker passes the plan's fields as params; the model
## reads the situation and the band *word* (never the raw intensity, D33) and picks one transition
## from the closed set; the command applies it — bounded nudge, hysteresis band, code-owned plot
## mutation, next wake — so no number here is the model's. This is the plan-format walking
## skeleton: real "latest developments" from memory retrieval are the next M5 piece.
func _plan_tick_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "plan_tick", "version": 1, "origin": "base_game",
		"params": {
			"plan_id": {"type": "string", "required": true},
			"situation": {"type": "string"},
			"direction": {"type": "string"},
			"latest": {"type": "string"},
			"subjects": {"type": "array"},
			"today": {"type": "int"},
		},
		"steps": [
			{"op": "ai", "family": "classify_plan_transition",
			 "facts": {"situation": "@situation", "direction": "@direction", "latest": "@latest"},
			 "as": "$$transition"},
			{"op": "run_command", "name": "apply_plan_transition",
			 "args": {"plan_id": "@plan_id", "transition": "$$transition", "today": "@today"}},
			# Record what happened so the next tick can retrieve it (D37). The memory is the
			# *development* (what changed); the plan's situation carries the who — so a generic line
			# tagged with the subjects reads coherently when retrieved beside the situation, and the
			# DSL never has to assemble a string. `else` is the `hold` case.
			{"op": "if", "cond": ["$$transition", "==", "escalate"],
			 "then": [_remember_development("Tensions around the matter rose further.")],
			 "elif": [
				{"cond": ["$$transition", "==", "de_escalate"],
				 "then": [_remember_development("Tensions around the matter eased.")]},
				{"cond": ["$$transition", "==", "resolve"],
				 "then": [_remember_development("The matter reached its conclusion.")]},
			 ],
			 "else": [_remember_development("Little changed in the matter this time.")]},
		]
	}


func _remember_development(text: String) -> Dictionary:
	return {"op": "remember", "text": text, "subjects": "@subjects", "day": "@today", "kind": "plan"}


## A tiny, validated workflow on the A3 kernel: read the food stores, emit a localizable
## month-end line (key + values, never an assembled string — D24 i18n discipline), and grant
## a little upkeep gold. Demonstrates the DSL end to end.
func _end_of_month_workflow() -> Dictionary:
	return {
		"op": "workflow",
		"id": "end_of_month_report",
		"version": 1,
		"origin": "base_game",
		"params": {},
		"steps": [
			{"op": "let", "as": "$$food",
			 "value": {"op": "read_state", "path": ["resources", "food"]}},
			{"op": "emit", "msg": "base_game.month_end", "values": {"food": "$$food"}},
			{"op": "run_command", "name": "grant_resource", "args": {"resource": "gold", "amount": 1}},
		],
	}
