class_name SafeArea
extends RefCounted

## How far a screen's *content* must stay clear of the display's edges — a navigation bar or a camera
## cutout the window itself does not already account for.
##
## **On the S26 Ultra this measures 0, and that is the correct answer.** Android hands the app a
## window already sized to the usable area (1080x2100 of a 1080x2340 screen — the navigation bar is
## excluded before Godot ever sees it), so `get_display_safe_area()` matches
## `screen_get_usable_rect()` and there is nothing left to avoid. This is kept for the devices and
## orientations where that is *not* true (gesture navigation drawing edge to edge, a side cutout in
## landscape), where content on that edge would otherwise be clipped.
##
## **Padding, never a smaller canvas.** The first attempt at this inset the whole router host, which
## produced the opposite of safe: it read the pre-settle window size during boot, shrank the app
## below the window Android had already sized correctly, and left a strip that no screen painted —
## screens paint their background *inside* the host — so it fell through to Godot's light grey and
## read as the app failing to fill the screen. Every screen now covers the entire window; only the
## controls on an affected edge move in.
##
## `DisplayServer.get_display_safe_area()` is Android/iOS-only; everywhere else (desktop, headless)
## it matches the screen and every accessor below returns 0.


## The bottom inset in *logical* units — the space a screen's own margins live in.
##
## The display server answers in physical pixels, which is a different scale from the stretched
## viewport whenever `display/window/stretch/mode` is set (project.godot); on the S26 Ultra that is
## 1.5x, so using the raw number would reserve half as much room again as the bar actually occupies.
static func bottom(viewport: Viewport) -> int:
	if viewport == null or DisplayServer.get_name() == "headless":
		return 0
	var screen := Rect2(DisplayServer.screen_get_usable_rect())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.size.y <= 0.0 or safe.size == Vector2.ZERO or safe == screen:
		return 0
	var physical_inset := screen.end.y - safe.end.y
	if physical_inset <= 0.0:
		return 0
	return int(physical_inset * viewport.get_visible_rect().size.y / screen.size.y)
