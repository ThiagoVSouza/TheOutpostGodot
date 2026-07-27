class_name Motion
extends RefCounted

## Named animation durations and easing for the shell (M8 Phase 1, ux_plan.md §1.3 rule 4:
## "Everything animates"). One place to decide timing so a panel opening, a button reacting to
## hover, and the split settling into place cannot quietly drift out of sync with each other by
## being written three times in three screens.

const DURATION_FAST := 0.12   ## hover/press feedback
const DURATION_NORMAL := 0.20 ## panel open/close, breakpoint re-layout

const EASE := Tween.EASE_OUT
const TRANS := Tween.TRANS_CUBIC


## Animate [param control]'s opacity to [param to]. Returns the tween so a caller can chain or await
## `finished` on it (e.g. to free a control only once it has actually faded out).
static func fade(control: CanvasItem, to: float, duration: float = DURATION_NORMAL) -> Tween:
	var tween := control.create_tween()
	tween.set_ease(EASE).set_trans(TRANS)
	tween.tween_property(control, "modulate:a", to, duration)
	return tween
