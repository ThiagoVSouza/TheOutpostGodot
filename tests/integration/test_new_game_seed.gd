extends GutTest

## begin_new_game seeds a living world (the in-game phase): the module seed hook runs through the
## whitelisted CommandBus, producing a named hero, a small cast with dispositions, starting
## resources, and one ticking plot — then announces new_game_started.

## The wizard's background/location -> state/memory wiring (base_game_module.gd's
## BACKGROUND_EFFECTS/LOCATION_EFFECTS) is deliberately a provisional first pass — the numbers are
## expected to be retuned. These tests read the *same table the code reads* rather than hard-coding
## expected amounts, so retuning the table never requires rewriting a test: only the wiring is
## pinned (a chosen background/location produces the state its own table entry says it should),
## never a specific number.
const BaseGameModule := preload("res://modules/base_game/base_game_module.gd")

const SCRATCH_WORK := "user://test_seed_work"


func _kernel() -> GameKernel:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # boots + loads base_game (which overrides seed_new_game)
	kernel.workspace = SaveWorkspace.new(SCRATCH_WORK)
	kernel.session.autosave_enabled = false  # no disk writes during the test
	return kernel


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_WORK):
		return
	var dir := DirAccess.open(SCRATCH_WORK)
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_WORK, file])
	DirAccess.remove_absolute(SCRATCH_WORK)


func test_begin_new_game_seeds_the_cast_resources_and_a_ticking_plot() -> void:
	var kernel := _kernel()
	var started: Array = []
	kernel.events.subscribe("new_game_started", func(p: Dictionary) -> void: started.append(p))

	kernel.session.begin_new_game({"hero_name": "Livia"})

	# The named hero and the rest of the cast, with dispositions.
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Livia")
	assert_true(Entities.exists(kernel.state, "steward"), "the cast was created")
	assert_eq(Entities.disposition(kernel.state, "king"), 10)

	# Starting resources.
	assert_eq(int((kernel.state.get_value("resources", {}) as Dictionary).get("food", 0)), 20)

	# One background plot, due within a few days so it ticks in a short hands-on session (the
	# placeholder pacing that makes the living-world loop observable in-game).
	var plans: Dictionary = kernel.state.get_value("plans", {})
	assert_true(plans.has("steward_extortion"), "a starting plot exists")
	assert_true(Plans.due(plans, 2).is_empty(), "not yet due on day 2")
	assert_false(Plans.due(plans, 3).is_empty(), "due by day 3")

	# The facts the narrated opening will dress (the screen plays the `opening` workflow over them),
	# and the announcement.
	var opening: Dictionary = kernel.state.get_value("opening", {})
	assert_eq(String(opening.get("hero", "")), "Livia", "the opening carries the hero's name")
	assert_eq(started.size(), 1, "new_game_started fired once")


func test_letting_days_pass_ticks_the_seeded_plot_in_play() -> void:
	# The in-play time-advance deliverable end to end: a freshly seeded game, then game days pass
	# (as the "let a day pass" control does — via the clock, not a direct ticker call), and the
	# seeded plot ticks on its own subscription and surfaces a chronicle emit.
	var kernel := _kernel()
	(kernel.ai_runner as FakeAiRunner).set_result("classify_plan_transition", "escalate")
	var chronicled: Array = []
	kernel.events.subscribe("workflow_emit", func(p: Dictionary) -> void: chronicled.append(p))

	kernel.session.begin_new_game({"hero_name": "Livia"})
	var before := int((kernel.state.get_value("plans", {})["steward_extortion"]["direction"]
		as Dictionary)["intensity"])

	kernel.clock.advance(3)  # reach the plot's wake day
	# The tick suspends a frame at its ai step (FakeAiRunner yields), so let it finish.
	for _i in range(5):
		await get_tree().process_frame

	var after := int((kernel.state.get_value("plans", {})["steward_extortion"]["direction"]
		as Dictionary)["intensity"])
	assert_gt(after, before, "the seeded plot escalated as the days passed")
	var ticked := chronicled.filter(func(p: Dictionary) -> bool:
		return String(p.get("msg", "")) == "base_game.plan_ticked")
	assert_false(ticked.is_empty(), "the tick surfaced a chronicle line in play")


