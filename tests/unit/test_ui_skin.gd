extends GutTest

## The painted skin's behavioural details — the ones where the art promises something the control has
## to deliver, and where a silent default makes a liar of the picture.

## A [ScrollContainer] leaves its bars' `step` at 0 so that dragging and the wheel move the view by
## whole pixels, and [ScrollBar] moves by exactly that step when an end plate is pressed — which is
## nowhere. It costs nothing anywhere else in Godot, because the stock bar's end plates are two grey
## triangles nobody aims at; here they are painted plates that light up under the pointer, so a player
## presses them and reasonably expects the view to move. Found by hand on a wizard card.
func test_the_end_plates_of_a_skinned_scrollbar_move_it() -> void:
	var scroll := ScrollContainer.new()
	add_child_autofree(scroll)
	UiSkin.apply_scroll_container(scroll)
	for bar: ScrollBar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
		# The expression ScrollBar itself uses to decide how far one press goes.
		var moves_by: float = bar.custom_step if bar.custom_step >= 0.0 else bar.step
		assert_gt(moves_by, 0.0,
			"a press of a %s end plate has to move the view" % bar.get_class())
