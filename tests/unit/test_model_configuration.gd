extends GutTest

const CATALOG_PATH := "res://config/ai/model_catalog.tres"


func test_catalog_loads_valid_e2b_and_bonsai_profiles() -> void:
	var catalog := load(CATALOG_PATH) as ModelCatalog
	assert_not_null(catalog)
	assert_eq(catalog.validate(), PackedStringArray())
	assert_eq(catalog.profiles.size(), 2)
	assert_eq(catalog.desktop_default_profile_id, "bonsai_27b_desktop_cuda")
	assert_eq(catalog.desktop_default().display_name, "Bonsai 27B Q1_0 (desktop CUDA)")
	assert_not_null(catalog.profile("gemma_e2b_desktop_cuda"))


func test_profile_projects_complete_server_arguments() -> void:
	var catalog := load(CATALOG_PATH) as ModelCatalog
	var profile := catalog.profile("gemma_e2b_desktop_cuda")
	assert_eq(profile.server_arguments(), PackedStringArray([
		"-m", "C:/Models/gemma-4/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf",
		"-ngl", "99",
		"-c", "16384",
		"-np", "4",
		"--cache-reuse", "256",
		"-rea", "off",
		"-t", "8",
	]))
	assert_false(profile.reasoning_enabled)
	assert_eq(profile.parallel_slots, profile.routing_family_count)


func test_profile_gate_allows_sufficient_available_ram_and_vram() -> void:
	var catalog := load(CATALOG_PATH) as ModelCatalog
	var profile := catalog.desktop_default()
	var decision := profile.capability_gate(ModelCapabilities.new("Windows", 8192, 8192))
	assert_true(bool(decision["allowed"]))
	assert_eq(String(decision["reason"]), "")


func test_profile_gate_rejects_insufficient_or_unknown_resources() -> void:
	var catalog := load(CATALOG_PATH) as ModelCatalog
	var profile := catalog.desktop_default()
	var low_ram := profile.capability_gate(ModelCapabilities.new("Windows", 4096, 8192))
	assert_false(bool(low_ram["allowed"]))
	assert_eq(String(low_ram["reason"]), "insufficient_ram")
	var low_vram := profile.capability_gate(ModelCapabilities.new("Windows", 8192, 4096))
	assert_false(bool(low_vram["allowed"]))
	assert_eq(String(low_vram["reason"]), "insufficient_vram")
	var unknown_vram := profile.capability_gate(ModelCapabilities.new("Windows", 8192, -1))
	assert_false(bool(unknown_vram["allowed"]))
	assert_eq(String(unknown_vram["reason"]), "vram_measurement_unavailable")


func test_profile_gate_rejects_another_platform() -> void:
	var catalog := load(CATALOG_PATH) as ModelCatalog
	var profile := catalog.profile("gemma_e2b_desktop_cuda")
	var decision := profile.capability_gate(ModelCapabilities.new("Android", 8192, 8192))
	assert_false(bool(decision["allowed"]))
	assert_eq(String(decision["reason"]), "platform_mismatch")


func test_invalid_profile_rejects_reasoning_and_underprovisioned_slots() -> void:
	var profile := ModelProfile.new()
	profile.profile_id = "invalid"
	profile.display_name = "Invalid profile"
	profile.platform = "Windows"
	profile.server_executable_path = "server.exe"
	profile.weights_path = "model.gguf"
	profile.reasoning_enabled = true
	profile.parallel_slots = 1
	profile.routing_family_count = 2
	var errors := profile.validate()
	assert_has(errors, "reasoning must be disabled (D7)")
	assert_has(errors, "parallel_slots must cover routing_family_count")
	var decision := profile.capability_gate(ModelCapabilities.new("Windows", 16384, 16384))
	assert_false(bool(decision["allowed"]))
	assert_eq(String(decision["reason"]), "invalid_profile")
