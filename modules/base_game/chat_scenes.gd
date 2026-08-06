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

## How many figures each step of the dev cycle puts on the stage — none, one on the right, then a pair
## facing each other. One first, because a single portrait is where a wrong anchor or a shadow drawn
## the wrong side of the figure is easiest to see.
const CHARACTER_STEPS := [0, 1, 2]


static func count() -> int:
	return SCENES.size()


## The figures on stage for [param step] of [constant CHARACTER_STEPS], as [ChatScene] takes them.
## `side` is +1 for the right of the band and -1 for the left; the left one is the mirror.
static func characters(step: int) -> Array:
	var staged: Array = []
	var wanted := int(CHARACTER_STEPS[clampi(step, 0, CHARACTER_STEPS.size() - 1)])
	for side: int in [1, -1]:
		if staged.size() >= wanted:
			break
		staged.append({
			"texture": CHARACTER_BASE,
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
