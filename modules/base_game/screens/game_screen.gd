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

## Conversation colours, as hex because they are BBCode inside a message rather than a theme
## override on a control. `wheat`, `gray`, `orange` and the rest were picked for a dark panel — on
## parchment `wheat` is very nearly the paper itself, which is what made the narrated opening the
## palest thing on the page. The player's own lines and the game master's keep their old tags: those
## two go only to the hidden semantic log `_append` filters by that exact text.

## The banner in the top bar — the one thing on this screen that is not held inside its own strip.
## It is taller than the bar at this width, and hanging past it is the point: a banner flies from a
## rail, it does not sit in a box.
const HEADER_FLAG_WIDTH := 88.0
const TOP_BAR_NAME_FONT_SIZE := UiSkin.FONT_BODY
const TOP_BAR_RANK_FONT_SIZE := UiSkin.FONT_SMALL - 4
const TOP_BAR_RESOURCE_VALUE_FONT_SIZE := UiSkin.FONT_BODY
const TOP_BAR_RESOURCE_INCREMENT_FONT_SIZE := TOP_BAR_RANK_FONT_SIZE

## **Every readout occupies the same width, whatever its number.** Left to size themselves, the three
## sit at whatever rhythm today's values happen to produce, and the group shuffles sideways the moment
## a figure gains a digit — a status bar that moves when the status changes. A fixed slot each makes
## the spacing a property of the bar rather than of the numbers on it.
const TOP_BAR_RESOURCE_SLOT_WIDTH := 98.0
const TOP_BAR_RESOURCE_SEPARATION := 14

## What the number and its delta are given inside that slot.
const TOP_BAR_RESOURCE_VALUES_WIDTH := 42.0

## **A third readout does not fit a phone at the desktop's measurements.** The bar is one row by
## definition and cannot wrap, and it already wanted about 870 units of a 720-wide screen with two
## readouts on it — adding score at full size ran the settlement's name into the coins and pushed the
## date off the right-hand edge. So on a phone the icon and the figures both give, which is the same
## answer this row has always reached: it is the type size that yields, because nothing here can move
## to another line. Measured back from what fits rather than chosen.
const TOP_BAR_RESOURCE_SLOT_WIDTH_MOBILE := 64.0
const TOP_BAR_RESOURCE_VALUES_WIDTH_MOBILE := 31.0

## Where the banner hangs from. **Negative on purpose**: the art carries a finial and a crossbar
## above the cloth — a quarter of its height — and at this size that is a long brown spike standing
## over the bar. Lifting it by most of that leaves the cloth starting just under the bar's top rule
## and the hardware off the screen, which is what a banner hung from a rail looks like.
const BANNER_TOP_INSET := -34.0

## **The banner casts the top bar's own shadow** — `UiSkin.HEADER_SHADOW_*`, the wide flat falloff
## that separates the chrome from the map. It hangs off that bar, so the two were the one pair on
## this screen that had no excuse for disagreeing, and a hard-edged black copy of the cloth read as a
## second flag behind the first rather than as a shadow.
##
## It cannot be the same *stylebox*. [method UiSkin.shadow_style] documents at length why its centre
## has to be an opaque fill — Godot draws no shadow at all without one, and the shadow is a filled
## rounded rect rather than a ring — which works only because a plate covers that fill completely.
## A notched cloth on a crossbar covers almost none of its own bounding box, so behind this the fill
## would be a near-black slab showing through the V at the foot and either side of the hardware: the
## same failure the arrow plates and the card fields hit through a few transparent pixels, at the
## scale of most of the shape.
##
## So the falloff is cast from the silhouette instead — several copies of the cloth in a ring, each
## faint enough that where they all overlap they compose to the header's own opacity, and the band
## where progressively fewer of them land is the blur. The colour, the drop and the radius are all
## read from the header's constants, so the two shadows cannot drift apart.
##
## Eight taps is where the ring stops scalloping at this radius: the union of the copies is what
## gives the shadow its outer edge, and too few leave that edge visibly polygonal.
const BANNER_SHADOW_TAPS := 8
const SPEED_BUTTON_SEPARATION := 4

## Wide enough that "Yes" and "No" are the same plate — an answer whose halves are different sizes
## reads as one of them being the expected one.
const ANSWER_BUTTON_WIDTH := 130.0

## Load sits beside the slot list, so it is sized rather than left to its caption.
const MENU_ACTION_WIDTH := 140.0

## The plates on the band — Build, the tools, Confirm and Cancel. All one width, so the row does not
## re-flow as the band changes what it is offering.
const BUILD_BUTTON_WIDTH := 124.0

## Whether the map-art dev keys are live — see [method _dev_map_keys]. Scaffolding for judging
## painted art against the running map; one constant so it leaves in one edit.
const DEV_MAP_KEYS := true

const MARKER_FLAG_WIDTH := 30.0
const MAIN_MENU_PAGE_ID := "main_menu"
const MAP_LAYERS_PAGE_ID := "map_layers"

var _shell: HudShell
var _map_view: OverworldMapView
## Held because selection has to ask the content what is at a cell, which the view cannot answer —
## it draws the map and never learns what has been built on it.
var _terrain_map: TerrainMap
var _selection_dock: SelectionDock
## What kind of thing is selected ([constant BaseGameMap.KIND_CONSTRUCTION] and friends), or empty.
## The map view holds the *footprint*; which layer that footprint belongs to is this screen's to
## remember, and it is what decides whether hiding the constructions has to drop it.
var _selection_kind := ""

## The roads, and the run the player is drawing but has not yet committed to.
##
## [member _plan] is `{subtile -> true}` for pieces that may be applied and `{subtile -> false}` for
## the ones that may not — both are in it, because a red piece is feedback about why the finished
## road has a gap, not something to hide. [member _build_tool] is empty when not building.
var _roads: RoadNetwork
var _build_tool := ""
var _plan: Dictionary = {}
var _confirm_button: SkinnedButton

var _source: AiInputSource
var _outpost_label: Label
var _tier_label: Label
var _flag_view: FlagView
## The copies that make up the banner's shadow. They never get the flag's value: the silhouette they
## are drawn for comes from the cloth's own alpha, which is the same whatever is painted on it.
var _flag_shadows: Array[FlagView] = []
var _gold_label: Label
var _gold_increment_label: Label
var _population_label: Label
var _population_increment_label: Label
## Score has no system behind it yet — it reads 0 and its delta reads +0, which is the honest answer
## until something computes one. It takes its place in the bar now rather than appearing later and
## shifting the two readouts beside it.
var _score_label: Label
var _score_increment_label: Label
## The status group and the spacer that positions it, held so [method _centre_status_group] can put
## the group on the bar's own centre line at any width.
var _resources_left: Control
var _resources_host: Control
var _resource_icons: Array[TextureRect] = []
var _date_label: Label
var _log_label: RichTextLabel
var _message_list: ChatMessageList
var _input: LineEdit
var _send_button: Button
var _retry_button: SkinnedButton
var _event_image: Control
var _speed_buttons: Dictionary = {}
var _speed_host: Control
## The plates in the map-layers flyout. Held because the same overlays are also reachable from the
## phone's Map Layers page, and the two must not contradict each other.
var _grid_layer_plate: SkinnedButton
var _terrain_layer_plate: SkinnedButton
var _trace_label: RichTextLabel

## The question the game master is waiting on, if any (M4/B4b). Lives in the dock, not inside the
## collapsible expanded-chat panel, so it stays visible to answer whether or not chat is expanded.
var _pending_row: HBoxContainer
var _pending_label: Label
var _pending_instance: String = ""
var _slots: OptionButton

