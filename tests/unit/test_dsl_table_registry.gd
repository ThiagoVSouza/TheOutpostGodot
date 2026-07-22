extends GutTest

## Rule tables (D24), both shapes: exact-key tables and the M3b **range tables** that map a
## number to the band it falls in. Bands are what keep a raw die out of authored content and
## out of the narrator's prompt — the workflow asks for the band's name and branches on that.


func _bands() -> DslTableRegistry:
	var tables := DslTableRegistry.new()
	tables.register_ranges("forage_outcome", [
		{"to": 8, "value": "meagre"},
		{"from": 8, "to": 16, "value": "steady"},
		{"from": 16, "value": "bountiful"},
	])
	return tables


func test_key_tables_still_look_up_by_exact_key() -> void:
	var tables := DslTableRegistry.new()
	tables.register("forage_yield", {"meagre": 0, "steady": 3, "bountiful": 5})

	assert_eq(tables.lookup("forage_yield", "steady"), 3, "an exact key returns its value")
	assert_null(tables.lookup("forage_yield", "lavish"), "a missing key is a null miss, not an error")
	assert_true(tables.has("forage_yield"))


func test_a_number_resolves_to_the_band_it_falls_in() -> void:
	var tables := _bands()

	assert_eq(tables.lookup("forage_outcome", 1), "meagre", "the bottom of the die")
	assert_eq(tables.lookup("forage_outcome", 7), "meagre", "just under the first threshold")
	assert_eq(tables.lookup("forage_outcome", 12), "steady", "the middle band")
	assert_eq(tables.lookup("forage_outcome", 20), "bountiful", "the top of the die")


func test_bands_are_half_open_so_adjacent_rows_share_an_edge() -> void:
	var tables := _bands()
	# `from` inclusive, `to` exclusive — the same convention as the DSL's `for` (A3), so a
	# threshold is written once and 8 belongs to exactly one band.
	assert_eq(tables.lookup("forage_outcome", 8), "steady", "the edge belongs to the row that starts on it")
	assert_eq(tables.lookup("forage_outcome", 16), "bountiful", "and again at the next edge")


func test_open_ended_rows_catch_everything_past_the_last_threshold() -> void:
	var tables := _bands()
	# The first row omits `from` and the last omits `to`, so no roll can fall out of the table
	# however the dice expression changes.
	assert_eq(tables.lookup("forage_outcome", -40), "meagre")
	assert_eq(tables.lookup("forage_outcome", 999), "bountiful")


func test_a_number_outside_every_band_is_a_null_miss() -> void:
	var tables := DslTableRegistry.new()
	tables.register_ranges("gap", [{"from": 1, "to": 5, "value": "low"}])

	assert_null(tables.lookup("gap", 9), "past the only band")
	assert_null(tables.lookup("gap", 0), "below the only band")


func test_a_non_numeric_key_is_refused_rather_than_coerced() -> void:
	var tables := _bands()
	# float("meagre") is 0.0, which would silently land in whichever band contains zero. An
	# author who points a range table at a string has made a mistake and should hear about it.
	assert_null(tables.lookup("forage_outcome", "meagre"), "a string key does not resolve to a band")
	assert_push_error("needs a number", "and the author is told why")


func test_overlapping_or_disordered_rows_are_refused_at_registration() -> void:
	var tables := DslTableRegistry.new()
	tables.register_ranges("overlap", [
		{"to": 10, "value": "low"},
		{"from": 5, "to": 20, "value": "high"},  # starts inside the row before it
	])
	assert_false(tables.has("overlap"),
		"an overlapping band table is a balance mistake and is not registered at all")
	assert_push_error("overlaps or precedes", "and the offending row is named")


func test_an_empty_band_is_refused() -> void:
	var tables := DslTableRegistry.new()
	tables.register_ranges("empty", [{"from": 10, "to": 10, "value": "never"}])
	assert_false(tables.has("empty"), "a row that can never match is refused")
	assert_push_error("is empty", "and says so")
