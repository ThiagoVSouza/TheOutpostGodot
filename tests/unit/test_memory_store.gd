extends GutTest

## The game master's memory (M5, D37): entity-tag + recency retrieval, and the append-only JSONL
## round-trip that lets a living game remember across a close/reopen.

const SCRATCH := "user://test_memory_store"


func after_each() -> void:
	if DirAccess.dir_exists_absolute(SCRATCH):
		var d := DirAccess.open(SCRATCH)
		for file in d.get_files():
			DirAccess.remove_absolute("%s/%s" % [SCRATCH, file])
		DirAccess.remove_absolute(SCRATCH)


func test_retrieve_returns_only_memories_sharing_a_subject() -> void:
	var store := MemoryStore.new()
	store.record("The steward demanded a bribe.", ["steward", "lord"], 10)
	store.record("A wolf killed sheep at the north farm.", ["farm", "wolf"], 11)

	var hits := store.retrieve(["steward"], 3)
	assert_eq(hits.size(), 1, "only the memory tagged with the steward")
	assert_string_contains(String((hits[0] as Dictionary)["text"]), "bribe")


func test_retrieve_orders_newest_first_and_limits_to_k() -> void:
	var store := MemoryStore.new()
	store.record("oldest", ["steward"], 5)
	store.record("middle", ["steward"], 10)
	store.record("newest", ["steward"], 20)

	var hits := store.retrieve(["steward"], 2)
	assert_eq(hits.size(), 2, "capped at k")
	assert_eq(String((hits[0] as Dictionary)["text"]), "newest")
	assert_eq(String((hits[1] as Dictionary)["text"]), "middle", "the third, older one falls off")


func test_retrieve_excludes_the_future() -> void:
	# A tick on day 12 must not see an event dated day 20 — memory is what has happened, not what will.
	var store := MemoryStore.new()
	store.record("already happened", ["steward"], 8)
	store.record("has not happened yet", ["steward"], 20)

	var hits := store.retrieve(["steward"], 3, 12)
	assert_eq(hits.size(), 1)
	assert_eq(String((hits[0] as Dictionary)["text"]), "already happened")


func test_retrieve_is_empty_when_nothing_matches() -> void:
	var store := MemoryStore.new()
	store.record("about someone else", ["merchant"], 5)
	assert_eq(store.retrieve(["steward"], 3).size(), 0)
	assert_eq(store.retrieve([], 3).size(), 0, "a query with no subjects matches nothing")


func test_the_append_only_log_survives_a_reopen() -> void:
	var path := "%s/memories.jsonl" % SCRATCH
	var first := MemoryStore.new(path, true)
	first.record("The steward was publicly humiliated.", ["steward"], 30)
	first.record("The lord gathered proof of the corruption.", ["steward", "lord"], 32)

	# A fresh store at the same path is a new launch reading the same file.
	var reopened := MemoryStore.new(path, true)
	assert_eq(reopened.count(), 2, "both memories were loaded from disk")
	var hits := reopened.retrieve(["lord"], 3)
	assert_eq(hits.size(), 1)
	assert_string_contains(String((hits[0] as Dictionary)["text"]), "proof")


func test_ids_keep_incrementing_after_a_reload() -> void:
	var path := "%s/memories.jsonl" % SCRATCH
	var first := MemoryStore.new(path, true)
	first.record("one", ["x"], 1)
	first.record("two", ["x"], 2)

	var reopened := MemoryStore.new(path, true)
	var third: Dictionary = reopened.record("three", ["x"], 3)
	assert_eq(String(third["id"]), "m3", "the id sequence continues past what was loaded")


func test_clear_empties_memory_and_deletes_the_file() -> void:
	var path := "%s/memories.jsonl" % SCRATCH
	var store := MemoryStore.new(path, true)
	store.record("something", ["x"], 1)
	assert_true(FileAccess.file_exists(path))

	store.clear()

	assert_eq(store.count(), 0)
	assert_false(FileAccess.file_exists(path), "a cleared log leaves no file to be read back")
