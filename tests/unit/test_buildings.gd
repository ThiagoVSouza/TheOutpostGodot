extends GutTest

## The house sheet, and the table that says which of its sixteen frames is which.
##
## Nearly all of this is about the **slot table**, because that is where a mistake is invisible: a
## wrong index does not crash, it draws a burnt house when you asked for a foundation, and nothing
## about the running map says which of the two is wrong.


func test_every_appearance_has_a_frame_in_both_weathers() -> void:
	assert_eq(Buildings.CLEAR_SLOTS.size(), Buildings.Appearance.size())
	assert_eq(Buildings.SNOW_SLOTS.size(), Buildings.Appearance.size())
	assert_eq(Buildings.APPEARANCE_TITLES.size(), Buildings.Appearance.size())
	for which in Buildings.Appearance.size():
		for snowed: bool in [false, true]:
			assert_not_null(Buildings.frame(which as Buildings.Appearance, snowed),
				"appearance %d, snowed %s" % [which, snowed])


## **Sixteen frames, sixteen distinct slots.** The sheet's order is nearly but not quite "all eight
## clear then all eight snowed" — the last two snowed build stages sit in the middle row after the
## ruined states — so a plausible-looking table can easily use one slot twice and leave another
## unreferenced. Both halves of that are caught here.
func test_the_slot_table_uses_every_frame_on_the_sheet_exactly_once() -> void:
	var seen: Dictionary = {}
	for slots: PackedInt32Array in [Buildings.CLEAR_SLOTS, Buildings.SNOW_SLOTS]:
		for slot: int in slots:
			assert_false(seen.has(slot), "slot %d is claimed twice" % slot)
			seen[slot] = true
	assert_eq(seen.size(), 16, "the sheet's sixteen painted frames are all spoken for")
	# The two empty cells at the end of the last row are the ones nothing may point at.
	for slot: int in [16, 17]:
		assert_false(seen.has(slot), "slot %d is empty on the sheet" % slot)


## A snowed house has to be a *different painting*, not the same one — the one failure mode of a slot
## table that is otherwise perfectly well formed.
func test_the_snowed_copy_of_a_state_is_never_the_clear_one() -> void:
	for which in Buildings.Appearance.size():
		var clear := Buildings.frame(which as Buildings.Appearance, false)
		var snowed := Buildings.frame(which as Buildings.Appearance, true)
		assert_ne(clear, snowed, "appearance %d is painted twice, not once" % which)


## Every frame is the whole cell, overhang included, and cut on the sheet's own pitch. A frame taken
## from anywhere else would make the house step sideways as its state changed — which reads as a bug
## in the map rather than in the sheet.
func test_the_frames_are_whole_cells_cut_on_the_sheets_pitch() -> void:
	var all := Buildings.frames()
	assert_eq(all.size(), Buildings.ATLAS_COLUMNS * Buildings.ATLAS_ROWS)
	for index in all.size():
		var frame := all[index] as AtlasTexture
		assert_eq(frame.get_size(), Vector2(Buildings.ATLAS_CELL, Buildings.ATLAS_CELL))
		assert_eq(frame.atlas, Buildings.ATLAS, "one texture, so the canvas can batch them")
		var row := index / Buildings.ATLAS_COLUMNS
		var column := index % Buildings.ATLAS_COLUMNS
		assert_eq(frame.region.position, Vector2(Buildings.ATLAS_ORIGIN)
			+ Vector2(float(column), float(row)) * float(Buildings.ATLAS_CELL),
			"frame %d is on the pitch" % index)


## The construction ladder and the ruined states are one list, in that order — so "the second half of
## the enum is the wrecked half" is a rule the dev keys are allowed to rely on.
func test_the_build_stages_come_before_the_ruined_states() -> void:
	assert_eq(int(Buildings.Appearance.FOUNDATION), 0)
	assert_eq(int(Buildings.Appearance.FINISHED), 3)
	assert_eq(int(Buildings.Appearance.RUIN), 4)
	assert_eq(int(Buildings.Appearance.ABANDONED), 7)


func test_the_current_state_is_what_gets_drawn_and_named() -> void:
	var was_appearance := Buildings.appearance
	var was_snow := Buildings.snow

	Buildings.appearance = Buildings.Appearance.BURNT
	Buildings.snow = false
	assert_eq(Buildings.title(), "Burnt-out house")
	assert_eq(Buildings.texture(), Buildings.frame(Buildings.Appearance.BURNT, false))
	Buildings.snow = true
	assert_eq(Buildings.texture(), Buildings.frame(Buildings.Appearance.BURNT, true))

	Buildings.appearance = was_appearance
	Buildings.snow = was_snow
