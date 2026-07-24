extends GutTest

## The new-game wizard (Background -> Location -> Identity -> Settings): step navigation, and that
## the choices made on every step reach `begin_new_game` intact.
##
## Uses the *autoload* Kernel, not a fresh GameKernel: `new_game_screen.gd` talks to `Kernel`
## directly, the same arrangement `test_confirmation_ui.gd` and `test_input_router.gd` use.

func before_each() -> void:
	# The real app sets this once from the boot scene (core/bootstrap/boot.gd); nothing plays that
	# role in a headless test run, so router.goto would otherwise be a no-op with a push_error.
	var host := Control.new()
	add_child_autofree(host)
	Kernel.router.set_host(host)


func _screen() -> Control:
	var screen: Control = Kernel.screens.instantiate("core.new_game")
	add_child_autofree(screen)
	return screen


func test_starts_on_the_background_step() -> void:
	var screen := _screen()
	assert_eq(int(screen.get("_current_step")), 0)


func test_next_advances_through_every_step_and_back_reverses() -> void:
	var screen := _screen()
	for _i in range(3):
		screen.call("_on_next")
	assert_eq(int(screen.get("_current_step")), 3, "four steps, zero-indexed")

	screen.call("_on_back")
	assert_eq(int(screen.get("_current_step")), 2)


func test_back_on_the_first_step_returns_to_the_main_menu() -> void:
	var screen := _screen()
	screen.call("_on_back")
	assert_eq(Kernel.router.current_id(), "core.main_menu")


func test_finishing_the_wizard_seeds_the_choices_made() -> void:
	var screen := _screen()
	screen.set("_selected_background", "knight")
	screen.set("_selected_location", "mountains")
	screen.set("_selected_verbosity", "long")
	screen.set("_sex", "female")
	(screen.get("_name_field") as LineEdit).text = "Livia"
	(screen.get("_outpost_name_field") as LineEdit).text = "Stonegate"
	var flag: FlagValue = screen.get("_flag_value")
	flag.shape_color = Color.html("#2f5fc0")

	for _i in range(3):
		screen.call("_on_next")
	screen.call("_on_next")  # the last step's Next button reads "Start"

	assert_eq(Kernel.router.current_id(), "core.loading", "the seeded game is entered")
	assert_eq(String(Entities.get_entity(Kernel.state, "hero").get("name", "")), "Livia")
	assert_eq(String(Entities.get_entity(Kernel.state, "outpost").get("name", "")), "Stonegate")

	var profile: Dictionary = Kernel.state.get_value("profile", {})
	assert_eq(String(profile.get("background", "")), "knight")
	assert_eq(String(profile.get("outpost_location", "")), "mountains")
	assert_eq(String(profile.get("sex", "")), "female")
	assert_eq(String(profile.get("verbosity", "")), "long")

	var flag_dict: Dictionary = Kernel.state.get_value("outpost_flag", {})
	assert_eq(String(flag_dict.get("shapeColor", "")), "#2f5fc0")


func test_defaults_are_used_when_the_player_changes_nothing() -> void:
	var screen := _screen()
	for _i in range(4):
		screen.call("_on_next")

	assert_eq(String(Entities.get_entity(Kernel.state, "hero").get("name", "")), "Marcus")
	assert_eq(String(Entities.get_entity(Kernel.state, "outpost").get("name", "")), "Ravenwatch")
