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
var _resource_label: Label
var _log_label: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _retry_button: Button
var _trace_label: RichTextLabel


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
	if Kernel.session.has_slot():
		_append("[b]%s[/b] — day %d. Welcome back." % [Kernel.session.slot_name, Kernel.clock.total_days])
	else:
		_append("[b]The Outpost[/b] — the game master awaits. Describe what you do.")
	_refresh_resources()


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

	_resource_label = Label.new()
	vbox.add_child(_resource_label)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_label)

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
	var advance := Button.new()
	advance.text = "Advance 1 month (dev)"
	advance.pressed.connect(_on_advance_month)
	dev_row.add_child(advance)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save)
	dev_row.add_child(save_button)
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
	_set_busy(false)
	# Only our own submits pass through _on_submit, which echoes the player's text
	# immediately. A turn from any other source (future voice, trace replay) never
	# did, so echo it here — a reply with no record of what was said is unreadable.
	if String(payload.get("source_id", "")) != _source.id():
		_append("[color=aqua]You:[/color] %s" % String(payload.get("text", "")))
	var result: Dictionary = payload.get("result", {})
	_append("[color=wheat]Game master:[/color] %s" % result.get("narrative", ""))
	var applied: Array = result.get("applied_commands", [])
	if not applied.is_empty():
		_append("[i](applied: %s)[/i]" % ", ".join(PackedStringArray(applied)))

	var trace: AiTrace = result.get("trace")
	if trace != null:
		_trace_label.text = trace.to_text()
	_refresh_resources()


func _set_busy(busy: bool) -> void:
	_input.editable = not busy
	_send_button.disabled = busy
	if not busy:
		_input.grab_focus()


func _on_save() -> void:
	var result: Dictionary = Kernel.session.save("manual")
	if bool(result["ok"]):
		_append("[color=gray]Saved '%s'.[/color]" % Kernel.session.slot_name)
	else:
		_append("[color=orange]System:[/color] Could not save (%s)." % result["error"])


func _on_advance_month() -> void:
	_append("[i]— A month passes —[/i]")
	Kernel.clock.advance(GameClock.DAYS_PER_MONTH)
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
