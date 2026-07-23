class_name Plans
extends RefCounted

## Pure logic for background plans (M5, D36): how a plan's numeric direction moves, and when a
## plot changes character. No I/O and no kernel — the command applies the result to GameState and
## the ticker runs the workflow; this holds only the rules, so every number a plan produces is
## decided in code (D4) and is unit-testable in isolation.
##
## A plan is a plain Dictionary stored under GameState["plans"][id]:
##   { id, template, tick_workflow, subjects: [..],
##     situation: "<english>", direction: { intensity: int, band: String },
##     flags: { .. }, history: [ {day, transition, intensity, band} .. ],
##     next_wake: int (total_days; -1 = not armed), status: "active" | "resolved" }

const TRANSITIONS: PackedStringArray = ["escalate", "hold", "de_escalate", "resolve"]

## Bounded nudges (D36, Fork 1): one tick moves intensity by at most a step, so the hysteresis
## gap below can absorb a lone mis-tick without the band flipping.
const NUDGE := {"escalate": 12, "de_escalate": -12, "hold": 0, "resolve": 0}

## Band thresholds with split rise/fall points — classic hysteresis. Each fall point sits a full
## nudge (12) below its rise point, so one escalate/de_escalate at a boundary cannot cross a band
## and come straight back: a plan that reached `boiling` at 70 holds boiling until it drops below
## 58. The plan-tick measurement saw ~1/6 temp-0 mis-ticks at boundaries; this is the format
## answering that, not guessing.
const RISE_TENSE := 30
const FALL_CALM := 18
const RISE_BOILING := 70
const FALL_TENSE := 58

## Adaptive cadence (D36): a hot plot is revisited sooner than a quiet one.
const WAKE_DAYS := {"calm": 60, "tense": 30, "boiling": 15}


static func intensity_delta(transition: String) -> int:
	return int(NUDGE.get(transition, 0))


## The band for an intensity, given the band it currently holds. Sticky between the fall and rise
## thresholds — the answer there depends on history, and that dependence *is* the hysteresis.
static func band_for(intensity: int, current_band: String) -> String:
	match current_band:
		"boiling":
			return "boiling" if intensity >= FALL_TENSE else "tense"
		"tense":
			if intensity >= RISE_BOILING:
				return "boiling"
			return "calm" if intensity < FALL_CALM else "tense"
		_:  # calm or unknown: only the rise thresholds apply
			if intensity >= RISE_BOILING:
				return "boiling"
			return "tense" if intensity >= RISE_TENSE else "calm"


static func wake_delta(band: String) -> int:
	return int(WAKE_DAYS.get(band, 30))


## Ids of active plans whose wake has arrived. The ticker snapshots this before running any, so a
## plan spawned mid-pass (with a future wake) is not ticked in the same advance.
static func due(plans: Dictionary, today: int) -> Array:
	var ids: Array = []
	for id: Variant in plans:
		var plan: Dictionary = plans[id]
		if String(plan.get("status", "active")) != "active":
			continue
		var wake := int(plan.get("next_wake", -1))
		if wake >= 0 and wake <= today:
			ids.append(id)
	return ids


## Apply one transition to a plan. Returns { plan: <updated copy>, spawned: [<new plans>] } and
## never mutates the input. Every number the result carries is decided here (D4); the model only
## chose *which* transition.
static func apply_transition(plan: Dictionary, transition: String, today: int) -> Dictionary:
	var updated: Dictionary = plan.duplicate(true)
	var direction: Dictionary = updated.get("direction", {})
	var band := String(direction.get("band", "calm"))

	if transition == "resolve":
		updated["status"] = "resolved"
		updated["next_wake"] = -1
		_record(updated, today, transition, int(direction.get("intensity", 0)), band)
		return {"plan": updated, "spawned": []}

	var intensity := clampi(int(direction.get("intensity", 0)) + intensity_delta(transition), 0, 100)
	var new_band := band_for(intensity, band)
	direction["intensity"] = intensity
	direction["band"] = new_band
	updated["direction"] = direction

	var spawned: Array = _mutate(updated, today)
	updated["next_wake"] = today + wake_delta(new_band)
	_record(updated, today, transition, intensity, new_band)
	return {"plan": updated, "spawned": spawned}


static func _record(plan: Dictionary, day: int, transition: String, intensity: int, band: String) -> void:
	var history: Array = plan.get("history", [])
	history.append({"day": day, "transition": transition, "intensity": intensity, "band": band})
	plan["history"] = history


## Code-owned plot mutation (D36, Fork 2): the model never proposes "the plot changes character";
## code detects the conditions and does it. The one template the skeleton ships: an extortion that
## reaches boiling once the lord has publicly humiliated the steward turns into a revenge plot.
## Idempotent — the `revenge_spawned` flag means a plan sitting at boiling spawns exactly one.
static func _mutate(plan: Dictionary, today: int) -> Array:
	if String(plan.get("template", "")) != "steward_extortion":
		return []
	var direction: Dictionary = plan.get("direction", {})
	var flags: Dictionary = plan.get("flags", {})
	if String(direction.get("band", "")) != "boiling":
		return []
	if not bool(flags.get("lord_humiliated", false)) or bool(flags.get("revenge_spawned", false)):
		return []
	flags["revenge_spawned"] = true
	plan["flags"] = flags
	var revenge := new_plan(
		"%s_revenge" % String(plan.get("id", "steward")),
		"steward_revenge", "plan_tick", plan.get("subjects", []),
		"The steward, publicly humiliated, has turned from extortion to plotting the lord's ruin.",
		today + wake_delta("tense"))
	return [revenge]


static func new_plan(id: String, template: String, tick_workflow: String, subjects: Variant,
		situation: String, next_wake: int, intensity: int = 40, band: String = "tense") -> Dictionary:
	return {
		"id": id,
		"template": template,
		"tick_workflow": tick_workflow,
		"subjects": subjects if subjects is Array else [],
		"situation": situation,
		"direction": {"intensity": intensity, "band": band},
		"flags": {},
		"history": [],
		"next_wake": next_wake,
		"status": "active",
	}
