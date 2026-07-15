extends Control

## Main scene entry point.
##
## The kernel autoload has already booted and modules have registered their screens by
## the time this runs. Boot simply displays the registered start screen. It contains no
## gameplay logic — it is the seam between "kernel is ready" and "show the first screen".

func _ready() -> void:
	var start_id := Kernel.screens.start_screen_id()
	if start_id.is_empty():
		Kernel.log.warn("Boot", "No start screen was registered by any module")
		return
	var screen := Kernel.screens.instantiate(start_id)
	if screen == null:
		Kernel.log.error("Boot", "Start screen '%s' failed to instantiate" % start_id)
		return
	add_child(screen)
	Kernel.log.info("Boot", "Showing start screen '%s'" % start_id)
