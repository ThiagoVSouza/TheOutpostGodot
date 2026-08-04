extends GutTest

## FlagValue round-trips the legacy flag-designer JSON so a flag authored in the old system loads
## unchanged, and reports pattern/emblem presence for the renderer.


func test_from_dict_reads_the_legacy_keys() -> void:
	var v := FlagValue.from_dict({
		"shapeColor": "#2f5fc0", "texture": "pattern03", "textureColor": "#f3c43f",
		"emblem": "emblem07", "emblemColor": "#000000",
	})
	assert_eq(v.shape_color, Color.html("#2f5fc0"))
	assert_eq(v.texture, "pattern03")
	assert_eq(v.emblem, "emblem07")
	assert_true(v.has_pattern())
	assert_true(v.has_emblem())


func test_none_pattern_and_emblem_are_absent() -> void:
	var v := FlagValue.from_dict({"texture": "none", "emblem": "none"})
	assert_false(v.has_pattern())
	assert_false(v.has_emblem())


func test_serialize_round_trips() -> void:
	var v := FlagValue.new()
	v.shape_color = Color.html("#2fa354")
	v.texture = "pattern10"
	v.texture_color = Color.html("#f7f7f2")
	v.emblem = "emblem02"
	v.emblem_color = Color.html("#8b5a2b")

	var back := FlagValue.deserialize(v.serialize())
	assert_eq(back.to_dict(), v.to_dict(), "a serialized flag deserializes to the same value")


func test_deserialize_falls_back_on_garbage() -> void:
	var v := FlagValue.deserialize("not json")
	assert_not_null(v, "a bad string yields a default flag, not a crash")
	assert_true(v.has_emblem(), "the default carries an emblem")


## **The quad is not the flag.** The art carries a pole, a crossbar and a finial, so the cloth hangs
## in only part of the rectangle — and anything heraldic laid out against the rectangle rather than
## against the cloth sits high on it. On the poleless cut that was a tenth of the flag's height.
func test_the_cloth_is_measured_off_the_art_and_is_not_the_whole_quad() -> void:
	for short: bool in [false, true]:
		var cloth := FlagView.cloth_rect(short)
		assert_gt(cloth.size.x, 0.0)
		assert_gt(cloth.size.y, 0.0)
		assert_lt(cloth.size.y, 1.0, "the cloth never fills the quad's height — the hardware is in it")
		assert_almost_eq(cloth.get_center().x, 0.5, 0.02,
			"it does hang centred left to right, whichever cut this is")

	# The poleless cut is the one the header banner flies, and the one the offset was visible on: its
	# cloth reaches the bottom of the quad, so its centre sits well below the quad's.
	var banner := FlagView.cloth_rect(true)
	assert_gt(banner.get_center().y, 0.55,
		"a centred emblem drawn at 0.5 would land above the middle of this cloth")
	assert_almost_eq(banner.end.y, 1.0, 0.02, "the poleless cut's cloth runs to the foot of its quad")
