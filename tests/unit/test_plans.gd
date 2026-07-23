extends GutTest

## The plan-format rules (M5, D36): bounded intensity nudges, hysteresis bands, code-owned plot
## mutation. Pure logic — no kernel, no I/O — so the two decisions the GATE 0 review earned are
## verified in isolation before anything runs a model.


func _steward(intensity: int, band: String, humiliated: bool = false) -> Dictionary:
	var plan := Plans.new_plan("steward", "steward_extortion", "plan_tick", ["steward", "lord"],
		"The steward is extorting the lord.", 30, intensity, band)
	(plan["flags"] as Dictionary)["lord_humiliated"] = humiliated
	return plan


func test_escalate_and_de_escalate_nudge_by_one_bounded_step() -> void:
	var up: Dictionary = Plans.apply_transition(_steward(40, "tense"), "escalate", 30)
	assert_eq(int((up["plan"]["direction"] as Dictionary)["intensity"]), 52)
	var down: Dictionary = Plans.apply_transition(_steward(40, "tense"), "de_escalate", 30)
	assert_eq(int((down["plan"]["direction"] as Dictionary)["intensity"]), 28)
	var held: Dictionary = Plans.apply_transition(_steward(40, "tense"), "hold", 30)
	assert_eq(int((held["plan"]["direction"] as Dictionary)["intensity"]), 40, "hold moves nothing")


func test_intensity_clamps_to_0_and_100() -> void:
	var high: Dictionary = Plans.apply_transition(_steward(95, "boiling"), "escalate", 30)
	assert_eq(int((high["plan"]["direction"] as Dictionary)["intensity"]), 100)
	var low: Dictionary = Plans.apply_transition(_steward(5, "calm"), "de_escalate", 30)
	assert_eq(int((low["plan"]["direction"] as Dictionary)["intensity"]), 0)


func test_band_rises_only_at_the_rise_threshold() -> void:
	# Coming up from calm, tense needs 30 and boiling needs 70 — nothing in between.
	assert_eq(Plans.band_for(29, "calm"), "calm")
	assert_eq(Plans.band_for(30, "calm"), "tense")
	assert_eq(Plans.band_for(69, "tense"), "tense")
	assert_eq(Plans.band_for(70, "tense"), "boiling")


func test_band_holds_through_the_hysteresis_gap() -> void:
	# The point of Fork 1: a plan that reached boiling holds it until well below the rise point,
	# so a lone mis-tick at the boundary cannot flip it back and forth.
	assert_eq(Plans.band_for(60, "boiling"), "boiling", "boiling holds down to the fall point")
	assert_eq(Plans.band_for(57, "boiling"), "tense", "and only then drops")
	assert_eq(Plans.band_for(60, "tense"), "tense", "the same 60, reached from below, is still tense")


func test_one_mis_tick_at_the_boundary_does_not_flip_the_band() -> void:
	# A plan sitting just inside boiling gets a single spurious de_escalate; it must stay boiling.
	var jittered: Dictionary = Plans.apply_transition(_steward(70, "boiling"), "de_escalate", 30)
	assert_eq(int((jittered["plan"]["direction"] as Dictionary)["intensity"]), 58)
	assert_eq(String((jittered["plan"]["direction"] as Dictionary)["band"]), "boiling",
		"58 is exactly the fall point — the band holds, absorbing the mis-tick")


func test_resolve_ends_the_plan_and_unarms_it() -> void:
	var done: Dictionary = Plans.apply_transition(_steward(40, "tense"), "resolve", 30)
	assert_eq(String((done["plan"] as Dictionary)["status"]), "resolved")
	assert_eq(int((done["plan"] as Dictionary)["next_wake"]), -1, "a resolved plan is never due again")


func test_next_wake_is_sooner_for_a_hotter_band() -> void:
	var boiling: Dictionary = Plans.apply_transition(_steward(76, "boiling"), "hold", 100)
	var calm: Dictionary = Plans.apply_transition(_steward(10, "calm"), "hold", 100)
	assert_lt(int((boiling["plan"] as Dictionary)["next_wake"]),
		int((calm["plan"] as Dictionary)["next_wake"]), "a boiling plot is revisited sooner")


func test_history_records_each_tick() -> void:
	var t: Dictionary = Plans.apply_transition(_steward(40, "tense"), "escalate", 30)
	var history: Array = (t["plan"] as Dictionary)["history"]
	assert_eq(history.size(), 1)
	assert_eq(String((history[0] as Dictionary)["transition"]), "escalate")
	assert_eq(int((history[0] as Dictionary)["day"]), 30)


func test_the_input_plan_is_never_mutated() -> void:
	var original := _steward(40, "tense")
	Plans.apply_transition(original, "escalate", 30)
	assert_eq(int((original["direction"] as Dictionary)["intensity"]), 40, "apply returns a copy")
	assert_eq((original["history"] as Array).size(), 0)


# --- code-owned plot mutation (Fork 2) ---

func test_extortion_turns_to_revenge_only_at_boiling_when_the_lord_humiliated_the_steward() -> void:
	# Reaching boiling (64 -> 76) with the humiliation flag set spawns the revenge sub-plan.
	var t: Dictionary = Plans.apply_transition(_steward(64, "tense", true), "escalate", 30)
	assert_eq(String((t["plan"]["direction"] as Dictionary)["band"]), "boiling")
	var spawned: Array = t["spawned"]
	assert_eq(spawned.size(), 1, "the plot changed character — code detected it, the model did not")
	assert_eq(String((spawned[0] as Dictionary)["template"]), "steward_revenge")
	assert_eq(String((spawned[0] as Dictionary)["id"]), "steward_revenge")


func test_no_revenge_without_the_humiliation() -> void:
	var t: Dictionary = Plans.apply_transition(_steward(64, "tense", false), "escalate", 30)
	assert_eq(String((t["plan"]["direction"] as Dictionary)["band"]), "boiling")
	assert_eq((t["spawned"] as Array).size(), 0, "boiling alone is not enough")


func test_revenge_spawns_exactly_once() -> void:
	var first: Dictionary = Plans.apply_transition(_steward(64, "tense", true), "escalate", 30)
	assert_eq((first["spawned"] as Array).size(), 1)
	# The updated plan carries the revenge_spawned flag; ticking it again at boiling spawns no more.
	var again: Dictionary = Plans.apply_transition(first["plan"] as Dictionary, "hold", 45)
	assert_eq((again["spawned"] as Array).size(), 0, "idempotent — a boiling plan does not respawn")


# --- due filtering ---

func test_due_returns_active_plans_whose_wake_has_arrived() -> void:
	var plans := {
		"soon": Plans.new_plan("soon", "steward_extortion", "plan_tick", [], "s", 30),
		"later": Plans.new_plan("later", "steward_extortion", "plan_tick", [], "l", 100),
	}
	assert_eq(Plans.due(plans, 30), ["soon"], "only the plan whose wake has come")
	assert_eq(Plans.due(plans, 100).size(), 2, "both once the clock reaches the later one")


func test_resolved_plans_are_never_due() -> void:
	var plan := Plans.new_plan("done", "steward_extortion", "plan_tick", [], "d", 30)
	plan["status"] = "resolved"
	assert_eq(Plans.due({"done": plan}, 999).size(), 0)
