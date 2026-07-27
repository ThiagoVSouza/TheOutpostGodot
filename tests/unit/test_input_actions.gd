extends GutTest

## The rebindable action set: what key each action ends up on, and the rules that decide it.
##
## `InputActions.install()` mutates the process-wide [InputMap], so every test here restores the
## real bindings afterwards — the autoload Kernel installed them at boot and the rest of the suite
## (and the running app) shares that state.

const SCRATCH := "user://test_input.cfg"

var _settings: AppSettings


func before_each() -> void:
	_settings = AppSettings.new(SCRATCH)
	_settings.persist = false  # nothing here needs disk; the persistence test opts back in


func after_each() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)
	# Put the InputMap back the way the running app had it.
	InputActions.install(Kernel.settings)


func test_every_action_has_a_default_key_and_a_group() -> void:
	# An action with no default is one the player has to discover is unbound.
	for action: Dictionary in InputActions.ACTIONS:
		assert_ne(int(action["default"]), KEY_NONE,
			"'%s' has a default key" % action["id"])
		assert_false(String(action["group"]).is_empty(), "'%s' has a group" % action["id"])


func test_no_two_actions_ship_on_the_same_default_key() -> void:
	# A conflict the player never made and cannot see, since the defaults are not shown as overrides.
	var seen: Dictionary = {}
	for action: Dictionary in InputActions.ACTIONS:
		var key := int(action["default"])
		assert_false(seen.has(key), "'%s' and '%s' both default to %s" %
			[seen.get(key, ""), action["id"], InputActions.key_name(key)])
		seen[key] = action["id"]


func test_install_registers_every_action_on_its_default() -> void:
	InputActions.install(_settings)
	for id: String in InputActions.ids():
		assert_true(InputMap.has_action(id), "'%s' is registered" % id)
		var event := InputEventKey.new()
		event.keycode = InputActions.default_keycode(id)
		assert_true(InputMap.event_is_action(event, id), "'%s' answers to its default key" % id)


func test_an_override_beats_the_default() -> void:
	_settings.set_key_binding(InputActions.TOGGLE_PAUSE, KEY_J)
	InputActions.install(_settings)

	assert_eq(InputActions.keycode_for(InputActions.TOGGLE_PAUSE, _settings), KEY_J)
	var event := InputEventKey.new()
	event.keycode = KEY_J
	assert_true(InputMap.event_is_action(event, InputActions.TOGGLE_PAUSE))
	event.keycode = InputActions.default_keycode(InputActions.TOGGLE_PAUSE)
	assert_false(InputMap.event_is_action(event, InputActions.TOGGLE_PAUSE),
		"and the default no longer triggers it")


func test_unbound_is_not_the_same_as_having_no_override() -> void:
	# The bug this constant exists for: an action whose key was taken by another action must end up
	# with *no* key. Storing "no override" would fall back to the default — the very key that was
	# just taken — and the clash would survive the fix.
	_settings.set_key_binding(InputActions.TOGGLE_PAUSE, AppSettings.UNBOUND)

	assert_eq(InputActions.keycode_for(InputActions.TOGGLE_PAUSE, _settings), KEY_NONE)
	assert_ne(InputActions.keycode_for(InputActions.TOGGLE_PAUSE, _settings),
		InputActions.default_keycode(InputActions.TOGGLE_PAUSE),
		"unbound must not quietly mean 'back to the default'")


func test_an_unbound_action_stays_registered_but_answers_to_nothing() -> void:
	# Callers ask `event.is_action(...)` unconditionally; an action that vanished from the InputMap
	# would make those calls error rather than simply answer false.
	_settings.set_key_binding(InputActions.TOGGLE_PAUSE, AppSettings.UNBOUND)
	InputActions.install(_settings)

	assert_true(InputMap.has_action(InputActions.TOGGLE_PAUSE))
	var event := InputEventKey.new()
	event.keycode = InputActions.default_keycode(InputActions.TOGGLE_PAUSE)
	assert_false(InputMap.event_is_action(event, InputActions.TOGGLE_PAUSE))


func test_action_using_finds_the_holder_of_a_key() -> void:
	var pause_key := InputActions.default_keycode(InputActions.TOGGLE_PAUSE)
	assert_eq(InputActions.action_using(pause_key, _settings), InputActions.TOGGLE_PAUSE)
	assert_eq(InputActions.action_using(pause_key, _settings, InputActions.TOGGLE_PAUSE), "",
		"the action asking about its own key is not a conflict with itself")


func test_no_key_is_never_reported_as_a_conflict() -> void:
	# Any number of actions may be unbound at once, so "nothing" must not read as a clash.
	_settings.set_key_binding(InputActions.TOGGLE_PAUSE, AppSettings.UNBOUND)
	_settings.set_key_binding(InputActions.OPEN_MAP, AppSettings.UNBOUND)
	assert_eq(InputActions.action_using(KEY_NONE, _settings), "")


func test_key_name_reads_as_the_player_would_say_it() -> void:
	assert_eq(InputActions.key_name(KEY_F5), "F5")
	assert_eq(InputActions.key_name(KEY_NONE), "Unbound")
