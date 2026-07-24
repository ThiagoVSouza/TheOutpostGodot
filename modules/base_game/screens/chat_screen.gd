extends Control

## The vertical-slice screen: a free-text conversation with the AI game master.
##
## Sends the player's message through the input-source seam (D18): the screen is just
## the "typed" [AiInputSource] — it submits text via [member GameKernel.input_router]
## and renders whatever turn completes on the event bus, whichever source produced it.
## Also reflects resource changes and (for development) exposes the AI trace and a
## button to advance the calendar so the month-end workflow can be observed.
## The UI is built in code to keep the scene file trivial.

var _source: AiInputSource
var _day_label: Label
var _resource_label: Label
var _log_label: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _retry_button: Button
var _trace_label: RichTextLabel

## The question the game master is waiting on, if any (M4/B4b). While one is pending the player
## must answer it before doing anything else — a `confirm` guards an action the rules have not
## applied yet, so letting a new turn run alongside it would leave the world in a state neither
## answer describes.
var _pending_row: HBoxContainer
var _pending_label: Label
var _pending_instance: String = ""
var _slots: OptionButton


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
	# Boot has already resumed the session by now, so say which settlement this is — opening
	# into a loaded world with no acknowledgement reads as if nothing was saved.
	var opening := String(Kernel.state.get_value("opening_line", ""))
	if Kernel.session.has_slot():
		_append("[b]%s[/b] — day %d. Welcome back." % [Kernel.session.slot_name, Kernel.clock.total_days])
	elif not opening.is_empty():
		# A fresh game seeded an opening (the in-game phase). Placeholder for a real narrated
		# opening workflow (throne room, the king's charge).
		_append("[color=wheat]%s[/color]" % opening)
	else:
		_append("[b]The Outpost[/b] — the game master awaits. Describe what you do.")
	_refresh_day()
	_refresh_resources()
	_refresh_slots()
	# The GATE 0 call for M4: a question the player was asked before they closed the game is
	# put back in front of them, not silently cancelled. B1 kept the instance; this is the half
	# that lets them actually answer it.
	_present_oldest_pending()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	vbox.add_child(status_row)
	_day_label = Label.new()
	status_row.add_child(_day_label)
	_resource_label = Label.new()
	_resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_resource_label)

	# Time is turn-driven, but the player owns when it passes: nothing here costs a day, and this
	# control lets a day go by so background plots tick (M5/D36). Sits in the play area, not the
	# dev row — it is a real game action, not a debug shortcut.
	var time_row := HBoxContainer.new()
	vbox.add_child(time_row)
	var pass_day := Button.new()
	pass_day.text = "Let a day pass"
	pass_day.pressed.connect(_on_pass_day)
	time_row.add_child(pass_day)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_label)

	# Hidden until the game master asks something. Sits above the input so the question is the
	# thing under the conversation, where the answer is expected.
	_pending_row = HBoxContainer.new()
	_pending_row.visible = false
	vbox.add_child(_pending_row)
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
	vbox.add_child(input_row)
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

	var dev_row := HBoxContainer.new()
	vbox.add_child(dev_row)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save)
	dev_row.add_child(save_button)
	var ask := Button.new()
	ask.text = "Ask me something (dev)"
	# No authored workflow uses `confirm` yet — game content is still scaffolding. This drives
	# the real path anyway (orchestrator → executor → suspension → instance store → resume), so
	# the machinery is verifiable in the running app rather than only in tests.
	ask.pressed.connect(func() -> void: await _on_dev_ask())
	dev_row.add_child(ask)

	var slot_row := HBoxContainer.new()
	vbox.add_child(slot_row)
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
	slot_row.add_child(new_button)
	var trace_toggle := CheckButton.new()
	trace_toggle.text = "Show AI trace"
	trace_toggle.toggled.connect(func(on: bool) -> void: _trace_label.visible = on)
	dev_row.add_child(trace_toggle)

	_trace_label = RichTextLabel.new()
	_trace_label.bbcode_enabled = false
	_trace_label.fit_content = true
	_trace_label.custom_minimum_size = Vector2(0, 140)
	_trace_label.visible = false
	vbox.add_child(_trace_label)


## The typed source's submit path: a real backend turn takes 0.85-4 s (D22), so input
## locks here and unlocks when the turn's completion event arrives — no frame blocking.
func _on_submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or Kernel.ai_orchestrator.is_busy():
		return
	_append("[color=aqua]You:[/color] %s" % message)
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
			Kernel.log.warn("ChatScreen", "Pending question for unavailable workflow '%s' — not shown"
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
	_refresh_day()
	_refresh_resources()
	# A loaded game brings its own unanswered question, if it had one.
	_present_oldest_pending()
	_set_busy(false)


func _on_new_game() -> void:
	Kernel.session.start_new()
	_clear_question()
	_append("[i]— A new settlement —[/i]")
	_refresh_day()
	_refresh_resources()
	_refresh_slots()
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
func _on_pass_day() -> void:
	if Kernel.ai_orchestrator.is_busy() or not _pending_instance.is_empty():
		return
	Kernel.clock.advance(1)
	_append("[i]— The day passes. Day %d. —[/i]" % Kernel.clock.total_days)
	_refresh_day()
	_refresh_resources()


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


func _refresh_day() -> void:
	_day_label.text = "Day %d" % Kernel.clock.total_days


func _refresh_resources() -> void:
	var resources: Dictionary = Kernel.state.get_value("resources", {})
	if resources.is_empty():
		_resource_label.text = "Resources: (none yet)"
		return
	var parts: Array = []
	for name in resources:
		parts.append("%s: %d" % [name, int(resources[name])])
	_resource_label.text = "Resources — " + "   ".join(PackedStringArray(parts))


func _append(bbcode: String) -> void:
	_log_label.append_text(bbcode + "\n")
