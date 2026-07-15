extends Module

## Entry point for the base-game module.
##
## Registers the base game's content with the kernel through stable seams. For the
## skeleton that is just one placeholder screen; systems, commands, AI tools and
## workflows are added here (or split into sub-registrars) in later milestones.

const PLACEHOLDER_SCREEN := preload("res://modules/base_game/screens/placeholder_screen.tscn")

const SCREEN_ID := "base_game.placeholder"


func register(kernel: GameKernel) -> void:
	kernel.screens.register(SCREEN_ID, PLACEHOLDER_SCREEN, true)
	kernel.log.info("BaseGame", "Registered start screen '%s'" % SCREEN_ID)