func test_the_opening_workflow_narrates_over_the_seeded_facts() -> void:
	# What the chat screen plays on first entry to a fresh game: the authored `opening` workflow
	# narrates over the seed's facts (D30 — the opening is a workflow, not a static string, and the
	# narrator is handed the decided facts rather than inventing them, D4).
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia"})
	var facts: Dictionary = kernel.state.get_value("opening", {})
	var definition: Variant = kernel.workflow_registry.get_definition("opening")
	assert_true(definition is Dictionary, "base_game authors an opening workflow")

	var instance := WorkflowInstance.create("opening", 1, facts, 0)
	var result: RefCounted = await WorkflowExecutor.for_kernel(kernel).run(
		definition as Dictionary, instance, AiTrace.new())

	var prose := String(result.get("narration"))
	assert_false(prose.is_empty(), "the opening produced narration")
	assert_string_contains(prose, "Livia", "the narrator was handed the hero's name")


func test_the_wizards_narration_choice_reaches_the_narrator() -> void:
	# The Settings step's payoff: the stored preference is what the executor resolves an authored
	# `verbosity` against, so choosing "Long" has to move the level the narrator is actually asked
	# to write at — not merely sit in the profile.
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia",
		GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_LONG})

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_LONG)
	# The `opening` beat is authored `long`; at this preference it resolves past what any author
	# writes, which is the whole point of the ladder being wider than the authored literals.
	assert_eq(kernel.narration.resolve("long"), "full")


func test_average_narration_is_a_real_middle_not_a_second_short() -> void:
	# The wizard offers three lengths, so they have to be three. `normal` earns its own base on the
	# ladder: without one it falls back to short's, and two of the three cards behave identically.
	var kernel := _kernel()
	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_NORMAL})
	var average := kernel.narration.resolve("normal")

	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT})
	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT, "the new game's choice applied")
	assert_ne(average, kernel.narration.resolve("normal"), "average reads longer than short")


func test_a_loaded_game_does_not_inherit_the_previous_games_narration_choice() -> void:
	# `narration` is not in the save (it is derived), so the only thing standing between a load and
	# the last game's setting is the kernel re-deriving it. A game saved at Short, loaded while Long
	# is in force, must read Short.
	var kernel := _kernel()
	kernel.session.begin_new_game({GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT})
	var saved: Dictionary = {"version": 1, "state": {
		GameSession.PROFILE_STATE_KEY: {GameSession.PROFILE_VERBOSITY: NarrationSettings.LEVEL_SHORT},
	}}
	kernel.narration.level = NarrationSettings.LEVEL_LONG

	kernel.saves.restore(kernel, saved)

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT,
		"the loaded game's own preference governs it")


func test_a_game_with_no_stored_preference_reads_as_unset_not_inherited() -> void:
	# An older save predating the wizard has no profile. It gets the default, not whatever the
	# session happened to be set to — "unset" and "inherit the last game" are different answers.
	var kernel := _kernel()
	kernel.narration.level = NarrationSettings.LEVEL_LONG

	kernel.saves.restore(kernel, {"version": 1, "state": {}})

	assert_eq(kernel.narration.level, NarrationSettings.LEVEL_SHORT)


func test_the_wizards_flag_is_stored_for_the_game_to_show() -> void:
	# The chat screen's header reads this back through FlagValue.from_dict, so what the wizard
	# stored has to survive the round trip — the flag the player designed, not a default.
	var kernel := _kernel()
	var designed := {"shapeColor": "#2f5fc0", "texture": "pattern07", "textureColor": "#f3c43f",
		"emblem": "emblem04", "emblemColor": "#f7f7f2"}
	kernel.session.begin_new_game({GameSession.OUTPOST_FLAG_STATE_KEY: designed})

	var stored: Dictionary = kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {})
	var value := FlagValue.from_dict(stored)
	assert_eq(value.shape_color, Color.html("#2f5fc0"), "the cloth colour survived")
	assert_eq(value.texture, "pattern07")
	assert_eq(value.emblem, "emblem04")


func test_the_outpost_is_given_a_place_on_the_overworld() -> void:
	# The map stops being scenery: seeding chooses where the settlement stands and records it as
	# world state, which is what the map overlay pins the outpost's banner to.
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia"})

	var site: Dictionary = kernel.state.get_value(GameSession.OUTPOST_SITE_STATE_KEY, {})
	assert_false(site.is_empty(), "the outpost has a site")
	var map := BaseGameMap.load_map()
	var biome := map.biome_at(int(site["x"]), int(site["y"]))
	assert_true(BaseGameMap.HABITABLE_BIOMES.has(biome),
		"founded on habitable ground, not in the ocean (got '%s')" % biome)


