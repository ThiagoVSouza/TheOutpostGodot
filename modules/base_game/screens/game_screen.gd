extends Control

## The wireframed game shell (M8 Phase 1, ux_plan.md): the overworld map as the base layer with
## persistent chrome around it via [HudShell], and the running conversation as a dock over the map
## instead of the routed screen it used to be. Replaces `chat_screen.gd` + `map_overlay.gd` — the
## map no longer needs its own toggle (`MapOverlay`'s reason for existing, ux_plan.md §2.1) because
## it is always on screen now, and Main Menu (Save/Load/New Game/dev tools) opens as a panel in the
## same shell instead of living in a permanent "dev row" (ux_plan.md §2.2, Phase 1's "nothing may
## regress" clause). The other six wireframed rail destinations are Phase 5's panel registry —
## deliberately not built here.
##
## **Field/method names kept from `chat_screen.gd`** (`_log_label`, `_input`, `_send_button`,
## `_pending_row`, `_pending_instance`, `_answer`, `_on_new_game`): `tests/integration/
## test_confirmation_ui.gd` and `tools/capture_screens.gd` reach into a screen instantiated as
## `"base_game.chat"` by exactly these names. Keeping them is Phase 1's "nothing may regress"
## promise kept literally, rather than by updating every caller.

const HEADER_FLAG_WIDTH := 26.0
const MARKER_FLAG_WIDTH := 30.0

var _shell: HudShell
var _map_view: OverworldMapView

var _source: AiInputSource
var _outpost_label: Label
var _flag_view: FlagView
var _gold_label: Label
var _population_label: Label
var _date_label: Label
var _log_label: RichTextLabel
var _message_list: ChatMessageList
var _input: LineEdit
var _send_button: Button
var _retry_button: Button
var _chat_expand_button: Button
var _event_image: Control
var _speed_buttons: Dictionary = {}
var _trace_label: RichTextLabel

## The question the game master is waiting on, if any (M4/B4b). Lives in the dock, not inside the
## collapsible expanded-chat panel, so it stays visible to answer whether or not chat is expanded.
var _pending_row: HBoxContainer
var _pending_label: Label
var _pending_instance: String = ""
var _slots: OptionButton

var _chat_panel: HudPanel
var _menu_panel: HudPanel


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	_source = Kernel.input_router.create_source("typed")
	# Replies arrive via the event bus (D18), not as a return value of the submit call.
	Kernel.events.subscribe(AiInputRouter.EVENT_TURN_COMPLETED, _on_turn_completed)
	# Surface workflow emits (e.g. the end-of-month report) in the conversation log.
	Kernel.events.subscribe("workflow_emit", _on_workflow_emit)
	# T5: reflect AI outage/recovery state as system messages + the Retry control.
	Kernel.events.subscribe(AiAvailability.EVENT_NAME, _on_ai_availability_changed)
	Kernel.events.subscribe("day_passed", _on_day_passed)
	if Kernel.time_driver != null:
		Kernel.time_driver.speed_changed.connect(_on_time_speed_changed)
	_shell.breakpoint_changed.connect(_on_shell_breakpoint_changed)
	call_deferred("_sync_speed_layout")
	# The shell's theme belongs to the menus, not to play. There is no in-game score yet, and
	# silence is a better answer than the title music running under a conversation.
	Kernel.audio.stop_music()
	# Status is shown before the greeting so day/resources are up even while a narrated opening
	# (an AI await) is still resolving.
	_refresh_outpost()
	_refresh_day()
	_refresh_resources()
	_refresh_slots()
	# Boot has already resumed the session by now, so say which settlement this is — opening
	# into a loaded world with no acknowledgement reads as if nothing was saved.
	if Kernel.session.has_slot():
		_append("[b]%s[/b] — day %d. Welcome back." % [Kernel.session.slot_name, Kernel.clock.total_days])
	elif not (Kernel.state.get_value("opening", {}) as Dictionary).is_empty():
		# A fresh game carries the opening's facts; play the narrated opening over them.
		await _play_opening()
	else:
		_append("[b]The Outpost[/b] — the game master awaits. Describe what you do.")
	# The GATE 0 call for M4: a question the player was asked before they closed the game is
	# put back in front of them, not silently cancelled. B1 kept the instance; this is the half
	# that lets them actually answer it.
	_present_oldest_pending()


