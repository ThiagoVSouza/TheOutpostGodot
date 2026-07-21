extends GutTest

## The player's narration preference composes with the authored literal rather than replacing
## it: an author's pacing survives every setting, and `topics` stays a form rather than becoming
## the shortest length. These rules are what keep `verbosity` an authored literal in the DSL
## (D4 amendment #3) while still letting the player choose how much they read.


func test_default_level_narrates_exactly_as_authored() -> void:
	var settings := NarrationSettings.new()
	assert_eq(settings.level, NarrationSettings.LEVEL_SHORT, "the shipped default is short prose")
	assert_eq(settings.resolve("short"), "short")
	assert_false(settings.loose, "unbound narration is dev-only and off by default")


func test_long_preference_reaches_past_anything_an_author_writes() -> void:
	# The player asked for long prose, so even a beat authored `short` must come back longer
	# than the longest beat an author would write on its own.
	var settings := NarrationSettings.new()
	settings.level = NarrationSettings.LEVEL_LONG
	assert_eq(settings.resolve("short"), "long")
	assert_eq(settings.resolve("normal"), "full")


func test_authored_pacing_survives_the_preference() -> void:
	# The point of resolving rather than overriding: at any setting, a beat authored `short`
	# stays no longer than one authored `long`.
	for level in [NarrationSettings.LEVEL_SHORT, NarrationSettings.LEVEL_LONG]:
		var settings := NarrationSettings.new()
		settings.level = level
		var terse := NarrationSettings.PROSE_LADDER.find(settings.resolve("short"))
		var rich := NarrationSettings.PROSE_LADDER.find(settings.resolve("long"))
		assert_true(terse <= rich, "authored pacing must hold at level '%s'" % level)


func test_the_ladder_clamps_at_both_ends() -> void:
	var short_pref := NarrationSettings.new()
	short_pref.level = NarrationSettings.LEVEL_SHORT
	assert_eq(short_pref.resolve("short"), "short", "cannot shift below the shortest prose")
	var long_pref := NarrationSettings.new()
	long_pref.level = NarrationSettings.LEVEL_LONG
	assert_eq(long_pref.resolve("long"), "full", "cannot shift above the longest prose")


func test_topics_is_a_form_not_a_length() -> void:
	# Every authored beat reports as topics — the preference changes the output's shape, so an
	# authored `long` must not shift it back into prose.
	var settings := NarrationSettings.new()
	settings.level = NarrationSettings.LEVEL_TOPICS
	for authored in ["short", "normal", "long"]:
		assert_eq(settings.resolve(authored), NarrationSettings.LEVEL_TOPICS)


func test_unknown_authored_verbosity_falls_back_to_normal() -> void:
	var settings := NarrationSettings.new()
	settings.level = NarrationSettings.LEVEL_LONG
	assert_eq(settings.resolve("whatever"), "full", "an unreadable literal is treated as normal")
	assert_eq(settings.resolve("whatever"), settings.resolve("normal"))


func test_an_unknown_level_is_rejected_rather_than_applied() -> void:
	var settings := NarrationSettings.new()
	settings.level = "epic"
	assert_eq(settings.level, NarrationSettings.LEVEL_SHORT, "the level stays a known one")


func test_changing_the_preference_announces_itself() -> void:
	# The UI and any future settings screen both bind to this signal.
	var settings := NarrationSettings.new()
	watch_signals(settings)
	settings.level = NarrationSettings.LEVEL_TOPICS
	settings.level = NarrationSettings.LEVEL_TOPICS  # same value: not a change
	settings.loose = true
	assert_signal_emit_count(settings, "changed", 2)
