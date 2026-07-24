extends Control

## App-shell load screen (placeholder). Lists the save slots newest-first (from SaveManager.slots());
## picking one loads it and enters the game. No delete/rename here yet — just enough to continue a
## named save.

const GAME_SCREEN := "base_game.chat"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Load Game"
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	var slots: Array = Kernel.saves.slots()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "No saved games."
		col.add_child(empty)
	else:
		for slot: Dictionary in slots:
			col.add_child(_slot_button(slot))

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func() -> void: Kernel.router.goto("core.main_menu"))
	col.add_child(back)


func _slot_button(slot: Dictionary) -> Button:
	var b := Button.new()
	var id := String(slot.get("id", ""))
	b.text = "%s  —  day %d" % [slot.get("name", "Unnamed"), int(slot.get("total_days", 0))]
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func() -> void: _load(id))
	return b


func _load(id: String) -> void:
	var result: Dictionary = Kernel.session.load_slot(id)
	if bool(result["ok"]):
		Kernel.router.goto(GAME_SCREEN)
	else:
		Kernel.log.error("LoadScreen", "Failed to load '%s': %s" % [id, result.get("error", "")])