var _chat_dock: ChatDock
var _menu_panel: HudPanel
var _destination_panels: Dictionary = {} # id -> persistent HudPanel


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
	elif _dev_map_keys(event):
		get_viewport().set_input_as_handled()


## **Dev keys for looking at map art, and nothing else.** Turn [constant DEV_MAP_KEYS] off and they
## are gone.
##
## [table]
## [cell]`5` `6` `7` `8`[/cell]        [cell]house: foundation, under construction, nearly finished, finished[/cell]
## [cell]`Shift+5` … `Shift+8`[/cell]  [cell]house: ruin, damaged, burnt, abandoned[/cell]
## [cell]`9`[/cell]                    [cell]advance the crop cycle one stage, wrapping[/cell]
## [cell]`0`[/cell]                    [cell]snow on the buildings, on and off[/cell]
## [/table]
##
## The building stages hold `5`–`8` because that is what they were asked for; the crop cycle had them
## on loan while there were no buildings and moves to one key that cycles, which is enough for four
## frames of the same field.
##
## Deliberately *not* in [InputActions]: that file's own rule is that only actions with something
## behind them live there, because a binding the player can change and then watch do nothing is the
## failure the whole `planned` discipline exists to prevent. These drive statics that no game system
## reads or writes — they are a way of seeing paintings, not a feature.
##
## They are also checked **last**, after every real action above, so nothing here can shadow a key the
## player actually uses. The day one of these is bound to something real, the real action wins.
func _dev_map_keys(event: InputEvent) -> bool:
	if not DEV_MAP_KEYS:
		return false
	var key := event as InputEventKey
	if key == null or key.ctrl_pressed or key.alt_pressed:
		return false
	var slot := [KEY_5, KEY_6, KEY_7, KEY_8].find(key.keycode)
	if slot >= 0:
		# The two rows of four: the build stages plain, the ruined states shifted. They are one enum,
		# so the shifted row is simply the second half of it.
		_set_house_appearance((slot + (4 if key.shift_pressed else 0)) as Buildings.Appearance)
		return true
	if key.shift_pressed:
		return false
	if key.keycode == KEY_9:
		_set_crop_stage(((int(BaseGameMap.crop_stage) + 1)
			% BaseGameMap.CropStage.size()) as BaseGameMap.CropStage)
		return true
	if key.keycode == KEY_0:
		Buildings.snow = not Buildings.snow
		_refresh_map_content()
		return true
	return false


func _set_crop_stage(stage: BaseGameMap.CropStage) -> void:
	if BaseGameMap.crop_stage == stage:
		return
	BaseGameMap.crop_stage = stage
	_refresh_map_content()


func _set_house_appearance(appearance: Buildings.Appearance) -> void:
	if Buildings.appearance == appearance:
		return
	Buildings.appearance = appearance
	_refresh_map_content()


## Push the fields and the houses at the map: the sprites drawn over the ground, and the ground colour
## under the fields that is what survives zooming out past the point where art is drawn at all.
##
## **The band is re-read too.** It names the crop and the house's state, so anything selected while
## these change would otherwise go on claiming to be the thing it was a moment ago.
func _refresh_map_content() -> void:
	if _map_view == null or _terrain_map == null:
		return
	_map_view.set_textures(BaseGameMap.load_textures(_terrain_map))
	_map_view.set_standing(BaseGameMap.standing(_terrain_map))
	if _selection_kind == BaseGameMap.KIND_CONSTRUCTION:
		_clear_selection()


## Esc closes whatever panel is on top before falling through to the exit-confirm dialog
## (ux_plan.md §1.3 rule 6) — `BACK_CLOSE` reaches here via `Kernel.request_back()`
## (`core/kernel.gd`'s `_handle_hardware_back`).
## **A plan in progress is the shallowest thing on the screen**, so Esc abandons it before anything
## the shell owns. It is also the only one that would otherwise be closed *from underneath* — the
## shell's own first move is to hide the band, which is where Cancel lives.
func on_hardware_back() -> bool:
	if is_building():
		_cancel_build()
		return true
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
	_append(prose)
	_say("King", prose)
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
	_build_selection_band()
	_build_menu_panel()
	_build_destination_actions()


func _build_map() -> void:
	_map_view = OverworldMapView.new()
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.base_layer.add_child(_map_view)
	var map := BaseGameMap.load_map()
	if map == null:
		return
	_terrain_map = map
	_map_view.setup(map, BaseGameMap.load_textures(map))
	_map_view.set_scatter(BaseGameMap.load_scatter(map))
	_map_view.set_ground_overrides(BaseGameMap.load_ground_overrides(map))
	_refresh_map_content()
	_roads = RoadNetwork.new()
	_refresh_roads()
	_map_view.subtile_clicked.connect(_on_subtile_clicked)
	_map_view.subtile_painted.connect(_on_subtile_painted)
	# The map drops a selection the player has zoomed away from, on its own. That is the only route by
	# which the band can go stale without anything here being pressed.
	_map_view.selection_changed.connect(_on_map_selection_changed)
	_refresh_map_marker()


## The outpost's banner pinned to the cell the seed founded it on. A separate call from
## `_build_map` because a New Game or Load started from inside the running shell (the Main Menu
## panel) can change *which* cell that is without the terrain itself changing — the old
## `MapOverlay` got this for free by rebuilding from scratch on every open; the map is now built
## once, so anything that can change the outpost's site has to ask for this explicitly.
##
## **Off while the map is being built up.** There is no settlement drawn on the ground yet for a
## banner to be planting itself over, so a flag on a bare cell is a label for something that is not
## there — and it is the one thing standing in the middle of the map while the terrain, the ground
## scatter and eventually the forests are being judged against each other. Everything it needs is
## kept, wired and called from all three places that can move the site; flip this back to true and the
## pin returns, over whatever the outpost has become by then.
const MAP_MARKER_ENABLED := false


