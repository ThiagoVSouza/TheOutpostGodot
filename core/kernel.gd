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
## Module-contributed pages inside the running game shell, distinct from routed application screens.
var hud_panels: HudPanelRegistry
## Runtime screen navigation (the in-game boot flow). Stateless — swaps the one mounted screen.
var router: ScreenRouter
var ai: AiBackend
var ai_availability: AiAvailability
var llama_server_manager: LlamaServerManager
var ai_orchestrator: AiOrchestrator
var trace_writer: AiTraceWriter
var input_router: AiInputRouter
var clock: GameClock
var time_driver: TimeDriver
var scheduler: Scheduler
## Runs due background plans off the game clock (M5, D36). Stateless — plans live in [member state].
var plan_ticker: PlanTicker
## The game master's memory (M5, D37): an append-only, English, entity-tagged log. Persists as its
## own JSONL in the workspace dir, so [method SaveWorkspace.clear] wipes it on a new game or load.
var memories: MemoryStore
var saves: SaveManager
## The game in progress, on disk as separate parts — the cheap, frequent write (M4/B4a).
var workspace: SaveWorkspace
## Where the game is written and when. The boot flow starts it; the kernel only drives the
## turn checkpoint and the OS lifecycle saves (see [method _notification]).
var session: GameSession

# --- workflow DSL kernel (M3a: A2 validation layer + A3 runtime) ---
var globals: GlobalStore
var dsl_functions: DslFunctionRegistry
var dsl_tables: DslTableRegistry
var workflow_registry: WorkflowRegistry
## Owns suspended instances between the turn that suspended and the wake that resumes them
## (M4/B1). Part of the save contract.
var workflow_instances: WorkflowInstanceStore
var narrator: DslNarrator
var narration: NarrationSettings

## Music and sound effects, from cues modules declare in data. A child node, not a bare
## [RefCounted]: it owns [AudioStreamPlayer]s, which have to live in the tree.
var audio: AudioManager

## The player's app-level preferences (audio levels today), persisted outside any save — they belong
## to the person, not to a settlement.
var settings: AppSettings
var prompt_families: PromptFamilyRegistry
var ai_runner: DslAiRunner

## Shown when the hardware/gesture back button has nowhere in-app to go (Android UX pass). Built
## lazily and kept for the process lifetime rather than one per press — a `Window`-derived node,
## so it needs to be in the tree, and the kernel autoload is the one thing guaranteed to outlive
## every screen it might be asked for from.
var _exit_confirm: ModalDialog = null

