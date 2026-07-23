extends SceneTree

## Classification-stability measurement harness (D17). Two families live here, picked by
## OUTPOST_MEASURE (default `difficulty`):
##
##   difficulty — the original +17/+20/+15 test (D4): does the same action get the same
##     low|medium|hard label regardless of phrasing or input language?
##
##   plan_tick — the M5 question (added 2026-07-23): does a background plan advance the same
##     way regardless of how its latest development is worded? A plan tick feeds the model the
##     plan's own structured fields (what it is, its current direction) plus a narrative of the
##     latest event, and asks it to pick one transition from a closed set. We hold the structured
##     fields CONSTANT and vary only the narrative wording across phrasings and languages — the
##     narrative is the part a real tick draws from retrieved memory, so it is the part whose
##     stability actually matters. Run this BEFORE the plan format is designed (plan.md M5): an
##     unmeasured guess here is the +17/+20/+15 mistake one level up.
##
## Both mirror the shipped prompt shape (LlamaAiRunner): a labels-with-descriptions block (D33 —
## bare labels are not enough), facts as JSON context, grammar-constrained at the sampler (D19),
## temperature 0, reason in English (D29).
##
## Run one model at a time (D17 method):
##   OUTPOST_MEASURE=plan_tick OUTPOST_AI_BACKEND=local-llama OUTPOST_MODEL_PROFILE=<profile> \
##     godot --headless --path . -s res://tools/measure_classification.gd
## Or against a manually-started server (the reliable path, see the skeleton-state memo):
##   OUTPOST_MEASURE=plan_tick OUTPOST_AI_BACKEND=remote-llama \
##     OUTPOST_AI_ENDPOINT=http://127.0.0.1:8099/v1/chat/completions \
##     godot --headless --path . -s res://tools/measure_classification.gd
## Output is TSV (action, expected, lang, verdict, phrasing) to stdout for tabulation.

## --- difficulty family -------------------------------------------------------------------

const DIFFICULTY_OPTIONS := ["low", "medium", "hard"]

const DIFFICULTY_SYSTEM := "You judge how hard an action is for a small settlement's people to " \
	+ "accomplish, given only the action described. Consider distance, danger, and whether it is " \
	+ "defended. Answer with exactly one label: low, medium, or hard. Reason in English regardless " \
	+ "of the language the action is written in."

## Difficulty labels are self-explanatory, so no descriptions block (the D17 result used bare
## labels; D33 matters where a label's meaning is not obvious from its name — see plan_tick).
const DIFFICULTY_DESCRIPTIONS := {}