## The play actions, as actions rather than keycodes — which is what makes them rebindable. Each
## does exactly what its on-screen control does. The kernel-level time driver owns the world gate,
## so every speed key inherits the same block while a turn, event, or plan tick is unresolved.
##
## `_unhandled_input` matters here: the chat input is a focused [LineEdit] most of the time, and it
## consumes the keystrokes meant for it before this ever runs. That is why "focus the input" can be
## a bare letter without stealing typing.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action(InputActions.FOCUS_INPUT):
		if _input.editable:
			_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.TOGGLE_PAUSE):
		Kernel.time_driver.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.SPEED_1):
		_set_time_speed(TimeDriver.Speed.SPEED_1)
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.SPEED_2):
		_set_time_speed(TimeDriver.Speed.SPEED_2)
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.SPEED_3):
		_set_time_speed(TimeDriver.Speed.SPEED_3)
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.OPEN_CHAT):
		_shell.set_chat_expanded(true)
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.OPEN_MAP):
		_on_open_map()
		get_viewport().set_input_as_handled()
	elif event.is_action(InputActions.QUICK_SAVE):
		_on_save()
		get_viewport().set_input_as_handled()


## Esc closes whatever panel is on top before falling through to the exit-confirm dialog
## (ux_plan.md §1.3 rule 6) — `BACK_CLOSE` reaches here via `Kernel.request_back()`
## (`core/kernel.gd`'s `_handle_hardware_back`).
func on_hardware_back() -> bool:
	return _shell.close_topmost()


## Play the narrated opening for a fresh game (the throne room, the king's charge). Narration is a
## workflow (D30), so this runs the authored `opening` workflow through the executor and renders its
## prose — the same seam a turn narrates through, not a hardcoded string. Input is locked while it
## resolves (a real narrator is an AI await); the opening facts are cleared afterward so it does not
## replay if the screen remounts within the session.
func _play_opening() -> void:
	var facts: Dictionary = Kernel.state.get_value("opening", {})
	var definition: Variant = Kernel.workflow_registry.get_definition("opening")
	if not (definition is Dictionary):
		_append("[b]The Outpost[/b] — the game master awaits. Describe what you do.")
		return
	_set_busy(true)
	var instance := WorkflowInstance.create(
		"opening", int((definition as Dictionary).get("version", 1)), facts, 0)
	var result: RefCounted = await WorkflowExecutor.for_kernel(Kernel).run(
		definition as Dictionary, instance, AiTrace.new())
	var prose := String(result.get("narration"))
	if prose.is_empty():
		# The narrator produced nothing (an outage, or the base stub): a fresh game still opens.
		prose = "The King has granted you the outpost. Make it endure."
	_append("[color=wheat]%s[/color]" % prose)
	Kernel.state.set_value("opening", {})  # played once; do not replay on remount
	_set_busy(false)


# --- building --------------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_shell = HudShell.new()
	add_child(_shell)
	_shell.chat_expanded_changed.connect(_on_chat_expanded_changed)

	_build_map()
	_build_top_bar()
	_build_chat_panel()
	_build_dock()
	_build_menu_panel()
	_shell.add_rail_action("Menu", _open_main_menu)


func _build_map() -> void:
	_map_view = OverworldMapView.new()
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.base_layer.add_child(_map_view)
	var map := BaseGameMap.load_map()
	if map == null:
		return
	_map_view.setup(map, BaseGameMap.load_textures(map))
	_refresh_map_marker()


## The outpost's banner pinned to the cell the seed founded it on. A separate call from
## `_build_map` because a New Game or Load started from inside the running shell (the Main Menu
## panel) can change *which* cell that is without the terrain itself changing — the old
## `MapOverlay` got this for free by rebuilding from scratch on every open; the map is now built
## once, so anything that can change the outpost's site has to ask for this explicitly.
func _refresh_map_marker() -> void:
	if _map_view == null:
		return
	_map_view.remove_marker("outpost")
	var site: Dictionary = Kernel.state.get_value(GameSession.OUTPOST_SITE_STATE_KEY, {})
	if site.is_empty():
		return
	var flag := FlagView.new()
	flag.custom_minimum_size = Vector2(MARKER_FLAG_WIDTH, MARKER_FLAG_WIDTH * FlagView.aspect())
	flag.set_value(FlagValue.from_dict(
		Kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {}) as Dictionary))
	_map_view.set_marker("outpost", Vector2i(int(site["x"]), int(site["y"])), flag)