func _refresh_map_marker() -> void:
	if _map_view == null:
		return
	_map_view.remove_marker("outpost")
	if not MAP_MARKER_ENABLED:
		return
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
	# The poleless cut here: at the tall aspect nearly all of what fits in a strip of chrome is pole.
	# The map pin keeps the full banner — a flag on a pole is what a pin should look like — so the two
	# cuts are used for what each is for rather than one being a fallback.
	#
	# **It hangs out of the bar.** At this size it is taller than the bar it flies from, so it cannot
	# live in the bar: a control that tall inside the row would simply make the row that tall. What
	# stands in the row is an empty slot of the right width, and the banner itself is parented to the
	# shell's overlay and placed against that slot — over the bar, over the map below it.
	var banner_slot := Control.new()
	banner_slot.custom_minimum_size.x = HEADER_FLAG_WIDTH
	banner_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(banner_slot)
	_shell.set_banner(_build_banner(), BANNER_TOP_INSET)
	_flag_view.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# The name and tier are a compact two-line identity stack, with the rank deliberately quieter below.
	var identity := Control.new()
	identity.name = "top_identity"
	_outpost_label = _bar_label(TOP_BAR_NAME_FONT_SIZE)
	# The settlement name is the header's primary identity, so give its ink a one-pixel same-colour
	# outline. It reads as a true bold weight without changing the size or disturbing the rank below.
	_outpost_label.add_theme_constant_override("outline_size", 1)
	_outpost_label.add_theme_color_override("font_outline_color", UiSkin.INK)
	_outpost_label.position = Vector2(0, -8)
	_outpost_label.size = Vector2(150, 28)
	identity.add_child(_outpost_label)
	# The growth axis the wireframe implies (Outpost -> Village -> Town -> ...) has no system
	# behind it yet — a fixed tier, not a computed one, until M7 designs the ladder (ux_plan.md §5).
	_tier_label = _bar_label(TOP_BAR_RANK_FONT_SIZE, true)
	_tier_label.text = "Outpost"
	_tier_label.position = Vector2(0, 22)
	_tier_label.size = Vector2(150, 19)
	identity.add_child(_tier_label)
	var identity_host := Control.new()
	identity_host.name = "top_identity_slot"
	identity_host.custom_minimum_size = Vector2(150, UiSkin.TOP_BAR_HEIGHT
		- UiSkin.TOP_BAR_PADDING_TOP - UiSkin.TOP_BAR_PADDING_BOTTOM)
	identity.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	identity_host.add_child(identity)
	bar.add_child(identity_host)

	# Coins, population and score share one status group between the identity and the date. Each keeps
	# its authored icon beside a two-line value stack: the amount is prominent and the neutral
	# placeholder delta sits beneath it at the same scale as the outpost rank.
	#
	# **The left spacer is sized, not stretched.** It used to expand with a hand-tuned 2.25 ratio to
	# compensate for the date-and-speed cluster being wider than the banner-and-identity one — but a
	# ratio splits the *free* space, and how much of that is free changes with the window, so one
	# number could only be right at one width. It carries a computed width now
	# ([method _centre_status_group]) and only the right-hand spacer expands, which is what keeps the
	# date and the speed plates flush to the right edge.
	_resources_left = Control.new()
	_resources_left.name = "top_resources_spacer"
	bar.add_child(_resources_left)
	var resources := HBoxContainer.new()
	resources.name = "top_resources"
	resources.alignment = BoxContainer.ALIGNMENT_CENTER
	resources.add_theme_constant_override("separation", TOP_BAR_RESOURCE_SEPARATION)
	resources.custom_minimum_size.y = TOP_BAR_NAME_FONT_SIZE + TOP_BAR_RANK_FONT_SIZE
	var gold := _resource_item(UiSkin.COIN_ICON, "Coins")
	_gold_label = gold.get_node("values/value") as Label
	_gold_increment_label = gold.get_node("values/increment") as Label
	resources.add_child(gold)
	var population := _resource_item(UiSkin.POPULATION_ICON, "Population")
	_population_label = population.get_node("values/value") as Label
	_population_increment_label = population.get_node("values/increment") as Label
	resources.add_child(population)
	var score := _resource_item(UiSkin.SCORE_ICON, "Score")
	_score_label = score.get_node("values/value") as Label
	_score_increment_label = score.get_node("values/increment") as Label
	resources.add_child(score)
	_resources_host = Control.new()
	_resources_host.name = "top_resources_slot"
	_resources_host.custom_minimum_size.y = (UiSkin.TOP_BAR_HEIGHT
		- UiSkin.TOP_BAR_PADDING_TOP - UiSkin.TOP_BAR_PADDING_BOTTOM)
	resources.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resources_host.add_child(resources)
	bar.add_child(_resources_host)
	var resources_right := Control.new()
	resources_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(resources_right)
	bar.resized.connect(_centre_status_group)

	_date_label = _bar_label(UiSkin.FONT_BODY)
	_date_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_date_label)
	# Four authored pick-one plates. The active speed keeps its blue selected artwork; the wrapper
	# supplies the same shadow, hover lift and press response as the rest of the painted controls.
	var speed_row := HBoxContainer.new()
	speed_row.name = "top_speed_buttons"
	speed_row.add_theme_constant_override("separation", SPEED_BUTTON_SEPARATION)
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_speed_host = Control.new()
	_speed_host.name = "top_speed_slot"
	_speed_host.custom_minimum_size = Vector2(UiSkin.SPEED_BUTTON_SIZE * 4
		+ SPEED_BUTTON_SEPARATION * 3, UiSkin.TOP_BAR_HEIGHT
		- UiSkin.TOP_BAR_PADDING_TOP - UiSkin.TOP_BAR_PADDING_BOTTOM)
	speed_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed_host.add_child(speed_row)
	for speed in [TimeDriver.Speed.PAUSED, TimeDriver.Speed.SPEED_1,
			TimeDriver.Speed.SPEED_2, TimeDriver.Speed.SPEED_3]:
		var button := UiSkin.speed_button(speed)
		button.tooltip_text = ["Pause", "Speed 1", "Speed 2", "Speed 3"][speed]
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_set_time_speed.bind(speed))
		speed_row.add_child(button)
		_speed_buttons[speed] = button
	bar.add_child(_speed_host)
	_refresh_time_buttons()


## The banner: the cloth, and the ring of faint copies behind it that is its shadow (see
## [constant BANNER_SHADOW_TAPS] for why it is built this way rather than from a stylebox).
##
## **The shadow has to be siblings drawn first, not children.** A [Control]'s children draw after it,
## so a shadow parented to the flag would fall in front of it.
func _build_banner() -> Control:
	var size := Vector2(HEADER_FLAG_WIDTH, HEADER_FLAG_WIDTH * FlagView.aspect(true))
	var banner := Control.new()
	banner.custom_minimum_size = size
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag_shadows.clear()
	# Solved rather than guessed at: compositing N layers of alpha `a` leaves `1 - (1 - a)^N`, so this
	# is the per-copy alpha whose overlap lands exactly on the header's. Stacking eight copies at the
	# header's own 0.34 would be a black cut-out.
	var tap_alpha := 1.0 - pow(1.0 - UiSkin.HEADER_SHADOW_COLOR.a, 1.0 / float(BANNER_SHADOW_TAPS))
	# The stylebox's `shadow_size` is how far the blur reaches *beyond* the box; a ring of radius r
	# spreads r outward and erodes r inward, so half the header's size puts the falloff's outer edge
	# in the same place.
	var radius := float(UiSkin.HEADER_SHADOW_SIZE) * 0.5
	for tap in BANNER_SHADOW_TAPS:
		var angle := TAU * float(tap) / float(BANNER_SHADOW_TAPS)
		var at := UiSkin.HEADER_SHADOW_OFFSET + Vector2(cos(angle), sin(angle)) * radius
		var cloth := _banner_cloth(banner, size)
		cloth.modulate = Color(UiSkin.HEADER_SHADOW_COLOR.r, UiSkin.HEADER_SHADOW_COLOR.g,
			UiSkin.HEADER_SHADOW_COLOR.b, tap_alpha)
		cloth.offset_left += at.x
		cloth.offset_right += at.x
		cloth.offset_top += at.y
		cloth.offset_bottom += at.y
		_flag_shadows.append(cloth)
	_flag_view = _banner_cloth(banner, size)
	return banner


## **The cloth is given its size explicitly.** [FlagView] fills in a default minimum of its own when
## it enters the tree with none set, and that default is wider than this banner — so the wrapper took
## *its* minimum instead and the banner flew half again too big, down over the first destination.
func _banner_cloth(parent: Control, size: Vector2) -> FlagView:
	var cloth := FlagView.new()
	cloth.short = true
	cloth.custom_minimum_size = size
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cloth)
	cloth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cloth


