class_name ChatScenes
extends RefCounted

## **The painted scenes the conversation can show, and what stands in each.**
##
## The catalogue only — [ChatScene] draws them and never learns that a throne room exists, the same
## division the map keeps between its renderer and `map_content.gd`.

## Where the floor is in a given painting, as a fraction of its height: the line a character's feet
## land on. Per scene rather than a constant, because an interior seen from the doorway puts its floor
## well up the frame while a courtyard puts it at the very bottom.
##
## The throne room's flagstones run out to the bottom edge, so its line is nearly one — the little that
## is left keeps a character's feet off the very last row of pixels, where the frame's rule begins.
const SCENES: Array[Dictionary] = [
	{
		"id": "throne_room",
		"title": "The throne room",
		"background": preload("res://core/assets/ui/chat_backgrounds/throne_room.png"),
		"floor": 0.97,
	},
]


## **The base figure every character is built from** — hair, face and clothes stack on top of it later.
##
## `content` is where the figure sits on the canvas, measured off the file. **The canvas cannot be
## trimmed to it**: layers have to share one canvas or a hat would not land on a head, so the file's
## size is an alignment grid and the box below is the part of it that is a person. [ChatScene] places
## and sizes the figure, never the canvas.
##
## The figure faces its own right, which is the viewer's left — so it needs no mirroring on the
## **right** of the band, where it looks inward across the room, and is mirrored on the left.
const CHARACTER_BASE := preload("res://core/assets/ui/chat_characters/character_base1.png")
const CHARACTER_BASE_CONTENT := Rect2(63, 55, 368, 502)

## **Age is a different base painting, not a tint.** Lines round the eyes and a slackening jaw are not
## something a colour can do, so each is painted whole — on the same canvas and to the same content
## box, so a hairstyle sits on any of the three heads without knowing which one it is.
##
## Every other choice composes over whichever of these is picked: the skin tone tints it, and the hair
## stacks on top of it.
## **Each age is painted twice**, at two exposures. The remap normalises whichever it is given, so the
## pair are not two brightnesses of the same result — a body painted with its midtones high sits high
## in its own range too, and comes out lighter for the same tone. That is what the pale end of the
## range needed and what a single body could not reach.
const AGES: Array[Dictionary] = [
	{
		"id": "young", "label": "Young",
		"texture": CHARACTER_BASE,
		"light": preload("res://core/assets/ui/chat_characters/character_base1_light.png"),
	},
	{
		"id": "adult",
		"label": "Adult",
		"texture": preload("res://core/assets/ui/chat_characters/character_base1_adult.png"),
		"light": preload("res://core/assets/ui/chat_characters/character_base1_adult_light.png"),
	},
	{
		"id": "old",
		"label": "Old",
		"texture": preload("res://core/assets/ui/chat_characters/character_base1_old.png"),
		"light": preload("res://core/assets/ui/chat_characters/character_base1_old_light.png"),
	},
]
const DEFAULT_AGE := 0

## Hair is authored on the base figure's complete 472 x 557 alignment canvas. Never trim these: the
## empty pixels are what put each style on the same head after scaling and mirroring.
const HAIR_STYLES: Array[Dictionary] = [
	{
		"id": "long",
		"label": "Long",
		"texture": preload("res://core/assets/ui/chat_characters/hair/hair1.png"),
	},
	{
		"id": "crop",
		"label": "Crop",
		"texture": preload("res://core/assets/ui/chat_characters/hair/hair2.png"),
	},
	{
		"id": "shaved",
		"label": "Shaved",
		"texture": preload("res://core/assets/ui/chat_characters/hair/hair3.png"),
	},
]

## Multiplicative tints preserve the grayscale highlights and shadows in the authored hair.
const HAIR_COLORS: Array[Dictionary] = [
	{"id": "black", "label": "Black", "color": Color("39302f")},
	{"id": "brown", "label": "Brown", "color": Color("965b38")},
	{"id": "auburn", "label": "Auburn", "color": Color("a7432b")},
	{"id": "blond", "label": "Blond", "color": Color("f1c875")},
	{"id": "gray", "label": "Gray", "color": Color("aeb2b9")},
]
const DEFAULT_HAIR_STYLE := 0
const DEFAULT_HAIR_COLOR := 1

