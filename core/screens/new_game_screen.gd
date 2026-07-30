extends Control

## App-shell new-game wizard: Background -> Location -> Hero -> Banner -> Settings, then Start seeds
## a fresh game and enters it. Splits the legacy Tauri wizard's Identity page on its real seam —
## person and place — so the banner choices remain usable on a phone.
## The module-pick screen and a module-config-driven wizard remain deferred — there is nothing yet
## for a module to configure.

const GAME_SCREEN := "base_game.chat"
const DEFAULT_HERO := "Marcus"
const DEFAULT_OUTPOST := "Ravenwatch"

const STEP_TITLES := ["Background", "Location", "Hero", "Banner", "Settings"]

## How small a card may get before it stops being readable. [CardPager] decides how many fit on a
## line from its own width; this is the floor a card is never squeezed below.
const CARD_MIN_WIDTH := 260.0

## The "ECONOMIC START" line over a background's prose. Warmer than the body ink and set small and
## upper-case, so it reads as a label on the card rather than the first line of the paragraph.
const CARD_META_COLOR := Color(0.58, 0.34, 0.05)

## Room between the card's plate and the text on it. Matches the field padding, so a card and a
## dropdown have the same air inside their borders.
const CARD_PADDING := UiSkin.INPUT_PADDING_H

## The drawn width of the sunken plate's rail. The painting stops here rather than at
## [constant CARD_PADDING], so it reaches the card's border and no further — any less and it covers
## the moulding, any more and it reads as a picture hung in a mount.
const CARD_BORDER_INSET := 5.0

## The least room a card's prose is ever given, under the painting. The card takes its height from the
## step, so this only decides what a card looks like in a window too short to give it one — and a
## painting with a single clipped line under it reads as a broken card rather than a short one.
const CARD_TEXT_MIN_HEIGHT := 90.0

## Wide enough that "Female" is not a tighter plate than "Male" — a pick-one pair whose halves are
## different sizes reads as one of them mattering more.
const SEX_BUTTON_WIDTH := 150.0

## The five compact property rows share the phone's content width with the preview. Options live in
## modals now, so this column no longer has to be wide enough for an entire thumbnail grid.
const BANNER_CONTROLS_WIDTH := 300.0

## The preview grows on desktop and gives the property column room on a phone. Both stay larger than
## a thumbnail; [FlagView.aspect] supplies their corresponding heights.
const FLAG_PREVIEW_MOBILE_WIDTH := 150.0
const FLAG_PREVIEW_DESKTOP_WIDTH := 200.0

const FLAG_GRID_GAP := 8

## Room for the longest name either field ships with, so a default value is never shown clipped.
const FIELD_MIN_WIDTH := 300.0

## The width of Back and Next. Wide enough for the longest word either shows ("Cancel", "Start") with
## room around it, and no wider — see the note where the footer is built.
const NAV_BUTTON_WIDTH := 240.0

## The five starting backgrounds, carried over from the legacy wizard's own content — the
## prose, the "Starts with" list and the badges are its words rather than a summary of them.
## `body` is BBCode because a card renders it through a [RichTextLabel]; the legacy stored
## the same text as markdown.
const BACKGROUNDS := [
	{"id": "wealthy_merchant", "title": "Merchant",
	 "image": "res://core/assets/wizard/background_merchant.jpg",
	 "meta": "Economic Start",
	 "badges": ["Coins", "Trade", "Negotiation"],
	 "body": "You spent your life trading across the kingdom's markets, building wealth "
		+ "through persistence and sharp instincts. You see the frontier not just as "
		+ "a duty, but as your greatest opportunity — a chance to rise from merchant "
		+ "to noble and build a fortune trading rare goods from the wildlands."
		+ "\n"
		+ "\n[b]Starts with:[/b]"
		+ "\n5,000 personal coins"
		+ "\nMerchant tag"
		+ "\nFormal education, bookkeeping and logistics"},
	{"id": "knight", "title": "Knight",
	 "image": "res://core/assets/wizard/background_knight.jpg",
	 "meta": "Military Start",
	 "badges": ["Soldiers", "Authority", "Combat"],
	 "body": "Since youth you excelled at arms, and your talent earned you a place among "
		+ "the King's own knights. You carry both the honor and the burden of that "
		+ "trust — the outpost must not fail again."
		+ "\n"
		+ "\n[b]Starts with:[/b]"
		+ "\n10 soldiers (sword, spear, chain armor)"
		+ "\nFull plate armor and warhorse"
		+ "\nKnight title"
		+ "\nCombat tactics and leadership"},
	{"id": "unlanded_noble", "title": "Noble",
	 "image": "res://core/assets/wizard/background_noble.jpg",
	 "meta": "Political Start",
	 "badges": ["Favor", "Politics", "Diplomacy"],
	 "body": "You are the last heir of an ancient noble house that lost its lands and "
		+ "title generations ago. The outpost is your chance to reclaim your "
		+ "birthright and restore your house to its former glory."
		+ "\n"
		+ "\n[b]Starts with:[/b]"
		+ "\nRoyal order for barracks, library and temple"
		+ "\nNoble tag (rank of Lord)"
		+ "\nDiplomacy, political acumen and scheme detection"},
	{"id": "mercenary_captain", "title": "Mercenary",
	 "image": "res://core/assets/wizard/background_mercenary.jpg",
	 "meta": "Frontier Start",
	 "badges": ["Adventurers", "Scouting", "Survival"],
	 "body": "You left the royal army to found your own mercenary company and have spent "
		+ "years venturing deep into the wildlands. The outpost offers a permanent "
		+ "base from which to launch expeditions and secure lasting fortune."
		+ "\n"
		+ "\n[b]Starts with:[/b]"
		+ "\n10 adventurers (light armor, bows, spears)"
		+ "\nAdventurer tag"
		+ "\nWildlands knowledge, tracking and monster lore"},
	{"id": "scholar", "title": "Scholar",
	 "image": "res://core/assets/wizard/background_scholar.jpg",
	 "meta": "Knowledge Start",
	 "badges": ["Knowledge", "Research", "Administration"],
	 "body": "Tutored by masters at the great library, you rose from humble origins "
		+ "through sheer intellect. The outpost is your chance to prove that wisdom "
		+ "and administration are worth more than swords."
		+ "\n"
		+ "\n[b]Starts with:[/b]"
		+ "\nScholar, blacksmith, carpenter, doctor and mason"
		+ "\nAdvanced education"
		+ "\nScholar tag"
		+ "\nLanguages, history, geography and theology"},
]

