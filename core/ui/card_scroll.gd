class_name CardScroll
extends ScrollContainer

## The scroll region inside a choice card — and the one thing a plain [ScrollContainer] there cannot
## do: hand the card back its click.
##
## **Why this class has to exist at all.** A card is a [PanelContainer] holding a [Button] and its
## content as *siblings*, the button underneath ([code]_card[/code] in the new-game wizard says why).
## That arrangement works only while every control on top of the button is
## [constant Control.MOUSE_FILTER_IGNORE], so hit-testing falls through to it. A scroll region cannot
## be ignored — it wants the wheel and the drag — so it becomes the control under the pointer, and
## Godot propagates GUI input **up the parent chain only**, never sideways to a sibling drawn beneath.
## [constant Control.MOUSE_FILTER_PASS] does not help: it bubbles to the card's container, which is
## not the button either. This is what took the click off the card's face the first time a scroll
## region went on it; no [member Control.mouse_filter] value fixes it, so the scroll has to hand the
## click over deliberately. That is [signal tapped].
##
## **Tap versus drag is decided by what the content did, not only by how far the finger moved.** A
## press and release with the pointer still and the content unmoved is a choice; anything that
## scrolled is not. Asking [member ScrollContainer.scroll_vertical] settles it exactly, where a
## distance threshold alone is a guess — and on a touchscreen the threshold that matters is
## [member ScrollContainer.scroll_deadzone], which Godot is already applying below.
##
## The scrollbar needs none of this: it is a child of this control with its own filter, so it takes
## its own drags and they never reach [method _gui_input].

## Emitted when a press and release on the content were a tap rather than a drag — the click the card
## behind this would have had.
signal tapped

## How far the pointer may travel between press and release and still be a tap. A mouse wobbles a
## pixel or two under a click; a finger wobbles more, which is what the deadzone below is for.
const TAP_SLOP := 8.0

## How far a finger must travel before Godot treats it as a scroll rather than a touch. Stock is 0,
## which makes every tap on a scrollable card a one-pixel drag and would leave the card unpickable on
## a phone — the case this widget exists to serve.
const DRAG_DEADZONE := 16

## Where the press landed, and how far down the content was when it did. [constant Vector2.INF] is
## "no press in flight", so a release that arrives without one — the pointer came in already held —
## cannot be read as a tap.
var _press_at := Vector2.INF
var _press_scroll := 0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = DRAG_DEADZONE


## Godot calls a script's [method _gui_input] *before* the control's own handling and only skips the
## latter if the event was accepted, so nothing here needs to call up to [ScrollContainer]: reading
## the event and leaving it unaccepted lets the wheel and the drag work exactly as they always did.
## By the time a release arrives, any motion has already moved the content — which is what makes the
## comparison below the whole test.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		_press_at = click.position
		_press_scroll = scroll_vertical
		return
	if _press_at.is_finite() and click.position.distance_to(_press_at) <= TAP_SLOP \
			and scroll_vertical == _press_scroll:
		tapped.emit()
	_press_at = Vector2.INF
