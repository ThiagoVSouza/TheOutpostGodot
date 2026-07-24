extends GutTest

## Loading must never inherit the game you were just playing (M4/B4a, D34).
##
## This is the failure mode that makes players restart: a partial reset leaves something from
## the previous session armed, an event fires that belongs to a game they are no longer in, and
## nothing in the UI can explain it. The bugs are individually small and collectively fatal to
## trust, so the rule here is absolute — **every store holding game state is replaced, never
## merged, and anything armed by play is dropped.**
##
## The last test is the important one: it fails when someone adds a kernel service without
## deciding which side of that line it sits on.

const SCRATCH_SAVES := "user://test_isolation_saves"
const SCRATCH_WORK := "user://test_isolation_work"


## Every member of [GameKernel], classified. Adding a kernel field means adding it here.
##
## SAVED — holds game state; must be captured and fully replaced on load.
const SAVED: Array[String] = ["state", "globals", "clock", "workflow_instances"]

## ARMED_BY_PLAY — accumulates during a game and must be dropped on load, even though it is not
## in the save. Keeping it is how the previous game bleeds into the next one.
const ARMED_BY_PLAY: Array[String] = ["scheduler"]

## CONTENT — registered by modules at boot, identical for every save in the process. Resetting
## these would unregister the game itself.
const CONTENT: Array[String] = ["command_registry", "tools", "modules", "screens",
	"workflow_registry", "dsl_functions", "dsl_tables", "prompt_families"]

## (router is RUNTIME below — it swaps the mounted screen and holds no game state.)

## RUNTIME — infrastructure with no game state: transports, buses, loggers, policy objects.
## `memories` sits here like `workspace`/`saves`/`trace_writer`: the field is a file-backed store,
## and its data lives in an append-only JSONL in the workspace dir (M5, D37). The workspace
## lifecycle governs replacement — `SaveWorkspace.clear()` removes the file and `GameSession`
## clears the store's cache on a new game or a load — so a game's memories never bleed into another.
const RUNTIME: Array[String] = ["log", "events", "commands", "ai", "ai_availability",
	"llama_server_manager", "ai_orchestrator", "trace_writer", "input_router", "saves",
	"workspace", "session", "narrator", "narration", "ai_runner", "plan_ticker", "memories",
	"router"]


func after_each() -> void:
	for path in [SCRATCH_SAVES, SCRATCH_WORK]:
		if not DirAccess.dir_exists_absolute(path):
			continue
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute("%s/%s" % [path, file])
		DirAccess.remove_absolute(path)


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.saves = SaveManager.new(SCRATCH_SAVES)
	kernel.workspace = SaveWorkspace.new(SCRATCH_WORK)
	kernel.session.autosave_enabled = true
	return kernel


func _tiny_workflow(id: String) -> Dictionary:
	return {"op": "workflow", "id": id, "version": 1, "params": {},
		"steps": [{"op": "emit", "msg": "test.fired", "values": {}}]}


func test_state_is_replaced_not_merged() -> void:
	var kernel := _kernel()
	kernel.state.set_value("resources", {"food": 5})
	kernel.state.set_value("leftover", "from the previous game")

	kernel.saves.restore(kernel, {"version": 1, "state": {"resources": {"food": 1}}})

	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary)["food"]), 1)
	assert_null(kernel.state.get_value("leftover", null),
		"a key the loaded save never had must not survive into it")


func test_globals_are_replaced_not_merged() -> void:
	var kernel := _kernel()
	kernel.globals.set_value("mood", "from the previous game")

	kernel.saves.restore(kernel, {"version": 1, "globals": {"weather": "rain"}})

	assert_null(kernel.globals.get_value("mood", null), "no leftover global")
	assert_eq(String(kernel.globals.get_value("weather", "")), "rain")


func test_pending_questions_are_replaced_not_merged() -> void:
	var kernel := _kernel()
	var stale := WorkflowInstance.create("old", 1, {}, 0)
	stale.status = WorkflowInstance.Status.SUSPENDED
	stale.wake = {"type": "confirmation"}
	kernel.workflow_instances.remember(stale)

	kernel.saves.restore(kernel, {"version": 1})

	assert_eq(kernel.workflow_instances.count(), 0,
		"a question from the previous game must not be waiting in the loaded one")


func test_events_armed_by_the_previous_game_are_dropped_on_load() -> void:
	var kernel := _kernel()
	# Something the *previous* game scheduled for a far-off day.
	kernel.scheduler.schedule_on_day(500, _tiny_workflow("from_the_old_game"))
	assert_eq(kernel.scheduler.pending_on_days(), 1)

	kernel.saves.restore(kernel, {"version": 1, "clock": {"total_days": 10}})

	# Loading a day-10 save must not leave a day-500 event armed from a game the player left.
	assert_eq(kernel.scheduler.pending_on_days(), 0, "nothing armed by the previous game survives")


func test_module_registered_schedules_survive_a_load() -> void:
	var kernel := _kernel()
	var registered := kernel.scheduler.pending_monthly()

	kernel.saves.restore(kernel, {"version": 1})

	# The other half of the rule: these are module *content*, registered once at boot. Clearing
	# them would silently disable the month-end report for the rest of the process.
	assert_eq(kernel.scheduler.pending_monthly(), registered, "module content is not reset")


func test_starting_a_new_game_inherits_nothing_from_the_loaded_one() -> void:
	var kernel := _kernel()
	# Load a save containing data for a module this build does not have; it is carried forward
	# so disabling a DLC does not erase it (B3).
	kernel.saves.restore(kernel, {"version": 1,
		"modules": {"dlc_module": {"version": "1.0.0", "data": {"relics": ["urn"]}}}})
	kernel.scheduler.schedule_on_day(500, _tiny_workflow("from_the_loaded_game"))

	kernel.session.start_new("A Completely Different Settlement")

	var payload := kernel.saves.capture(kernel, "slot_x", "A Completely Different Settlement")
	assert_false((payload["modules"] as Dictionary).has("dlc_module"),
		"one settlement's DLC data must not be written into another's save")
	assert_eq(kernel.scheduler.pending_on_days(), 0, "nor its armed events")


func test_every_kernel_service_is_classified() -> void:
	# The guard. Adding a kernel field without deciding whether it holds game state is how the
	# leak comes back — this fails until it has been put in one of the four lists above, each
	# of which carries the consequence of choosing it.
	var kernel := _kernel()
	var classified: Array[String] = []
	classified.append_array(SAVED)
	classified.append_array(ARMED_BY_PLAY)
	classified.append_array(CONTENT)
	classified.append_array(RUNTIME)

	var unclassified: Array[String] = []
	for property in kernel.get_property_list():
		var name := String(property["name"])
		# Only the kernel's own object-valued seams; skips Node's own properties and internals.
		if name.begins_with("_") or int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if int(property["type"]) != TYPE_OBJECT:
			continue
		if not classified.has(name):
			unclassified.append(name)

	assert_eq(unclassified, [] as Array[String],
		"unclassified kernel service(s) %s — decide in test_load_isolation.gd whether each holds "
		% str(unclassified) + "game state (SAVED), accumulates during play (ARMED_BY_PLAY), is "
		+ "module content (CONTENT), or is stateless infrastructure (RUNTIME)")
