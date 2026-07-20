class_name DslRef
extends RefCounted

## Sigil resolution for the workflow DSL (D24, §4): the rule that decides whether a string
## in a value position is a reference or a literal, shared by the validator (well-formedness)
## and the evaluator (resolution) so both agree exactly.
##
## Rules (A2, settling brainstorm §12's "sigil escaping" open detail):
##   "@name"      -> workflow param reference (an atomic name)
##   "$$name"     -> instance-local reference (an atomic name)
##   "\<rest>"    -> escape: the literal string <rest> (so "\@x" is the literal "@x")
##   anything else -> a literal string, unchanged
##
## Sigils are ATOMIC: "." carries no meaning inside a name. Nested access into a dict/array
## value is an explicit `get` op ({"op":"get","from":"$$route","key":"arrival_day"}), never
## a dotted sigil — decided in the A2 syntax review, diverging from the older §6 examples so
## that no path-parser hides inside a string and every traversal is visible to the validator.
##
## One backslash escapes; to get a literal leading backslash, write two ("\\foo" -> "\foo").

enum Kind { LITERAL, PARAM, LOCAL }


## Classify a string value. Returns:
##   {kind: Kind.PARAM|LOCAL, name: String}   for a reference
##   {kind: Kind.LITERAL, value: String}      for a literal (escape already applied)
static func classify(s: String) -> Dictionary:
	if s.begins_with("\\"):
		return {"kind": Kind.LITERAL, "value": s.substr(1)}
	if s.begins_with("$$"):
		return {"kind": Kind.LOCAL, "name": s.substr(2)}
	if s.begins_with("@"):
		return {"kind": Kind.PARAM, "name": s.substr(1)}
	return {"kind": Kind.LITERAL, "value": s}


## True when the string carries a reference sigil (before escape handling).
static func is_reference(s: String) -> bool:
	return s.begins_with("@") or s.begins_with("$$")


## A reference is well-formed when it names something: a non-empty atomic name.
## Used by the validator; the evaluator trusts validated input.
static func is_well_formed(s: String) -> bool:
	var c := classify(s)
	if int(c["kind"]) == Kind.LITERAL:
		return true
	return not String(c["name"]).is_empty()
