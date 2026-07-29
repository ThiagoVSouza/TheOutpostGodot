class_name SkinnedButton
extends PanelContainer

## A [UiSkin] button plate that casts a shadow and answers the pointer by changing size.
##
## Three jobs a bare [Button] cannot do here:
##
## - **The shadow.** [StyleBoxTexture] has no shadow, so this container's own panel is a shadow-only
##   [StyleBoxFlat] ([method UiSkin.button_shadow_style]) sitting behind the plate.
## - **The growing and shrinking.** [member Control.scale] is a *visual* transform: the [VBoxContainer]
##   above still lays this out at its unscaled size, so a hovered button can swell past its slot
##   without shoving its neighbours down the column. Scaling the container rather than the [Button]
##   is what keeps the shadow attached to the plate it belongs to.
## - **Touch.** A phone has no hover, so growing on `mouse_entered` alone would leave the plate inert
##   under a thumb. The press states are driven by [signal BaseButton.button_down] /
##   [signal BaseButton.button_up], which a touch does emit.
##
## Use [method create]; [signal pressed] is forwarded from the inner [Button].

signal pressed

var button: Button = null
## The caption. Separate from [member button] because a [Button] cannot draw a font shadow.
var label: Label = null

var _font_size := UiSkin.BUTTON_FONT_SIZE
var _tween: Tween = null


static func create(text: String, variant: UiSkin.Variant, height: float,
		font_size: int) -> SkinnedButton:
	var skinned := SkinnedButton.new()
	skinned._font_size = font_size
	skinned.add_theme_stylebox_override("panel", UiSkin.button_shadow_style())

	# The plate carries no text of its own. A Button has no font shadow anywhere in its theme — only
	# [Label] does — so the caption is a real Label laid over an empty plate. The Button keeps the
	# behaviour, the states and the stylebox; the Label keeps the lettering.
	var inner := Button.new()
	inner.custom_minimum_size = Vector2(0, height)
	UiSkin.apply_button(inner, variant)
	skinned.button = inner
	skinned.add_child(inner)

	# A sibling under the same PanelContainer rather than a child of the Button: this way the caption's
	# width counts towards the container's minimum size, so a long label widens the plate instead of
	# spilling over its rail.
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", int(UiSkin.BUTTON_PADDING_H))
	padding.add_theme_constant_override("margin_right", int(UiSkin.BUTTON_PADDING_H))
	padding.add_theme_constant_override("margin_top", int(UiSkin.BUTTON_PADDING_V))
	padding.add_theme_constant_override("margin_bottom", int(UiSkin.BUTTON_PADDING_V))
	skinned.add_child(padding)

	var caption := Label.new()
	caption.text = text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.label_style(caption, font_size)
	skinned.label = caption
	padding.add_child(caption)

	skinned._wire()
	return skinned


## A plate with no caption on it, where the art *is* the whole button: the pager's arrows. It gets the
## same three answers to the pointer as a captioned plate — the shadow, the change in light, the
## change in size — because it is a button, and one that behaved differently from every other button
## on the screen is what this replaced. A [TextureButton] can do the light and nothing else.
static func create_bare(normal_style: StyleBox, hover_style: StyleBox, pressed_style: StyleBox,
		size: Vector2) -> SkinnedButton:
	var skinned := SkinnedButton.new()
	skinned.add_theme_stylebox_override("panel", UiSkin.button_shadow_style())

	var inner := Button.new()
	inner.custom_minimum_size = size
	inner.add_theme_stylebox_override("normal", normal_style)
	inner.add_theme_stylebox_override("hover", hover_style)
	inner.add_theme_stylebox_override("pressed", pressed_style)
	inner.add_theme_stylebox_override("focus", hover_style)
	inner.add_theme_stylebox_override("disabled", normal_style)
	UiSkin.apply_cursor(inner)
	skinned.button = inner
	skinned.add_child(inner)

	skinned._wire()
	return skinned


## The pointer's three answers, shared by both factories.
func _wire() -> void:
	var inner := button
	inner.pressed.connect(func() -> void: pressed.emit())
	inner.mouse_entered.connect(func() -> void: _to(UiSkin.HOVER_SCALE, UiSkin.HOVER_TIME))
	inner.mouse_exited.connect(func() -> void: _to(1.0, UiSkin.HOVER_TIME))
	inner.button_down.connect(func() -> void: _to(UiSkin.PRESSED_SCALE, UiSkin.PRESSED_TIME))
	inner.button_up.connect(func() -> void:
		# Back to hovered if the pointer is still on it (mouse), to rest if it never was (touch).
		_to(UiSkin.HOVER_SCALE if inner.is_hovered() else 1.0, UiSkin.PRESSED_TIME))
	# Keyboard and gamepad focus gets the same treatment as hover, so arrowing down the menu is as
	# legible as pointing at it. Focus is deliberately left enabled — the plate is still a Button.
	inner.focus_entered.connect(func() -> void: _to(UiSkin.HOVER_SCALE, UiSkin.HOVER_TIME))
	inner.focus_exited.connect(func() -> void: _to(1.0, UiSkin.HOVER_TIME))


func _ready() -> void:
	_centre_pivot()
	resized.connect(_centre_pivot)


## Grow from the middle. Without this the pivot is the top-left corner and the plate slides down and
## right as it scales instead of swelling in place.
func _centre_pivot() -> void:
	pivot_offset = size * 0.5


func set_disabled(value: bool) -> void:
	if button == null:
		return
	button.disabled = value
	# A disabled plate still takes the pointer, so it has to stop claiming to be clickable.
	UiSkin.apply_cursor(button, not value)
	# The caption is ours now, so the disabled ink is ours to apply — the Button's own
	# `font_disabled_color` governs text it no longer draws.
	if label != null:
		UiSkin.label_style(label, _font_size, value)
	# `modulate`, not `self_modulate`: it carries down to the plate and the caption, so the whole
	# button recedes as one object.
	modulate.a = UiSkin.DISABLED_ALPHA if value else 1.0
	# And the shadow goes away entirely while it is faded. Its stylebox is an opaque fill plus a blur
	# ([method UiSkin.shadow_style] explains why the fill has to be drawn); the fill is invisible only
	# because the plate covers it, so a translucent plate lets that near-black show through and the
	# button reads *darker* instead of receded. A control this faded should not be casting a shadow
	# onto the frame anyway.
	add_theme_stylebox_override("panel",
		StyleBoxEmpty.new() if value else UiSkin.button_shadow_style())
	if value:
		_to(1.0, UiSkin.PRESSED_TIME)


func _to(target: float, seconds: float) -> void:
	if button != null and button.disabled:
		target = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "scale", Vector2(target, target), seconds)
