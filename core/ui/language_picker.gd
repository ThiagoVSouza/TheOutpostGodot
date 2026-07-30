class_name LanguagePicker
extends Button

## A compact language field backed by a themed, scrolling choice modal. Godot 4.7.1's PopupMenu
## ignores Window.max_size, so a 24-item OptionButton expands to the whole screen instead of creating
## the scrollbar its API promises. Owning the scroll viewport here keeps the behavior deterministic.

signal language_selected(code: String)

const PICKER_CONTENT_HEIGHT := 560.0
const FIELD_HEIGHT := 84.0
const OPTION_HEIGHT := 80.0
const CJK_FONT: FontFile = preload("res://core/assets/fonts/NotoSansCJK-LanguageLabels.otf")

static var _display_font: FontVariation = null

var _selected_code := AppSettings.DEFAULT_LANGUAGE
var _active_modal: PickerModal = null


static func create(selected_code: String) -> LanguagePicker:
	var picker := LanguagePicker.new()
	picker.name = "LanguagePicker"
	picker.alignment = HORIZONTAL_ALIGNMENT_LEFT
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_theme_constant_override("icon_max_width", 36)
	UiSkin.apply_input(picker)
	picker.custom_minimum_size.y = FIELD_HEIGHT
	picker.add_theme_font_override("font", _language_display_font())
	picker.set_selected_code(selected_code)
	picker.pressed.connect(picker.open_picker)
	return picker


func set_selected_code(code: String) -> void:
	_selected_code = code if AppSettings.is_language(code) else AppSettings.DEFAULT_LANGUAGE
	for entry: Dictionary in AppSettings.language_options():
		if String(entry["id"]) != _selected_code:
			continue
		text = String(entry["label"])
		icon = load(String(entry["icon"])) as Texture2D
		return


func selected_code() -> String:
	return _selected_code


func option_count() -> int:
	return AppSettings.LANGUAGES.size()


func option_codes() -> Array[String]:
	var codes: Array[String] = []
	for entry: Dictionary in AppSettings.LANGUAGES:
		codes.append(String(entry["code"]))
	return codes


func open_picker() -> void:
	if _active_modal != null:
		_active_modal.queue_free()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for entry: Dictionary in AppSettings.language_options():
		var code := String(entry["id"])
		var choice := Button.new()
		choice.set_meta("language_code", code)
		choice.text = String(entry["label"])
		choice.icon = load(String(entry["icon"])) as Texture2D
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.add_theme_constant_override("icon_max_width", 36)
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = code == _selected_code
		UiSkin.apply_input(choice)
		choice.custom_minimum_size.y = OPTION_HEIGHT
		# Buttons stop GUI events by default. PASS preserves taps but also lets a finger drag reach the
		# modal's ScrollContainer, which is required for touch scrolling on Android.
		choice.mouse_filter = Control.MOUSE_FILTER_PASS
		choice.add_theme_font_override("font", _language_display_font())
		choice.pressed.connect(func() -> void:
			set_selected_code(code)
			language_selected.emit(code))
		content.add_child(choice)

	_active_modal = PickerModal.create("Choose a language", content, PICKER_CONTENT_HEIGHT)
	var modal := _active_modal
	modal.closed.connect(func() -> void:
		if _active_modal == modal:
			_active_modal = null
		modal.queue_free())
	add_child(modal)
	modal.open()


func close_picker() -> bool:
	if _active_modal == null or not _active_modal.visible:
		return false
	_active_modal.close()
	return true


func active_modal() -> PickerModal:
	return _active_modal


static func _language_display_font() -> FontVariation:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = ThemeDB.fallback_font
		var fallbacks: Array[Font] = [CJK_FONT]
		_display_font.fallbacks = fallbacks
	return _display_font
