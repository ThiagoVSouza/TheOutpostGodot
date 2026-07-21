extends SceneTree

## D17 measurement harness: is AI difficulty classification stable across phrasings and input
## languages? This is the +17/+20/+15 test (D4) repeated on the new grammar-constrained design —
## the number that says whether the difficulty enum can be trusted enough to drive workflows.
##
## For each action we ask the model to pick low|medium|hard (grammar-constrained, temperature 0)
## for several phrasings in English, Portuguese and Spanish, and record every verdict. Stability
## is: does the *same action* get the *same label* regardless of how it was said or in what
## language (D29 says the model reasons in English; this measures whether that holds)?
##
## Run one model at a time (D17 method): set the profile, then:
##   OUTPOST_AI_BACKEND=local-llama OUTPOST_MODEL_PROFILE=<profile> \
##     godot --headless --path . -s res://tools/measure_classification.gd
## Output is TSV (action, expected, lang, verdict, phrasing) to stdout for tabulation.

const DIFFICULTY := ["low", "medium", "hard"]

const SYSTEM := "You judge how hard an action is for a small settlement's people to accomplish, " \
	+ "given only the action described. Consider distance, danger, and whether it is defended. " \
	+ "Answer with exactly one label: low, medium, or hard. Reason in English regardless of the " \
	+ "language the action is written in."

## Actions spanning the difficulty range, each phrased two ways in en / pt / es.
const CASES := [
	{
		"id": "gather_nearby", "expect": "low",
		"en": ["I gather berries from the bushes beside camp", "pick fruit from the trees just outside the walls"],
		"pt": ["Colho frutas dos arbustos ao lado do acampamento", "pegar frutas das árvores logo fora das muralhas"],
		"es": ["Recojo bayas de los arbustos junto al campamento", "tomar fruta de los árboles justo fuera de las murallas"],
	},
	{
		"id": "forage_far", "expect": "medium",
		"en": ["I forage the distant hills for food", "send scouts across the far valley to find provisions"],
		"pt": ["Procuro comida nas colinas distantes", "enviar batedores pelo vale distante para achar provisões"],
		"es": ["Busco comida en las colinas lejanas", "enviar exploradores por el valle lejano a buscar provisiones"],
	},
	{
		"id": "raid_granary", "expect": "hard",
		"en": ["I raid the guarded granary inside the enemy fortress", "storm the fortified storehouse held by armed soldiers"],
		"pt": ["Ataco o celeiro guardado dentro da fortaleza inimiga", "invadir o armazém fortificado defendido por soldados armados"],
		"es": ["Asalto el granero custodiado dentro de la fortaleza enemiga", "irrumpir en el almacén fortificado defendido por soldados armados"],
	},
]


func _init() -> void:
	var kernel := GameKernel.new()
	root.add_child(kernel)
	kernel.boot()
	var profile := OS.get_environment("OUTPOST_MODEL_PROFILE")
	print("=== D17 difficulty classification === backend=%s profile=%s ===" % [kernel.ai.backend_id(), profile])

	for _i in range(120):
		if kernel.ai.is_ready():
			break
		await create_timer(1.0).timeout
	if not kernel.ai.is_ready():
		print("!! server not ready after wait — aborting")
		quit()
		return

	print("action\texpect\tlang\tverdict\tphrasing")
	for case_v in CASES:
		var case: Dictionary = case_v
		for lang in ["en", "pt", "es"]:
			for phrasing in case[lang]:
				var verdict := await _classify(kernel, String(phrasing))
				print("%s\t%s\t%s\t%s\t%s" % [case["id"], case["expect"], lang, verdict, phrasing])
	print("=== done ===")
	quit()


func _classify(kernel: GameKernel, phrasing: String) -> String:
	var request := {
		"messages": [
			{"role": "system", "content": SYSTEM},
			{"role": "user", "content": "Action: %s\nDifficulty:" % phrasing},
		],
		"grammar": LlamaAiRunner.gbnf_for_options(PackedStringArray(DIFFICULTY)),
		"temperature": 0.0,
		"max_tokens": 4,
	}
	var out: Dictionary = await LlamaAiCall.run(kernel, request, 20.0)
	return String(out.get("content", "")).strip_edges() if bool(out.get("ok", false)) else "ERROR"
