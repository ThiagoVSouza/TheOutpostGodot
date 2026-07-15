extends GutTest

## The roll_die tool: deterministic when seeded, always within bounds.

const DiceTool := preload("res://modules/base_game/ai_tools/dice_tool.gd")


func test_seeded_roll_is_deterministic() -> void:
	var tool := DiceTool.new()
	var a := tool.execute({"sides": 6, "count": 3, "seed": 123}, null)
	var b := tool.execute({"sides": 6, "count": 3, "seed": 123}, null)
	assert_eq(a["rolls"], b["rolls"], "same seed should give the same rolls")
	assert_eq(a["total"], b["total"])


func test_rolls_within_bounds_and_count() -> void:
	var tool := DiceTool.new()
	var r := tool.execute({"sides": 6, "count": 10, "seed": 1}, null)
	assert_eq((r["rolls"] as Array).size(), 10, "should roll the requested count")
	for v in r["rolls"]:
		assert_between(v, 1, 6, "each roll within [1, sides]")


func test_reports_name_and_schema() -> void:
	var tool := DiceTool.new()
	assert_eq(tool.tool_name(), "roll_die")
	assert_true(tool.params_schema().has("sides"))
