class_name ModelRuntimeProbe
extends RefCounted

## Windows-only measurements at the runtime boundary for T3's model gate.
##
## T4 intentionally kept [ModelCapabilities] injectable. This probe is the small
## platform adapter that supplies those values before a desktop process is started.
## Unknown measurements remain -1, which causes profiles that require them to fail
## closed through [method ModelProfile.capability_gate].


static func probe() -> ModelCapabilities:
	var platform := OS.get_name()
	if platform != "Windows":
		return ModelCapabilities.new(platform, -1, -1)
	return ModelCapabilities.new(platform, _available_ram_mib(), _available_vram_mib())


static func _available_ram_mib() -> int:
	var output: Array = []
	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-Command",
			"Add-Type -AssemblyName Microsoft.VisualBasic; [Math]::Floor(([Microsoft.VisualBasic.Devices.ComputerInfo]::new().AvailablePhysicalMemory / 1MB)).ToString([System.Globalization.CultureInfo]::InvariantCulture)",
		]),
		output,
		true
	)
	if exit_code != 0 or output.is_empty():
		return -1
	var text: String = String(output[0]).strip_edges()
	if not text.is_valid_int():
		return -1
	return text.to_int()


static func _available_vram_mib() -> int:
	var output: Array = []
	var exit_code := OS.execute(
		"nvidia-smi.exe",
		PackedStringArray(["--query-gpu=memory.free", "--format=csv,noheader,nounits"]),
		output,
		true
	)
	if exit_code != 0 or output.is_empty():
		return -1
	var highest_free_mib := -1
	var lines := String(output[0]).split("\n", false)
	for line in lines:
		var value := String(line).strip_edges()
		if value.is_valid_int():
			highest_free_mib = max(highest_free_mib, value.to_int())
	return highest_free_mib