## The four founding sites. No `meta` line: the legacy gave the backgrounds one ("Economic
## Start") and the locations none, and the three fact lines at the foot of the body already
## say what kind of place this is.
const LOCATIONS := [
	{"id": "coast", "title": "Coast",
	 "image": "res://core/assets/wizard/location_coast.jpg",
	 "badges": ["Food", "Trade"],
	 "body": "A sheltered bay with calm waters and easy access to sea routes. Trade with "
		+ "the capital and foreign ships makes this the most forgiving start."
		+ "\n"
		+ "\n[b]Difficulty:[/b] Easy"
		+ "\n[b]Fertility:[/b] Average"
		+ "\n[b]Barbarians:[/b] Friendly"},
	{"id": "valley", "title": "Valley",
	 "image": "res://core/assets/wizard/location_valley.jpg",
	 "badges": ["Farming", "Growth"],
	 "body": "A wide river valley with fertile soil and open terrain. Farming comes "
		+ "easily, but the mixed local tribes require careful diplomacy."
		+ "\n"
		+ "\n[b]Difficulty:[/b] Average"
		+ "\n[b]Fertility:[/b] High"
		+ "\n[b]Barbarians:[/b] Mixed"},
	{"id": "forest", "title": "Forest",
	 "image": "res://core/assets/wizard/location_forest.jpg",
	 "badges": ["Wood", "Crafting"],
	 "body": "Dense woodland offering abundant timber, furs and game. Clearing land for "
		+ "settlement is slow work, and the forest tribes are unpredictable."
		+ "\n"
		+ "\n[b]Difficulty:[/b] Hard"
		+ "\n[b]Fertility:[/b] Average"
		+ "\n[b]Barbarians:[/b] Mixed"},
	{"id": "mountains", "title": "Mountains",
	 "image": "res://core/assets/wizard/location_mountains.jpg",
	 "badges": ["Defense", "Stone"],
	 "body": "Rocky highlands rich in ore and stone, but unforgiving terrain where "
		+ "little grows. Hostile barbarian clans roam the passes and food will be "
		+ "scarce."
		+ "\n"
		+ "\n[b]Difficulty:[/b] Very Hard"
		+ "\n[b]Fertility:[/b] Poor"
		+ "\n[b]Barbarians:[/b] Hostile"},
]

const OUTPOST_NAMES := ["Ravenwatch", "Stonegate", "Ironward", "Dawnrest", "Northpass",
	"Amberhold", "Greyhaven", "Frostmere", "Redcliff", "Oakmarch"]

## The Settings step speaks [NarrationSettings]' own vocabulary rather than a display vocabulary of
## its own, so the stored answer *is* the level and nothing has to translate between the two. Only
## the titles are dressed up: "Average" reads better on a card than "Normal".
const VERBOSITIES := [
	{"id": NarrationSettings.LEVEL_SHORT, "title": "Short", "desc": "Terse, to the point."},
	{"id": NarrationSettings.LEVEL_NORMAL, "title": "Average", "desc": "Balanced narration."},
	{"id": NarrationSettings.LEVEL_LONG, "title": "Long", "desc": "Rich, descriptive prose."},
]

