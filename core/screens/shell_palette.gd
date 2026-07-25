class_name ShellPalette
extends RefCounted

## The few colours the app shell paints itself with.
##
## Not a theme — there isn't one yet. Every screen builds its UI in code and paints its own
## background, and until a real [Theme] exists these are the values they agree on. Naming them here
## is what keeps a screen from quietly drifting a shade off, or from having no background at all and
## falling through to Godot's light default, which is what the game screen used to do: the shell
## went dark, the game went grey, and the two read as different applications.
##
## When a real theme lands, this is what it replaces.

## The standard page: menus, the new-game wizard, the load screen, the game itself.
const BACKGROUND := Color(0.07, 0.07, 0.10)

## Deliberately darker, for the moments before the shell proper — the eye should settle *into* the
## app rather than be handed full brightness at once.
const BACKGROUND_SPLASH := Color(0.05, 0.05, 0.08)
const BACKGROUND_LOADING := Color(0.06, 0.06, 0.09)


## Add a full-rect background of [param color] as [param screen]'s first child, behind everything
## else it builds. Call it before adding any content.
static func paint(screen: Control, color: Color = BACKGROUND) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nothing in a background should ever eat a click meant for the controls in front of it.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	return bg
