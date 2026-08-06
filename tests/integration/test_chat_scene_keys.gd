extends GutTest

## The controls that choose what the conversation's painted scene shows.
##
## These were dev keys, and the trap that retired them is worth remembering: showing a scene **opens
## the board**, and opening the board puts the caret in the chat field — a focused [LineEdit] swallows
## every printable key, so the key that opened the scene was the last one that worked. Buttons have no
## such argument with the keyboard.


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("base_game.chat")
	add_child_autofree(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 800)
	return screen


func _dock(screen: Control) -> ChatDock:
	return (screen.get("_shell") as HudShell).get("_chat_dock") as ChatDock


## **Carrying a scene is not the same as opening the board.** The conversation still opens when the
## player asks it to and not before — a picture waiting on a closed board costs nothing, and forcing
## it open at boot would put an expanded chat over the map before anyone has spoken.
func test_setting_a_scene_does_not_open_the_conversation() -> void:
	var screen := _screen()
	await wait_process_frames(4)
	var shell := screen.get("_shell") as HudShell

	assert_true(_dock(screen).has_scene(), "the picture is there")
	assert_false(shell.is_chat_expanded(), "and the board is still closed until it is opened")


## **The board carries a picture from the moment it is built** — there is no off, and nothing has to
## be pressed to bring it on.
func test_the_conversation_opens_already_carrying_a_scene() -> void:
	var screen := _screen()
	await wait_process_frames(4)
	assert_true(_dock(screen).has_scene(), "the picture is part of the conversation, not a toggle")

	var scene_buttons := screen.get("_scene_buttons") as Array
	assert_eq(scene_buttons.size(), ChatScenes.count(), "one button per painted scene")
	for index in scene_buttons.size():
		(scene_buttons[index] as Button).pressed.emit()
		assert_true(_dock(screen).has_scene(), "scene %d stays a scene" % index)
		assert_eq(screen.get("_chat_scene"), index)


## The cast is chosen by button too, and picking nobody must not take the picture away with them.
func test_the_cast_buttons_fill_and_empty_the_stage_without_removing_the_scene() -> void:
	var screen := _screen()
	await wait_process_frames(4)
	var dock := _dock(screen)
	var cast_buttons := screen.get("_cast_buttons") as Array
	assert_eq(cast_buttons.size(), ChatScenes.CHARACTER_STEPS.size())

	for step in cast_buttons.size():
		(cast_buttons[step] as Button).pressed.emit()
		assert_true(dock.has_scene(), "the picture survives an empty stage")
		assert_eq((dock.scene.get("_characters") as Array).size(),
			int(ChatScenes.CHARACTER_STEPS[step]), "and carries that many figures")


func test_the_stage_fills_and_empties_without_disturbing_the_scene() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	var dock := _dock(screen)
	assert_true(dock.has_scene())

	# The character step is held on the screen and re-read every time the scene is drawn, so cycling
	# it must not put the picture away.
	for step in ChatScenes.CHARACTER_STEPS.size():
		screen.set("_chat_characters", step)
		screen.call("_show_chat_scene", screen.get("_chat_scene"))
		assert_true(dock.has_scene(), "the scene survives step %d" % step)
		assert_eq((dock.scene.get("_characters") as Array).size(),
			int(ChatScenes.CHARACTER_STEPS[step]), "and carries that many figures")


## The left figure is the mirror of the right one, so a pair face each other across the room rather
## than both looking the same way.
func test_a_pair_face_each_other() -> void:
	var staged := ChatScenes.characters(ChatScenes.CHARACTER_STEPS.size() - 1)
	assert_eq(staged.size(), 2)
	var sides: Array = []
	for character: Dictionary in staged:
		sides.append(int(character["side"]))
	assert_true(sides.has(1) and sides.has(-1), "one to each side of the band")