const FLAG_PALETTE := ["#b62a2a", "#2f5fc0", "#2fa354", "#f3c43f", "#000000", "#f7f7f2",
	"#8b5a2b", "#a03291"]
const FLAG_PATTERN_COUNT := 14
const FLAG_EMBLEM_COUNT := 13

var _current_step := 0
var _step_pages: Array = []
var _step_label: Label = null
var _back: SkinnedButton = null
var _next: SkinnedButton = null

var _selected_background := ""
var _selected_location := ""
## Starts at the player's app-level preference rather than a hardcoded default, so someone who always
## wants long prose is not re-choosing it at every new game. Read in `_build_settings_step`, since
## `Kernel` is not available at property-initialisation time.
var _selected_verbosity := NarrationSettings.LEVEL_NORMAL
## Like narration length, this starts from the app preference but belongs to the game being created.
## Translation is not applied yet; preserving the code now keeps saves ready for it later.
var _selected_language := AppSettings.DEFAULT_LANGUAGE
var _sex := "male"

var _name_field: LineEdit = null
var _outpost_name_field: LineEdit = null

var _flag_value := FlagValue.new()
var _flag_view: FlagView = null
var _banner_property_buttons: Dictionary = {}
var _banner_property_swatches: Dictionary = {}
var _active_picker: PickerModal = null
var _language_picker: LanguagePicker = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ShellPalette.paint_shell(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	# The Back/Next row sits on this edge, so it has to clear the navigation bar.
	margin.add_theme_constant_override("margin_bottom", 20 + SafeArea.bottom(get_viewport()))
	add_child(margin)

	# The same parchment the menu and the settings page sit on. This screen wore `plate_style`'s dark
	# glass while it was unskinned — the honest placeholder for lettering that had to stay light — and
	# the frame is what replaces it now that everything on it is written in ink.
	var shadow := PanelContainer.new()
	shadow.add_theme_stylebox_override("panel", UiSkin.frame_shadow_style())
	margin.add_child(shadow)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiSkin.frame_style())
	shadow.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	frame.add_child(col)

	var title := Label.new()
	title.text = "New Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiSkin.FONT_TITLE)
	title.add_theme_color_override("font_color", UiSkin.INK)
	col.add_child(title)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	_step_label.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	col.add_child(_step_label)

	# **The steps scroll.** They did not before, and on a phone that was the same trap the settings
	# page had: the Banner step alone is taller than the viewport, so its lower fields simply had
	# nowhere to be. A VBox, not the old absolutely-positioned host — a hidden child contributes
	# nothing to a container's minimum size, so the scroll region is always exactly the step on show.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSkin.apply_scroll_container(scroll)
	col.add_child(scroll)

	# **Room inside the clip for what the cards draw outside themselves.** A [ScrollContainer] clips to
	# its own rect, and a card's shadow — and the chosen card's glow — spread past the card's edge, so
	# without this the topmost card had its glow sliced off flat while the sides kept theirs. The
	# margin is the widest of those spreads.
	var bleed := MarginContainer.new()
	bleed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bleed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		bleed.add_theme_constant_override(side, UiSkin.CARD_GLOW_SIZE)
	scroll.add_child(bleed)

	var pages_host := VBoxContainer.new()
	pages_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# **A [ScrollContainer] stretches its child to the view only if that child asks to expand.** The
	# flag has to be on this host — the direct child — not just on the page inside it, which is what
	# left the cards sitting in the top third of an empty page. With it, a short step fills the view
	# and a tall one keeps its own height and scrolls.
	pages_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bleed.add_child(pages_host)

	_step_pages = [
		_build_background_step(),
		_build_location_step(),
		_build_hero_step(),
		_build_banner_step(),
		_build_settings_step(),
	]
	for page: Control in _step_pages:
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Vertical too, so a step shorter than the page still takes the whole page — which is what
		# lets the Hero, Banner and Settings steps put their footer where the eye expects it rather than
		# bunched under the last field. The cards do not stretch with it; see [CardPager].
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pages_host.add_child(page)

	# A rule between the step and the two plates that leave it. Everything above it belongs to the
	# choice being made — including the pager's own arrows, which sit just above the line — and
	# everything below it moves you off the step entirely. Without it the pager's arrows and the
	# wizard's Back read as one row of navigation, which is two quite different jobs.
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", UiSkin.separator_style())
	col.add_child(divider)

	# Cancel/Back on the left and Next/Start on the right, the same hands as the settings footer and
	# the exit modal: leaving is always the left plate.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	col.add_child(nav)

	# Sized to their words and pushed to opposite edges, not stretched to half the page each. A plate
	# grows to the size of the job it does, and "Next" is not a half-screen-wide job — two enormous
	# slabs filling the foot of the wizard read as a dialog demanding an answer rather than as a step
	# in something. The gap between them is a spacer, so the hands stay put as the captions change
	# from Cancel/Next to Back/Start.
	_back = SkinnedButton.create("Back", UiSkin.BROWN, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	_back.custom_minimum_size.x = NAV_BUTTON_WIDTH
	_back.pressed.connect(_on_back)
	nav.add_child(_back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(spacer)

	# Blue: on every step the one thing the screen wants is to carry on.
	_next = SkinnedButton.create("Next", UiSkin.BLUE, UiSkin.BUTTON_HEIGHT, UiSkin.BUTTON_FONT_SIZE)
	_next.custom_minimum_size.x = NAV_BUTTON_WIDTH
	_next.pressed.connect(_on_next)
	nav.add_child(_next)

	_goto_step(0)


func _goto_step(step: int) -> void:
	_current_step = step
	for i in _step_pages.size():
		(_step_pages[i] as Control).visible = i == step
	_step_label.text = "Step %d of %d — %s" % [step + 1, STEP_TITLES.size(), STEP_TITLES[step]]
	_back.label.text = "Back" if step > 0 else "Cancel"
	_next.label.text = "Start" if step == _step_pages.size() - 1 else "Next"


func _on_back() -> void:
	if _current_step == 0:
		Kernel.router.goto("core.main_menu")
	else:
		_goto_step(_current_step - 1)


## Hardware/gesture back does exactly what the on-screen Back/Cancel button does (Android UX
## pass) — never a surprise exit mid-wizard.
func on_hardware_back() -> bool:
	if _language_picker != null and _language_picker.close_picker():
		return true
	if _active_picker != null and _active_picker.visible:
		_active_picker.close()
		return true
	_on_back()
	return true


func _on_next() -> void:
	if _current_step == _step_pages.size() - 1:
		_finish()
	else:
		_goto_step(_current_step + 1)


func _finish() -> void:
	var hero_name := _name_field.text.strip_edges()
	if hero_name.is_empty():
		hero_name = DEFAULT_HERO
	var outpost_name := _outpost_name_field.text.strip_edges()
	if outpost_name.is_empty():
		outpost_name = DEFAULT_OUTPOST
	var fields := {
		"hero_name": hero_name,
		"sex": _sex,
		"outpost_name": outpost_name,
		"background": _selected_background,
		"outpost_location": _selected_location,
		"outpost_flag": _flag_value.to_dict(),
		"verbosity": _selected_verbosity,
		"language": _selected_language,
	}
	Kernel.session.begin_new_game(fields)
	Kernel.router.goto("core.loading", {"next": GAME_SCREEN})


# --- Step 1: Background -----------------------------------------------------------------

func _build_background_step() -> Control:
	_selected_background = String(BACKGROUNDS[0]["id"])
	return _card_select_column(BACKGROUNDS, _selected_background,
		func(id: String) -> void: _selected_background = id)


# --- Step 2: Location --------------------------------------------------------------------

func _build_location_step() -> Control:
	_selected_location = String(LOCATIONS[0]["id"])
	return _card_select_column(LOCATIONS, _selected_location,
		func(id: String) -> void: _selected_location = id)


## The pick-one steps: a [CardPager] over the cards, which is the presentation the legacy wizard
## named for both of them (`"presentation": "centered_pager"`).
##
## It replaced a flow of cards, which was the right shape while a card was three lines long and the
## wrong one the moment the cards carried the legacy's real copy. Five cards of prose wrapped into a
## grid put the last row well below the fold, and on a pick-one step an option the player has to
## scroll to discover may as well not be offered.
func _card_select_column(items: Array, default_id: String, on_select: Callable) -> Control:
	var group := ButtonGroup.new()
	var cards: Array[Control] = []
	var selected := 0
	for i in items.size():
		var item: Dictionary = items[i]
		var chosen := String(item["id"]) == default_id
		if chosen:
			selected = i
		cards.append(_card(item, group, chosen, on_select))
	return CardPager.create(cards, selected)


## One picture card: the painting, the name, and the line that says what it gets you.
##
## **The plate and the content are siblings, not parent and child** — the same arrangement
## [SkinnedButton] uses, and for the same reason. A [Button] is not a container: anything added to it
## has to be positioned by hand and contributes nothing to its size, so a card built that way is
## whatever height was hardcoded rather than whatever its text needs. Here a [PanelContainer] holds
## both, each filling it, and its minimum size is the taller of the two — the [Button] keeps the press
## behaviour, the [ButtonGroup] and the painted plate, while the content decides how big the card is.
##
## **Everything in the content ignores the mouse, or it would swallow the click meant for the plate
## behind it** — with one deliberate exception, the [CardScroll] over the prose, which cannot ignore
## the mouse and hands back what it takes. That class is where the rule and its exception are
## explained; nothing else on a card may be anything but
## [constant Control.MOUSE_FILTER_IGNORE].
func _card(item: Dictionary, group: ButtonGroup, selected: bool, on_select: Callable) -> Control:
	var host := PanelContainer.new()
	host.custom_minimum_size.x = CARD_MIN_WIDTH
	# The host draws the card's shadow — and, when this is the chosen card, its glow instead. It has to
	# be given a stylebox explicitly either way: left alone it takes [OutpostTheme]'s panel, which is a
	# dark slab with a blue border, and every card gains a navy frame around its parchment.
	host.add_theme_stylebox_override("panel",
		UiSkin.card_glow_style() if selected else UiSkin.card_shadow_style())

	var button := Button.new()
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	UiSkin.apply_card(button)
	# **`toggled` carries the choice, not `pressed`.** Two things pick this card — the plate itself,
	# where the painting is, and a tap forwarded from the scroll region over the prose, which arrives
	# as `button_pressed = true` and never fires `pressed` at all. `toggled` is the one signal both
	# routes go through, so the selection is made in one place. It is also the only one that tells the
	# card being *deselected*, which is what takes the glow back off it.
	button.toggled.connect(func(on: bool) -> void:
		host.add_theme_stylebox_override("panel",
			UiSkin.card_glow_style() if on else UiSkin.card_shadow_style())
		if on:
			on_select.call(String(item["id"])))
	host.add_child(button)

	# Two insets, not one. The painting runs out to the plate's drawn rail, so only the rail's own
	# width holds it off the edge; the lettering keeps the full field padding. One shared margin would
	# mean choosing between a picture floating in a parchment mount and text jammed against the
	# moulding.
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		padding.add_theme_constant_override(side, int(CARD_BORDER_INSET))
	host.add_child(padding)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 0)
	padding.add_child(content)

	# **The card's width decides the painting's height**, so the whole image is shown and never
	# cropped whatever width the pager hands the card. It was a fixed 134 with a cover-crop before,
	# which threw away the top and bottom of every painting — and threw away *more* of it the wider
	# the card got, which is the opposite of what extra room should buy.
	#
	# Godot has a mode that says exactly this, `EXPAND_FIT_WIDTH_PROPORTIONAL`, and it cannot be used
	# here: it derives the minimum height from the control's *current* width, which is zero at the
	# moment a container asks what its minimum is, so the picture reports no height, is given none,
	# and never appears at all. Driving it from `resized` instead is stable — the height follows the
	# width, and recomputing from an unchanged width yields the same number, so it settles in one pass.
	var art := TextureRect.new()
	var texture: Texture2D = load(String(item["image"]))
	art.texture = texture
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	var aspect := float(texture.get_width()) / float(texture.get_height())
	art.resized.connect(func() -> void: art.custom_minimum_size.y = art.size.x / aspect)
	content.add_child(art)

	# **The prose scrolls inside the card, not the card inside the step.** The painting stays put at the
	# top and everything under it moves, down to the card's own bottom edge. Scrolling the whole step
	# instead put the bar down the side of the page and slid the picture away the moment you read past
	# it; and on a phone it stacked a scroll region inside a scroll region under the same finger. Each
	# card is a fixed frame with its own contents now, so a row of them stays aligned however much text
	# any one of them has, and there is exactly one thing on the step that scrolls: the card you are
	# reading.
	#
	# **The scroll region takes the whole face under the painting, and the padding goes inside it.** The
	# bar is then on the card's own rail, level with the edges of the picture above it and running the
	# full height of everything below it — a fitting of the card rather than a control floating on it.
	# Padding the region from the outside instead inset the bar on all four sides, which left it
	# hanging in the parchment with a strip of card either side of it.
	#
	# [CardScroll] rather than a [ScrollContainer]: a scroll region is the one thing that can be on a
	# card's face without being [constant Control.MOUSE_FILTER_IGNORE], so it is also the one thing that
	# would swallow the card's click. It hands the tap back; the class says why nothing simpler works.
	# Hover has to be handed back the same way — the plate cannot see a pointer that never reaches it.
	var scroll := CardScroll.new()
	scroll.custom_minimum_size.y = CARD_TEXT_MIN_HEIGHT
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSkin.apply_scroll_container(scroll)
	scroll.tapped.connect(func() -> void: button.button_pressed = true)
	scroll.mouse_entered.connect(func() -> void: UiSkin.set_card_hover(button, true))
	scroll.mouse_exited.connect(func() -> void: UiSkin.set_card_hover(button, false))
	content.add_child(scroll)

	# The prose keeps the field padding, but as part of what scrolls — so the first line starts clear of
	# the painting and the last one clears the card's bottom rail, and both edges of the paragraph stay
	# off the moulding. A [ScrollContainer] hands its child the view's width only if the child asks to
	# expand into it; without that flag the prose wraps to its own minimum width and the card becomes a
	# column of text down its left-hand side.
	var text := MarginContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right"]:
		text.add_theme_constant_override(side, int(CARD_PADDING - CARD_BORDER_INSET))
	text.add_theme_constant_override("margin_top", int(CARD_PADDING - CARD_BORDER_INSET))
	text.add_theme_constant_override("margin_bottom", int(CARD_PADDING - CARD_BORDER_INSET))
	scroll.add_child(text)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	text.add_child(column)
	content = column

	var title := Label.new()
	title.text = String(item["title"])
	title.add_theme_font_size_override("font_size", UiSkin.FONT_HEADING)
	title.add_theme_color_override("font_color", UiSkin.INK)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)

	# "Economic Start" — the one-phrase answer to "what kind of start is this", above the paragraph
	# that explains it. Only the backgrounds carry one; a location's three fact lines say it instead.
	if item.has("meta"):
		var meta := Label.new()
		meta.text = String(item["meta"]).to_upper()
		meta.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
		meta.add_theme_color_override("font_color", CARD_META_COLOR)
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(meta)

	# A [RichTextLabel], because the body is BBCode: the "Starts with:" heading and the location's
	# "Difficulty:" labels are bold, and a plain [Label] would print the tags.
	#
	# `fit_content` is what makes it size to its text — without it a RichTextLabel reports a minimum
	# height of zero, and the card collapses to the painting with the prose clipped to nothing.
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = String(item["body"])
	body.fit_content = true
	body.scroll_active = false
	body.add_theme_font_size_override("normal_font_size", UiSkin.FONT_SMALL)
	body.add_theme_font_size_override("bold_font_size", UiSkin.FONT_SMALL)
	body.add_theme_color_override("default_color", UiSkin.INK_MUTED)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(body)

	var badges: Array = item.get("badges", [])
	if not badges.is_empty():
		var strip := HFlowContainer.new()
		strip.add_theme_constant_override("h_separation", 6)
		strip.add_theme_constant_override("v_separation", 6)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(strip)
		for badge: String in badges:
			strip.add_child(_badge(badge))
	return host


