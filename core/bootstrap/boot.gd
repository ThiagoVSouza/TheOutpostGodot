extends Control

## Main scene entry point.
##
## The kernel autoload has booted and modules have registered their screens by the time this runs.
## Boot is the mount point for the [ScreenRouter]: it hosts the screens and starts the flow. It
## contains no gameplay logic — it is the seam between "kernel is ready" and "show the first screen".

func _ready() -> void:
	Kernel.router.set_host(self)

	# Dev bypass: skip the shell and land straight in the game/playground, resuming as before. Keeps
	# the fast inner-loop for hand-testing the AI/workflow path (OUTPOST_PLAYGROUND=1).
	if OS.get_environment("OUTPOST_PLAYGROUND") == "1":
		var resumed: Dictionary = Kernel.session.continue_or_start()
		if bool(resumed["continued"]):
			Kernel.log.info("Boot", "Continued '%s' (from the %s)" % [
				Kernel.session.slot_name, resumed["source"]])
		var start_id := Kernel.screens.start_screen_id()
		if not start_id.is_empty():
			Kernel.router.goto(start_id)
		return

	# The normal flow: the shell owns *when* to resume — the main menu's Continue does it, not boot.
	Kernel.router.goto("core.splash")
