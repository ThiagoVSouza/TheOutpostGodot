extends Module

## Entry point for the base-game module.
##
## Registers the base game's content with the kernel through stable seams: the AI dice
## tool, the whitelisted grant_resource command, the chat screen (start screen), and the
## end-of-month workflow. Systems, more tools/commands and screens are added here (or in
## sub-registrars) in later milestones.

const CHAT_SCREEN := preload("res://modules/base_game/screens/chat_screen.tscn")
const DiceTool := preload("res://modules/base_game/ai_tools/dice_tool.gd")

const SCREEN_ID := "base_game.chat"


func register(kernel: GameKernel) -> void:
	# AI tool the game master may call.
	kernel.tools.register(DiceTool.new())

	# Whitelist the only resource-mutating command the AI/workflows may produce.
	kernel.command_registry.register("grant_resource", GrantResourceCommand.from_args)

	# Start screen.
	kernel.screens.register(SCREEN_ID, CHAT_SCREEN, true)

	# Run a short chronicle workflow at the end of every month.
	kernel.scheduler.schedule_monthly(_end_of_month_workflow())

	# --- M3b: the orchestration a player turn runs through (the ribosome, D30) ---
	# The closed intent set the model classifies into (grammar-constrained, D19).
	kernel.prompt_families.register(PromptFamily.new("classify_intent",
		PackedStringArray(["forage", "general"])))
	# Balance numbers live in a tunable table, not in code (D24).
	kernel.dsl_tables.register("forage_yield", {"success": 5})
	# The entry workflow (the one hardcoded id) and the intent workflows it dispatches to.
	kernel.workflow_registry.register(_entry_workflow())
	kernel.workflow_registry.register(_forage_workflow())

	kernel.log.info(
		"BaseGame",
		"Registered dice tool, grant_resource command, chat screen, month-end + orchestration workflows"
	)


## The ribosome's entry workflow (D30): real guardrails, then classify the intent from a
## closed set, then hand off to the intent's workflow. An unrecognized intent is acknowledged
## in prose rather than resolved — the "I sing to the goats" case has no mechanical stake.
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
			 "else": [{"op": "narrate",
					   "instruction": "acknowledge the player's words without resolving an action",
					   "context": {"message": "@message"}, "verbosity": "short", "language": "en"}]}
		]
	}


## The forage intent (economy anchor): a seeded roll decides the outcome, the reward comes from
## a rule table (never the model), the command owns the state change, and the model only
## narrates the decided result (D4).
func _forage_workflow() -> Dictionary:
	return {
		"op": "workflow", "id": "forage", "version": 1, "origin": "base_game",
		"params": {"message": {"type": "string", "required": true}},
		"steps": [
			{"op": "roll", "dice": "1d20", "as": "$$roll"},
			{"op": "if", "cond": ["$$roll", ">=", 8],
			 "then": [
				{"op": "let", "as": "$$amount",
				 "value": {"op": "table_get", "table": "forage_yield", "key": "success"}},
				{"op": "run_command", "name": "grant_resource",
				 "args": {"resource": "food", "amount": "$$amount"}},
				{"op": "narrate", "instruction": "the foraging party returns with food",
				 "context": {"amount": "$$amount", "roll": "$$roll"}, "verbosity": "short", "language": "en"}
			 ],
			 "else": [
				{"op": "narrate", "instruction": "the foraging party returns empty-handed",
				 "context": {"roll": "$$roll"}, "verbosity": "short", "language": "en"}
			 ]}
		]
	}


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
