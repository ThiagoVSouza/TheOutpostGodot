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
var ai_availability: AiAvailability
var llama_server_manager: LlamaServerManager
var ai_orchestrator: AiOrchestrator
var trace_writer: AiTraceWriter
var input_router: AiInputRouter
var clock: GameClock
var scheduler: Scheduler
var saves: SaveManager
var workflows: WorkflowEngine

# --- workflow DSL kernel (M3a: A2 validation layer + A3 runtime) ---
var globals: GlobalStore
var dsl_functions: DslFunctionRegistry
var dsl_tables: DslTableRegistry
var workflow_registry: WorkflowRegistry

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

	# 1b. Trace sink (A1, D21): JSONL + Markdown per orchestration, on by default in
	#     dev builds. No retention policy yet — that is M4's problem, which is exactly
	#     why the automated suite opts itself out (tools/test.ps1 sets OUTPOST_TEST_RUN)
	#     instead of writing unbounded files into a real dev's user:// on every run.
	#     Tests that exercise the writer itself construct their own, pointed at a
	#     scratch directory, same as ModuleRegistry's `root` override.
	var is_test_run := OS.get_environment("OUTPOST_TEST_RUN") == "1"
	trace_writer = AiTraceWriter.new("user://traces", OS.is_debug_build() and not is_test_run)

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

	# 6. AI seam — FakeAiBackend by default; real backends swap in later. Availability
	#    implements the T5 outage policy (D16 amendment); a provider closure keeps it
	#    correct across backend swaps.
	ai = _create_ai_backend()
	ai_availability = AiAvailability.new(events, func() -> AiBackend: return ai)

	# 7. Calendar + workflow subsystems (scheduler listens on the event bus and runs
	#    due workflows through the engine).
	workflows = WorkflowEngine.new()

	# 7b. Workflow DSL kernel (D24/D31): the global store, the fn/table registries the
	#     `fn`/`table_get` ops resolve names through, and the validated-definition registry.
	#     The A3 executor is constructed per run via WorkflowExecutor.for_kernel(self).
	globals = GlobalStore.new()
	dsl_functions = DslFunctionRegistry.new()
	dsl_tables = DslTableRegistry.new()
	workflow_registry = WorkflowRegistry.new()
	clock = GameClock.new(events)
	scheduler = Scheduler.new(events, workflows, self)
	saves = SaveManager.new()

	# 8. AI orchestrator ties the above together (needs tools, command_registry, ai,
	#    commands, workflows, scheduler, events).
	ai_orchestrator = AiOrchestrator.new(self)

	# 8b. Input-source seam (D18): all player text — typed, voice, replay — reaches
	#     the orchestrator through this router, never directly from a control.
	input_router = AiInputRouter.new(self)

	# 9. Discover + load modules; each registers its content through the seams above.
	modules.load_all(self)
	log.info("Kernel", "Boot complete: %d module(s) loaded" % modules.loaded_modules().size())

	# 10. Announce readiness; the boot scene shows the start screen.
	events.emit("kernel_booted", {})


func is_booted() -> bool:
	return _booted


func _exit_tree() -> void:
	if is_instance_valid(llama_server_manager):
		llama_server_manager.shutdown()


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
	if selected == "local-llama":
		return _create_local_llama_backend()

	log.warn("Kernel", "Unknown OUTPOST_AI_BACKEND '%s'; using fake backend" % selected)
	return FakeAiBackend.new()


func _create_local_llama_backend() -> AiBackend:
	const MODEL_CATALOG_PATH := "res://config/ai/model_catalog.tres"
	var catalog := load(MODEL_CATALOG_PATH) as ModelCatalog
	var requested_profile := OS.get_environment("OUTPOST_MODEL_PROFILE").strip_edges()
	var profile: ModelProfile = null
	if catalog != null:
		profile = catalog.profile(requested_profile) if not requested_profile.is_empty() else catalog.desktop_default()
	if profile == null:
		log.error("Kernel", "Local llama profile '%s' could not be loaded" % requested_profile)
	else:
		log.info("Kernel", "Using local llama profile %s" % profile.profile_id)
	var endpoint := OS.get_environment("OUTPOST_AI_ENDPOINT").strip_edges()
	if endpoint.is_empty():
		endpoint = RemoteLlamaBackend.DEFAULT_ENDPOINT
	var endpoint_base := endpoint.trim_suffix("/v1/chat/completions")
	llama_server_manager = LlamaServerManager.new(profile, endpoint_base)
	add_child(llama_server_manager)
	# Begin loading during kernel boot so a player who reaches the chat screen after a
	# cold launch is not also paying for process startup on their first submission.
	llama_server_manager.ensure_started()
	var key := OS.get_environment("OUTPOST_AI_API_KEY")
	var remote := RemoteLlamaBackend.new(self, endpoint, key)
	return LocalLlamaBackend.new(llama_server_manager, remote)
