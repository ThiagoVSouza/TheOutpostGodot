class_name CardPager
extends VBoxContainer

## A row of choice cards, with an arrow either side of a dot-per-card beneath them — the legacy
## wizard's `centered_pager`, which is how both of its pick-one steps were presented.
##
## **It exists because a card cannot be made narrow enough.** A choice card here carries a painting,
## a name, a line of prose and a row of badges; below about [constant CARD_WIDTH] that stops being a
## card and becomes a column of clipped words. Five of them will not fit across a phone at any size
## worth reading, so something has to give — and the two usual answers are both worse than paging.
## Shrinking the cards makes every option unreadable to save the player a tap. Wrapping them into a
## grid buries the last row below the fold, where a player who does not scroll never learns it was
## an option at all: on a pick-one step, an option you have to discover is a bug.
##
## **How many are on screen is the window's decision, not the caller's.** The count comes from the
## width this widget is actually given — three on a desktop, one on a phone — and is recomputed on
## resize, so the same wizard step is a row on one machine and a pager on another with nothing
## branching on a device type. The legacy screen JSON said the same thing in a
## `{wide: 3, narrow: 2, compact: 1}` map; the arithmetic here replaces the map.
##
## The cards themselves are built by the caller — this knows nothing about what is on one — and keep
## their own [ButtonGroup], so selection is still theirs. This only decides which are on screen.

## How much room one card wants. Below this a card is not worth drawing; above it, a second card can
## share the line.
const CARD_WIDTH := 300.0

## Never more than three at once even on a very wide window. Past three the cards stop reading as a
## choice between a few things and start reading as a catalogue, and each is far enough from the next
## that comparing the two ends means moving your head rather than your eyes.
const MAX_VISIBLE := 3

const DOT_SIZE := 12.0
const DOT_SPACING := 8

## How far the arrows and dots sit above whatever the screen puts below them.
const CONTROLS_LIFT := 14.0

var _cards: Array[Control] = []
## Index of the leftmost card on screen.
var _first := 0
var _visible := 1
var _strip: HBoxContainer = null
var _left: SkinnedButton = null
var _right: SkinnedButton = null
var _dots: HBoxContainer = null


## [param cards] are ready-built and already carry their own selection behaviour; [param selected]
## is the one to open on, so a step returned to shows the choice already made rather than the top of
## the list.
static func create(cards: Array[Control], selected: int) -> CardPager:
	var pager := CardPager.new()
	pager.add_theme_constant_override("separation", 10)

	# **The cards get the full width; the arrows sit underneath.** Flanking the strip cost a phone
	# about 130 units of the ~500 it has, which is a quarter of the card gone to two controls that are
	# only reachable at the ends of the list — and the card is the thing being read. Below the strip
	# they cost height, which a phone has far more of, and they group naturally with the dots: one row
	# that is entirely "where am I in this list".
	#
	# **The strip does not scroll — the cards do, inside themselves.** It did scroll, and that put the
	# bar down the side of the page for a card whose own prose was the thing that did not fit. Worse on
	# a phone: a scroll region holding scroll regions means the finger's first drag has two plausible
	# readings. A card is a fixed frame with its own scrolling contents now, so the strip is exactly as
	# tall as the room it is given and never has anywhere to go.
	pager._strip = HBoxContainer.new()
	pager._strip.add_theme_constant_override("separation", 10)
	pager._strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Vertical too: it is what makes the cards reach down to the controls instead of stopping at the
	# end of their text, which is what keeps a row of them level with each other.
	pager._strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pager.add_child(pager._strip)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_child(controls)

	pager._left = UiSkin.arrow_button(true)
	pager._left.pressed.connect(func() -> void: pager._step(-1))
	controls.add_child(pager._left)

	pager._dots = HBoxContainer.new()
	pager._dots.add_theme_constant_override("separation", DOT_SPACING)
	pager._dots.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_child(pager._dots)

	pager._right = UiSkin.arrow_button(false)
	pager._right.pressed.connect(func() -> void: pager._step(1))
	controls.add_child(pager._right)

	# Air under the arrows, so they sit clear of the rule the screen draws beneath them rather than
	# resting on it. They belong to the cards above, and a control touching a divider reads as
	# belonging to whatever is on the other side of it.
	var lift := Control.new()
	lift.custom_minimum_size.y = CONTROLS_LIFT
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pager.add_child(lift)

	for card in cards:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# `FILL`, not `EXPAND`: the height comes from the strip, which is the one thing here that
		# negotiates with the scroll above it. An [HBoxContainer] gives every child its own height, so
		# whatever the strip settles on, the cards are level with each other — at the tallest card's
		# content when the room is tight, and at the room itself when there is more of it.
		card.size_flags_vertical = Control.SIZE_FILL
		pager._cards.append(card)
		pager._strip.add_child(card)
		pager._dots.add_child(pager._dot())
	pager._first = selected
	return pager


func _ready() -> void:
	resized.connect(_refresh)
	_refresh()


## Move the window, not the selection. The arrows show you the next option; choosing it is still a
## tap on the card. Conflating the two would mean a player could not look without also picking.
func _step(direction: int) -> void:
	_first = clampi(_first + direction, 0, maxi(0, _cards.size() - _visible))
	_refresh()


func _refresh() -> void:
	if _cards.is_empty():
		return
	# `size.x` is zero until the first layout pass, and a zero width would compute a window of one
	# card and then never revisit it — `resized` is what brings us back with a real number. The whole
	# width counts now that the arrows are below rather than beside the strip.
	_visible = clampi(int(size.x / CARD_WIDTH), 1, mini(MAX_VISIBLE, _cards.size()))
	_first = clampi(_first, 0, maxi(0, _cards.size() - _visible))
	for i in _cards.size():
		_cards[i].visible = i >= _first and i < _first + _visible
	# Faded rather than removed at the ends: an arrow that vanishes would shuffle the row of controls
	# sideways every time the player reached either end. `set_disabled` does the fading, and drops the
	# shadow with it.
	_left.set_disabled(_first <= 0)
	_right.set_disabled(_first + _visible >= _cards.size())
	# One dot per card, and the ones on screen are filled. With three cards visible that is three
	# filled dots, which is the honest picture: the dots say what you are looking at, not where a
	# cursor is.
	_dots.visible = _cards.size() > _visible
	for i in _dots.get_child_count():
		var dot := _dots.get_child(i) as Control
		dot.modulate.a = 1.0 if (i >= _first and i < _first + _visible) else DOT_DIM


const DOT_DIM := 0.3


func _dot() -> Control:
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiSkin.INK_MUTED
	style.set_corner_radius_all(int(DOT_SIZE * 0.5))
	dot.add_theme_stylebox_override("panel", style)
	return dot