## One short tag under a card's prose — "Coins", "Trade".
func _badge(text: String) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiSkin.badge_style())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiSkin.FONT_SMALL)
	label.add_theme_color_override("font_color", UiSkin.INK_MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(label)
	return plate


# --- Step 3: Hero -------------------------------------------------------------------------

func _build_hero_step() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)

	col.add_child(_field_label("Hero name"))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = DEFAULT_HERO
	UiSkin.apply_line_edit(_name_field)
	_name_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	_name_field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_name_field)

	# Sex is a hero attribute and already reads as a card-style pick-one. Appearance joins this step
	# when there is art to choose; no empty promise is shown before then.
	col.add_child(_field_label("Sex"))
	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	col.add_child(sex_row)
	var sex_group := ButtonGroup.new()
	sex_row.add_child(_sex_button("Male", "male", sex_group, true))
	sex_row.add_child(_sex_button("Female", "female", sex_group, false))
	return col


# --- Step 4: Banner -----------------------------------------------------------------------

func _build_banner_step() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)

	col.add_child(_field_label("Outpost name"))
	# Flows, so Randomize drops below the field rather than squeezing the default name on a phone.
	var outpost_row := HFlowContainer.new()
	outpost_row.add_theme_constant_override("h_separation", 8)
	outpost_row.add_theme_constant_override("v_separation", 8)
	col.add_child(outpost_row)
	_outpost_name_field = LineEdit.new()
	_outpost_name_field.text = DEFAULT_OUTPOST
	UiSkin.apply_line_edit(_outpost_name_field)
	_outpost_name_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	outpost_row.add_child(_outpost_name_field)
	var reroll := SkinnedButton.create("Randomize", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	reroll.pressed.connect(_randomize_outpost_name)
	outpost_row.add_child(reroll)

	# Preview and controls share a line on desktop and wrap into preview-above-controls on a phone.
	# One HFlowContainer owns both arrangements, so crossing the breakpoint cannot lose state.
	var designer := HFlowContainer.new()
	designer.add_theme_constant_override("h_separation", 16)
	designer.add_theme_constant_override("v_separation", 16)
	col.add_child(designer)

	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation", 8)
	preview.add_child(_field_label("Banner preview"))
	_flag_value.texture = "pattern03"
	_flag_value.emblem = "emblem01"
	_flag_view = FlagView.new()
	_flag_view.custom_minimum_size = Vector2(
		FLAG_PREVIEW_MOBILE_WIDTH, FLAG_PREVIEW_MOBILE_WIDTH * FlagView.aspect())
	preview.add_child(_flag_view)
	designer.add_child(preview)
	designer.resized.connect(func() -> void: _size_banner_preview(designer.size.x))

	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = BANNER_CONTROLS_WIDTH
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	designer.add_child(controls)

	# Five compact properties are the whole flag model. Each row shows the current value and opens a
	# focused editor, instead of making the player scroll past every possible value on the main step.
	_banner_property_button(controls, "shape_color", "Cloth colour",
		func() -> void: _open_color_picker("Cloth colour", "shape_color"), true)
	_banner_property_button(controls, "texture", "Pattern",
		func() -> void: _open_shape_picker("Choose a pattern", "pattern", FLAG_PATTERN_COUNT))
	_banner_property_button(controls, "texture_color", "Pattern colour",
		func() -> void: _open_color_picker("Pattern colour", "texture_color"), true)
	_banner_property_button(controls, "emblem", "Emblem",
		func() -> void: _open_shape_picker("Choose an emblem", "emblem", FLAG_EMBLEM_COUNT))
	_banner_property_button(controls, "emblem_color", "Emblem colour",
		func() -> void: _open_color_picker("Emblem colour", "emblem_color"), true)

	var randomize_flag := SkinnedButton.create("Randomize flag", UiSkin.BROWN,
		UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_FONT_SIZE)
	randomize_flag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	randomize_flag.pressed.connect(_randomize_flag)
	controls.add_child(randomize_flag)

	_refresh_banner_properties()
	_flag_view.set_value(_flag_value)
	return col


## One of the two sex choices. A card rather than a plate: it is a pick-one, the same kind of answer
## the Background and Location steps take, and it should look like one.
func _sex_button(text: String, id: String, group: ButtonGroup, selected: bool) -> Control:
	var host := PanelContainer.new()
	host.add_theme_stylebox_override("panel",
		UiSkin.card_glow_style() if selected else UiSkin.card_shadow_style())
	host.custom_minimum_size = Vector2(SEX_BUTTON_WIDTH, UiSkin.CONTROL_HEIGHT)
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	UiSkin.apply_card(button)
	button.toggled.connect(func(on: bool) -> void:
		host.add_theme_stylebox_override("panel",
			UiSkin.card_glow_style() if on else UiSkin.card_shadow_style())
		if on:
			_sex = id)
	host.add_child(button)
	return host


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	l.add_theme_color_override("font_color", UiSkin.INK)
	# **Wrapping, so a label cannot set the width of the page.** A Label's minimum width is its whole
	# line unless it may wrap, and "How should the game master narrate?" is 556 units of it at this
	# type scale — enough on its own to push the Settings step 20 past a 720-wide phone. Wrapping
	# drops that minimum to the longest single word. The flag designer's layer names are unaffected:
	# they are short and carry their own column width.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _banner_property_button(parent: Node, key: String, label_text: String,
		on_press: Callable, show_swatch: bool = false) -> void:
	var button := Button.new()
	button.set_meta("property_label", label_text)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 72.0
	UiSkin.apply_input(button)
	button.pressed.connect(on_press)
	_banner_property_buttons[key] = button
	parent.add_child(button)
	if show_swatch:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		chip.offset_left = -54.0
		chip.offset_right = -14.0
		chip.offset_top = -20.0
		chip.offset_bottom = 20.0
		button.add_child(chip)
		_banner_property_swatches[key] = chip