## Actions spanning the difficulty range, each phrased two ways in en / pt / es.
const DIFFICULTY_CASES := [
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


## --- plan_tick family --------------------------------------------------------------------

const PLAN_TICK_OPTIONS := ["escalate", "hold", "de_escalate", "mutate", "resolve"]

const PLAN_TICK_SYSTEM := "You advance an ongoing situation in a Greco-Roman strategy game by " \
	+ "one step. You are given what the situation is, its current direction, and the latest " \
	+ "development. Answer with exactly one transition label and nothing else. Judge only from " \
	+ "what is described. Reason in English regardless of the language of the development."

## D33: these labels carry no meaning in their names alone — `hold` vs `de_escalate` vs `resolve`
## all look like "nothing much happened" without a definition, and `mutate` is meaningless bare.
const PLAN_TICK_DESCRIPTIONS := {
	"escalate": "the situation intensifies — the actors push harder, raise the stakes, or move toward open conflict",
	"hold": "nothing decisive changed this step; the situation persists roughly as it was",
	"de_escalate": "tension eases — the actors back down, are appeased, or the threat recedes",
	"mutate": "the situation changes character — it becomes a different kind of plot (for example extortion turning into a personal vendetta)",
	"resolve": "the situation reaches an end — settled, concluded, or no longer active",
}

## Each scenario holds its plan and direction fields CONSTANT and varies only the latest
## development across two phrasings in en / pt / es. `expect` is a soft calibration guess, not a
## correctness key (D17: forage_far read `low` vs the guessed `medium` — that was calibration, not
## instability). Drawn from the briefing's examples: the corrupt steward, a brewing revolt, a
## hired raid, a trade bid, a watchful neighbor.
const PLAN_TICK_CASES := [
	{
		"id": "steward_refused", "expect": "escalate",
		"plan": "The King's Steward is pressuring the outpost's lord for bribes in exchange for a favorable progress report.",
		"direction": "The Steward is applying pressure and testing how far he can push.",
		"en": [
			"The lord publicly refused the Steward's demand and mocked him before the court.",
			"The lord turned down the bribe outright and had the Steward escorted from the hall.",
		],
		"pt": [
			"O senhor recusou publicamente a exigência do administrador e zombou dele diante da corte.",
			"O senhor rejeitou o suborno de imediato e mandou escoltar o administrador para fora do salão.",
		],
		"es": [
			"El señor rechazó públicamente la exigencia del administrador y se burló de él ante la corte.",
			"El señor rehusó el soborno de inmediato e hizo escoltar al administrador fuera del salón.",
		],
	},
	{
		"id": "revolt_appeased", "expect": "de_escalate",
		"plan": "Peasants in the outer farms are planning a revolt over high taxes and food shortages.",
		"direction": "Unrest is building toward open protest.",
		"en": [
			"The lord cut the grain tax in half and opened the granary to the hungry families.",
			"Food was distributed to the farms and the harshest tax was suspended.",
		],
		"pt": [
			"O senhor reduziu o imposto do grão pela metade e abriu o celeiro às famílias famintas.",
			"Comida foi distribuída às fazendas e o imposto mais pesado foi suspenso.",
		],
		"es": [
			"El señor redujo a la mitad el impuesto del grano y abrió el granero a las familias hambrientas.",
			"Se repartió comida a las granjas y se suspendió el impuesto más gravoso.",
		],
	},
	{
		"id": "bandits_unopposed", "expect": "escalate",
		"plan": "A bandit company was hired to raid the outpost's trade road.",
		"direction": "The bandits are scouting the road and preparing to strike.",
		"en": [
			"The road is still unguarded and a rich caravan is due to pass at dawn.",
			"No patrols were posted, and the merchants travel the road alone and unprotected.",
		],
		"pt": [
			"A estrada continua sem guarda e uma caravana rica deve passar ao amanhecer.",
			"Nenhuma patrulha foi posicionada, e os mercadores viajam pela estrada sozinhos e desprotegidos.",
		],
		"es": [
			"El camino sigue sin vigilancia y una rica caravana pasará al amanecer.",
			"No se apostaron patrullas, y los mercaderes viajan por el camino solos y sin protección.",
		],
	},
	{
		"id": "trade_signed", "expect": "resolve",
		"plan": "A merchant is seeking to establish a new trade route through the outpost.",
		"direction": "Negotiations are underway over terms and tariffs.",
		"en": [
			"Both parties signed the trade agreement and the first caravan has departed.",
			"The deal was sealed and the route is now formally open.",
		],
		"pt": [
			"As duas partes assinaram o acordo comercial e a primeira caravana já partiu.",
			"O negócio foi fechado e a rota está agora formalmente aberta.",
		],
		"es": [
			"Ambas partes firmaron el acuerdo comercial y la primera caravana ya ha partido.",
			"El trato quedó cerrado y la ruta está ahora formalmente abierta.",
		],
	},
	{
		"id": "neighbor_quiet", "expect": "hold",
		"plan": "A neighboring tribe is weighing whether to deepen ties with the outpost.",
		"direction": "The tribe is cautious and watching how the outpost treats them.",
		"en": [
			"Nothing of note passed between them this season; messengers came and went as usual.",
			"The season was quiet, with only routine trade and no new overtures either way.",
		],
		"pt": [
			"Nada digno de nota se passou entre eles nesta estação; mensageiros iam e vinham como de costume.",
			"A estação foi tranquila, com apenas comércio rotineiro e nenhuma nova aproximação de qualquer lado.",
		],
		"es": [
			"Nada digno de mención ocurrió entre ellos esta temporada; los mensajeros iban y venían como siempre.",
			"La temporada fue tranquila, con solo comercio rutinario y ningún nuevo acercamiento por ninguna parte.",
		],
	},
	{
		"id": "steward_exposed", "expect": "mutate",
		"plan": "The King's Steward is extorting the outpost's lord for bribes.",
		"direction": "The Steward is applying financial pressure for personal gain.",
		"en": [
			"The lord gathered proof of the corruption and threatened to send it to the King; the humiliated Steward now wants revenge.",
			"The scheme was exposed to the court, and the Steward has turned from greed to plotting the lord's ruin.",
		],
		"pt": [
			"O senhor reuniu provas da corrupção e ameaçou enviá-las ao Rei; o administrador humilhado agora quer vingança.",
			"O esquema foi exposto à corte, e o administrador deixou a ganância para tramar a ruína do senhor.",
		],
		"es": [
			"El señor reunió pruebas de la corrupción y amenazó con enviarlas al Rey; el administrador humillado ahora quiere venganza.",
			"La trama quedó expuesta ante la corte, y el administrador pasó de la codicia a maquinar la ruina del señor.",
		],
	},
]


func _init() -> void:
	var kernel := GameKernel.new()
	root.add_child(kernel)
	kernel.boot()

	var mode := OS.get_environment("OUTPOST_MEASURE")
	if mode.is_empty():
		mode = "difficulty"
	var profile := OS.get_environment("OUTPOST_MODEL_PROFILE")
	print("=== D17 %s classification === backend=%s profile=%s ===" % [mode, kernel.ai.backend_id(), profile])

	for _i in range(120):
		if kernel.ai.is_ready():
			break
		await create_timer(1.0).timeout
	if not kernel.ai.is_ready():
		print("!! server not ready after wait — aborting")
		quit()
		return

	match mode:
		"difficulty":
			await _run_difficulty(kernel)
		"plan_tick":
			await _run_plan_tick(kernel)
		_:
			print("!! unknown OUTPOST_MEASURE=%s (want: difficulty | plan_tick)" % mode)
	print("=== done ===")
	quit()


func _run_difficulty(kernel: GameKernel) -> void:
	var options := PackedStringArray(DIFFICULTY_OPTIONS)
	var allowed := _allowed_block(options, DIFFICULTY_DESCRIPTIONS)
	print("action\texpect\tlang\tverdict\tphrasing")
	for case_v in DIFFICULTY_CASES:
		var case: Dictionary = case_v
		for lang in ["en", "pt", "es"]:
			for phrasing_v in case[lang]:
				var phrasing := String(phrasing_v)
				var facts := {"action": phrasing}
				var user := "%s\nContext: %s\nLabel:" % [allowed, JSON.stringify(facts)]
				var verdict := await _classify(kernel, DIFFICULTY_SYSTEM, user, options)
				print("%s\t%s\t%s\t%s\t%s" % [case["id"], case["expect"], lang, verdict, phrasing])


func _run_plan_tick(kernel: GameKernel) -> void:
	var options := PackedStringArray(PLAN_TICK_OPTIONS)
	var allowed := _allowed_block(options, PLAN_TICK_DESCRIPTIONS)
	print("scenario\texpect\tlang\tverdict\tdevelopment")
	for case_v in PLAN_TICK_CASES:
		var case: Dictionary = case_v
		for lang in ["en", "pt", "es"]:
			for development_v in case[lang]:
				var development := String(development_v)
				# Structured fields held constant; only `development` varies across lang/phrasing.
				var facts := {
					"situation": case["plan"],
					"current_direction": case["direction"],
					"latest_development": development,
				}
				var user := "%s\nContext: %s\nTransition:" % [allowed, JSON.stringify(facts)]
				var verdict := await _classify(kernel, PLAN_TICK_SYSTEM, user, options)
				print("%s\t%s\t%s\t%s\t%s" % [case["id"], case["expect"], lang, verdict, development])


func _classify(kernel: GameKernel, system: String, user: String, options: PackedStringArray) -> String:
	var request := {
		"messages": [
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		],
		"grammar": LlamaAiRunner.gbnf_for_options(options),
		"temperature": 0.0,
		"max_tokens": 8,
	}
	var out: Dictionary = await LlamaAiCall.run(kernel, request, 20.0)
	return String(out.get("content", "")).strip_edges() if bool(out.get("ok", false)) else "ERROR"


## Mirror of LlamaAiRunner._allowed_block so the measured prompt matches the shipped one (D33).
func _allowed_block(options: PackedStringArray, descriptions: Dictionary) -> String:
	if descriptions.is_empty():
		return "Allowed labels: %s" % ", ".join(Array(options))
	var lines: Array = ["Allowed labels:"]
	for option in options:
		var described := String(descriptions.get(option, ""))
		lines.append("- %s: %s" % [option, described] if not described.is_empty() else "- %s" % option)
	return "\n".join(lines)
