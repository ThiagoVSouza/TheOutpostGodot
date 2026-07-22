class_name PromptFamily
extends RefCounted

## A registered classification family (§8, D30): a bounded question the model answers by
## picking **one** value from a closed [member options] set. The set is grammar-constrained at
## the sampler (D19), so an out-of-set answer is unsampleable, not merely rejected. This is how
## the AI participates without adjudicating — it proposes from a fixed set, code owns what the
## verdict maps onto (D4).
##
## For now a family is its id and its option set; the prompt template and the facts→prompt
## assembly live here too once the real `AiBackend` is wired behind the runner (a follow-up,
## mirroring the narrator). Kept a plain object so families can be defined in code or data.

var id: String
var options: PackedStringArray

## Optional one-line meaning per label, `label -> description`. The grammar constrains *what*
## the model may answer but says nothing about what the labels mean, so a bare set leaves the
## model guessing from the words themselves — and a catch-all named `general` carries no hint
## that it is the "nothing mechanical happens here" bucket, so the model reaches for a
## plausible action instead of declining. Authored content, like the option set itself.
var descriptions: Dictionary = {}


func _init(family_id: String, family_options: PackedStringArray = PackedStringArray(),
		option_descriptions: Dictionary = {}) -> void:
	id = family_id
	options = family_options
	descriptions = option_descriptions
