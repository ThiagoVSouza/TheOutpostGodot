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

	kernel.log.info(
		"BaseGame",
		"Registered dice tool, grant_resource command, chat screen, month-end workflow"
	)


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
