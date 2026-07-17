extends Control

## The vertical-slice screen: a free-text conversation with the AI game master.
##
## Sends the player's message through [member GameKernel.ai_orchestrator], shows the
## narrative reply, reflects resource changes, and (for development) exposes the AI trace
## and a button to advance the calendar so the month-end workflow can be observed.
## The UI is built in code to keep the scene file trivial.

var _resource_label: Label
var _log_label: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _trace_label: RichTextLabel


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	# Surface workflow narration (e.g. the end-of-month report) in the conversation log.
	Kernel.events.subscribe("workflow_narrative", _on_workflow_narrative)
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
	_send_button.pressed.connect(func() -> void: await _on_submit(_input.text))
	input_row.add_child(_send_button)

	var dev_row := HBoxContainer.new()
	vbox.add_child(dev_row)
	var advance := Button.new()
	advance.text = "Advance 1 month (dev)"
	advance.pressed.connect(_on_advance_month)
	dev_row.add_child(advance)
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


## Coroutine: a real backend turn takes 0.85-4 s (D22), so input locks while the game
## master "thinks" and the reply arrives via await without blocking the frame.
func _on_submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or Kernel.ai_orchestrator.is_busy():
		return
	_append("[color=aqua]You:[/color] %s" % message)
	_input.clear()
	_set_busy(true)

	var result: Dictionary = await Kernel.ai_orchestrator.handle_message(message)
	_set_busy(false)
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


func _on_advance_month() -> void:
	_append("[i]— A month passes —[/i]")
	Kernel.clock.advance(GameClock.DAYS_PER_MONTH)
	_refresh_resources()


func _on_workflow_narrative(payload: Dictionary) -> void:
	_append("[color=gray]Chronicle:[/color] %s" % payload.get("text", ""))


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
