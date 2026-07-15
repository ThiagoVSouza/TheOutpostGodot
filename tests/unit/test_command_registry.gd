extends GutTest

## CommandRegistry is the whitelist boundary: only registered names can be built.

func test_whitelisted_create_succeeds() -> void:
	var reg := CommandRegistry.new()
	reg.register("grant_resource", GrantResourceCommand.from_args)
	assert_true(reg.has("grant_resource"))
	var cmd := reg.create("grant_resource", {"resource": "gold", "amount": 2})
	assert_not_null(cmd, "whitelisted command should be built")
	assert_eq(cmd.command_name(), "grant_resource")


func test_unknown_name_is_rejected() -> void:
	var reg := CommandRegistry.new()
	assert_false(reg.has("delete_everything"))
	assert_null(reg.create("delete_everything", {}), "unknown command must not be built")
