class_name AtomicFile
extends RefCounted

## Durable single-file writes, shared by [SaveManager] (slot snapshots) and [SaveWorkspace]
## (the live game's parts) so the durability rules are written once (M4/B4a).
##
## The guarantee: **whatever survives a crash is a complete file, never a half-written one.**
## A write goes to `.tmp`, is read back before being trusted, the previous contents move to
## `.bak`, and only then does the temp file take the real name. A crash can therefore cost the
## newest write but never the file.

const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"


## Write [param text] to [param path] durably. Returns true on success.
static func write_text(path: String, text: String) -> bool:
	var temp := path + TEMP_SUFFIX
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	# Read it back before trusting it: a full disk fails at flush, and finding that out now is
	# much better than finding out when the player tries to load.
	if FileAccess.get_file_as_string(temp).length() != text.length():
		DirAccess.remove_absolute(temp)
		return false

	var backup := path + BACKUP_SUFFIX
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		# Rename rather than copy: the old bytes are never in two incomplete states at once.
		if DirAccess.rename_absolute(path, backup) != OK:
			DirAccess.remove_absolute(temp)
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		# Put the previous file back — failing to write must not also lose what was there.
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return false
	return true


## Read and parse a JSON object, falling back to the `.bak` when the main file is missing or
## unreadable — the case a crash mid-write leaves behind. Returns `{ok, error, data}`.
static func read_json(path: String) -> Dictionary:
	var parsed := _parse(path)
	if bool(parsed["ok"]):
		return parsed
	var backup := _parse(path + BACKUP_SUFFIX)
	return backup if bool(backup["ok"]) else parsed


static func _parse(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "not_found", "data": {}}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "empty_file", "data": {}}
	# `JSON.parse_string` pushes an engine error on malformed input; a corrupt file is an
	# expected condition here (that is what the backup is for), not a fault worth logging.
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"ok": false, "error": "corrupt_save", "data": {}}
	return {"ok": true, "error": "", "data": json.data as Dictionary}


## Remove a file and its backup/temp companions. Returns true if anything was removed.
static func remove_all(path: String) -> bool:
	var removed := false
	for candidate in [path, path + BACKUP_SUFFIX, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
			removed = true
	return removed
