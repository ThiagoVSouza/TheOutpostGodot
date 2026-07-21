class_name PromptFamilyRegistry
extends RefCounted

## The prompt families the `ai` op may invoke (§8): workflows name a registered family and get
## back a grammar-constrained value — they never make a free-form model call. Components
## register families here; the DSL can never invent one (the validator forbids a computed
## `ai.family`). Mirrors the fn/table registries.

var _families: Dictionary = {}  # id -> PromptFamily


func register(family: PromptFamily) -> void:
	_families[family.id] = family


func has(family_id: String) -> bool:
	return _families.has(family_id)


func get_family(family_id: String) -> PromptFamily:
	return _families.get(family_id, null)
