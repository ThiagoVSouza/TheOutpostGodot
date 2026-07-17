class_name GameKernel
extends Node

## The core kernel: stable infrastructure the whole game and all modules build on.
##
## Registered as the "Kernel" autoload, so it is reachable globally as `Kernel`.
## (The script is named [GameKernel] to avoid colliding with the autoload's own name.)
## It boots its subsystems in a deterministic order — each only depends on ones already
## constructed — then loads modules, which register their content through these seams.
## The kernel deliberately contains NO gameplay/DLC logic.

# --- Subsystems (constructed in boot()) ---
var log: GameLog
var events: EventBus
var state: GameState
var commands: CommandBus
var command_registry: CommandRegistry
var tools: ToolRegistry
var modules: ModuleRegistry
var screens: ScreenRegistry
var ai: AiBackend
var ai_orchestrator: AiOrchestrator
var clock: GameClock
var scheduler: Scheduler
var saves: SaveManager
var workflows: WorkflowEngine

var _booted: bool = false


func _ready() -> void:
	# Autoloads ready before the main (boot) scene, so subsystems and module-registered
	# screens are available by the time the boot scene runs.
	boot()


## Construct subsystems in dependency order and load modules. Idempotent.
func boot() -> void:
	if _booted:
		return
	_booted = true

	# 1. Diagnostics first so everything after can log.
	log = GameLog.new()
	log.info("Kernel", "Booting The Outpost kernel")

	# 2-3. Communication + state.
	events = EventBus.new()
	state = GameState.new()

	# 4. Command choke point (needs state) + the whitelist of AI-producible commands.
	commands = CommandBus.new(state, events, log)
	command_registry = CommandRegistry.new()

	# 5. Registries modules populate.
	tools = ToolRegistry.new()
	modules = ModuleRegistry.new(log)
	screens = ScreenRegistry.new()

	# 6. AI seam — FakeAiBackend by default; real backends swap in later.
	ai = _create_ai_backend()

	# 7. Calendar + workflow subsystems (scheduler listens on the event bus and runs
	#    due workflows through the engine).
	workflows = WorkflowEngine.new()
	clock = GameClock.new(events)
	scheduler = Scheduler.new(events, workflows, self)
	saves = SaveManager.new()

	# 8. AI orchestrator ties the above together (needs tools, command_registry, ai,
	#    commands, workflows, scheduler, events).
	ai_orchestrator = AiOrchestrator.new(self)

	# 9. Discover + load modules; each registers its content through the seams above.
	modules.load_all(self)
	log.info("Kernel", "Boot complete: %d module(s) loaded" % modules.loaded_modules().size())

	# 10. Announce readiness; the boot scene shows the start screen.
	events.emit("kernel_booted", {})


func is_booted() -> bool:
	return _booted


func _create_ai_backend() -> AiBackend:
	var selected := OS.get_environment("OUTPOST_AI_BACKEND").strip_edges().to_lower()
	if selected.is_empty() or selected == "fake":
		return FakeAiBackend.new()
	if selected == "remote-llama":
		var endpoint := OS.get_environment("OUTPOST_AI_ENDPOINT").strip_edges()
		if endpoint.is_empty():
			endpoint = RemoteLlamaBackend.DEFAULT_ENDPOINT
		var key := OS.get_environment("OUTPOST_AI_API_KEY")
		log.info("Kernel", "Using remote llama backend at %s" % endpoint)
		return RemoteLlamaBackend.new(self, endpoint, key)

	log.warn("Kernel", "Unknown OUTPOST_AI_BACKEND '%s'; using fake backend" % selected)
	return FakeAiBackend.new()
