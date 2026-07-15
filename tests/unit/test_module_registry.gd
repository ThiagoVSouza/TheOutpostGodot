extends GutTest

## Smoke test for the boot skeleton: the kernel boots, discovers the base_game
## module from its .tres manifest, and that module registers its start screen.


func test_kernel_boots_and_loads_base_game() -> void:
	var kernel := GameKernel.new()
	add_child_autofree(kernel)  # entering the tree triggers _ready() -> boot()

	assert_true(kernel.is_booted(), "kernel should be booted after entering the tree")
	assert_true(kernel.modules.is_loaded("base_game"), "base_game module should load")
	assert_true(
		kernel.screens.has("base_game.placeholder"),
		"base_game should register its placeholder screen"
	)
	assert_eq(
		kernel.screens.start_screen_id(),
		"base_game.placeholder",
		"placeholder should be the start screen"
	)


func test_module_registry_discovers_manifest() -> void:
	var registry := ModuleRegistry.new(GameLog.new())
	var manifests := registry.discover()

	var ids: Array = []
	for m in manifests:
		ids.append(m.id)
	assert_has(ids, "base_game", "discover() should find the base_game manifest")


func test_resolve_order_skips_missing_dependency() -> void:
	var registry := ModuleRegistry.new(GameLog.new())

	var good := ModuleManifest.new()
	good.id = "good"
	good.entry_script = Module

	var broken := ModuleManifest.new()
	broken.id = "broken"
	broken.entry_script = Module
	broken.dependencies = ["does_not_exist"]

	var manifests: Array[ModuleManifest] = [good, broken]
	var ordered := registry.resolve_order(manifests)

	var ids: Array = []
	for m in ordered:
		ids.append(m.id)
	assert_has(ids, "good", "module with satisfiable deps should be ordered")
	assert_does_not_have(ids, "broken", "module with a missing dependency should be skipped")
