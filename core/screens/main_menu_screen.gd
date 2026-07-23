extends Control

## App-shell main menu (placeholder). Continue / New Game / Load are wired to the real session;
## Settings / Help / News are disabled stubs. The whole shell exists to reach a real game start.

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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(280, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "THE OUTPOST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	col.add_child(title)

	col.add_child(_spacer(20))

	var can_continue := Kernel.session.workspace().exists() or not Kernel.saves.slots().is_empty()
	col.add_child(_menu_button("Continue", _on_continue, can_continue))
	col.add_child(_menu_button("New Game", _on_new_game, true))
	col.add_child(_menu_button("Load Game", _on_load, not Kernel.saves.slots().is_empty()))
	col.add_child(_menu_button("Settings", Callable(), false))
	col.add_child(_menu_button("Help", Callable(), false))
	col.add_child(_menu_button("News", Callable(), false))


func _menu_button(text: String, on_press: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 40)
	if enabled and on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _on_continue() -> void:
	var resumed: Dictionary = Kernel.session.continue_or_start()
	if bool(resumed["ok"]) and bool(resumed["continued"]):
		Kernel.router.goto(GAME_SCREEN)
	else:
		Kernel.log.warn("MainMenu", "Continue found nothing to resume (%s)" % resumed.get("source", ""))


func _on_new_game() -> void:
	Kernel.router.goto("core.new_game")


func _on_load() -> void:
	Kernel.router.goto("core.load")