func test_hair_styles_share_the_character_canvas_and_carry_the_selected_tint() -> void:
	for style: Dictionary in ChatScenes.HAIR_STYLES:
		assert_eq((style["texture"] as Texture2D).get_size(), ChatScenes.CHARACTER_BASE.get_size(),
			"%s uses the base alignment canvas" % String(style["id"]))

	# Asked for the darkest tone, so the body is the age's ordinary painting rather than its lighter
	# one — which is the distinction `light_body` draws, and asserting `CHARACTER_BASE` outright would
	# quietly depend on whatever the default tone happens to be.
	var staged := ChatScenes.characters(1, 2, 4, ChatScenes.SKIN_TONES.size() - 1)
	var layers := staged[0]["layers"] as Array
	assert_eq(layers.size(), 2)
	assert_eq(layers[0]["texture"], ChatScenes.AGES[ChatScenes.DEFAULT_AGE]["texture"])
	assert_eq(layers[1]["texture"], ChatScenes.HAIR_STYLES[2]["texture"])
	assert_eq(layers[1]["tint"], ChatScenes.HAIR_COLORS[4]["color"])


func test_chat_hair_buttons_select_texture_and_colour() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	screen.set("_chat_characters", 1)
	screen.call("_show_chat_scene", 0)

	var controls := screen.get("_hair_controls") as VBoxContainer
	var style_buttons := screen.get("_hair_style_buttons") as Array
	var color_buttons := screen.get("_hair_color_buttons") as Array
	assert_true(controls.visible)
	assert_eq(style_buttons.size(), ChatScenes.HAIR_STYLES.size())
	assert_eq(color_buttons.size(), ChatScenes.HAIR_COLORS.size())

	(style_buttons[2] as Button).pressed.emit()
	(color_buttons[3] as Button).pressed.emit()
	var dock := _dock(screen)
	var layers := (dock.scene.get("_characters") as Array)[0]["layers"] as Array
	assert_eq(layers[1]["texture"], ChatScenes.HAIR_STYLES[2]["texture"])
	assert_eq(layers[1]["tint"], ChatScenes.HAIR_COLORS[3]["color"])
	assert_true((style_buttons[2] as Button).button_pressed)
	assert_true((color_buttons[3] as Button).button_pressed)


## Skin is one tint on the base layer, so the stack needed nothing added for it — but it must land on
## the *base* and leave the hair's own colour alone.
func test_chat_skin_buttons_tint_the_base_layer_without_touching_the_hair() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	screen.set("_chat_characters", 1)
	screen.call("_show_chat_scene", 0)

	var skin_buttons := screen.get("_skin_tone_buttons") as Array
	assert_eq(skin_buttons.size(), ChatScenes.SKIN_TONES.size())

	(skin_buttons[4] as Button).pressed.emit()
	var layers := (_dock(screen).scene.get("_characters") as Array)[0]["layers"] as Array
	var tone := layers[0]["tone"] as Dictionary
	assert_eq(tone["shadow"], ChatScenes.SKIN_TONES[4]["shadow"], "the base carries the tone's shadow")
	assert_eq(tone["highlight"], ChatScenes.SKIN_TONES[4]["highlight"], "and its highlight")
	assert_false(layers[1].has("tone"), "the hair is multiplied, not remapped")
	assert_eq(layers[1]["tint"], ChatScenes.HAIR_COLORS[ChatScenes.DEFAULT_HAIR_COLOR]["color"],
		"and keeps its own colour")
	assert_true((skin_buttons[4] as Button).button_pressed)


## **Age is a different body painting, not a tint** — so it replaces the base layer, and everything
## else composes over whichever one was picked.
func test_chat_age_buttons_swap_the_body_and_keep_the_other_choices() -> void:
	var screen := _screen()
	await wait_process_frames(2)
	screen.set("_chat_characters", 1)
	screen.call("_show_chat_scene", 0)

	var age_buttons := screen.get("_age_buttons") as Array
	assert_eq(age_buttons.size(), ChatScenes.AGES.size())

	(screen.get("_skin_tone_buttons") as Array)[3].pressed.emit()
	(age_buttons[2] as Button).pressed.emit()
	var layers := (_dock(screen).scene.get("_characters") as Array)[0]["layers"] as Array
	# Tone 3 is a mid tone, so it is painted from the age's ordinary body rather than its lighter one.
	assert_eq(layers[0]["texture"], ChatScenes.AGES[2]["texture"], "the body is the chosen age")
	assert_eq((layers[0]["tone"] as Dictionary)["shadow"], ChatScenes.SKIN_TONES[3]["shadow"],
		"and the skin tone chosen before it survives the swap")
	assert_true((age_buttons[2] as Button).button_pressed)


