class_name DateFormat
extends RefCounted

## Renders [GameClock]'s day count as the wireframed date string ("January 1st 374",
## ux_plan.md §1.1's top bar). [GameClock] itself only knows day counts — scheduling stays on the
## simple 30-day month it already had (D24) — so month *names*, a 12-month year and a starting
## epoch are display-only additions that live here, never fed back into scheduling.

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const MONTHS_PER_YEAR := 12

## No lore has fixed an epoch yet, so Year 1 is simply the outpost's founding — a placeholder
## like the domain-level ladder (ux_plan.md §5), not a claim about the wider setting's history.
const EPOCH_YEAR := 1


## The current date, e.g. "January 1st 1" on the day a game begins.
static func render(clock: GameClock) -> String:
	var months := clock.months_elapsed()
	var year := EPOCH_YEAR + months / MONTHS_PER_YEAR
	var month_name: String = MONTH_NAMES[months % MONTHS_PER_YEAR]
	# day_of_month() reads 0 before any day has passed; the calendar still shows a first day.
	var day := maxi(clock.day_of_month(), 1)
	return "%s %s %d" % [month_name, _ordinal(day), year]


## English ordinal suffix: 1st, 2nd, 3rd, 4th... 11th/12th/13th are the exception the %10 rule
## alone gets wrong.
static func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
		_: return "%dth" % n
