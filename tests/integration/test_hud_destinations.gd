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


func test_rail_hover_label_draws_above_content_but_below_its_icon() -> void:
	var screen := _screen()
	var shell := screen.get("_shell") as HudShell
	var label_clip := shell.get("_rail_label_clip") as Control
	var rail := shell.get("_rail") as Control
	var page := shell.get("_page_slot") as Control

	assert_gt(label_clip.z_index, page.z_index,
		"hover labels draw above destination pages and the chat")
	assert_gt(rail.z_index, label_clip.z_index,
		"destination icons still cover the label's overlapping cap")


func test_map_layers_uses_a_rail_sized_plate_and_reveals_its_label_to_the_left() -> void:
	var screen := _screen()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	await wait_process_frames(2)

	var shell := screen.get("_shell") as HudShell
	var button := shell.get("_map_layers_button") as SkinnedButton
	var label_clip := shell.get("_map_layers_label_clip") as Control
	assert_eq(button.get_combined_minimum_size(),
		Vector2(UiSkin.MAP_LAYERS_ICON_SIZE, UiSkin.MAP_LAYERS_ICON_SIZE),
		"the floating shortcut is drawn smaller than a rail destination — it sits on the map")
	assert_lt(UiSkin.MAP_LAYERS_ICON_SIZE, UiSkin.DESTINATION_ICON_SIZE)
	var shadow := button.get_theme_stylebox("panel") as StyleBoxFlat
	assert_gte(shadow.corner_radius_top_left, UiSkin.MAP_LAYERS_SHADOW_RADIUS,
		"the circular artwork cannot expose a square shadow through its transparent corners")

	shell.call("_show_map_layers_label", "Map Layers", button)
	await wait_seconds(HudShell.RAIL_LABEL_TIME + 0.05)
	assert_true(label_clip.visible)
	assert_lt(label_clip.get_global_rect().position.x, button.get_global_rect().position.x,
		"the label opens toward the map from the right-hand button")
	assert_almost_eq(label_clip.get_global_rect().end.x,
		button.get_global_rect().position.x + HudShell.RAIL_LABEL_OVERLAP, 0.1,
		"the label's cap stays tucked underneath the button")


## Three readouts on an even rhythm, each in a slot of its own so the group cannot shuffle sideways
## when a figure gains a digit — a status bar that moved when the status changed.
func test_the_three_status_readouts_each_hold_a_slot_of_the_same_width() -> void:
	var screen := _screen()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	await wait_process_frames(3)

	var shell := screen.get("_shell") as HudShell
	var group := shell.top_bar.find_child("top_resources", true, false) as HBoxContainer
	# `game_screen.gd` has no `class_name` (it is reached as a registered screen), so its constants
	# come off the script rather than through one.
	var slot: float = screen.get_script().get_script_constant_map()["TOP_BAR_RESOURCE_SLOT_WIDTH"]
	assert_eq(group.get_child_count(), 3, "coins, population, and score after it")
	for item: Control in group.get_children():
		assert_eq(item.get_combined_minimum_size().x, slot,
			"%s occupies the same fixed width as its neighbours" % item.name)
	assert_eq(group.get_child(2).name, "top_score", "score sits after population, not before it")


## The group belongs on the middle of the *window*, not on the middle of whatever gap the clusters
## either side of it happen to leave. It used to be sized by a hand-tuned stretch ratio, which put it
## about ninety units right of centre at this width and a different amount wrong at every other.
func test_the_status_group_is_centred_on_the_bar_itself() -> void:
	var screen := _screen()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for width: float in [1280.0, 1000.0, 1600.0]:
		screen.size = Vector2(width, 800)
		await wait_process_frames(3)
		var shell := screen.get("_shell") as HudShell
		var host := shell.top_bar.find_child("top_resources_slot", true, false) as Control
		assert_almost_eq(host.position.x + host.size.x * 0.5, shell.top_bar.size.x * 0.5, 1.0,
			"centred at %d wide, not only at the one width a ratio was tuned for" % int(width))