## The status readout the wireframes' top bar specifies (ux_plan.md §1.1, M8 Phase 2): flag, domain
## name + a placeholder domain-level tier, coins and population each with a placeholder delta (no
## economy computes a real one yet — ux_plan.md §5 — a neutral-coloured "+0" is the honest answer,
## not an invented number), and the real date via `DateFormat`. "Let a day pass" stays a real
## button here — it only retires once Phase 4's `TimeDriver` replaces it with the four speeds.
func _build_top_bar() -> void:
	var bar := _shell.top_bar
	_flag_view = FlagView.new()
	_flag_view.custom_minimum_size = Vector2(HEADER_FLAG_WIDTH, HEADER_FLAG_WIDTH * FlagView.aspect())
	_flag_view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_flag_view)

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 0)
	bar.add_child(identity)
	_outpost_label = Label.new()
	_outpost_label.add_theme_font_size_override("font_size", 16)
	identity.add_child(_outpost_label)
	var domain_level := Label.new()
	# The growth axis the wireframe implies (Outpost -> Village -> Town -> ...) has no system
	# behind it yet — a fixed tier, not a computed one, until M7 designs the ladder (ux_plan.md §5).
	domain_level.text = "Outpost"
	domain_level.modulate = OutpostTheme.TEXT_MUTED
	domain_level.add_theme_font_size_override("font_size", 12)
	identity.add_child(domain_level)

	_gold_label = Label.new()
	bar.add_child(_gold_label)
	_population_label = Label.new()
	bar.add_child(_population_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_date_label = Label.new()
	bar.add_child(_date_label)
	for speed in [TimeDriver.Speed.PAUSED, TimeDriver.Speed.SPEED_1,
			TimeDriver.Speed.SPEED_2, TimeDriver.Speed.SPEED_3]:
		var button := Button.new()
		button.text = ["||", ">", ">>", ">>>"][speed]
		button.toggle_mode = true
		button.tooltip_text = ["Pause", "Speed 1", "Speed 2", "Speed 3"][speed]
		button.pressed.connect(_set_time_speed.bind(speed))
		bar.add_child(button)
		_speed_buttons[speed] = button
	_refresh_time_buttons()


## The expanded-chat shape (ux_plan.md §1.2 state 2): built once and kept parented under
## `_shell.chat_slot` for the screen's whole lifetime (see [HudShell]'s class doc) so the log and
## trace survive being collapsed and re-expanded.
func _build_chat_panel() -> void:
	_chat_panel = HudPanel.new()
	_shell.chat_slot.add_child(_chat_panel)
	_chat_panel.set_title("Conversation")
	_chat_panel.dismissed.connect(func() -> void: _shell.set_chat_expanded(false))

	var event_image := PanelContainer.new()
	_event_image = event_image
	event_image.custom_minimum_size = Vector2(0, 120)
	event_image.tooltip_text = "Event artwork"
	var event_style := StyleBoxFlat.new()
	event_style.bg_color = Color(0.09, 0.10, 0.14)
	event_style.border_color = OutpostTheme.BORDER
	event_style.set_border_width_all(1)
	event_style.set_corner_radius_all(OutpostTheme.CORNER_RADIUS)
	event_image.add_theme_stylebox_override("panel", event_style)
	_chat_panel.body.add_child(event_image)
	var placeholder := VBoxContainer.new()
	placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
	event_image.add_child(placeholder)
	var placeholder_title := Label.new()
	placeholder_title.text = "Event illustration"
	placeholder_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_title.add_theme_color_override("font_color", OutpostTheme.TEXT_MUTED)
	placeholder.add_child(placeholder_title)
	var placeholder_note := Label.new()
	placeholder_note.text = "Artwork arrives with the authored event."
	placeholder_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_note.add_theme_color_override("font_color", OutpostTheme.TEXT_DISABLED)
	placeholder.add_child(placeholder_note)

	_message_list = ChatMessageList.new()
	_chat_panel.body.add_child(_message_list)

	# Existing integration tests inspect this semantic transcript directly. It remains as a
	# hidden mirror while the visible conversation is rendered as structured message rows.
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.visible = false
	_chat_panel.body.add_child(_log_label)


## The bottom edge, full width, always visible (ux_plan.md §1.1) — the input line the wireframes'
## "Main" state collapses everything else to, plus the pending-question row (kept out of the
## collapsible panel above so an unanswered question is never hidden by a collapsed chat).
func _build_dock() -> void:
	var dock := _shell.dock

	_pending_row = HBoxContainer.new()
	_pending_row.visible = false
	dock.add_child(_pending_row)
	_pending_label = Label.new()
	_pending_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_row.add_child(_pending_label)
	var yes := Button.new()
	yes.text = "Yes"
	yes.pressed.connect(func() -> void: await _answer(true))
	_pending_row.add_child(yes)
	var no := Button.new()
	no.text = "No"
	no.pressed.connect(func() -> void: await _answer(false))
	_pending_row.add_child(no)

	var input_row := HBoxContainer.new()
	dock.add_child(input_row)
	_chat_expand_button = Button.new()
	_chat_expand_button.text = "^"
	_chat_expand_button.tooltip_text = "Show conversation"
	_chat_expand_button.pressed.connect(
		func() -> void: _shell.set_chat_expanded(not _shell.is_chat_expanded()))
	input_row.add_child(_chat_expand_button)
	_input = LineEdit.new()
	_input.placeholder_text = "e.g. I send scouts to forage the hills"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_submit)
	input_row.add_child(_input)
	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.pressed.connect(func() -> void: _on_submit(_input.text))
	input_row.add_child(_send_button)
	_retry_button = Button.new()
	_retry_button.text = "Retry connection"
	_retry_button.visible = false
	_retry_button.pressed.connect(func() -> void: Kernel.ai_availability.retry())
	input_row.add_child(_retry_button)


