class_name ModelCapabilities
extends RefCounted

## Runtime measurements used to decide whether a model profile is eligible (D11).
##
## Values are intentionally injected rather than probed here: platform-specific RAM and
## VRAM measurement belongs at the runtime boundary, while this value object keeps the
## configuration gate deterministic and fully unit-testable. A negative value means the
## measurement is unavailable and fails closed for profiles that require that resource.

var platform: String
var available_ram_mib: int
var available_vram_mib: int


func _init(
	platform_name: String = "",
	ram_mib: int = -1,
	vram_mib: int = -1
) -> void:
	platform = platform_name
	available_ram_mib = ram_mib
	available_vram_mib = vram_mib
