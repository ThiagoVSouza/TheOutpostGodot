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
