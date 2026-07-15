extends Control

## Placeholder start screen for the base game.
##
## Exists to prove the module -> screen-registry -> navigation seam. Real base-game
## screens replace this in later milestones.

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# The kernel is guaranteed booted here (autoloads ready before the main scene).
	if Kernel.ai != null:
		Kernel.log.debug("PlaceholderScreen", "AI backend: %s" % Kernel.ai.backend_id())