func _open_color_picker(title: String, target: String) -> void:
	var content := VBoxContainer.new()
	var initial := _flag_color(target)
	var picker := ColorPicker.new()
	picker.color = initial
	picker.edit_alpha = false
	picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.custom_minimum_size.y = 360.0
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(picker)

	picker.color_changed.connect(func(color: Color) -> void:
		_set_flag_color(target, color))
	_open_picker_modal(title, content, 420.0)


func _open_shape_picker(title: String, kind: String, count: int) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	var selected := _flag_value.texture if kind == "pattern" else _flag_value.emblem
	_flag_thumbnail_grid(content, kind, count, selected, func(id: String) -> void:
		if kind == "pattern":
			_flag_value.texture = id
		else:
			_flag_value.emblem = id
		_refresh_banner_properties()
		_flag_view.set_value(_flag_value))
	_open_picker_modal(title, content, 360.0)


func _open_picker_modal(title: String, content: Control, preferred_height: float) -> void:
	if _active_picker != null:
		_active_picker.queue_free()
	_active_picker = PickerModal.create(title, content, preferred_height)
	var modal := _active_picker
	modal.closed.connect(func() -> void:
		if _active_picker == modal:
			_active_picker = null
		modal.queue_free())
	add_child(modal)
	modal.open()


