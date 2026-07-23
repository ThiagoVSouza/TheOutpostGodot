class_name AppShell
extends RefCounted

## Registers the core app-shell screens (splash, loading, main menu, new game, load) with the
## [ScreenRegistry]. These are core — module-agnostic — the flow the [ScreenRouter] drives before
## and around any module's game screen. None is flagged as the start screen: the router navigates to
## them explicitly (the boot scene sends it to `core.splash`). Called once from [method GameKernel.boot].

const SPLASH := preload("res://core/screens/splash_screen.tscn")
const LOADING := preload("res://core/screens/loading_screen.tscn")
const MAIN_MENU := preload("res://core/screens/main_menu_screen.tscn")
const NEW_GAME := preload("res://core/screens/new_game_screen.tscn")
const LOAD := preload("res://core/screens/load_screen.tscn")


static func register_screens(kernel: GameKernel) -> void:
	kernel.screens.register("core.splash", SPLASH)
	kernel.screens.register("core.loading", LOADING)
	kernel.screens.register("core.main_menu", MAIN_MENU)
	kernel.screens.register("core.new_game", NEW_GAME)
	kernel.screens.register("core.load", LOAD)