## Every body has to be painted on the one canvas and to the one content box, or a hairstyle would sit
## on the young head and slide off the old one — **both exposures of every age**, since a pale tone
## swaps the painting underneath the same hair.
func test_every_age_shares_the_character_canvas() -> void:
	for age: Dictionary in ChatScenes.AGES:
		for variant: String in ["texture", "light"]:
			assert_eq((age[variant] as Texture2D).get_size(), ChatScenes.CHARACTER_BASE.get_size(),
				"%s (%s) is painted on the shared canvas" % [String(age["id"]), variant])
	# Distinct paintings, not the same one listed three times.
	var seen: Array = []
	for age: Dictionary in ChatScenes.AGES:
		assert_false(seen.has(age["texture"]), "%s is its own painting" % String(age["id"]))
		seen.append(age["texture"])


## **The whole point of giving the two ends separately**: a darker tone may keep as much tonal range
## as a lighter one, where a multiply had to shrink it in step with the brightness.
func test_a_dark_tone_keeps_its_contrast_instead_of_scaling_it_away() -> void:
	var ranges: Array[float] = []
	for tone: Dictionary in ChatScenes.SKIN_TONES:
		var shadow := tone["shadow"] as Color
		var highlight := tone["highlight"] as Color
		assert_lt(shadow.v, highlight.v, "%s runs dark to light" % String(tone["id"]))
		ranges.append(highlight.v - shadow.v)

	var darkest := ChatScenes.SKIN_TONES[ChatScenes.SKIN_TONES.size() - 1]
	var lightest := ChatScenes.SKIN_TONES[0]
	assert_lt((darkest["highlight"] as Color).v, (lightest["highlight"] as Color).v,
		"the deep tone really is darker overall")
	# The multiply this replaced left the darkest tone with 44% of the original range. Anything near
	# that here would be the same failure wearing a different shape.
	assert_gt(ranges[ranges.size() - 1] / ranges[0], 0.75,
		"and keeps most of its range while doing it, rather than scaling contrast with brightness")


## **The pale tones are painted from the lighter body**, which is the whole reason it exists: the
## remap normalises whatever it is given, so reaching genuinely pale meant a painting whose midtones
## already sit high rather than a brighter ramp over a mid one.
func test_the_pale_tones_take_the_lighter_body_and_the_rest_take_the_original() -> void:
	var pale := 0
	for index in ChatScenes.SKIN_TONES.size():
		var tone: Dictionary = ChatScenes.SKIN_TONES[index]
		var layers := ChatScenes.characters(1, 0, 0, index, 0)[0]["layers"] as Array
		var body := (layers[0] as Dictionary)["texture"] as Texture2D
		if bool(tone.get("light_body", false)):
			pale += 1
			assert_eq(body, ChatScenes.AGES[0]["light"], "%s is painted light" % String(tone["id"]))
		else:
			assert_eq(body, ChatScenes.AGES[0]["texture"], "%s is not" % String(tone["id"]))
	assert_gt(pale, 0, "some tone has to use it, or the lighter paintings are dead weight")
	assert_lt(pale, ChatScenes.SKIN_TONES.size(), "and the darker end must not")


## A swatch is the tone at the level the painting's skin actually sits at — neither end of the ramp,
## which would offer a shadow or a specular rather than a complexion.
func test_a_skin_swatch_shows_the_complexion_rather_than_an_end_of_the_ramp() -> void:
	for index in ChatScenes.SKIN_TONES.size():
		var tone: Dictionary = ChatScenes.SKIN_TONES[index]
		var swatch := ChatScenes.skin_swatch(index)
		assert_gt(swatch.v, (tone["shadow"] as Color).v, "swatch %d is lighter than its shadow" % index)
		assert_lt(swatch.v, (tone["highlight"] as Color).v, "and darker than its highlight")
