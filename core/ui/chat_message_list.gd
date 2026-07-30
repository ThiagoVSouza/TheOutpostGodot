class_name ChatMessageList
extends ScrollContainer

## Structured conversation rows with avatar slots.
##
## The conversation is read on parchment, so every colour here is the skin's ink rather than the dark
## theme's — cream lettering on a page is very nearly invisible, which is exactly what it was.
##
## The resolution timeline that used to hang under a resolved turn has been taken out: it is a
## developer's view of the orchestration and it was sitting in the middle of the fiction. The trace
## still exists on every turn and still reaches `AiTrace`; what it wants is a dev overlay of its own,
## not a place in the chronicle.

## The portrait mount beside a line of the conversation, and how far inside its frame the initial
## sits while there is no art in it.
const AVATAR_SIZE := 56.0
const AVATAR_INSET := 4.0

## Who is speaking, over the plain ink of what they said. The king's own colour is the one the
## wizard uses for a card's "ECONOMIC START" line — the same job, naming the kind of thing being read.
const SPEAKER_COLOR := Color(0.58, 0.34, 0.05)

var _messages: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 14)
	UiSkin.apply_scroll_container(self)
	add_child(_messages)

## [param trace] is accepted and ignored — callers hand a resolved turn's trace over as they always
## did, and this decides it is not part of the conversation.
func add_message(speaker: String, message: String, _trace: AiTrace = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_messages.add_child(row)
	# The portrait slot: a mount with the speaker's initial in it until there is art to hang there.
	# A framed empty square says "a face belongs here" in a way a bare letter does not.
	var avatar_mount := PanelContainer.new()
	avatar_mount.add_theme_stylebox_override("panel", UiSkin.thin_frame_style(AVATAR_INSET))
	avatar_mount.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar_mount.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	avatar_mount.tooltip_text = "%s avatar" % speaker
	row.add_child(avatar_mount)
	var avatar := Label.new()
	avatar.text = speaker.left(1).to_upper()
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	avatar.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	avatar_mount.add_child(avatar)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	row.add_child(content)
	var heading := Label.new()
	heading.text = speaker
	heading.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	heading.add_theme_color_override("font_color",
		SPEAKER_COLOR if speaker == "King" else UiSkin.INK_MUTED)
	content.add_child(heading)
	var prose := RichTextLabel.new()
	prose.bbcode_enabled = true
	prose.fit_content = true
	prose.scroll_active = false
	# Preserve real BBCode from system messages while hiding FakeNarrator's deterministic test tag.
	prose.add_theme_font_size_override("normal_font_size", UiSkin.FONT_BODY)
	prose.add_theme_font_size_override("bold_font_size", UiSkin.FONT_BODY)
	prose.add_theme_color_override("default_color", UiSkin.INK)
	prose.append_text(AiTimeline.player_text(message))
	content.add_child(prose)
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)
