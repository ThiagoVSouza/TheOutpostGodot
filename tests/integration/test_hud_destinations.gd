extends GutTest

## Phase 5's destinations are registered by a module but rendered inside the persistent game shell.
## These assertions keep both halves honest: the desktop rail has the seven destinations, mobile's
## expanded list folds in Map Layers and Return, and the real-state Domain page can be opened.


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	return screen


func test_seven_destinations_fill_the_rail_and_mobile_adds_map_layers_and_return() -> void:
	var screen := _screen()
	var shell := screen.get("_shell") as HudShell
	var rail := shell.get("_rail") as VBoxContainer
	var mobile_menu := shell.get("_menu_list_box") as VBoxContainer

	assert_eq(rail.get_child_count(), 7, "the desktop rail contains the seven game destinations")
	assert_eq(mobile_menu.get_child_count(), 9,
		"mobile contains those seven, Map Layers, and Return")
	# A destination is a painted plate now, so its caption is the plate's own [Label] — a
	# [SkinnedButton] draws no text of its own (only a [Label] can carry the font shadow).
	assert_eq((mobile_menu.get_child(-1) as SkinnedButton).label.text, "Return",
		"Return stays at the foot of the list")


func test_domain_page_is_built_from_the_registry_and_reads_current_state() -> void:
	Kernel.state.set_value("resources", {"population": 42})
	var screen := _screen()

	screen.call("_open_destination", "domain")

	var shell := screen.get("_shell") as HudShell
	assert_true(shell.is_page_open(), "opening a registry destination opens a HUD page")
	var panels: Dictionary = screen.get("_destination_panels")
	var panel := panels.get("domain") as HudPanel
	assert_not_null(panel, "the Domain panel was built through its registered builder")
	assert_string_contains((panel.body.get_node("domain_name") as Label).text, "Settlement:")
	assert_string_contains((panel.body.get_node("domain_today") as Label).text, "Today:")
