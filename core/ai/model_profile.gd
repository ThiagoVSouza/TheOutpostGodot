class_name ModelProfile
extends Resource

## One complete llama-server model configuration (D6).
##
## A profile owns every launch setting that materially changes model behavior or
## resource use. T3 will launch llama-server from [method server_arguments], so model
## swapping is a resource selection rather than a code path.

const BACKEND_CUDA := "cuda"
const BACKEND_CPU := "cpu"
const BACKEND_METAL := "metal"
const KNOWN_BACKENDS := [BACKEND_CUDA, BACKEND_CPU, BACKEND_METAL]

@export var profile_id: String = ""
@export var display_name: String = ""
@export var platform: String = ""
@export_enum("cuda", "cpu", "metal") var backend: String = BACKEND_CUDA
@export var server_executable_path: String = ""
@export var weights_path: String = ""
@export_range(0, 999, 1) var gpu_layers: int = 0
@export_range(1024, 131072, 1024) var context_total: int = 8192
@export_range(1, 32, 1) var parallel_slots: int = 1
@export_range(1, 32, 1) var routing_family_count: int = 1
@export_range(0, 8192, 1) var cache_reuse_tokens: int = 256
@export var reasoning_enabled: bool = false
@export_range(1, 128, 1) var threads: int = 1
@export_range(0, 1048576, 1) var required_available_ram_mib: int = 0
@export_range(0, 1048576, 1) var required_available_vram_mib: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if profile_id.strip_edges().is_empty():
		errors.append("profile_id is required")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if platform.strip_edges().is_empty():
		errors.append("platform is required")
	if not KNOWN_BACKENDS.has(backend):
		errors.append("backend is unsupported")
	if server_executable_path.strip_edges().is_empty():
		errors.append("server_executable_path is required")
	if weights_path.strip_edges().is_empty():
		errors.append("weights_path is required")
	if context_total < 1024:
		errors.append("context_total must be at least 1024")
	if parallel_slots < routing_family_count:
		errors.append("parallel_slots must cover routing_family_count")
	if reasoning_enabled:
		errors.append("reasoning must be disabled (D7)")
	if threads < 1:
		errors.append("threads must be positive")
	if required_available_ram_mib < 0 or required_available_vram_mib < 0:
		errors.append("resource floors cannot be negative")
	return errors


## Project the profile into the model-specific portion of a llama-server invocation.
## Host, port, process lifecycle, and health checks stay with T3.
func server_arguments() -> PackedStringArray:
	return PackedStringArray([
		"-m", weights_path,
		"-ngl", str(gpu_layers),
		"-c", str(context_total),
		"-np", str(parallel_slots),
		"--cache-reuse", str(cache_reuse_tokens),
		"-rea", "off",
		"-t", str(threads),
	])


## Returns a stable, player-safe capability decision:
##   { allowed: bool, reason: String }
func capability_gate(capabilities: ModelCapabilities) -> Dictionary:
	var validation := validate()
	if not validation.is_empty():
		return {"allowed": false, "reason": "invalid_profile"}
	if capabilities.platform != platform:
		return {"allowed": false, "reason": "platform_mismatch"}
	if required_available_ram_mib > 0:
		if capabilities.available_ram_mib < 0:
			return {"allowed": false, "reason": "ram_measurement_unavailable"}
		if capabilities.available_ram_mib < required_available_ram_mib:
			return {"allowed": false, "reason": "insufficient_ram"}
	if required_available_vram_mib > 0:
		if capabilities.available_vram_mib < 0:
			return {"allowed": false, "reason": "vram_measurement_unavailable"}
		if capabilities.available_vram_mib < required_available_vram_mib:
			return {"allowed": false, "reason": "insufficient_vram"}
	return {"allowed": true, "reason": ""}
