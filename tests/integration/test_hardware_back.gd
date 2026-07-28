extends GutTest

## The Android hardware/gesture back button (Android UX pass, 2026-07-26). `quit_on_go_back` is off
## (project.godot), so `GameKernel._handle_hardware_back()` is the only thing deciding what happens.
## Uses the *autoload* Kernel — the same arrangement `test_new_game_wizard.gd` and
## `test_settings_screen.gd` use, since these screens talk to `Kernel` directly.

func before_each() -> void:
	var host := Control.new()
	add_child_autofree(host)
	Kernel.router.set_host(host)
	# The per-frame guard below is real behaviour, but tests share a frame with each other — clear it
	# so each test's first press is not mistaken for a duplicate of the previous test's.
	Kernel.set("_last_back_frame", -1)


func _screen(id: String, params: Dictionary = {}) -> Control:
	Kernel.router.goto(id, params)
	return Kernel.router.current_screen()


func test_the_wizard_mirrors_its_own_back_button() -> void:
	var screen := _screen("core.new_game")
	screen.call("_on_next")  # step 0 -> step 1
	assert_eq(int(screen.get("_current_step")), 1)

	Kernel.call("_handle_hardware_back")

	assert_eq(int(screen.get("_current_step")), 0, "hardware back stepped back exactly like the button")


func test_the_wizards_hardware_back_on_the_first_step_goes_to_the_main_menu() -> void:
	_screen("core.new_game")
	Kernel.call("_handle_hardware_back")
	assert_eq(Kernel.router.current_id(), "core.main_menu")


func test_settings_hardware_back_goes_wherever_the_caller_said() -> void:
	_screen("core.settings", {"back": "base_game.chat"})
	Kernel.call("_handle_hardware_back")
	assert_eq(Kernel.router.current_id(), "base_game.chat")


func test_load_screens_hardware_back_returns_to_the_main_menu() -> void:
	_screen("core.load")
	Kernel.call("_handle_hardware_back")
	assert_eq(Kernel.router.current_id(), "core.main_menu")


func test_loading_hardware_back_is_swallowed_not_left_to_the_exit_dialog() -> void:
	_screen("core.loading")
	Kernel.call("_handle_hardware_back")
	# Consumed by the screen itself: no navigation happened.
	assert_eq(Kernel.router.current_id(), "core.loading")


func test_a_screen_with_nowhere_to_go_raises_the_exit_confirm_dialog() -> void:
	_screen("core.main_menu")
	Kernel.set("_exit_confirm", null)  # a prior test may have already built one

	Kernel.call("_handle_hardware_back")

	var dialog: ModalDialog = Kernel.get("_exit_confirm")
	assert_not_null(dialog, "the fallback dialog was built")
	assert_string_contains(dialog.message, "Exit")


func test_the_main_menu_exit_action_uses_the_same_confirm_dialog() -> void:
	var screen := _screen("core.main_menu")
	Kernel.set("_exit_confirm", null)

	screen.call("_on_exit")

	var dialog: ModalDialog = Kernel.get("_exit_confirm")
	assert_not_null(dialog)
	assert_eq(dialog.message, "Exit the game?")


func test_the_game_screen_also_falls_through_to_the_exit_dialog() -> void:
	# The game screen has no on-screen "back" of its own to mirror — it should behave like the main
	# menu, not silently do nothing.
	_screen("base_game.chat")
	Kernel.set("_exit_confirm", null)

	Kernel.call("_handle_hardware_back")

	assert_not_null(Kernel.get("_exit_confirm"))


func test_androids_duplicate_notification_only_navigates_one_level() -> void:
	# Android delivers WM_GO_BACK_REQUEST *twice* per press (~2 ms apart, measured on an S26 Ultra).
	# Found on device: one press took the wizard from step 2 to the main menu instead of step 1.
	# Every test above calls the handler once, so only this one proves the guard exists.
	var screen := _screen("core.new_game")
	screen.call("_on_next")
	screen.call("_on_next")
	assert_eq(int(screen.get("_current_step")), 2, "parked two steps in, with room to go back twice")

	Kernel.call("_handle_hardware_back")
	Kernel.call("_handle_hardware_back")  # the duplicate, same frame

	assert_eq(int(screen.get("_current_step")), 1, "one press moved exactly one step")


func test_a_genuinely_separate_press_still_navigates() -> void:
	# The guard must not swallow real presses — only same-frame duplicates.
	var screen := _screen("core.new_game")
	screen.call("_on_next")
	assert_eq(int(screen.get("_current_step")), 1)

	Kernel.call("_handle_hardware_back")
	await get_tree().process_frame  # a separate press lands on a later frame
	Kernel.call("_handle_hardware_back")

	assert_eq(Kernel.router.current_id(), "core.main_menu",
		"step 1 -> step 0 on the first press, then out to the menu on the second")


func test_confirming_the_exit_dialog_is_wired_to_actually_quit() -> void:
	# Never fire this in a test (it would end the process) — just prove the wiring exists, the same
	# structural check the settings-screen tests use for controls they cannot safely operate either.
	_screen("core.main_menu")
	Kernel.set("_exit_confirm", null)
	Kernel.call("_handle_hardware_back")

	var dialog: ModalDialog = Kernel.get("_exit_confirm")
	assert_gt(dialog.confirmed.get_connections().size(), 0, "Yes/Exit is connected to something")
