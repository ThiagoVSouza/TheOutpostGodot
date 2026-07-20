extends GutTest

## A1 acceptance test: a real orchestration writes a trace file a human can read start to
## end and confirm the run behaved correctly. `kernel.trace_writer` is repointed at a
## scratch directory so this never touches a dev build's real `user://traces`.

const SCRATCH_DIR := "user://test_ai_trace_e2e"


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(SCRATCH_DIR)


func test_a_real_orchestration_writes_a_readable_trace_file() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.trace_writer = AiTraceWriter.new(SCRATCH_DIR, true)

	var fake := kernel.ai as FakeAiBackend
	fake.queue_responses("forage", [
		{"tool_calls": [{"name": "roll_die", "args": {"sides": 6, "count": 1, "seed": 42}}]},
		{
			"commands": [{"name": "grant_resource", "args": {"resource": "food", "amount": 3}}],
			"narrative": "Your scouts return with baskets of food.",
		},
	])

	var result: Dictionary = await kernel.ai_orchestrator.handle_message("I send scouts to forage the hills")
	assert_true(result["ok"], "the orchestration itself should still succeed")

	var trace: AiTrace = result["trace"]
	var jsonl_path := "%s/%s.jsonl" % [SCRATCH_DIR, trace.id]
	var md_path := "%s/%s.md" % [SCRATCH_DIR, trace.id]
	assert_true(FileAccess.file_exists(jsonl_path), "the orchestration's trace should be on disk as JSONL")
	assert_true(FileAccess.file_exists(md_path), "and as a Markdown export")

	# "readable start to finish": the file's stage order matches the in-memory trace, and
	# the human export names every stage of this run.
	var f := FileAccess.open(jsonl_path, FileAccess.READ)
	var recorded_stages: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if not line.is_empty():
			recorded_stages.append((JSON.parse_string(line) as Dictionary)["stage"])
	f.close()
	assert_eq(recorded_stages, trace.stages(), "the file should record every stage, in order")

	var md_text := FileAccess.get_file_as_string(md_path)
	for stage in trace.stages():
		assert_string_contains(md_text, stage, "the Markdown export should name stage '%s'" % stage)
	assert_string_contains(md_text, "Your scouts return with baskets of food.")


func test_disabled_trace_writer_leaves_no_file_behind() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	kernel.trace_writer = AiTraceWriter.new(SCRATCH_DIR, false)

	var fake := kernel.ai as FakeAiBackend
	fake.set_response("general", {"narrative": "The outpost is calm."})

	await kernel.ai_orchestrator.handle_message("How are the walls holding?")

	assert_false(DirAccess.dir_exists_absolute(SCRATCH_DIR), "a disabled writer should create nothing")
