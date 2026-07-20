extends GutTest

## AiTrace gets an id (A1) and a Markdown export; AiTraceWriter (D21) is the sink that
## turns a finished trace into one JSONL file (one stage entry per line) plus that
## Markdown export, under a directory the caller controls.

const SCRATCH_DIR := "user://test_ai_traces"


func after_each() -> void:
	_clear_scratch_dir()


func _clear_scratch_dir() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(SCRATCH_DIR)


func test_each_trace_gets_a_unique_id() -> void:
	var a := AiTrace.new()
	var b := AiTrace.new()
	assert_ne(a.id, b.id, "two traces in the same run should never collide on filename")
	assert_true(a.id.begins_with("orch_"), "id should be recognizable as an orchestration trace")


func test_to_markdown_reads_start_to_end() -> void:
	var trace := AiTrace.new()
	trace.add("guardrails", {"ok": true})
	trace.add("narrative", {"text": "Your scouts return with food."})

	var md := trace.to_markdown()

	assert_string_contains(md, trace.id, "export should name the orchestration it belongs to")
	assert_string_contains(md, "guardrails", "every stage should appear")
	assert_string_contains(md, "narrative")
	assert_string_contains(md, "Your scouts return with food.", "stage data should be readable, not opaque")


func test_disabled_writer_writes_nothing() -> void:
	var writer := AiTraceWriter.new(SCRATCH_DIR, false)
	var trace := AiTrace.new()
	trace.add("guardrails", {"ok": true})

	var paths := writer.write(trace)

	assert_true(paths.is_empty(), "a disabled writer should be a no-op")
	assert_false(DirAccess.dir_exists_absolute(SCRATCH_DIR), "no directory should be created")


func test_write_is_noop_for_null_trace() -> void:
	var writer := AiTraceWriter.new(SCRATCH_DIR, true)
	assert_true(writer.write(null).is_empty(), "writing a null trace should not error or create files")


func test_write_creates_one_jsonl_line_per_stage_and_a_markdown_export() -> void:
	var writer := AiTraceWriter.new(SCRATCH_DIR, true)
	var trace := AiTrace.new()
	trace.add("guardrails", {"ok": true})
	trace.add("classify_intent", {"intent": "forage"})
	trace.add("narrative", {"text": "The outpost is calm."})

	var paths := writer.write(trace)

	assert_true(paths.has("jsonl"), "write() should report the jsonl path")
	assert_true(paths.has("markdown"), "write() should report the markdown path")
	assert_true(FileAccess.file_exists(paths["jsonl"]), "the jsonl file should exist on disk")
	assert_true(FileAccess.file_exists(paths["markdown"]), "the markdown file should exist on disk")

	var f := FileAccess.open(paths["jsonl"], FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if not line.is_empty():
			lines.append(line)
	f.close()

	assert_eq(lines.size(), 3, "one JSONL line per stage entry")
	var first := JSON.parse_string(lines[0]) as Dictionary
	assert_eq(first["stage"], "guardrails", "line order should match recording order")
	assert_eq((first["data"] as Dictionary)["ok"], true)

	var md_text := FileAccess.get_file_as_string(paths["markdown"])
	assert_eq(md_text, trace.to_markdown(), "the exported file should match to_markdown() exactly")


func test_default_directory_matches_d21_and_trims_trailing_slash() -> void:
	# Mirrors ModuleRegistry's `root` override (test_module_registry.gd): the directory
	# is a constructor param precisely so tests never touch a dev build's real traces.
	var default_writer := AiTraceWriter.new()
	assert_eq(default_writer.traces_dir, "user://traces", "D21: JSONL/Markdown live under user://traces")

	var trailing_slash := AiTraceWriter.new("user://traces/")
	assert_eq(trailing_slash.traces_dir, "user://traces", "a trailing slash should not produce a doubled separator")