## The frame the back button was last acted on. Android delivers `WM_GO_BACK_REQUEST` **twice** per
## press (measured on an S26 Ultra: two notifications ~2 ms apart), which without this made one press
## navigate two levels — the wizard jumped from step 2 straight to the main menu instead of step 1.
## One back action per frame; a real press cannot recur inside a single frame.
var _last_back_frame: int = -1

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

	# 1c. Audio. Early, and before modules register, so a module's `register` can declare its cues
	#     and the very first screen already has sound.
	audio = AudioManager.new(log)
	add_child(audio)
	# The player's own preferences, applied to the mixer before anything can be heard.
	settings = AppSettings.new()
	settings.load_from_disk()
	settings.apply_audio(audio)
	settings.apply_video()
	# Register the input actions and bind them (defaults, or the player's overrides). Before any
	# screen exists, so the first one mounted can already ask about actions rather than keycodes.
	InputActions.install(settings)
	# 1d. The real Theme (M8 Phase 2), before any screen exists so nothing ever renders a frame in
	# Godot's stock light theme. Root-viewport-wide rather than per-screen: every default control a
	# screen builds picks it up automatically, including dialogs no screen owns (the exit-confirm
	# dialog `_ensure_exit_confirm` builds on the kernel itself).
	get_tree().root.theme = OutpostTheme.build()
	# And the one app-wide default a Theme cannot carry: the pointer turning into a hand over anything
	# clickable. `mouse_default_cursor_shape` is a node property, not a theme item.
	UiSkin.watch_cursors(get_tree())

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
	hud_panels = HudPanelRegistry.new()
	# Screen navigation + the core app-shell screens (splash → loading → menu → new game → load).
	# Registered before modules so the router can reach them; the boot scene sets the host and the
	# first screen. Modules still register their own game screens (e.g. base_game.chat).
	router = ScreenRouter.new(screens)
	# Every screen's buttons get the click sound here rather than screen by screen: a UI sound that
	# some controls make and others do not reads as a bug, and hand-wiring drifts into exactly that.
	router.screen_mounted.connect(_on_screen_mounted)
	AppShell.register_screens(self)

	# 6. AI seam — FakeAiBackend by default; real backends swap in later. Availability
	#    implements the T5 outage policy (D16 amendment); a provider closure keeps it
	#    correct across backend swaps.
	ai = _create_ai_backend()
	ai_availability = AiAvailability.new(events, func() -> AiBackend: return ai)

	# 7. Workflow DSL kernel (D24/D31): the global store, the fn/table registries the
	#    `fn`/`table_get` ops resolve names through, and the validated-definition registry.
	#    The A3 executor is constructed per run via WorkflowExecutor.for_kernel(self).
	globals = GlobalStore.new()
	dsl_functions = DslFunctionRegistry.new()
	dsl_tables = DslTableRegistry.new()
	workflow_registry = WorkflowRegistry.new()
	workflow_instances = WorkflowInstanceStore.new()
	# The `ai`/`narrate` seams (M3b). Against a real backend they call the model
	# (grammar-constrained classify — D19; bounded prose — D4/D29, with the per-call timeout and
	# T5 reporting living at the seam, D22/D30); against the fake they stay deterministic.
	prompt_families = PromptFamilyRegistry.new()
	# The player's reading-length preference, applied to every `narrate` op by the executor.
	narration = NarrationSettings.new()
	if ai is FakeAiBackend:
		narrator = FakeNarrator.new()
		ai_runner = FakeAiRunner.new()
	else:
		narrator = LlamaNarrator.new(self)
		ai_runner = LlamaAiRunner.new(self)

	# 7b. Calendar + scheduler: the scheduler listens on the event bus and runs due
	#     workflows on the DSL kernel above (validated when scheduled, run via the executor).
	clock = GameClock.new(events)
	time_driver = TimeDriver.new(clock, func() -> bool: return is_world_time_gated(), not is_test_run)
	add_child(time_driver)
	scheduler = Scheduler.new(events, self)
	saves = SaveManager.new()
	workspace = SaveWorkspace.new()
	# The game master's memory (M5, D37): its own append-only JSONL in the workspace dir, so a new
	# game or a load wipes it with the rest of the workspace (D34's replace-never-merge, for free).
	# In-memory only under the test runner, so an automated run never writes into a real user://.
	memories = MemoryStore.new("%s/memories.jsonl" % workspace.dir, not is_test_run)
	# Constructed, but deliberately does not load anything here: boot() must stay a pure
	# wiring step so tests get a clean world, and *when* to resume is the boot flow's call.
	session = GameSession.new(self)
	# The kernel owns this subscription rather than the session doing it itself: the session is
	# RefCounted and reaches the bus through the kernel, so a handler capturing it would form
	# the leaking cycle the T1 notes warn about. This node's lifetime is explicit.
	#
	# A completed turn is the natural checkpoint point — the world is consistent, the player is
	# reading the reply, and nothing is mid-flight. There is no dirty-flag plumbing behind this:
	# the workspace compares each part's content and writes only what actually moved, so a
	# checkpoint after a turn that changed nothing costs a comparison and no I/O.
	events.subscribe(AiInputRouter.EVENT_TURN_COMPLETED, _on_turn_completed)
	# The runtime preference objects are derived from the current game, so they have to be
	# re-derived every time the current game changes — on a fresh game *and* on a load. Doing only
	# the former is how the last game's settings quietly govern the one just loaded, which is the
	# same bleed the load-isolation contract above exists to prevent.
	events.subscribe("new_game_started", _on_new_game_became_current)
	events.subscribe("game_loaded", _on_loaded_game_became_current)

	# 8. AI orchestrator ties the above together (needs tools, command_registry, ai,
	#    commands, workflows, scheduler, events).
	ai_orchestrator = AiOrchestrator.new(self)

	# 8b. Input-source seam (D18): all player text — typed, voice, replay — reaches
	#     the orchestrator through this router, never directly from a control.
	input_router = AiInputRouter.new(self)

	# 8c. Background plans (M5, D36): runs due plan ticks off the clock. Stateless — plans live
	#     in GameState — and separate from the Scheduler because a tick needs its plan's id as
	#     context, where the scheduler runs param-less definitions.
	plan_ticker = PlanTicker.new(self)

	# 9. Discover + load modules; each registers its content through the seams above.
	modules.load_all(self)
	log.info("Kernel", "Boot complete: %d module(s) loaded" % modules.loaded_modules().size())

	# 10. Announce readiness; the boot scene shows the start screen.
	events.emit("kernel_booted", {})


