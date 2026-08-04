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


func test_a_selected_colour_chip_gets_a_ring_without_changing_its_colour() -> void:
	var color := Color.html("#2fa354")
	var plain := UiSkin.swatch_style(color, false)
	var selected := UiSkin.swatch_style(color, true)
	assert_eq(plain.bg_color, color)
	assert_eq(selected.bg_color, color, "selection must not tint the colour being compared")
	assert_gt(selected.border_width_left, plain.border_width_left,
		"the chosen swatch has a visibly heavier ring")


func test_destination_art_is_full_strength_at_rest_and_brighter_on_hover() -> void:
	var button := UiSkin.destination_button(UiSkin.MAP_LAYERS_TEXTURE)
	add_child_autofree(button)
	var normal := button.button.get_theme_stylebox("normal") as StyleBoxTexture
	var hover := button.button.get_theme_stylebox("hover") as StyleBoxTexture
	assert_eq(normal.texture, UiSkin.MAP_LAYERS_TEXTURE,
		"rail destinations keep their authored colour at rest")
	assert_eq(hover.texture, UiSkin.MAP_LAYERS_TEXTURE)
	assert_gt(hover.modulate_color.r, normal.modulate_color.r,
		"hover still brightens a full-colour destination")


## Godot looks `hover_pressed` up as a state of its own. A latched plate without that override falls
## back to the theme's default box, so the authored artwork disappears at exactly the moment the
## pointer arrives to switch it off — a silent default making a liar of the picture.
func test_a_latched_plate_keeps_its_selected_art_under_the_pointer() -> void:
	for button: SkinnedButton in [
			UiSkin.map_layers_button(),
			UiSkin.map_layer_button(UiSkin.MAP_LAYER_GRID_TEXTURE,
				UiSkin.MAP_LAYER_GRID_SELECTED_TEXTURE)]:
		add_child_autofree(button)
		assert_true(button.button.toggle_mode, "an open layer stays open when the pointer leaves")
		var pressed := button.button.get_theme_stylebox("pressed") as StyleBoxTexture
		var hover_pressed := button.button.get_theme_stylebox("hover_pressed") as StyleBoxTexture
		assert_not_null(hover_pressed)
		assert_eq(hover_pressed.texture, pressed.texture,
			"pointing at a selected plate must not lose the selected artwork")
		assert_gt(hover_pressed.modulate_color.r, pressed.modulate_color.r,
			"it still brightens, like every other plate under the pointer")


## The foot has to reserve the gap, the shortcut, *and* the moulding again — reserving only the plate
## and one gap left the column ending on the shortcut's own bottom edge, so every side had a margin
## except that one and the button read as poking out through the bottom of the column.
func test_the_map_layers_column_closes_under_the_shortcut_at_its_foot() -> void:
	var style := UiSkin.map_layers_flyout_style()
	assert_eq(style.content_margin_bottom, UiSkin.MAP_LAYERS_SEPARATION
		+ UiSkin.MAP_LAYERS_ICON_SIZE + UiSkin.MAP_LAYERS_COLUMN_PADDING,
		"one gap, the shortcut, and the same moulding the other three sides carry")
	for margin: float in [style.content_margin_top, style.content_margin_left,
			style.content_margin_right]:
		assert_eq(margin, UiSkin.MAP_LAYERS_COLUMN_PADDING,
			"the moulding is the rail's, held to this column's smaller proportion")
	assert_lt(UiSkin.MAP_LAYERS_COLUMN_PADDING, UiSkin.SIDEMENU_PADDING)


func test_top_bar_keeps_its_painted_metal_edge_at_source_height() -> void:
	var style := UiSkin.top_bar_style()
	assert_eq(style.texture.get_height(), UiSkin.TOP_BAR_TEXTURE.get_height(),
		"the header centre may compress, but its bottom metal rule must not be resampled away")
	var content_center := (style.content_margin_top
		+ UiSkin.TOP_BAR_HEIGHT - style.content_margin_bottom) * 0.5
	var parchment_center := (UiSkin.TOP_BAR_HEIGHT - style.texture_margin_bottom) * 0.5
	assert_almost_eq(content_center, parchment_center, 0.01,
		"header contents are optically centred above the painted bottom rail")


## The board runs to the bottom of the screen, so it has no bottom border region to protect: its
## parchment has to stretch all the way to its own last row. A bottom slice of any size would hold
## that many units of the art's *middle* against the screen's edge and stop the sheet reaching it.
func test_the_chat_board_is_one_sheet_that_reaches_its_own_bottom_edge() -> void:
	var style := UiSkin.chat_frame_style()
	assert_eq(style.texture_margin_bottom, 0.0,
		"nothing is protected at the foot — the parchment ends where the board does")
	for margin: float in [style.texture_margin_left, style.texture_margin_top,
			style.texture_margin_right]:
		assert_eq(margin, UiSkin.CHAT_FRAME_SLICE,
			"the other three sides each protect their rule and the shadow it throws inward")
	# What the slice must clear is the *rule* — the hard feature. The long soft vignette it throws
	# inward reaches much further, and that is fine: a gradient stretches into a wider gradient, where
	# a rule caught in the middle region would be smeared down the whole board.
	var art := UiSkin.CHAT_FRAME_TEXTURE.get_image()
	if art.is_compressed():
		art.decompress()
	var rule := art.get_pixel(4, art.get_height() / 2).get_luminance()
	var parchment := art.get_pixel(art.get_width() / 2, art.get_height() / 2).get_luminance()
	var first_stretched := art.get_pixel(int(UiSkin.CHAT_FRAME_SLICE),
		art.get_height() / 2).get_luminance()
	assert_lt(rule, parchment * 0.7, "the metal really is dark against the parchment it frames")
	assert_gt(first_stretched, parchment * 0.8,
		"and it is wholly inside the protected border — the middle begins on open parchment")


## A content margin is measured from the box's edge, and on three sides the first units of that are
## painted metal. Equal margins all round therefore leave *unequal* parchment: the same air at the
## foot as at the head, plus the rule's worth again, and the input row sits visibly high in its board.
func test_the_input_row_sits_on_equal_parchment_top_and_bottom() -> void:
	var style := UiSkin.chat_frame_style()
	var air_above := style.content_margin_top - UiSkin.CHAT_FRAME_RULE
	assert_almost_eq(style.content_margin_bottom, air_above, 0.01,
		"the foot has no rule to clear, so it gets the air alone")
	assert_almost_eq(style.content_margin_left - UiSkin.CHAT_FRAME_RULE, air_above, 0.01,
		"and the sides, which do have one, match the head")
	assert_gt(style.content_margin_bottom, 0.0,
		"the row still may not touch the screen's own edge")