func test_the_outposts_site_survives_a_save_and_a_reload() -> void:
	# Chosen once and then part of the world, rather than recomputed when the map opens: a rule
	# evaluated at display time would move the town if the rule ever changed.
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia"})
	var site: Dictionary = kernel.state.get_value(GameSession.OUTPOST_SITE_STATE_KEY, {})

	kernel.saves.restore(kernel, {"version": 1, "state":
		{GameSession.OUTPOST_SITE_STATE_KEY: site}})

	assert_eq(kernel.state.get_value(GameSession.OUTPOST_SITE_STATE_KEY, {}), site)


func test_begin_new_game_replaces_a_previous_game() -> void:
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "First"})
	kernel.session.begin_new_game({"hero_name": "Second"})

	# start_new clears before seeding, so the second game does not inherit the first's hero name
	# and the plot is created fresh (create_plan would reject a duplicate otherwise).
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Second")
	assert_eq((kernel.state.get_value("plans", {}) as Dictionary).size(), 1, "one plot, not two")


# --- Background / location wiring ------------------------------------------------------------

func _first_with_key(table: Dictionary, key: String) -> String:
	for id in table:
		if (table[id] as Dictionary).has(key):
			return String(id)
	return ""


func test_a_backgrounds_resource_bonus_lands_on_top_of_the_flat_starting_grant() -> void:
	var id := _first_with_key(BaseGameModule.BACKGROUND_EFFECTS, "resource")
	assert_false(id.is_empty(), "at least one background grants a resource, to exercise this path")
	var effect: Dictionary = BaseGameModule.BACKGROUND_EFFECTS[id]
	var resource := String(effect["resource"])

	var baseline := _kernel()
	baseline.session.begin_new_game({"hero_name": "Livia"})
	var base_amount := int((baseline.state.get_value("resources", {}) as Dictionary).get(resource, 0))

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "background": id})
	var chosen_amount := int((kernel.state.get_value("resources", {}) as Dictionary).get(resource, 0))

	assert_eq(chosen_amount - base_amount, int(effect["amount"]),
		"the background's table amount landed on top of the baseline, whatever either happens to be")


func test_a_backgrounds_trait_lands_on_the_hero_alongside_founder() -> void:
	var id := _first_with_key(BaseGameModule.BACKGROUND_EFFECTS, "trait")
	assert_false(id.is_empty(), "at least one background grants a trait, to exercise this path")
	var expected_trait := String(BaseGameModule.BACKGROUND_EFFECTS[id]["trait"])

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "background": id})

	var traits: Array = Entities.get_entity(kernel.state, "hero").get("traits", [])
	assert_true(traits.has(expected_trait), "the background's own trait was added to the hero")
	assert_true(traits.has("founder"), "and the base trait is still there too")


func test_a_backgrounds_disposition_nudge_lands_on_its_own_target() -> void:
	var id := _first_with_key(BaseGameModule.BACKGROUND_EFFECTS, "disposition_target")
	assert_false(id.is_empty(),
		"at least one background nudges a disposition, to exercise this path")
	var effect: Dictionary = BaseGameModule.BACKGROUND_EFFECTS[id]
	var target := String(effect["disposition_target"])

	var baseline := _kernel()
	baseline.session.begin_new_game({"hero_name": "Livia"})
	var base_disposition := Entities.disposition(baseline.state, target)

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "background": id})
	var chosen_disposition := Entities.disposition(kernel.state, target)

	assert_eq(chosen_disposition - base_disposition, int(effect["disposition_delta"]),
		"the background's own delta landed on its own target, on top of the baseline")


func test_a_backgrounds_origin_memory_is_recorded_and_tagged_to_the_hero() -> void:
	var id := _first_with_key(BaseGameModule.BACKGROUND_EFFECTS, "memory")
	assert_false(id.is_empty(), "every background grants a memory, to exercise this path")
	var expected_text := String(BaseGameModule.BACKGROUND_EFFECTS[id]["memory"])

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "background": id})

	var recalled: Array = kernel.memories.retrieve(["hero"], 10)
	var texts: Array = recalled.map(func(m: Dictionary) -> String: return String(m.get("text", "")))
	assert_true(texts.has(expected_text), "the background's own origin line reached the memory store")