## One of the top bar's icon slots — the coin, the head. A [TextureRect] rather than a [Label] with a
## glyph in it, so the art is the art.
func _bar_icon(texture: Texture2D, tooltip: String, size: int = UiSkin.TOP_BAR_ICON_SIZE) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UiSkin.top_bar_icon(texture, size)
	# The art at its authored size, kept because the drawn one is a resampled copy: crossing the
	# breakpoint has to re-derive from the source, not from the copy made for the other breakpoint.
	icon.set_meta("source", texture)
	icon.tooltip_text = tooltip
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _resource_item(texture: Texture2D, tooltip: String) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.name = "top_%s" % tooltip.to_lower()
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 5)
	item.custom_minimum_size = Vector2(TOP_BAR_RESOURCE_SLOT_WIDTH,
		TOP_BAR_NAME_FONT_SIZE + TOP_BAR_RANK_FONT_SIZE)
	var icon := _bar_icon(texture, tooltip)
	_resource_icons.append(icon)
	item.add_child(icon)
	var values := Control.new()
	values.name = "values"
	values.custom_minimum_size = Vector2(TOP_BAR_RESOURCE_VALUES_WIDTH, 44)
	var value := _bar_label(TOP_BAR_RESOURCE_VALUE_FONT_SIZE)
	value.name = "value"
	value.position = Vector2(0, -6)
	value.size = Vector2(TOP_BAR_RESOURCE_VALUES_WIDTH, 29)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	values.add_child(value)
	var increment := _bar_label(TOP_BAR_RESOURCE_INCREMENT_FONT_SIZE, true)
	increment.name = "increment"
	increment.position = Vector2(0, 22)
	increment.size = Vector2(TOP_BAR_RESOURCE_VALUES_WIDTH, 19)
	increment.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	values.add_child(increment)
	item.add_child(values)
	return item


## Put the status group on the bar's own centre line — the middle of the *window*, not the middle of
## whatever gap the clusters either side of it happen to leave.
##
## **Corrected from the laid-out rect rather than calculated from the parts.** Working it out up front
## means summing two fixed clusters, the container's separations and the group's own minimum, and
## every one of those is a number this file would then own a copy of. Measuring how far off centre the
## group actually landed and moving the spacer by exactly that much needs none of them, and it is a
## single pass: nothing before the spacer expands, so widening it shifts the group and moves nothing
## else.
func _centre_status_group() -> void:
	if _resources_left == null or _resources_host == null or not is_inside_tree():
		return
	var bar := _shell.top_bar
	if bar == null or bar.size.x <= 0.0 or _resources_host.size.x <= 0.0:
		return
	var offset := bar.size.x * 0.5 - (_resources_host.position.x + _resources_host.size.x * 0.5)
	if is_zero_approx(offset):
		return
	_resources_left.custom_minimum_size.x = maxf(0.0, _resources_left.size.x + offset)


## A line of lettering on the game's own parchment chrome.
##
## **Not [method UiSkin.label_style]**, which is for a caption on a dark button plate: it paints the
## cream ink and the drop shadow that make text readable *there*, and cream on parchment is very
## nearly invisible. This is the same ink the wizard's field labels use.
func _bar_label(font_size: int, muted: bool = false) -> Label:
	var label := Label.new()
	_ink(label, font_size, muted)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _ink(label: Label, font_size: int, muted: bool = false) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiSkin.INK_MUTED if muted else UiSkin.INK)


## The conversation: one [ChatDock] built once and left in the stage for the screen's whole
## lifetime, so the chronicle survives being collapsed and re-expanded. Collapsed and expanded are
## the same board at two heights — the shell owns that geometry, this owns what is on it.
func _build_chat_panel() -> void:
	_chat_dock = ChatDock.new()
	_shell.set_chat_dock(_chat_dock)
	_chat_dock.set_title("Conversation")

	# The slot art will hang in is a mount, so it is drawn as one: the thin frame, empty, with the
	# note inside saying what belongs there. It was a dark rounded rectangle from the old theme —
	# the one remaining piece of chrome that would still have looked borrowed once the panel around
	# it was parchment.
	var event_image := PanelContainer.new()
	_event_image = event_image
	event_image.custom_minimum_size = Vector2(0, 140)
	event_image.tooltip_text = "Event artwork"
	event_image.add_theme_stylebox_override("panel", UiSkin.thin_frame_style())
	_chat_dock.body.add_child(event_image)
	var placeholder := VBoxContainer.new()
	placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
	event_image.add_child(placeholder)
	var placeholder_title := Label.new()
	placeholder_title.text = "Event illustration"
	placeholder_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(placeholder_title, UiSkin.FONT_BODY, true)
	placeholder.add_child(placeholder_title)
	var placeholder_note := Label.new()
	placeholder_note.text = "Artwork arrives with the authored event."
	placeholder_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(placeholder_note, UiSkin.FONT_SMALL, true)
	placeholder.add_child(placeholder_note)

	_message_list = ChatMessageList.new()
	_chat_dock.body.add_child(_message_list)

	# Existing integration tests inspect this semantic transcript directly. It remains as a
	# hidden mirror while the visible conversation is rendered as structured message rows.
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.visible = false
	_chat_dock.body.add_child(_log_label)