func is_booted() -> bool:
	return _booted


func _on_turn_completed(_payload: Dictionary) -> void:
	if session != null:
		session.checkpoint("turn")


func _on_screen_mounted(_id: String, screen: Node) -> void:
	if audio != null:
		audio.wire_clicks(screen)
	if time_driver != null:
		time_driver.set_active(_id == "base_game.chat")


func _on_new_game_became_current(_payload: Dictionary) -> void:
	apply_player_preferences()
	if time_driver != null:
		time_driver.start_new_game()


func _on_loaded_game_became_current(_payload: Dictionary) -> void:
	apply_player_preferences()
	if time_driver != null:
		time_driver.loaded_game()


## The world gate is deliberately kernel-owned: the time driver reads it, and the HUD reads the
## same predicate for event mode. Nothing here knows which UI happens to expose a confirmation.
func is_world_time_gated() -> bool:
	return (ai_orchestrator != null and ai_orchestrator.is_busy()) \
		or (workflow_instances != null and not workflow_instances.pending_confirmations().is_empty()) \
		or (plan_ticker != null and plan_ticker.is_draining())


## Point the runtime preference objects at the current game's stored answers (the new-game wizard's
## Settings step). These objects are not saved and hold nothing authoritative — they are re-derived
## from [GameState] here, which is why the load-isolation contract can leave them alone.
##
## A game with no stored preference gets the class default rather than whatever the last game set,
## so an older save reads as "unset", never as "inherit".
func apply_player_preferences() -> void:
	if state == null or narration == null:
		return
	var profile: Dictionary = state.get_value(GameSession.PROFILE_STATE_KEY, {})
	var stored := String(profile.get(GameSession.PROFILE_VERBOSITY, ""))
	narration.set_level(stored if NarrationSettings.is_level(stored)
		else NarrationSettings.LEVEL_SHORT)


func _exit_tree() -> void:
	if is_instance_valid(llama_server_manager):
		llama_server_manager.shutdown()
	# Cut, not fade: there is no next frame to fade in, and a playback still open when the process
	# ends is reported as a leaked instance.
	if is_instance_valid(audio):
		audio.stop_music(false)


## The last moments we are guaranteed to run code (M4/B4a). On Android the OS can kill a
## backgrounded app without warning and never asks first, so the save taken when we are *told*
## we are leaving the foreground is the only one that is genuinely guaranteed — the per-turn
## autosave merely limits how much a hard kill can cost.
##
## `APPLICATION_PAUSED` is the Android/iOS background signal; `WM_CLOSE_REQUEST` is the desktop
## window close; `WM_GO_BACK_REQUEST` is the Android back button, which can end the app.
func _notification(what: int) -> void:
	if session == null:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			session.save_on_lifecycle_event("app_paused")
		NOTIFICATION_WM_CLOSE_REQUEST:
			session.save_on_lifecycle_event("app_closing")
		NOTIFICATION_WM_GO_BACK_REQUEST:
			session.save_on_lifecycle_event("app_back")
			_handle_hardware_back()


## The Android hardware/gesture back button (Android UX pass, 2026-07-26). `application/config
## .quit_on_go_back` is off (project.godot), so this is the only thing that decides what happens —
## previously nothing did, and the OS silently killed the app with no warning. What was actually
## missing was never state (the lifecycle save above already runs unconditionally, first), it was
## a screen vanishing without asking.
##
## The mounted screen gets first refusal: if it implements `on_hardware_back() -> bool` and returns
## true, it decided for itself (typically by doing exactly what its own on-screen Back/Cancel button
## does) and nothing further happens here. Anything else — no such method, or one that declines —
## falls through to a confirm-to-exit dialog rather than quitting outright.
## Ask to go back, from wherever the request came from — Android's gesture/hardware back, or the
## `back_close` key on a desktop. Both mean the same thing to the player, so both land here.
func request_back() -> void:
	_handle_hardware_back()