func _on_chat_expanded_changed(expanded: bool) -> void:
	_chat_expand_button.text = "v" if expanded else "^"


## The Main Menu panel (ux_plan.md §2.2: "Main Menu is one of the seven destinations and opens as a
## panel... the player does not leave the game shell unless they choose to"). Carries forward
## exactly the old dev row's controls (Save / slots+Load / New game / dev-ask / trace toggle —
## Phase 1's "nothing may regress"), plus Settings and Quit to title, which the wireframe's own
## description of this panel names. Built once, like the chat panel, so the trace label's last
## content survives being closed and reopened.
func _build_menu_panel() -> void:
	_menu_panel = HudPanel.new()
	# Parented immediately, hidden, so `HudPanel._ready()` builds `.body`/its title label before
	# anything below touches them — configuring first and parenting later (`_shell.show_page` does
	# that part, on the player's first Menu click) would find both still null, the same "0x0 at
	# _ready" shape as the `map_overlay.gd` anchors trap, just for construction order instead of
	# anchors. `HudShell.show_page` reparents it into the page slot the first time it is shown.
	_menu_panel.visible = false
	add_child(_menu_panel)
	_menu_panel.set_title("Main Menu")

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save)
	_menu_panel.body.add_child(save_button)

	var slot_row := HBoxContainer.new()
	_menu_panel.body.add_child(slot_row)
	_slots = OptionButton.new()
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(_slots)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load)
	slot_row.add_child(load_button)

	var new_button := Button.new()
	new_button.text = "New game"
	new_button.pressed.connect(_on_new_game)
	_menu_panel.body.add_child(new_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(
		func() -> void: Kernel.router.goto("core.settings", {"back": "base_game.chat"}))
	_menu_panel.body.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = "Quit to title"
	quit_button.pressed.connect(func() -> void: Kernel.router.goto("core.main_menu"))
	_menu_panel.body.add_child(quit_button)

	_menu_panel.body.add_child(HSeparator.new())

	var dev_ask := Button.new()
	dev_ask.text = "Ask me something (dev)"
	# No authored workflow uses `confirm` yet — game content is still scaffolding. This drives
	# the real path anyway (orchestrator → executor → suspension → instance store → resume), so
	# the machinery is verifiable in the running app rather than only in tests.
	dev_ask.pressed.connect(func() -> void: await _on_dev_ask())
	_menu_panel.body.add_child(dev_ask)

	var trace_toggle := CheckButton.new()
	trace_toggle.text = "Show AI trace"
	trace_toggle.toggled.connect(func(on: bool) -> void: _trace_label.visible = on)
	_menu_panel.body.add_child(trace_toggle)

	_trace_label = RichTextLabel.new()
	_trace_label.bbcode_enabled = false
	_trace_label.fit_content = true
	_trace_label.custom_minimum_size = Vector2(0, 140)
	_trace_label.visible = false
	_menu_panel.body.add_child(_trace_label)


func _open_main_menu() -> void:
	_refresh_slots()
	_shell.show_page(_menu_panel)


## The typed source's submit path: a real backend turn takes 0.85-4 s (D22), so input
## locks here and unlocks when the turn's completion event arrives — no frame blocking.
func _on_submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or Kernel.ai_orchestrator.is_busy():
		return
	_append("[color=aqua]You:[/color] %s" % message)
	_message_list.add_message("You", message)
	_input.clear()
	_set_busy(true)
	_source.submit(message)


## Renders any completed turn, whichever source produced it — a future voice or
## replayed turn belongs in the conversation log just like a typed one.
func _on_turn_completed(payload: Dictionary) -> void:
	# Only our own submits pass through _on_submit, which echoes the player's text
	# immediately. A turn from any other source (future voice, trace replay) never
	# did, so echo it here — a reply with no record of what was said is unreadable.
	if String(payload.get("source_id", "")) != _source.id():
		_append("[color=aqua]You:[/color] %s" % String(payload.get("text", "")))
	_render_turn(payload.get("result", {}))
	_set_busy(false)


## Render whatever a turn produced — a completed one, or one that stopped to ask.
func _render_turn(result: Dictionary) -> void:
	_append("[color=wheat]Game master:[/color] %s" % result.get("narrative", ""))
	var applied: Array = result.get("applied_commands", [])
	if not applied.is_empty():
		_append("[i](applied: %s)[/i]" % ", ".join(PackedStringArray(applied)))

	var trace: AiTrace = result.get("trace")
	if trace != null:
		_trace_label.text = trace.to_text()
	_message_list.add_message("King", String(result.get("narrative", "")), trace)
	_refresh_resources()

	# A turn that suspended hands back the handle to answer it with (B1). Ask right away,
	# while the player is still reading the reply that led to the question.
	var pending := String(result.get("pending_instance", ""))
	if not pending.is_empty():
		var instance: WorkflowInstance = Kernel.workflow_instances.get_instance(pending)
		if instance != null:
			_show_question(pending, instance.wake)


func _set_busy(busy: bool) -> void:
	# A pending question locks input as firmly as a turn in flight does.
	var blocked := busy or not _pending_instance.is_empty()
	_input.editable = not blocked
	_send_button.disabled = blocked
	if not blocked:
		_input.grab_focus()


# --- pending questions (M4/B4b) -----------------------------------------------------------

## Put the oldest unanswered question back in front of the player. Called on entry, so a
## question asked before the game was closed is re-presented rather than quietly dropped.
func _present_oldest_pending() -> void:
	for instance: WorkflowInstance in Kernel.workflow_instances.pending_confirmations():
		# Skip questions this session cannot honour — a disabled module, or a workflow that was
		# registered at runtime and so does not exist after a restart. The instance is kept
		# (D34: refuse, never discard), so re-enabling whatever owns it makes it answerable
		# again; offering a button that cannot work would be worse than staying quiet.
		if not Kernel.ai_orchestrator.can_resume(instance.instance_id):
			Kernel.log.warn("GameScreen", "Pending question for unavailable workflow '%s' — not shown"
				% instance.workflow_id)
			continue
		_show_question(instance.instance_id, instance.wake)
		return


func _show_question(instance_id: String, wake: Dictionary) -> void:
	_pending_instance = instance_id
	# `msg` is a localization key and `scope` its values (i18n discipline, D24) — the same
	# treatment `_on_workflow_emit` gives a chronicle line until translations are wired.
	var scope: Dictionary = wake.get("scope", {})
	var suffix := "  %s" % JSON.stringify(scope) if not scope.is_empty() else ""
	_pending_label.text = "%s%s" % [String(wake.get("msg", "confirm")), suffix]
	_pending_row.visible = true
	_shell.set_event_active(true)
	_event_image.visible = true
	_append("[color=yellow]Game master asks:[/color] %s" % _pending_label.text)
	_set_busy(false)  # re-evaluates the lock now that a question is pending


func _answer(confirmed: bool) -> void:
	if _pending_instance.is_empty():
		return
	var instance_id := _pending_instance
	# Cleared before resuming, not after: resuming is itself a turn that can ask a *new*
	# question, and that answer must not be overwritten by this one finishing.
	_clear_question()
	_append("[color=aqua]You:[/color] %s" % ("Yes" if confirmed else "No"))
	_set_busy(true)
	var result: Dictionary = await Kernel.ai_orchestrator.resume(instance_id, {"confirmed": confirmed})
	_render_turn(result)
	_set_busy(false)


func _clear_question() -> void:
	_pending_instance = ""
	_pending_row.visible = false
	_shell.set_event_active(false)


## Dev-only: run the `dev_confirm` workflow (registered at boot by the module in debug builds)
## so the confirm → suspend → resume path can be driven in the running app.
func _on_dev_ask() -> void:
	var definition: Variant = Kernel.workflow_registry.get_definition("dev_confirm")
	if not (definition is Dictionary):
		_append("[color=orange]System:[/color] dev_confirm is not registered (release build?).")
		return
	var instance := WorkflowInstance.create("dev_confirm", 1, {}, 0)
	var result: RefCounted = await WorkflowExecutor.for_kernel(Kernel).run(
		definition as Dictionary, instance, AiTrace.new())
	if int(result.get("status")) == WorkflowInstance.Status.SUSPENDED:
		Kernel.workflow_instances.remember(result.get("instance"))
		_show_question(instance.instance_id, instance.wake)


# --- slots (M4/B4b) -------------------------------------------------------------------------

func _refresh_slots() -> void:
	_slots.clear()
	for meta: Dictionary in Kernel.saves.slots():
		_slots.add_item("%s — day %d" % [meta.get("name", "?"), int(meta.get("total_days", 0))])
		_slots.set_item_metadata(_slots.item_count - 1, String(meta["id"]))
	if _slots.item_count == 0:
		_slots.add_item("(no saved settlements)")
		_slots.set_item_metadata(0, "")


func _on_load() -> void:
	var id := String(_slots.get_item_metadata(_slots.selected)) if _slots.selected >= 0 else ""
	if id.is_empty():
		return
	var loaded: Dictionary = Kernel.session.load_slot(id)
	if not bool(loaded["ok"]):
		_append("[color=orange]System:[/color] Could not load (%s)." % loaded["error"])
		return
	_clear_question()
	_append("[i]— Loaded '%s', day %d —[/i]" % [Kernel.session.slot_name, Kernel.clock.total_days])
	_refresh_outpost()
	_refresh_day()
	_refresh_resources()
	_refresh_map_marker()
	# A loaded game brings its own unanswered question, if it had one.
	_present_oldest_pending()
	_set_busy(false)


func _on_new_game() -> void:
	Kernel.session.start_new()
	_clear_question()
	_append("[i]— A new settlement —[/i]")
	_refresh_outpost()
	_refresh_day()
	_refresh_resources()
	_refresh_slots()
	_refresh_map_marker()
	_set_busy(false)


func _on_save() -> void:
	var result: Dictionary = Kernel.session.snapshot("manual")
	if bool(result["ok"]):
		_append("[color=gray]Saved '%s'.[/color]" % Kernel.session.slot_name)
		_refresh_slots()
	else:
		_append("[color=orange]System:[/color] Could not save (%s)." % result["error"])


## Let one day of game time pass. Time is turn-driven and the player triggers it explicitly
## (the chosen model): advancing the clock fires `day_passed`, which the [PlanTicker] handles off
## its own subscription — a due plot ticks in the background and surfaces as a chronicle line via
## `workflow_emit`, so no awaiting is needed here. Blocked while a turn or question is in flight,
## for the same reason input is: the world must not move under an unresolved action.
func _on_day_passed(_payload: Dictionary) -> void:
	_append("[i]— The day passes. Day %d. —[/i]" % Kernel.clock.total_days)
	_refresh_day()
	_refresh_resources()


## The map has no toggle any more (ux_plan.md §2.1 — it is the base layer, always on screen); the
## action that used to open the overlay now just re-centres the view.
func _set_time_speed(speed: int) -> void:
	if Kernel.time_driver != null:
		Kernel.time_driver.set_speed(speed)


func _on_time_speed_changed(_speed: int) -> void:
	_refresh_time_buttons()


func _refresh_time_buttons() -> void:
	if Kernel.time_driver == null:
		return
	var current := Kernel.time_driver.speed()
	for speed: Variant in _speed_buttons:
		var button: Button = _speed_buttons[speed]
		button.button_pressed = int(speed) == current


## The mobile wireframe keeps only the fastest speed in the constrained top bar. Pause and exact
## speed selection remain available through their rebindable keys; desktop keeps all four buttons.
func _on_shell_breakpoint_changed(_is_mobile: bool) -> void:
	_sync_speed_layout()


func _sync_speed_layout() -> void:
	var mobile := _shell.size.x < HudShell.MOBILE_BREAKPOINT_WIDTH
	for speed: Variant in _speed_buttons:
		_speed_buttons[speed].visible = not mobile or int(speed) == TimeDriver.Speed.SPEED_3


func _on_open_map() -> void:
	if _map_view != null:
		_map_view.fit()


## A workflow emit carries a message key + values (i18n discipline, D24), not assembled
## prose. Until translations are wired (later milestone), render the key and its values so
## the chronicle line stays visible in the dev conversation log.
func _on_workflow_emit(payload: Dictionary) -> void:
	var msg := String(payload.get("msg", ""))
	var values: Dictionary = payload.get("values", {})
	var suffix := "  %s" % JSON.stringify(values) if not values.is_empty() else ""
	_append("[color=gray]Chronicle:[/color] %s%s" % [msg, suffix])


func _on_ai_availability_changed(payload: Dictionary) -> void:
	var state := String(payload.get("state", ""))
	var attempt := int(payload.get("attempt", 0))
	match state:
		"recovering":
			if attempt == 0:
				_append("[color=orange]System:[/color] Game master connection lost — attempting to recover.")
			else:
				_append("[color=orange]System:[/color] Reconnecting (attempt %d/%d)…" % [attempt, AiAvailability.MAX_ATTEMPTS])
			_retry_button.visible = false
		"unavailable":
			_append("[color=orange]System:[/color] The game master is unavailable. Press Retry to reconnect.")
			_retry_button.visible = true
		"available":
			if int(payload.get("attempts_used", 0)) > 0:
				_append("[color=orange]System:[/color] Game master connection restored.")
			_retry_button.visible = false


## The settlement's identity in the header: its banner and its name. Both come from state, so a
## loaded game shows its own outpost rather than the one that was on screen a moment ago.
func _refresh_outpost() -> void:
	var stored: Dictionary = Kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {})
	# A game seeded before the wizard existed has no flag; the default is a real flag, not a hole,
	# so there is nothing to hide here.
	_flag_view.set_value(FlagValue.from_dict(stored))
	var outpost: Dictionary = Entities.get_entity(Kernel.state, "outpost")
	_outpost_label.text = String(outpost.get("name", "The Outpost"))


func _refresh_day() -> void:
	_date_label.text = DateFormat.render(Kernel.clock)


## Coins and population, each with the placeholder "+0" delta ux_plan.md §5 asks for rather than a
## number nothing computes yet. Neutral-coloured on purpose — green/red would claim a real signal.
func _refresh_resources() -> void:
	var resources: Dictionary = Kernel.state.get_value("resources", {})
	_gold_label.text = "Gold %d  +0" % int(resources.get("gold", 0))
	_population_label.text = "Population %d  +0" % int(resources.get("population", 0))


func _append(bbcode: String) -> void:
	_log_label.append_text(bbcode + "\n")
	# Player and game-master turns are added with their trace by their callers. Everything else
	# (opening copy, chronicles, questions, connection status) still deserves a visible row.
	if _message_list != null and not bbcode.contains("You:[/color]") and not bbcode.contains("Game master:[/color]"):
		_message_list.add_message("Chronicle", bbcode)