func _flag_thumbnail_grid(parent: Node, kind: String, count: int,
		selected_id: String, on_pick: Callable) -> Array[FlagThumbnail]:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", FLAG_GRID_GAP)
	flow.add_theme_constant_override("v_separation", FLAG_GRID_GAP)
	parent.add_child(flow)
	var group := ButtonGroup.new()
	var choices: Array[FlagThumbnail] = []
	for i in count + 1:
		var id := FlagValue.NONE if i == 0 else "%s%02d" % [kind, i]
		var choice := FlagThumbnail.new()
		var foreground := _flag_value.texture_color
		if kind == "emblem":
			foreground = _flag_value.emblem_color
		choice.setup(kind, id, _flag_value.shape_color, foreground, group, id == selected_id)
		choice.toggled.connect(func(on: bool) -> void:
			if on:
				on_pick.call(id))
		choices.append(choice)
		flow.add_child(choice)
	return choices


func _randomize_outpost_name() -> void:
	_outpost_name_field.text = OUTPOST_NAMES[randi() % OUTPOST_NAMES.size()]


func _randomize_flag() -> void:
	_flag_value.shape_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.texture_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.emblem_color = Color.html(FLAG_PALETTE[randi() % FLAG_PALETTE.size()])
	_flag_value.texture = "pattern%02d" % (1 + randi() % FLAG_PATTERN_COUNT)
	_flag_value.emblem = "emblem%02d" % (1 + randi() % FLAG_EMBLEM_COUNT)
	_refresh_banner_properties()
	_flag_view.set_value(_flag_value)