## The board's bottom section: the line the player writes on, the send plate, and the pending
## question kept beside them. **The question stays on the collapsed strip** — ux_plan.md put it in
## the dock precisely so an unanswered one is never hidden, and that reason survives the two frames
## becoming one.
func _build_dock() -> void:
	_pending_row = HBoxContainer.new()
	_pending_row.add_theme_constant_override("separation", 8)
	_pending_row.visible = false
	_chat_dock.set_pending_row(_pending_row)
	_pending_label = Label.new()
	_pending_label.add_theme_font_size_override("font_size", UiSkin.FONT_BODY)
	_pending_label.add_theme_color_override("font_color", UiSkin.LABEL)
	_pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pending_row.add_child(_pending_label)
	var yes := SkinnedButton.create("Yes", UiSkin.GREEN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	yes.custom_minimum_size.x = ANSWER_BUTTON_WIDTH
	yes.pressed.connect(func() -> void: await _answer(true))
	_pending_row.add_child(yes)
	var no := SkinnedButton.create("No", UiSkin.RED, UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_FONT_SIZE)
	no.custom_minimum_size.x = ANSWER_BUTTON_WIDTH
	no.pressed.connect(func() -> void: await _answer(false))
	_pending_row.add_child(no)

	var input_row := _chat_dock.input_row
	_input = LineEdit.new()
	_input.placeholder_text = "e.g. I send scouts to forage the hills"
	UiSkin.apply_chat_input(_input)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_submit)
	# Writing *is* opening the conversation. Reaching the field by any route — a tap on it, the
	# focus-input key, or a press on the board around it — is the same intent, so they all land here.
	_input.focus_entered.connect(func() -> void: _shell.set_chat_expanded(true))
	input_row.add_child(_input)
	# The send plate carries its arrow in the art, so it has no caption and stays square whatever the
	# type size is.
	_send_button = Button.new()
	_send_button.tooltip_text = "Send"
	UiSkin.apply_chat_send(_send_button)
	_send_button.pressed.connect(func() -> void: _on_submit(_input.text))
	input_row.add_child(_send_button)
	_retry_button = SkinnedButton.create("Retry connection", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	_retry_button.visible = false
	_retry_button.pressed.connect(func() -> void: Kernel.ai_availability.retry())
	input_row.add_child(_retry_button)


# --- map selection ---------------------------------------------------------------------------

## The band that describes whatever the player has picked off the map. Built once and left in the
## stage, like the conversation: showing it is a layout decision, not a construction one.
func _build_selection_band() -> void:
	_selection_dock = SelectionDock.new()
	_shell.set_selection_dock(_selection_dock)
	# Esc and the band's own ✕ both reach the shell, never this screen — so the map's outline is
	# cleared from the shell's own report rather than from each of the routes that can close the band.
	_shell.selection_visibility_changed.connect(_on_selection_visibility_changed)


## A press on the map that was not a pan. **The ladder is walked here**, in the module: which things
## contain which is game content, while how big they are on screen is the view's — so this asks
## `BaseGameMap` what is at the subtile and `BaseGameMap` asks the view whether it is big enough to
## be worth aiming at.
func _on_subtile_clicked(subtile: Vector2i) -> void:
	if _terrain_map == null or _map_view == null:
		return
	var picked := BaseGameMap.selection_at(_terrain_map, _map_view, subtile,
		_map_view.is_construction_layer_visible(), _roads)
	# Nothing selectable there — off the map, or everything under the pointer is too small at this
	# zoom to point at. Either way the honest answer is that the player has selected nothing.
	if picked.is_empty():
		_clear_selection()
		return
	var footprint: Array[Rect2i] = picked["footprint"]
	# Pressing the same thing again puts it away, which is the only way to deselect that does not
	# require finding a key or a small ✕.
	if _shell.is_selection_visible() and _map_view.selection() == footprint:
		_clear_selection()
		return
	_selection_kind = String(picked["kind"])
	_map_view.set_selection(footprint)
	_selection_dock.show_selection(String(picked["title"]),
		_holder_of(bool(picked["owned"])), picked["art"] as Texture2D)
	_fill_selection_actions()
	_shell.set_selection_visible(true)


## What can be done with what is selected. **Only open ground can be built on**, so only open ground
## offers the button — a selected farm gets an empty action area rather than a Build that would
## refuse. There is one thing to build, so Build goes straight to the tools rather than through a
## menu with a single entry.
func _fill_selection_actions() -> void:
	_selection_dock.clear_actions()
	_selection_dock.set_closable(true)
	if _selection_kind != BaseGameMap.KIND_TERRAIN:
		return
	var build := SkinnedButton.create("Build", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	build.custom_minimum_size.x = BUILD_BUTTON_WIDTH
	build.pressed.connect(_show_build_tools)
	_selection_dock.actions.add_child(build)


## The things that can be built. Two plates, because demolishing is how you take back a road you drew
## wrong and there is no undo.
func _show_build_tools() -> void:
	_selection_dock.clear_actions()
	for tool: Array in [[BaseGameMap.TOOL_ROAD, "Road", UiSkin.BROWN],
			[BaseGameMap.TOOL_DEMOLISH, "Demolish", UiSkin.RED]]:
		var plate := SkinnedButton.create(String(tool[1]), tool[2] as UiSkin.Variant,
			UiSkin.CONTROL_HEIGHT, UiSkin.CONTROL_FONT_SIZE)
		plate.custom_minimum_size.x = BUILD_BUTTON_WIDTH
		plate.pressed.connect(_enter_build_mode.bind(String(tool[0])))
		_selection_dock.actions.add_child(plate)
	var back := SkinnedButton.create("Back", UiSkin.GRAY, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	back.custom_minimum_size.x = BUILD_BUTTON_WIDTH
	back.pressed.connect(_fill_selection_actions)
	_selection_dock.actions.add_child(back)


# --- build mode ---------------------------------------------------------------------------------

## Hand the map over to drawing. The selection goes: what is on the band from here is the run being
## drawn, and an outline round the square the player happened to click first would only be in the way.
func _enter_build_mode(tool: String) -> void:
	_build_tool = tool
	_plan.clear()
	_map_view.clear_selection()
	_map_view.set_paint_mode(true)
	_map_view.clear_road_plan()
	_selection_kind = ""
	_refresh_build_bar()
	_shell.set_selection_visible(true)


## The band while building: what is being drawn, how, and the two ways out of it.
func _refresh_build_bar() -> void:
	var demolishing := _build_tool == BaseGameMap.TOOL_DEMOLISH
	_selection_dock.show_selection("Demolish" if demolishing else "Build a road",
		"Drag on the map to draw. W A S D or the screen edge moves the view.",
		RoadNetwork.ATLAS)
	_selection_dock.set_closable(false)
	_selection_dock.clear_actions()
	_confirm_button = SkinnedButton.create("Confirm", UiSkin.GREEN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	_confirm_button.custom_minimum_size.x = BUILD_BUTTON_WIDTH
	_confirm_button.pressed.connect(_confirm_build)
	_selection_dock.actions.add_child(_confirm_button)
	var cancel := SkinnedButton.create("Cancel", UiSkin.BROWN, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	cancel.custom_minimum_size.x = BUILD_BUTTON_WIDTH
	cancel.pressed.connect(_cancel_build)
	_selection_dock.actions.add_child(cancel)
	_restate_confirm()


## Nothing drawn yet is nothing to confirm. A plan of only refusals is the same: pressing Confirm
## would apply none of it and look like the button was broken.
func _restate_confirm() -> void:
	if _confirm_button == null:
		return
	var buildable := 0
	for subtile: Vector2i in _plan:
		if bool(_plan[subtile]):
			buildable += 1
	_confirm_button.button.disabled = buildable == 0


## One subtile crossed by the drag. The plan grows; nothing touches the world until Confirm.
func _on_subtile_painted(subtile: Vector2i) -> void:
	if _build_tool.is_empty() or _terrain_map == null:
		return
	var state := BaseGameMap.plan_state(_terrain_map, subtile, _roads, _build_tool)
	if state == "skip":
		return
	_plan[subtile] = state == "valid"
	_refresh_plan_ghosts()
	_restate_confirm()


## Draw the plan as it stands. The pieces are shaped as though the plan and the network were already
## one thing, so a run drawn up to an existing road shows the junction it is about to make rather
## than two roads ending beside each other.
func _refresh_plan_ghosts() -> void:
	var demolishing := _build_tool == BaseGameMap.TOOL_DEMOLISH
	var pieces: Dictionary = {}
	var refused: Dictionary = {}
	# **Every piece in the plan is shaped against every other**, refused ones included. A stretch that
	# cannot be built still runs *through* the ground it was drawn across, so drawing each refusal as
	# an isolated stub gives a dotted line of red specks where what the player needs to see is a red
	# road: the shape they drew, in the colour that says it will not be laid.
	for subtile: Vector2i in _plan:
		var mask := _roads.mask_at(subtile, _plan)
		pieces[subtile] = RoadNetwork.silhouette_for_mask(mask)
		# Demolition is refusal all the way through: there is no valid-looking way to draw a road
		# about to be taken away, and red is already the colour for "this will not be here".
		if demolishing or not bool(_plan[subtile]):
			refused[subtile] = true
	_map_view.set_road_plan(pieces, refused)


## Apply the plan. **The refused pieces are simply dropped** — sweeping a road across a farm gives
## the road either side of it, which is what the player was drawing.
func _confirm_build() -> void:
	var demolishing := _build_tool == BaseGameMap.TOOL_DEMOLISH
	for subtile: Vector2i in _plan:
		if not bool(_plan[subtile]):
			continue
		if demolishing:
			_roads.remove(subtile)
		else:
			_roads.add(subtile)
	Kernel.state.set_value(RoadNetwork.STATE_KEY, _roads.to_state())
	_refresh_roads()
	_leave_build_mode()


func _cancel_build() -> void:
	_leave_build_mode()


func _leave_build_mode() -> void:
	_build_tool = ""
	_plan.clear()
	_confirm_button = null
	_map_view.set_paint_mode(false)
	_map_view.clear_road_plan()
	_selection_dock.set_closable(true)
	_selection_dock.clear_actions()
	_shell.set_selection_visible(false)


func is_building() -> bool:
	return not _build_tool.is_empty()


## Push the network at the map, and re-read it from state. Called on entry and after anything that
## can replace the world under it — a load or a new game — for the same reason the outpost's marker is.
## **A world that has never had roads gets the demonstration figure**, and one that has gets its own.
## The distinction is whether the key is *there*, not whether it is empty: a player who demolishes
## their last road has a world with no roads in it, and putting the fixture back would be the game
## rebuilding what they just took down.
func _refresh_roads() -> void:
	if _map_view == null or _roads == null:
		return
	if Kernel.state.has_value(RoadNetwork.STATE_KEY):
		_roads.from_state(Kernel.state.get_value(RoadNetwork.STATE_KEY, []))
	else:
		_roads.clear()
		for at: Vector2i in BaseGameMap.demonstration_roads(_terrain_map):
			_roads.add(at)
	_map_view.set_roads(_roads.textures())


## Who holds the selected thing. The settlement's own name for anything the player owns; nothing at
## all for wild ground, rather than a word invented to stand in for "no one". There is no faction
## system to ask yet, so "owned" is the only distinction the content can honestly draw.
func _holder_of(owned: bool) -> String:
	if not owned:
		return ""
	var outpost: Dictionary = Entities.get_entity(Kernel.state, "outpost")
	return String(outpost.get("name", "The Outpost"))


func _on_selection_visibility_changed(visible: bool) -> void:
	if not visible:
		_selection_kind = ""
		if _map_view != null:
			_map_view.clear_selection()


## The map let a selection go by itself — the player zoomed out past the point where it was worth
## outlining. The band describes something that is no longer marked on the map, so it goes too.
func _on_map_selection_changed(footprint: Array[Rect2i]) -> void:
	if footprint.is_empty():
		_shell.set_selection_visible(false)


func _clear_selection() -> void:
	_shell.set_selection_visible(false)
	if _map_view != null:
		_map_view.clear_selection()


## Opening the conversation puts the caret where the player is about to type. There is no expand
## chevron any more: the board itself is the control, and the header's close is what puts it away.
func _on_chat_expanded_changed(expanded: bool) -> void:
	if expanded and _input.editable and not _input.has_focus():
		_input.grab_focus()


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

	# The last unskinned controls in the game: this page kept Godot's default plates while the panel
	# around it became parchment, so the one page a player opens most often was also the one that
	# still looked like a debug menu.
	var save_button := _menu_action("Save", UiSkin.BLUE, _on_save)
	_menu_panel.body.add_child(save_button)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	_menu_panel.body.add_child(slot_row)
	_slots = OptionButton.new()
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiSkin.apply_input(_slots)
	slot_row.add_child(_slots)
	var load_button := _menu_action("Load", UiSkin.BROWN, _on_load)
	load_button.custom_minimum_size.x = MENU_ACTION_WIDTH
	slot_row.add_child(load_button)

	_menu_panel.body.add_child(_menu_action("New game", UiSkin.BROWN, _on_new_game))
	_menu_panel.body.add_child(_menu_action("Settings", UiSkin.BROWN,
		func() -> void: Kernel.router.goto("core.settings", {"back": "base_game.chat"})))
	_menu_panel.body.add_child(_menu_action("Quit to title", UiSkin.BROWN,
		func() -> void: Kernel.router.goto("core.main_menu")))

	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", UiSkin.separator_style())
	_menu_panel.body.add_child(rule)

	# No authored workflow uses `confirm` yet — game content is still scaffolding. This drives
	# the real path anyway (orchestrator → executor → suspension → instance store → resume), so
	# the machinery is verifiable in the running app rather than only in tests.
	_menu_panel.body.add_child(_menu_action("Ask me something (dev)", UiSkin.GRAY,
		func() -> void: await _on_dev_ask()))

	var trace_toggle := CheckButton.new()
	trace_toggle.text = "Show AI trace"
	UiSkin.apply_toggle(trace_toggle)
	trace_toggle.toggled.connect(func(on: bool) -> void: _trace_label.visible = on)
	_menu_panel.body.add_child(trace_toggle)

	_trace_label = RichTextLabel.new()
	_trace_label.bbcode_enabled = false
	_trace_label.fit_content = true
	_trace_label.custom_minimum_size = Vector2(0, 140)
	_trace_label.add_theme_color_override("default_color", UiSkin.INK)
	_trace_label.add_theme_font_size_override("normal_font_size", UiSkin.FONT_SMALL)
	_trace_label.visible = false
	_menu_panel.body.add_child(_trace_label)


func _menu_action(text: String, variant: UiSkin.Variant, on_pressed: Callable) -> SkinnedButton:
	var button := SkinnedButton.create(text, variant, UiSkin.CONTROL_HEIGHT,
		UiSkin.CONTROL_FONT_SIZE)
	button.pressed.connect(on_pressed)
	return button


func _open_main_menu() -> void:
	_refresh_slots()
	_shell.show_page(_menu_panel)


## The shell only knows how to place destination actions. What those actions are comes from modules
## through HudPanelRegistry, in the same registration pass that contributes screens and commands.
func _build_destination_actions() -> void:
	for id: String in Kernel.hud_panels.page_ids():
		var definition: Dictionary = Kernel.hud_panels.definition(id)
		var label := String(definition.get("label", id))
		if id == MAP_LAYERS_PAGE_ID:
			_shell.add_map_layers_action(label, _open_destination.bind(id))
			_build_map_layer_toggles()
		else:
			_shell.add_rail_action(label, _open_destination.bind(id),
				definition.get("icon") as Texture2D)


func _open_destination(id: String) -> void:
	if id == MAIN_MENU_PAGE_ID:
		_open_main_menu()
		return
	var panel: HudPanel = _destination_panels.get(id, null) as HudPanel
	if panel == null:
		var definition: Dictionary = Kernel.hud_panels.definition(id)
		panel = HudPanel.new()
		panel.visible = false
		add_child(panel)
		panel.set_meta("hud_page_id", id)
		panel.set_title(String(definition.get("title", id.capitalize())))
		Kernel.hud_panels.build(id, panel, Kernel)
		if id == MAP_LAYERS_PAGE_ID:
			_wire_map_layer_toggles(panel)
		_destination_panels[id] = panel
	Kernel.hud_panels.refresh(id, panel, Kernel)
	if id == MAP_LAYERS_PAGE_ID:
		_sync_map_layer_toggles(panel)
	_shell.show_page(panel)


## The layers the desktop shortcut's flyout offers. **The two coordinate overlays are one layer
## here**: the subgrid is the tile grid's own subdivision, and a plate that showed the fine lines
## while the tiles they divide were off would be offering a state nobody wants. The page keeps them
## separate because a page has room to explain the difference; a plate does not.
##
## **Terrain is a view, not a layer of its own.** The ground is always drawn — it is the surface
## everything else stands on, so there is nothing coherent for a plate that hid it to leave behind.
## What the plate does instead is strip the map back *to* the ground: latched, it takes away the
## constructions and the units together, which is the one arrangement that answers "show me the land
## itself". It is registered last because the column reads as a stack, with the ground at its foot.
func _build_map_layer_toggles() -> void:
	var grids_on := _map_view != null and _map_view.is_tile_grid_visible()
	_grid_layer_plate = _shell.add_map_layers_toggle("Grid", UiSkin.MAP_LAYER_GRID_TEXTURE,
		UiSkin.MAP_LAYER_GRID_SELECTED_TEXTURE, _set_map_grids_visible, grids_on)
	# Unlatched by default: the map opens as the world, with everything on it, and stripping it back
	# is the thing the player asks for.
	_terrain_layer_plate = _shell.add_map_layers_toggle("Terrain",
		UiSkin.MAP_LAYER_TERRAIN_TEXTURE, UiSkin.MAP_LAYER_TERRAIN_SELECTED_TEXTURE,
		_set_terrain_only, false)


## Strip the map back to bare ground, or put the world back on it.
##
## Both layers move together because that is what "terrain only" means; they are separate flags on
## the view so that a later plate can turn units off on their own without this one being in the way.
func _set_terrain_only(only: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_construction_layer_visible(not only)
	_map_view.set_units_layer_visible(not only)
	# A selected farm that is no longer drawn would leave an outline round what now looks like plain
	# grass. Bare ground survives — it is still there, and still what the outline encloses.
	if only and _selection_kind == BaseGameMap.KIND_CONSTRUCTION:
		_clear_selection()


func _set_map_grids_visible(shown: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_tile_grid_visible(shown)
	_map_view.set_subgrid_visible(shown)


func _wire_map_layer_toggles(panel: HudPanel) -> void:
	if _map_view == null:
		return
	var tile_grid := panel.find_child(BaseGameMap.TILE_GRID_TOGGLE_NAME, true, false) as CheckButton
	var subgrid := panel.find_child(BaseGameMap.SUBGRID_TOGGLE_NAME, true, false) as CheckButton
	var terrain_only := panel.find_child(BaseGameMap.TERRAIN_ONLY_TOGGLE_NAME, true,
		false) as CheckButton
	if tile_grid != null:
		tile_grid.toggled.connect(func(value: bool) -> void:
			_map_view.set_tile_grid_visible(value)
			_restate_grid_plate())
	if subgrid != null:
		subgrid.toggled.connect(_map_view.set_subgrid_visible)
	if terrain_only != null:
		terrain_only.toggled.connect(func(value: bool) -> void:
			_set_terrain_only(value)
			_restate_terrain_plate())


## Two controls reach the same overlays — the phone's page and the desktop shortcut's flyout — so
## neither may state the map's condition from memory. The page is re-read from the map view each time
## it is opened, which is the only moment it can have gone stale; the plate is re-stated the moment
## the page changes anything, because it is on screen behind the page rather than rebuilt on sight.
func _sync_map_layer_toggles(panel: HudPanel) -> void:
	if _map_view == null:
		return
	var tile_grid := panel.find_child(BaseGameMap.TILE_GRID_TOGGLE_NAME, true, false) as CheckButton
	var subgrid := panel.find_child(BaseGameMap.SUBGRID_TOGGLE_NAME, true, false) as CheckButton
	var terrain_only := panel.find_child(BaseGameMap.TERRAIN_ONLY_TOGGLE_NAME, true,
		false) as CheckButton
	if tile_grid != null:
		tile_grid.set_pressed_no_signal(_map_view.is_tile_grid_visible())
	if subgrid != null:
		subgrid.set_pressed_no_signal(_map_view.is_subgrid_visible())
	if terrain_only != null:
		# The page's row is the plate's own question asked the other way round: the plate latches to
		# strip the map back, and the map reports what it is drawing.
		terrain_only.set_pressed_no_signal(not _map_view.is_construction_layer_visible())


func _restate_grid_plate() -> void:
	if _grid_layer_plate != null and _map_view != null:
		_grid_layer_plate.button.set_pressed_no_signal(_map_view.is_tile_grid_visible())


func _restate_terrain_plate() -> void:
	if _terrain_layer_plate != null and _map_view != null:
		_terrain_layer_plate.button.set_pressed_no_signal(
			not _map_view.is_construction_layer_visible())


## The typed source's submit path: a real backend turn takes 0.85-4 s (D22), so input
## locks here and unlocks when the turn's completion event arrives — no frame blocking.
func _on_submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or Kernel.ai_orchestrator.is_busy():
		return
	_append("[color=aqua]You:[/color] %s" % message)
	_say("You", message)
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
		_say("You", String(payload.get("text", "")))
	_render_turn(payload.get("result", {}))
	_set_busy(false)


## Render whatever a turn produced — a completed one, or one that stopped to ask.
func _render_turn(result: Dictionary) -> void:
	_append("[color=wheat]Game master:[/color] %s" % result.get("narrative", ""))
	# The applied commands go to the log only: `(applied: grant_resource)` sat in the conversation
	# reading like something the game master had said.
	var applied: Array = result.get("applied_commands", [])
	if not applied.is_empty():
		_append("[i](applied: %s)[/i]" % ", ".join(PackedStringArray(applied)))

	var trace: AiTrace = result.get("trace")
	if trace != null:
		_trace_label.text = trace.to_text()
	_say("King", String(result.get("narrative", "")), trace)
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
	# **Only while the conversation is already open.** Focus is what opens the board now, so putting
	# the caret in the field unasked opened it — including on the way in, which meant a new game began
	# with the chronicle covering the map the player had just chosen a site on. Between turns, with
	# the board open, keeping the caret ready is still exactly right.
	if not blocked and _shell.is_chat_expanded():
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
	_append("[color=#95560d]Game master asks:[/color] %s" % _pending_label.text)
	_say("King", _pending_label.text)
	_set_busy(false)  # re-evaluates the lock now that a question is pending


func _answer(confirmed: bool) -> void:
	if _pending_instance.is_empty():
		return
	var instance_id := _pending_instance
	# Cleared before resuming, not after: resuming is itself a turn that can ask a *new*
	# question, and that answer must not be overwritten by this one finishing.
	_clear_question()
	_append("[color=aqua]You:[/color] %s" % ("Yes" if confirmed else "No"))
	_say("You", "Yes" if confirmed else "No")
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
		_append("[color=#8c2f2f]System:[/color] dev_confirm is not registered (release build?).")
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
		_append("[color=#8c2f2f]System:[/color] Could not load (%s)." % loaded["error"])
		return
	_clear_question()
	_append("[i]— Loaded '%s', day %d —[/i]" % [Kernel.session.slot_name, Kernel.clock.total_days])
	_refresh_outpost()
	_refresh_day()
	_refresh_resources()
	_refresh_map_marker()
	# A loaded world brings its own roads, and drops the ones the previous one had.
	_refresh_roads()
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
	# A new settlement starts on unbuilt ground.
	_refresh_roads()
	_set_busy(false)


func _on_save() -> void:
	var result: Dictionary = Kernel.session.snapshot("manual")
	if bool(result["ok"]):
		_append("[color=#5d4f42]Saved '%s'.[/color]" % Kernel.session.slot_name)
		_refresh_slots()
	else:
		_append("[color=#8c2f2f]System:[/color] Could not save (%s)." % result["error"])


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
		var button: SkinnedButton = _speed_buttons[speed]
		button.button.set_pressed_no_signal(int(speed) == current)


## The mobile wireframe keeps only the fastest speed in the constrained top bar. Pause and exact
## speed selection remain available through their rebindable keys; desktop keeps all four buttons.
func _on_shell_breakpoint_changed(_is_mobile: bool) -> void:
	_sync_speed_layout()


func _sync_speed_layout() -> void:
	var mobile := _shell.size.x < HudShell.MOBILE_BREAKPOINT_WIDTH
	# Derived from the slot the readouts actually occupy rather than a number kept in step by hand:
	# adding score changed how wide this group is, and a literal here would have gone on reserving
	# room for two.
	# The gaps *between* the bar's clusters are the cheapest room a phone has: six of them at the
	# desktop's spacing is nearly a hundred units of a 720-wide row, spent on air rather than on
	# anything that says something.
	_shell.top_bar.add_theme_constant_override("separation", 8 if mobile else 16)
	var slot := TOP_BAR_RESOURCE_SLOT_WIDTH_MOBILE if mobile else TOP_BAR_RESOURCE_SLOT_WIDTH
	var count := float(_resource_icons.size())
	_resources_host.custom_minimum_size.x = (slot * count
		+ TOP_BAR_RESOURCE_SEPARATION * maxf(0.0, count - 1.0))
	var icon_size := (UiSkin.TOP_BAR_ICON_SIZE_MOBILE if mobile else UiSkin.TOP_BAR_ICON_SIZE)
	for icon: TextureRect in _resource_icons:
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.texture = UiSkin.top_bar_icon(icon.get_meta("source") as Texture2D, icon_size)
	var values_width := (TOP_BAR_RESOURCE_VALUES_WIDTH_MOBILE if mobile
		else TOP_BAR_RESOURCE_VALUES_WIDTH)
	for item: Control in _resources_host.get_child(0).get_children():
		item.custom_minimum_size.x = slot
		# The figures are laid out by hand inside their own box rather than by a container, so the
		# box narrowing is not enough on its own — each label has to be told as well.
		var values := item.get_node("values") as Control
		values.custom_minimum_size.x = values_width
		for label: Control in values.get_children():
			label.size.x = values_width
	_speed_host.custom_minimum_size.x = (UiSkin.SPEED_BUTTON_SIZE if mobile
		else UiSkin.SPEED_BUTTON_SIZE * 4 + SPEED_BUTTON_SEPARATION * 3)
	for speed: Variant in _speed_buttons:
		_speed_buttons[speed].visible = not mobile or int(speed) == TimeDriver.Speed.SPEED_3
	# **The bar is the one strip that cannot re-flow.** A page wraps and a card pager drops to one
	# card, but the top bar is a single row by definition, so on a phone it is the type size that
	# gives. At the desktop size this row wants about 870 units of a 720-wide screen, and a Godot
	# container does not clip: the overflow pushed the date and the speed control clean off the
	# right-hand edge, and the panels below inherited the same too-wide row.
	var size := UiSkin.FONT_SMALL if mobile else UiSkin.FONT_BODY
	# The settlement's name is drawn by hand inside a fixed 150-unit box and a [Label] does not clip,
	# so at the desktop size a name of any length simply runs on past it. That was invisible while the
	# bar had room to its right; with a third readout there it ran into the coins. The name is the one
	# thing on this row that cannot be shortened, so it is the size that gives instead.
	_outpost_label.add_theme_font_size_override("font_size", size)
	_date_label.add_theme_font_size_override("font_size", size)
	var resource_value_size := UiSkin.FONT_SMALL + 4 if mobile else TOP_BAR_RESOURCE_VALUE_FONT_SIZE
	for label: Label in [_gold_label, _population_label, _score_label]:
		label.add_theme_font_size_override("font_size", resource_value_size)
	for label: Label in [_gold_increment_label, _population_increment_label,
			_score_increment_label]:
		label.add_theme_font_size_override("font_size", TOP_BAR_RESOURCE_INCREMENT_FONT_SIZE)
	# The tier is the first thing off a phone's bar. It stood under the name until the bar was
	# shortened and the two went side by side, which is what tipped the row over 720 again — and it is
	# a placeholder tier (ux_plan.md §5) reading "Outpost" beside a settlement that says as much.
	_tier_label.add_theme_font_size_override("font_size", TOP_BAR_RANK_FONT_SIZE)
	_tier_label.visible = true
	_refresh_resources()
	# The group's width has just changed, so where its centre falls has too. Deferred: the container
	# has not laid the new minimums out yet, and this measures the result rather than predicting it.
	_centre_status_group.call_deferred()


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
	_append("[color=#5d4f42]Chronicle:[/color] %s%s" % [msg, suffix])


func _on_ai_availability_changed(payload: Dictionary) -> void:
	var state := String(payload.get("state", ""))
	var attempt := int(payload.get("attempt", 0))
	match state:
		"recovering":
			if attempt == 0:
				_append("[color=#8c2f2f]System:[/color] Game master connection lost — attempting to recover.")
			else:
				_append("[color=#8c2f2f]System:[/color] Reconnecting (attempt %d/%d)…" % [attempt, AiAvailability.MAX_ATTEMPTS])
			_retry_button.visible = false
		"unavailable":
			_append("[color=#8c2f2f]System:[/color] The game master is unavailable. Press Retry to reconnect.")
			_retry_button.visible = true
		"available":
			if int(payload.get("attempts_used", 0)) > 0:
				_append("[color=#8c2f2f]System:[/color] Game master connection restored.")
			_retry_button.visible = false


## The settlement's identity in the header: its banner and its name. Both come from state, so a
## loaded game shows its own outpost rather than the one that was on screen a moment ago.
func _refresh_outpost() -> void:
	var stored: Dictionary = Kernel.state.get_value(GameSession.OUTPOST_FLAG_STATE_KEY, {})
	# A game seeded before the wizard existed has no flag; the default is a real flag, not a hole,
	# so there is nothing to hide here.
	var flag := FlagValue.from_dict(stored)
	_flag_view.set_value(flag)
	var outpost: Dictionary = Entities.get_entity(Kernel.state, "outpost")
	_outpost_label.text = String(outpost.get("name", "The Outpost"))


func _refresh_day() -> void:
	_date_label.text = DateFormat.render(Kernel.clock)


## Coins and population, each with the placeholder "+0" delta ux_plan.md §5 asks for rather than a
## number nothing computes yet. Neutral-coloured on purpose — green/red would claim a real signal.
func _refresh_resources() -> void:
	var resources: Dictionary = Kernel.state.get_value("resources", {})
	# The icon says which number this is, so the label is the number. The placeholder "+0" delta
	# ux_plan.md §5 asks for goes beside it on a screen wide enough to hold one.
	var gold := int(resources.get("gold", 0))
	var population := int(resources.get("population", 0))
	# Score is read the same way as the other two, so the day something writes it the bar shows it
	# without another edit here. Nothing does yet, which is why it reads zero rather than a number
	# invented to fill the slot.
	var score := int(resources.get("score", 0))
	_gold_label.text = "%d" % gold
	_gold_increment_label.text = "+0"
	_population_label.text = "%d" % population
	_population_increment_label.text = "+0"
	_score_label.text = "%d" % score
	_score_increment_label.text = "+0"


func _append(bbcode: String) -> void:
	_log_label.append_text(bbcode + "\n")


## Say something *in* the conversation — the narrow door, which a caller has to mean to walk through.
##
## **[method _append] no longer opens it.** It used to add a "Chronicle" row for anything that was
## not a player or game-master turn, so the conversation filled with the day ticker, save
## confirmations and connection notices — bookkeeping, in the middle of the fiction. The conversation
## is for what is said and what happens to the player: their own lines, the game master's, and
## events. Everything else still reaches the hidden log, so nothing is lost and the integration tests
## still read it; anything that deserves to be *seen* wants a place of its own rather than a seat
## here.
func _say(speaker: String, text: String, trace: AiTrace = null) -> void:
	if _message_list != null:
		_message_list.add_message(speaker, text, trace)
