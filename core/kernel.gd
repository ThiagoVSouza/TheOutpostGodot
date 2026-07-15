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
var modules: ModuleRegistry
var screens: ScreenRegistry
var ai: AiBackend
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

	# 4. Command choke point (needs state).
	commands = CommandBus.new(state, events, log)

	# 5-6. Module + screen registries.
	modules = ModuleRegistry.new(log)
	screens = ScreenRegistry.new()

	# 7. AI seam — FakeAiBackend by default; orchestrator wired in a later milestone.
	ai = FakeAiBackend.new()

	# 8. Deferred seams: constructed so their types/interfaces exist, inert for now.
	clock = GameClock.new()
	scheduler = Scheduler.new()
	saves = SaveManager.new()
	workflows = WorkflowEngine.new()

	# 9. Discover + load modules; each registers its content through the seams above.
	modules.load_all(self)
	log.info("Kernel", "Boot complete: %d module(s) loaded" % modules.loaded_modules().size())

	# 10. Announce readiness; the boot scene shows the start screen.
	events.emit("kernel_booted", {})


func is_booted() -> bool:
	return _booted