func _flag_palette_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for hex: String in FLAG_PALETTE:
		colors.append(Color.html(hex))
	return colors


func _flag_color(target: String) -> Color:
	match target:
		"shape_color":
			return _flag_value.shape_color
		"texture_color":
			return _flag_value.texture_color
		"emblem_color":
			return _flag_value.emblem_color
	return Color.WHITE


func _set_flag_color(target: String, color: Color) -> void:
	var opaque := color
	opaque.a = 1.0
	match target:
		"shape_color":
			_flag_value.shape_color = opaque
		"texture_color":
			_flag_value.texture_color = opaque
		"emblem_color":
			_flag_value.emblem_color = opaque
	_refresh_banner_properties()
	_flag_view.set_value(_flag_value)


func _refresh_banner_properties() -> void:
	_set_banner_property("shape_color", "")
	_set_banner_property("texture", _flag_option_name("pattern", _flag_value.texture))
	_set_banner_property("texture_color", "")
	_set_banner_property("emblem", _flag_option_name("emblem", _flag_value.emblem))
	_set_banner_property("emblem_color", "")
	for key: String in _banner_property_swatches:
		(_banner_property_buttons[key] as Button).tooltip_text = (
			"#" + _flag_color(key).to_html(false).to_upper())
		(_banner_property_swatches[key] as PanelContainer).add_theme_stylebox_override(
			"panel", UiSkin.swatch_style(_flag_color(key), false))


