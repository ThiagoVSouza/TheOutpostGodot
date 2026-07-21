class_name DslNarrator
extends RefCounted

## The seam the `narrate` op speaks to (A5, D4 amendment #3): turns the decided facts of a
## turn into bounded, player-facing prose. Its inputs are deliberately fixed — an
## **instruction** (what to narrate), the **context** it may draw on, a **verbosity** level,
## and an **output language** (D29) — so that raising verbosity *decorates* the outcome
## rather than inventing new facts. The narrator never adjudicates: every number it is handed
## was already decided by code (D4).
##
## Synchronous for now. Wiring the real [AiBackend] behind this makes narration an in-memory
## await (D30) and turns the executor into a coroutine — that lands with the M3b orchestration,
## where there is an actual turn to narrate. [FakeNarrator] keeps A5 deterministic and testable.
func narrate(_instruction: String, _context: Dictionary, _verbosity: String, _language: String) -> String:
	return ""
