extends SceneTree

## Headless module-manifest validator (run via tools/validate.ps1).
##
## Scans res://modules for `*.tres` [ModuleManifest]s and reports empty ids, missing
## entry scripts, duplicate ids, and unresolved dependencies. Exits 1 on any problem.

const MODULES_ROOT := "res://modules"


func _initialize() -> void:
	var problems: Array[String] = []
	var ids_seen: Dictionary = {}
	var all_ids: Dictionary = {}
	var deps: Dictionary = {}  # id -> Array[String]

	var root := DirAccess.open(MODULES_ROOT)
	if root == null:
		push_error("No modules directory at %s" % MODULES_ROOT)
		quit(1)
		return

	for sub in root.get_directories():
		var module_dir := "%s/%s" % [MODULES_ROOT, sub]
		var sub_dir := DirAccess.open(module_dir)
		if sub_dir == null:
			continue
		for file in sub_dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var path := "%s/%s" % [module_dir, file]
			var manifest := load(path) as ModuleManifest
			if manifest == null:
				continue
			for err in manifest.validation_errors():
				problems.append("%s: %s" % [path, err])
			if ids_seen.has(manifest.id):
				problems.append("%s: duplicate module id '%s'" % [path, manifest.id])
			ids_seen[manifest.id] = true
			all_ids[manifest.id] = true
			deps[manifest.id] = manifest.dependencies

	for id in deps.keys():
		for dep in deps[id]:
			if not all_ids.has(dep):
				problems.append("module '%s' depends on missing module '%s'" % [id, dep])

	if problems.is_empty():
		print("Manifest validation OK — %d module(s): %s" % [all_ids.size(), ", ".join(all_ids.keys())])
		quit(0)
	else:
		for p in problems:
			printerr("INVALID: %s" % p)
		print("Manifest validation FAILED with %d problem(s)." % problems.size())
		quit(1)
