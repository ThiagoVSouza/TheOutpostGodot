extends Control

## Dev playground: a conversation with the game master on the left, a live breakdown of what
## the orchestration actually did on the right. It surfaces the [AiTrace] every turn already
## produces (A1/D21) — the classified intent, the hand-off, the seeded roll and command, the
## narration — so a human can drive real turns and watch D4 hold (the model classifies and
## narrates; code owns the numbers). Selected as the start screen when OUTPOST_PLAYGROUND=1.

# Palette shared with the review artifacts, so screen and docs read as one system.
const C_AI := "3f74c9"       # a bounded AI call
const C_EFFECT := "a9741f"   # a state-changing effect
const C_NARRATE := "8a52bf"  # narration
const C_CONTROL := "5360b0"  # dispatch / control
const C_DONE := "1f8a86"     # completed
const C_FAIL := "c0472c"     # failure
const C_MUTED := "8b95a6"
const C_FAINT := "6b7688"

var _source: AiInputSource
var _backend_label: Label
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
	Kernel.events.subscribe(AiInputRouter.EVENT_TURN_COMPLETED, _on_turn_completed)
	Kernel.events.subscribe(AiAvailability.EVENT_NAME, _on_ai_availability_changed)
	_backend_label.text = "backend: %s   ·   %s" % [Kernel.ai.backend_id(), Kernel.ai_runner.get_class()]
	_append("[b]The Outpost — Playground[/b]")
	_append("[color=#%s]Describe what you do. Watch the breakdown on the right.[/color]" % C_MUTED)
	_refresh_resources()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 460
	add_child(split)

	# --- left: the conversation ---
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad(left)
	split.add_child(left)

	_backend_label = Label.new()
	_backend_label.add_theme_color_override("font_color", Color.html("#%s" % C_FAINT))
	left.add_child(_backend_label)

	_resource_label = Label.new()
	left.add_child(_resource_label)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_log_label)

	var input_row := HBoxContainer.new()
	left.add_child(input_row)
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
	left.add_child(dev_row)
	var advance := Button.new()
	advance.text = "Advance 1 month"
	advance.pressed.connect(_on_advance_month)
	dev_row.add_child(advance)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void: _log_label.clear())
	dev_row.add_child(clear)

	# --- right: the turn breakdown ---
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad(right)
	split.add_child(right)

	var header := Label.new()
	header.text = "TURN BREAKDOWN"
	header.add_theme_color_override("font_color", Color.html("#%s" % C_FAINT))
	right.add_child(header)

	_trace_label = RichTextLabel.new()
	_trace_label.bbcode_enabled = true
	_trace_label.scroll_following = false
	_trace_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trace_label.text = "[color=#%s]Send a message to see how the orchestration resolves it.[/color]" % C_FAINT
	right.add_child(_trace_label)


func _pad(box: Control) -> void:
	box.add_theme_constant_override("margin_left", 14)
	box.add_theme_constant_override("margin_top", 14)


func _on_submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or Kernel.ai_orchestrator.is_busy():
		return
	_append("[color=#%s]You:[/color] %s" % [C_AI, message])
	_input.clear()
	_set_busy(true)
	_trace_label.text = "[color=#%s]…thinking[/color]" % C_MUTED
	_source.submit(message)


func _on_turn_completed(payload: Dictionary) -> void:
	_set_busy(false)
	if String(payload.get("source_id", "")) != _source.id():
		_append("[color=#%s]You:[/color] %s" % [C_AI, String(payload.get("text", ""))])
	var result: Dictionary = payload.get("result", {})
	var reply := String(result.get("narrative", ""))
	if bool(result.get("ok", false)):
		_append("[color=#%s]Game master:[/color] %s" % [C_EFFECT, reply])
	else:
		_append("[color=#%s]— %s (%s)[/color]" % [C_FAIL, reply, result.get("error", "")])

	var trace: AiTrace = result.get("trace")
	if trace != null:
		_trace_label.text = render_trace(trace)
	_refresh_resources()


## Render an AiTrace to a readable, colour-coded breakdown (static + pure, so it's testable
## without a live screen). Each stage reads as one line naming who did what.
static func render_trace(trace: AiTrace) -> String:
	var lines: Array = []
	for entry_v in trace.entries():
		var entry: Dictionary = entry_v
		var stage := String(entry["stage"])
		var d: Dictionary = entry["data"]
		match stage:
			"turn_started":
				lines.append("[color=#%s]▸ turn started[/color]  [color=#%s](source: %s)[/color]" % [C_MUTED, C_FAINT, d.get("source", "")])
			"workflow_started":
				lines.append("[color=#%s]▸ %s[/color]" % [C_CONTROL, d.get("workflow", "")])
			"workflow_ai":
				lines.append("   [color=#%s]ai classify[/color] [color=#%s][%s][/color] → [b][color=#%s]%s[/color][/b]" % [C_AI, C_FAINT, d.get("family", ""), C_AI, d.get("value", "")])
			"workflow_dispatched":
				lines.append("   [color=#%s]dispatch →[/color] [b]%s[/b]  [color=#%s](segment %s)[/color]" % [C_CONTROL, d.get("to", ""), C_FAINT, d.get("segment", "")])
			"workflow_command":
				var ok := bool(d.get("ok", false))
				lines.append("   [color=#%s]command[/color] %s  %s" % [C_EFFECT, d.get("command", ""), "[color=#%s]✓[/color]" % C_DONE if ok else "[color=#%s]✗[/color]" % C_FAIL])
			"workflow_global_set":
				lines.append("   [color=#%s]set_global[/color] %s = %s" % [C_EFFECT, d.get("name", ""), d.get("value", "")])
			"workflow_emit":
				lines.append("   [color=#%s]emit[/color] %s" % [C_FAINT, d.get("msg", "")])
			"workflow_narrated":
				lines.append("   [color=#%s]narrate[/color] [i]%s[/i]" % [C_NARRATE, d.get("text", "")])
			"workflow_completed":
				lines.append("[color=#%s]✓ completed[/color]" % C_DONE)
			"workflow_failed":
				lines.append("[color=#%s]✗ failed: %s[/color]" % [C_FAIL, d.get("fail_code", "")])
			"workflow_require_failed":
				lines.append("   [color=#%s]guardrail failed: %s[/color]" % [C_FAIL, d.get("fail_code", "")])
			"guardrails":
				lines.append("[color=#%s]guardrail: %s[/color]" % [C_FAIL, d.get("reason", "")])
			"unavailable":
				lines.append("[color=#%s]unavailable (%s)[/color]" % [C_FAIL, d.get("state", "")])
			_:
				lines.append("[color=#%s]%s[/color]" % [C_FAINT, stage])
	return "\n".join(lines)


func _set_busy(busy: bool) -> void:
	_input.editable = not busy
	_send_button.disabled = busy
	if not busy:
		_input.grab_focus()


func _on_advance_month() -> void:
	_append("[color=#%s]— A month passes —[/color]" % C_FAINT)
	Kernel.clock.advance(GameClock.DAYS_PER_MONTH)
	_refresh_resources()


func _on_ai_availability_changed(payload: Dictionary) -> void:
	var state := String(payload.get("state", ""))
	match state:
		"unavailable":
			_append("[color=#%s]System: game master unavailable — press Retry.[/color]" % C_FAIL)
			_retry_button.visible = true
		"available":
			_retry_button.visible = false
		_:
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
