class_name ModuleRegistry
extends RefCounted

## Discovers module manifests, resolves dependency order, and loads modules.
##
## Discovery is filesystem-driven: it scans [member search_root] for `*.tres`
## resources that are [ModuleManifest]s. Load order is a topological sort over
## [member ModuleManifest.dependencies]; missing dependencies and cycles are reported
## and those modules are skipped rather than crashing the boot.

var search_root: String = "res://modules"

var _log: GameLog
var _manifests: Array[ModuleManifest] = []
var _modules: Array[Module] = []           # instantiated entries, in load order
var _loaded_ids: Dictionary = {}           # id -> true


func _init(log: GameLog = null, root: String = "res://modules") -> void:
	_log = log
	search_root = root


## Scan the search root for module manifests (does not load them).
func discover() -> Array[ModuleManifest]:
	_manifests = []
	var dir := DirAccess.open(search_root)
	if dir == null:
		_warn("Module search root not found: %s" % search_root)
		return _manifests
	for sub in dir.get_directories():
		var module_dir := "%s/%s" % [search_root, sub]
		var sub_dir := DirAccess.open(module_dir)
		if sub_dir == null:
			continue
		for file in sub_dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var res: Resource = load("%s/%s" % [module_dir, file])
			var manifest := res as ModuleManifest
			if manifest != null:
				_manifests.append(manifest)
	return _manifests


## Topologically sort manifests so dependencies load first. Skips manifests with
## missing dependencies or that participate in a cycle (both reported).
func resolve_order(manifests: Array[ModuleManifest]) -> Array[ModuleManifest]:
	var by_id: Dictionary = {}
	for m in manifests:
		if by_id.has(m.id):
			_warn("Duplicate module id '%s' — ignoring later manifest" % m.id)
			continue
		by_id[m.id] = m

	var ordered: Array[ModuleManifest] = []
	var placed: Dictionary = {}   # id -> true
	var visiting: Dictionary = {} # id -> true (cycle detection)

	var visit := func(id: String, visit_ref: Callable) -> bool:
		if placed.has(id):
			return true
		if visiting.has(id):
			_warn("Dependency cycle involving module '%s' — skipping" % id)
			return false
		var m: ModuleManifest = by_id[id]
		visiting[id] = true
		for dep in m.dependencies:
			if not by_id.has(dep):
				_warn("Module '%s' depends on missing '%s' — skipping" % [id, dep])
				visiting.erase(id)
				return false
			if not visit_ref.call(dep, visit_ref):
				visiting.erase(id)
				return false
		visiting.erase(id)
		placed[id] = true
		ordered.append(m)
		return true

	for m in manifests:
		if by_id.has(m.id):
			visit.call(m.id, visit)
	return ordered


## Full load: discover -> resolve order -> instantiate entry scripts -> register.
func load_all(kernel: GameKernel) -> void:
	discover()
	var ordered := resolve_order(_manifests)
	for manifest in ordered:
		if not manifest.enabled:
			_info("Skipping disabled module '%s'" % manifest.id)
			continue
		var errors := manifest.validation_errors()
		if not errors.is_empty():
			_warn("Invalid manifest '%s': %s" % [manifest.id, ", ".join(errors)])
			continue
		var module := manifest.entry_script.new() as Module
		if module == null:
			_warn("Module '%s' entry_script did not produce a Module" % manifest.id)
			continue
		module.manifest = manifest
		module.register(kernel)
		_modules.append(module)
		_loaded_ids[manifest.id] = true
		_info("Loaded module '%s' v%s" % [manifest.id, manifest.version])


func loaded_modules() -> Array[Module]:
	return _modules


func is_loaded(id: String) -> bool:
	return _loaded_ids.has(id)


func _info(msg: String) -> void:
	if _log != null:
		_log.info("ModuleRegistry", msg)


func _warn(msg: String) -> void:
	if _log != null:
		_log.warn("ModuleRegistry", msg)