func test_a_locations_resource_bonus_lands_on_top_of_the_flat_starting_grant() -> void:
	var id := _first_with_key(BaseGameModule.LOCATION_EFFECTS, "resource")
	assert_false(id.is_empty(), "at least one location grants a resource, to exercise this path")
	var effect: Dictionary = BaseGameModule.LOCATION_EFFECTS[id]
	var resource := String(effect["resource"])

	var baseline := _kernel()
	baseline.session.begin_new_game({"hero_name": "Livia"})
	var base_amount := int((baseline.state.get_value("resources", {}) as Dictionary).get(resource, 0))

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "outpost_location": id})
	var chosen_amount := int((kernel.state.get_value("resources", {}) as Dictionary).get(resource, 0))

	assert_eq(chosen_amount - base_amount, int(effect["amount"]),
		"the location's table amount landed on top of the baseline, whatever either happens to be")


func test_a_locations_origin_memory_is_recorded_and_tagged_to_the_outpost() -> void:
	var id := _first_with_key(BaseGameModule.LOCATION_EFFECTS, "memory")
	assert_false(id.is_empty(), "every location grants a memory, to exercise this path")
	var expected_text := String(BaseGameModule.LOCATION_EFFECTS[id]["memory"])

	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "outpost_location": id})

	var recalled: Array = kernel.memories.retrieve(["outpost"], 10)
	var texts: Array = recalled.map(func(m: Dictionary) -> String: return String(m.get("text", "")))
	assert_true(texts.has(expected_text), "the location's own origin line reached the memory store")


func test_an_unrecognised_background_or_location_is_a_safe_no_op() -> void:
	# A blank or typo'd id (the wizard's own defaults, or a future authoring mistake) must not
	# crash the seed — it just grants nothing extra, same as choosing nothing at all.
	var kernel := _kernel()
	kernel.session.begin_new_game({"hero_name": "Livia", "background": "not_a_real_background",
		"outpost_location": "not_a_real_location"})
	assert_eq(String(Entities.get_entity(kernel.state, "hero").get("name", "")), "Livia")


func test_every_background_and_location_effect_applies_without_a_single_command_rejection() -> void:
	# The catch-all: whatever the table's numbers end up being, every entry's disposition_target
	# (if any) has to name a real entity, and every resource/amount pair has to be valid — this
	# fails loudly on a typo in the table without needing a per-entry assertion for it.
	for background in BaseGameModule.BACKGROUND_EFFECTS:
		var kernel := _kernel()
		var rejected: Array = []
		kernel.events.subscribe("command_rejected", func(p: Dictionary) -> void: rejected.append(p))
		kernel.session.begin_new_game({"hero_name": "Livia", "background": String(background)})
		assert_true(rejected.is_empty(), "background '%s' had a rejected command: %s" %
			[background, rejected])

	for location in BaseGameModule.LOCATION_EFFECTS:
		var kernel := _kernel()
		var rejected: Array = []
		kernel.events.subscribe("command_rejected", func(p: Dictionary) -> void: rejected.append(p))
		kernel.session.begin_new_game({"hero_name": "Livia", "outpost_location": String(location)})
		assert_true(rejected.is_empty(), "location '%s' had a rejected command: %s" %
			[location, rejected])


## The two shapes of "this choice is not really a choice", both of which the first pass shipped and
## a human spotted by reading the table rather than by running anything. Neither asserts a *number*,
## so retuning stays a one-place edit — they only require that the numbers say something.

func test_every_choice_grants_at_least_one_mechanical_effect() -> void:
	# An option that changes nothing reads as the one nobody should pick, whatever its flavour text
	# promises. Scholar was exactly that: a trait and a memory, and no number anywhere.
	var tables := {
		"BACKGROUND_EFFECTS": BaseGameModule.BACKGROUND_EFFECTS,
		"LOCATION_EFFECTS": BaseGameModule.LOCATION_EFFECTS,
	}
	for table_name in tables:
		var table: Dictionary = tables[table_name]
		for id in table:
			var effect: Dictionary = table[id]
			assert_true(effect.has("resource") or effect.has("disposition_target"),
				"%s['%s'] changes no game state — it is a choice in name only" % [table_name, id])


func test_no_two_locations_are_mechanically_identical() -> void:
	# Coast and Forest shipped with the same grant, so two of the four cards differed by prose alone.
	# With only food/gold the *type* cannot always differ, but the whole (type, amount) pair must.
	var seen: Dictionary = {}
	for id in BaseGameModule.LOCATION_EFFECTS:
		var effect: Dictionary = BaseGameModule.LOCATION_EFFECTS[id]
		var signature := "%s:%d" % [String(effect.get("resource", "")), int(effect.get("amount", 0))]
		assert_false(seen.has(signature),
			"locations '%s' and '%s' grant exactly the same thing (%s)" %
			[seen.get(signature, ""), id, signature])
		seen[signature] = id
