extends GutTest

## D18 contract tests: the chat screen is just one input source. Any source can feed
## text through the router, and every completed turn — success or busy rejection —
## comes back on the event bus tagged with the originating source id.


func _make_kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)
	return kernel


## Subscribes a collector for completed turns; payloads append into `turns`.
func _collect_turns(kernel: GameKernel, turns: Array) -> void:
	kernel.events.subscribe(AiInputRouter.EVENT_TURN_COMPLETED, func(payload: Dictionary) -> void:
		turns.append(payload))


func test_second_source_feeds_text_end_to_end() -> void:
	var kernel := _make_kernel()
	var turns: Array = []
	_collect_turns(kernel, turns)

	var source := kernel.input_router.create_source("scripted")
	assert_eq(source.id(), "scripted")
	source.submit("hello there outpost")
	if turns.is_empty():
		await wait_frames(10)

	assert_eq(turns.size(), 1, "one submission produces exactly one completed turn")
	var payload: Dictionary = turns[0]
	assert_eq(String(payload["source_id"]), "scripted")
	assert_eq(String(payload["text"]), "hello there outpost")
	var result: Dictionary = payload["result"]
	assert_true(bool(result["ok"]))
	assert_false(String(result["narrative"]).strip_edges().is_empty())


func test_busy_collision_between_two_sources() -> void:
	var kernel := _make_kernel()
	var turns: Array = []
	_collect_turns(kernel, turns)

	var typed := kernel.input_router.create_source("typed")
	var voice := kernel.input_router.create_source("voice")
	typed.submit("hello there outpost")
	voice.submit("me too")
	if turns.size() < 2:
		await wait_frames(10)

	assert_eq(turns.size(), 2, "both sources hear back, even the rejected one")
	var by_source: Dictionary = {}
	for payload_v in turns:
		var payload := payload_v as Dictionary
		by_source[String(payload["source_id"])] = payload["result"]

	var first: Dictionary = by_source["typed"]
	assert_true(bool(first["ok"]), "the in-flight orchestration is unaffected")
	var second: Dictionary = by_source["voice"]
	assert_false(bool(second["ok"]))
	assert_eq(String(second["error"]), "busy")


# --- chat screen as one source among others ---
#
# These use the *autoload* Kernel, not a fresh GameKernel: chat_screen.gd talks to the
# autoload, so a locally constructed kernel would not be the one it subscribes to.

func _make_chat_screen() -> Control:
	var screen: Control = Kernel.screens.instantiate(Kernel.screens.start_screen_id())
	add_child_autofree(screen)
	return screen


func _screen_log(screen: Control) -> String:
	# append_text() does not update .text — the parsed text is the rendered content.
	return (screen.get("_log_label") as RichTextLabel).get_parsed_text()


func test_screen_echoes_player_text_from_a_foreign_source() -> void:
	var screen := _make_chat_screen()
	await wait_frames(2)

	var scripted := Kernel.input_router.create_source("scripted")
	scripted.submit("hello there outpost")
	await wait_frames(10)

	var text := _screen_log(screen)
	assert_string_contains(text, "You: hello there outpost")
	assert_string_contains(text, "Game master:")


func test_typed_submit_echoes_exactly_once() -> void:
	var screen := _make_chat_screen()
	await wait_frames(2)

	screen.call("_on_submit", "hello there outpost")
	await wait_frames(10)

	var text := _screen_log(screen)
	assert_eq(
		text.count("You: hello there outpost"),
		1,
		"the screen's own submit already echoed — the turn event must not echo again"
	)
	assert_string_contains(text, "Game master:")


func test_source_id_is_recorded_in_the_trace() -> void:
	var kernel := _make_kernel()
	var turns: Array = []
	_collect_turns(kernel, turns)

	var source := kernel.input_router.create_source("replay")
	source.submit("hello there outpost", {"scope": {"region": "hills"}})
	if turns.is_empty():
		await wait_frames(10)

	assert_eq(turns.size(), 1)
	var result: Dictionary = (turns[0] as Dictionary)["result"]
	assert_true(bool(result["ok"]))
	var trace: AiTrace = result["trace"]
	var recorded := ""
	for entry_v in trace.entries():
		var entry := entry_v as Dictionary
		if String(entry["stage"]) == "turn_started":
			recorded = String((entry["data"] as Dictionary).get("source", ""))
	assert_eq(recorded, "replay", "the originating source id reaches the pipeline trace")
