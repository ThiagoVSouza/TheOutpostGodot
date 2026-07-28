class_name AppShell
extends RefCounted

## Registers the core app-shell screens (loading, main menu, new game, load) with the
## [ScreenRegistry]. These are core — module-agnostic — the flow the [ScreenRouter] drives before
## and around any module's game screen. None is flagged as the start screen: the router navigates to
## them explicitly (the boot scene sends it to `core.loading`). Called once from [method GameKernel.boot].
##
## There is no splash screen here. The engine's own boot splash is the game's splash — it is on screen
## before a scene can exist, so a scene repeating it would simply be a second one.

## The cue the whole shell is scored with — logo, menu, wizard, load screen. Named here, where the
## shell's screens are named, so the shell has one answer to "what is playing" rather than four.
const SHELL_MUSIC := "main_menu"

const LOADING := preload("res://core/screens/loading_screen.tscn")
const MAIN_MENU := preload("res://core/screens/main_menu_screen.tscn")
const NEW_GAME := preload("res://core/screens/new_game_screen.tscn")
const LOAD := preload("res://core/screens/load_screen.tscn")
const SETTINGS := preload("res://core/screens/settings_screen.tscn")


static func register_screens(kernel: GameKernel) -> void:
	kernel.screens.register("core.loading", LOADING)
	kernel.screens.register("core.main_menu", MAIN_MENU)
	kernel.screens.register("core.new_game", NEW_GAME)
	kernel.screens.register("core.load", LOAD)
	kernel.screens.register("core.settings", SETTINGS)
