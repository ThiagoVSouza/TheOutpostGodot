class_name ChatMessageList
extends ScrollContainer

## Structured conversation rows with avatar slots and optional resolution timelines.

var _messages: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 12)
	add_child(_messages)

func add_message(speaker: String, message: String, trace: AiTrace = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_messages.add_child(row)
	var avatar := Label.new()
	avatar.text = speaker.left(1).to_upper()
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.custom_minimum_size = Vector2(42, 42)
	avatar.tooltip_text = "%s avatar" % speaker
	row.add_child(avatar)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	row.add_child(content)
	var heading := Label.new()
	heading.text = "%s says:" % speaker
	heading.add_theme_color_override("font_color", OutpostTheme.ACCENT if speaker == "King" else OutpostTheme.TEXT_MUTED)
	content.add_child(heading)
	var prose := RichTextLabel.new()
	prose.bbcode_enabled = true
	prose.fit_content = true
	prose.scroll_active = false
	# Preserve real BBCode from system messages while hiding FakeNarrator's deterministic test tag.
	prose.append_text(AiTimeline.player_text(message))
	content.add_child(prose)
	if trace != null:
		var timeline := AiTimeline.new()
		content.add_child(timeline)
		timeline.show_trace(trace)
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)
