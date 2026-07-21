class_name NarrationSettings
extends RefCounted

## The player's narration preference: how much prose they want to read, and in what form.
##
## This is a **presentation** preference, not a game decision — it sits beside language (D29)
## and never touches what happened. That is why it lives here rather than in the DSL: a
## workflow's `verbosity` stays an authored literal (D4 amendment #3, see `OpRegistry`), so
## authors keep their pacing — a beat written `short` stays relatively terser than one written
## `long` at every setting — while the player still chooses their reading length.
##
## Resolution composes the two: [member level] picks the band, the authored literal nudges
## within it. `topics` is deliberately NOT a point on the length ladder — it is a different
## output *form* (a terse list of what happened), so it absorbs the authored nudge instead of
## being shifted off by it.

## What the player picked. The playground exposes these as three buttons.
const LEVEL_TOPICS := "topics"
const LEVEL_SHORT := "short"
const LEVEL_LONG := "long"

## The ladder of levels a narrator can actually write at, shortest first. It is deliberately
## wider than the set of authored literals: authors write `short`/`normal`/`long` to express
## a beat's *relative* weight, and the preference decides where on this scale that lands, so a
## player who asks for long prose gets prose longer than any beat an author would write alone.
const PROSE_LADDER := ["short", "normal", "long", "full"]

## Where each preference plants the base of the scale, as an index into [constant PROSE_LADDER].
const BASE := {LEVEL_SHORT: 0, LEVEL_LONG: 3}

## How far an authored literal nudges the beat around that base.
const NUDGE := {"short": -1, "normal": 0, "long": 1}

signal changed()

## The player's chosen level; one of the LEVEL_* constants.
var level: String = LEVEL_SHORT: set = set_level

## Playground-only escape hatch: let the narrator write freely instead of binding it to the
## decided facts. It exists to learn what the model *wants* to write — it deliberately gives up
## the D4 guarantee, so it is off by default and never set outside dev tooling.
var loose: bool = false: set = set_loose


func set_level(value: String) -> void:
	var next := value.strip_edges().to_lower()
	if next != LEVEL_TOPICS and not PROSE_LADDER.has(next):
		return
	if next == level:
		return
	level = next
	changed.emit()


func set_loose(value: bool) -> void:
	if value == loose:
		return
	loose = value
	changed.emit()


## Resolve an authored verbosity literal against the player's preference into the level the
## narrator should actually write at. Returns `topics` or a member of [constant PROSE_LADDER].
func resolve(authored: String) -> String:
	if level == LEVEL_TOPICS:
		return LEVEL_TOPICS
	var nudge: int = int(NUDGE.get(authored, 0))  # an unreadable literal reads as `normal`
	var base: int = int(BASE.get(level, 0))
	return String(PROSE_LADDER[clampi(base + nudge, 0, PROSE_LADDER.size() - 1)])