func _set_banner_property(key: String, value: String) -> void:
	if not _banner_property_buttons.has(key):
		return
	var button := _banner_property_buttons[key] as Button
	var label_text := String(button.get_meta("property_label"))
	button.text = label_text if value.is_empty() else "%s  —  %s" % [label_text, value]


func _size_banner_preview(available_width: float) -> void:
	var desktop_floor := BANNER_CONTROLS_WIDTH + FLAG_PREVIEW_DESKTOP_WIDTH + 16.0
	var width := FLAG_PREVIEW_DESKTOP_WIDTH if available_width >= desktop_floor \
		else FLAG_PREVIEW_MOBILE_WIDTH
	_flag_view.custom_minimum_size = Vector2(width, width * FlagView.aspect())


func _flag_option_name(kind: String, id: String) -> String:
	if id == FlagValue.NONE:
		return "None"
	var prefix_length := 7 if kind == "pattern" else 6
	return str(int(id.substr(prefix_length)))


# --- Step 5: Settings ----------------------------------------------------------------------

func _build_settings_step() -> Control:
	_selected_verbosity = Kernel.settings.narration_level()
	_selected_language = Kernel.settings.language()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.add_child(_field_label("Language"))
	_language_picker = LanguagePicker.create(_selected_language)
	_language_picker.language_selected.connect(func(code: String) -> void:
		_selected_language = code)
	col.add_child(_language_picker)

	col.add_child(_field_label("How should the game master narrate?"))
	var group := ButtonGroup.new()
	for item: Dictionary in VERBOSITIES:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		UiSkin.apply_card(b)
		b.custom_minimum_size.y = UiSkin.CONTROL_HEIGHT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s — %s" % [String(item["title"]), String(item["desc"])]
		b.button_pressed = String(item["id"]) == _selected_verbosity
		b.pressed.connect(func() -> void: _selected_verbosity = String(item["id"]))
		col.add_child(b)
	return col
