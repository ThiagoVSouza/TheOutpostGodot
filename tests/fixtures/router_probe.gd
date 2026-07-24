extends Control

## Test fixture (not a test): a screen that records the params the router hands it via on_enter,
## so test_screen_router can assert the router delivers them. Named without a `test_` prefix so GUT
## does not treat it as a suite.

var entered_params: Dictionary = {}


func on_enter(params: Dictionary) -> void:
	entered_params = params.duplicate()
