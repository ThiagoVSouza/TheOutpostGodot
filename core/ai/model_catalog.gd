class_name ModelCatalog
extends Resource

## Configured model profiles and the default selection for a platform tier.
##
## The catalog is intentionally data-only: selecting E2B or Bonsai is an ID change in
## the resource, while T3 will consume the selected [ModelProfile] to start a server.

@export var desktop_default_profile_id: String = ""
@export var android_default_profile_id: String = ""
@export var profiles: Array[ModelProfile] = []


func profile(profile_id: String) -> ModelProfile:
	for entry in profiles:
		if entry.profile_id == profile_id:
			return entry
	return null


func desktop_default() -> ModelProfile:
	return profile(desktop_default_profile_id)


func android_default() -> ModelProfile:
	return profile(android_default_profile_id)


## The profile to use when nothing named one explicitly. A phone cannot run the
## desktop default at all — different weights, no CUDA, and no way to spawn a
## server — so the platform, not a preference, decides this.
func default_for_current_platform() -> ModelProfile:
	if OS.get_name() == "Android":
		return android_default()
	return desktop_default()


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for entry in profiles:
		if entry == null:
			errors.append("catalog contains a null profile")
			continue
		if seen.has(entry.profile_id):
			errors.append("catalog has a duplicate profile_id")
		seen[entry.profile_id] = true
		for error in entry.validate():
			errors.append("%s: %s" % [entry.profile_id, error])
	if desktop_default() == null:
		errors.append("desktop_default_profile_id does not resolve")
	# Optional: a catalog that ships no mobile profile is a valid desktop-only
	# catalog. Naming one that does not exist is still an error.
	if not android_default_profile_id.strip_edges().is_empty() and android_default() == null:
		errors.append("android_default_profile_id does not resolve")
	return errors