## Show the one process-owned exit confirmation. An on-screen Exit Game action must use this rather
## than making a second dialog, so hardware Back and the main menu always ask the same question.
func request_exit() -> void:
	var dialog := _ensure_exit_confirm()
	# The dialog is still built in headless tests, but only a real display server can show it.
	if DisplayServer.get_name() != "headless":
		dialog.open()


func _handle_hardware_back() -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_back_frame:
		return  # the duplicate notification Android sends for the same press
	_last_back_frame = frame
	var screen: Node = router.current_screen() if router != null else null
	if screen != null and screen.has_method("on_hardware_back") and bool(screen.call("on_hardware_back")):
		return
	request_exit()
	# The headless test runner has no real display server to pop a Window into — the same guard
	# `AppSettings.apply_video()` uses. The dialog still gets built either way, so a test can assert
	# on it without triggering the OS call that only a real window can answer.


## Exit is the destructive answer here, so it takes the red plate — the inverse of
## [method ModalDialog.create]'s default, which is why the variants are arguments. Return is the
## ordinary brown one rather than green: green would read as a recommendation, and going back to what
## you were doing is simply the other choice, not the encouraged one.
func _ensure_exit_confirm() -> ModalDialog:
	if _exit_confirm == null:
		_exit_confirm = ModalDialog.create("Exit the game?", "Exit", "Return",
			UiSkin.RED, UiSkin.BROWN)
		_exit_confirm.confirmed.connect(func() -> void: get_tree().quit())
		add_child(_exit_confirm)
	return _exit_confirm


func _create_ai_backend() -> AiBackend:
	var selected := OS.get_environment("OUTPOST_AI_BACKEND").strip_edges().to_lower()
	if selected.is_empty():
		selected = _default_backend_id()
	if selected == "fake":
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
	if selected == "in-process-llama":
		return _create_in_process_llama_backend()

	log.warn("Kernel", "Unknown OUTPOST_AI_BACKEND '%s'; using fake backend" % selected)
	return FakeAiBackend.new()


## What runs when nothing named a backend. A phone has no environment to set one
## in, and no alternative to fall back on: the server runtime cannot ship there
## at all (iOS forbids subprocesses, Android blocks exec from app data), so the
## in-process binding is the platform's default rather than something a player
## opts into. Desktop stays on the fake backend so the test suite and a plain
## `godot --path .` never load 2.4 GiB of weights they did not ask for.
func _default_backend_id() -> String:
	if OS.get_name() == "Android":
		return "in-process-llama"
	return "fake"


func _resolve_model_profile() -> ModelProfile:
	const MODEL_CATALOG_PATH := "res://config/ai/model_catalog.tres"
	var catalog := load(MODEL_CATALOG_PATH) as ModelCatalog
	var requested_profile := OS.get_environment("OUTPOST_MODEL_PROFILE").strip_edges()
	var profile: ModelProfile = null
	if catalog != null:
		profile = catalog.profile(requested_profile) if not requested_profile.is_empty() else catalog.default_for_current_platform()
	if profile == null:
		log.error("Kernel", "Model profile '%s' could not be loaded" % requested_profile)
	else:
		log.info("Kernel", "Using model profile %s" % profile.profile_id)
	return profile


func _create_local_llama_backend() -> AiBackend:
	var profile := _resolve_model_profile()
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


## M6 Phase 1 (Windows proof-of-concept): binds libllama in-process via the
## outpost_llama GDExtension instead of spawning llama-server. See
## InProcessLlamaBackend for why loading is async even though this call looks
## synchronous - ensure_started() only kicks off the background load.
func _create_in_process_llama_backend() -> AiBackend:
	var profile := _resolve_model_profile()
	var backend := InProcessLlamaBackend.new(profile)
	backend.ensure_started()
	return backend