## **Skin is recoloured by remapping its range, not by tinting it down.** Each tone is the colour its
## deepest shadow and its brightest highlight should be; everything between is the painting's own
## shading carried across. `core/ui/theme/skin_tone.gdshader` does the work and explains why.
##
## The multiply this replaced scaled contrast by the same factor as brightness, so the darkest tone
## kept only 44% of the skin's tonal range and its brightest highlight came out at 83 of 255 — dark
## skin without the sheen that makes it read as skin. Given the two ends separately, a deep tone can
## have a *wider* range than the original, which is what it needs.
##
## **A tone also chooses which of the two bodies it is painted from** (`light_body`). The pale end
## takes the lighter painting, whose midtones sit high in its own range and therefore land near the
## highlight after the remap; everything from olive down takes the original, whose midtones sit in the
## middle where a mid or deep tone wants them.
##
## The pairs below get deeper and warmer together, and their highlights stay bright on purpose: a
## specular is light on any skin, and it is the first thing a multiply takes away.
##
## **The saturation lives in the shadows, not the highlights.** A highlight is close to the colour of
## the light falling on it whatever the skin, so a strongly coloured one reads as orange plastic; the
## warmth belongs at the dark end, where subsurface scattering actually puts it. The first attempt had
## it the other way round and every tone came out the same orange.
const SKIN_TONES: Array[Dictionary] = [
	{
		"id": "fair", "label": "Fair", "light_body": true,
		"shadow": Color(0.55, 0.42, 0.39), "highlight": Color(1.00, 0.97, 0.95),
	},
	{
		"id": "light", "label": "Light", "light_body": true,
		"shadow": Color(0.46, 0.33, 0.29), "highlight": Color(1.00, 0.93, 0.88),
	},
	{
		"id": "olive", "label": "Olive",
		"shadow": Color(0.34, 0.24, 0.18), "highlight": Color(0.93, 0.84, 0.73),
	},
	{
		"id": "tan", "label": "Tan",
		"shadow": Color(0.29, 0.19, 0.15), "highlight": Color(0.86, 0.75, 0.62),
	},
	{
		"id": "brown", "label": "Brown",
		"shadow": Color(0.22, 0.14, 0.11), "highlight": Color(0.75, 0.62, 0.50),
	},
	{
		"id": "deep", "label": "Deep",
		"shadow": Color(0.15, 0.10, 0.08), "highlight": Color(0.63, 0.50, 0.40),
	},
]
const DEFAULT_SKIN_TONE := 1

## Where the painting's own skin sits between its shadow and its highlight — the median, measured off
## the file. What a swatch should show, and the one point of the ramp that stands for the whole tone.
const SKIN_SWATCH_LEVEL := 0.68


## The colour a swatch should show for [param index]: the tone's own ramp at the level the painting's
## skin actually sits at. Taking either end instead would offer the player a shadow or a specular
## rather than a complexion.
static func skin_swatch(index: int) -> Color:
	var tone := SKIN_TONES[clampi(index, 0, SKIN_TONES.size() - 1)]
	return (tone["shadow"] as Color).lerp(tone["highlight"] as Color, SKIN_SWATCH_LEVEL)

## How many figures each step of the dev cycle puts on the stage — none, one on the right, then a pair
## facing each other. One first, because a single portrait is where a wrong anchor or a shadow drawn
## the wrong side of the figure is easiest to see.
const CHARACTER_STEPS := [0, 1, 2]


static func count() -> int:
	return SCENES.size()


## The figures on stage for [param step] of [constant CHARACTER_STEPS], as [ChatScene] takes them.
## `side` is +1 for the right of the band and -1 for the left; the left one is the mirror.
static func characters(step: int, hair_style: int = DEFAULT_HAIR_STYLE,
		hair_color: int = DEFAULT_HAIR_COLOR, skin_tone: int = DEFAULT_SKIN_TONE,
		age: int = DEFAULT_AGE) -> Array:
	var staged: Array = []
	var wanted := int(CHARACTER_STEPS[clampi(step, 0, CHARACTER_STEPS.size() - 1)])
	var hair := HAIR_STYLES[clampi(hair_style, 0, HAIR_STYLES.size() - 1)]["texture"] as Texture2D
	var tint := HAIR_COLORS[clampi(hair_color, 0, HAIR_COLORS.size() - 1)]["color"] as Color
	var skin := SKIN_TONES[clampi(skin_tone, 0, SKIN_TONES.size() - 1)]
	var chosen_age: Dictionary = AGES[clampi(age, 0, AGES.size() - 1)]
	var body := chosen_age[("light" if bool(skin.get("light_body", false)) else "texture")] as Texture2D
	for side: int in [1, -1]:
		if staged.size() >= wanted:
			break
		staged.append({
			"layers": [
				{"texture": body, "tone": {"shadow": skin["shadow"], "highlight": skin["highlight"]}},
				{"texture": hair, "tint": tint},
			],
			# Every age is painted on the one canvas, so this is a fact about the *set* rather than
			# about whichever body was picked.
			"canvas": CHARACTER_BASE.get_size(),
			"content": CHARACTER_BASE_CONTENT,
			"side": side,
		})
	return staged


## The scene under [param id], or an empty dictionary — which is also what "no scene" is, so a caller
## can pass the result straight on without asking whether it found anything.
static func scene(id: String) -> Dictionary:
	for entry: Dictionary in SCENES:
		if String(entry["id"]) == id:
			return entry
	return {}


## The scene at [param index] in catalogue order, or an empty dictionary for **anything out of range**
## — which is how "none" is expressed. [method next] walks off the end deliberately.
static func at(index: int) -> Dictionary:
	if index < 0 or index >= SCENES.size():
		return {}
	return SCENES[index]


## The next scene in the cycle a dev key walks: every scene in order, then none, then round again.
## Returns an index for [method at], where anything outside the catalogue means no scene.
static func next(index: int) -> int:
	var following := index + 1
	return following if following < SCENES.size() else -1