func test_top_bar_speeds_use_authored_normal_and_selected_button_sets() -> void:
	var screen := _screen()
	var buttons: Dictionary = screen.get("_speed_buttons")
	assert_eq(buttons.size(), 4)
	var current := Kernel.time_driver.speed()
	var selected_count := 0
	for speed: Variant in buttons:
		var skinned := buttons[speed] as SkinnedButton
		assert_eq(skinned.get_combined_minimum_size(),
			Vector2(UiSkin.SPEED_BUTTON_SIZE, UiSkin.SPEED_BUTTON_SIZE))
		var normal := skinned.button.get_theme_stylebox("normal") as StyleBoxTexture
		var selected := skinned.button.get_theme_stylebox("pressed") as StyleBoxTexture
		var shadow := skinned.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(normal.texture, UiSkin.SPEED_BUTTON_TEXTURES[int(speed)])
		assert_eq(selected.texture, UiSkin.SPEED_BUTTON_SELECTED_TEXTURES[int(speed)])
		assert_eq(shadow.shadow_offset, UiSkin.SPEED_SHADOW_OFFSET)
		assert_eq(skinned.button.button_pressed, int(speed) == current)
		selected_count += 1 if skinned.button.button_pressed else 0
	assert_eq(selected_count, 1, "exactly one speed plate keeps its blue selected state")

	var next_speed := (current + 1) % 4
	(buttons[next_speed] as SkinnedButton).pressed.emit()
	assert_eq(Kernel.time_driver.speed(), next_speed, "the painted plate still drives game time")
	assert_true((buttons[next_speed] as SkinnedButton).button.button_pressed,
		"the newly chosen speed takes the selected artwork")
	screen.call("_set_time_speed", current)


func test_top_bar_identity_resources_and_speed_spacing_match_the_header_roles() -> void:
	var screen := _screen()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	await wait_process_frames(2)

	var shell := screen.get("_shell") as HudShell
	var identity := shell.top_bar.find_child("top_identity", true, false) as Control
	var name_label := identity.get_child(0) as Label
	var rank_label := identity.get_child(1) as Label
	assert_true(identity != null)
	assert_lt(rank_label.get_theme_font_size("font_size"),
		name_label.get_theme_font_size("font_size"), "rank is the smaller line under the name")

	var resources := shell.top_bar.find_child("top_resources", true, false) as HBoxContainer
	var resources_center := resources.get_global_rect().get_center().x
	assert_almost_eq(resources_center, screen.size.x * 0.5, 55.0,
		"gold and population occupy the centered status group")
	for resource_name in ["top_coins", "top_population"]:
		var resource := resources.find_child(resource_name, true, false) as HBoxContainer
		var icon := resource.get_child(0) as TextureRect
		var values := resource.get_node("values") as Control
		var value := values.get_node("value") as Label
		var increment := values.get_node("increment") as Label
		assert_almost_eq(icon.custom_minimum_size.x, float(UiSkin.TOP_BAR_ICON_SIZE), 0.1,
			"resource icons use the enlarged authored slot")
		assert_gt(value.get_theme_font_size("font_size"),
			increment.get_theme_font_size("font_size"),
			"resource amount is larger than its delta")
		assert_eq(increment.get_theme_font_size("font_size"), rank_label.get_theme_font_size("font_size"),
			"resource delta matches the outpost rank scale")
		assert_eq(values.get_child(1), increment, "resource delta is below the amount")
		assert_eq(increment.text, "+0", "resource delta is shown as its own line")

	var speed_row := shell.top_bar.find_child("top_speed_buttons", true, false) as HBoxContainer
	assert_eq(speed_row.get_theme_constant("separation"), 4,
		"speed plates are kept as a compact group")


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


func test_desktop_chat_is_centred_after_the_rail_and_keeps_its_width() -> void:
	var screen := _screen()
	# The test viewport is portrait by default. Give this screen a fixed desktop rect so the shell
	# exercises the rail layout without depending on the runner's own window dimensions.
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	await wait_process_frames(2)

	var shell := screen.get("_shell") as HudShell
	var chat := shell.chat_slot
	var expected_left := HudShell.RAIL_MARGIN + UiSkin.SIDEMENU_WIDTH + HudShell.CHAT_SIDE_INSET
	assert_eq(chat.offset_left, expected_left,
		"the conversation begins after the complete side menu")
	assert_eq(chat.offset_right, -expected_left,
		"the complete left clearance is mirrored on the right")
	var initial_width := chat.size.x

	shell.set_chat_expanded(true)
	await wait_process_frames(2)
	assert_eq(chat.size.x, initial_width,
		"the first expansion changes only the conversation's height")


func test_destination_panel_matches_chat_and_stays_clear_of_header_and_input() -> void:
	var screen := _screen()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	await wait_process_frames(2)
	screen.call("_open_destination", "domain")
	await wait_process_frames(2)

	var shell := screen.get("_shell") as HudShell
	var chat := shell.chat_slot
	var page := shell.get("_page_slot") as Control
	assert_eq(page.position.x, chat.position.x,
		"destination pages share the chat's left edge")
	assert_eq(page.size.x, chat.size.x,
		"destination pages share the chat's width")
	assert_eq(page.position.y, HudShell.PAGE_VERTICAL_INSET,
		"destination pages leave space below the top header")
	assert_eq(page.get_rect().end.y, chat.get_rect().position.y - HudShell.PAGE_VERTICAL_INSET,
		"destination pages stop above the collapsed chat")
