extends Node

const SAVE_PATH := "user://savegame.dat"

func save_high_score(key: String, value: int) -> void:
	var data := _load_all()
	data[key] = value
	_write_all(data)

func load_high_score(key: String) -> int:
	var data := _load_all()
	# Guard the type as well as the key: a corrupted/hand-edited save could hold
	# a non-int here, which would fail the int return type at runtime.
	if data.has(key) and typeof(data[key]) == TYPE_INT:
		return data[key]
	return 0

# Generic key/value store (settings etc.) - same file, any Variant value, with a
# caller-supplied default so "unset" is distinguishable from a saved 0/false.
func save_value(key: String, value: Variant) -> void:
	var data := _load_all()
	data[key] = value
	_write_all(data)

func load_value(key: String, default_value: Variant) -> Variant:
	var data := _load_all()
	return data.get(key, default_value)

func clear_all() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.dat"):
		dir.remove("savegame.dat")

# FileAccess.open() returns null on failure (read-only location, disk full, and
# notably IndexedDB hiccups on the Web export) - the previous code dereferenced
# it unchecked, which would hard-crash the game on any save/load failure rather
# than degrading to "progress not saved".
func _write_all(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open %s for writing (error %d) - progress not saved."
			% [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_var(data)

func _load_all() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: could not open %s for reading (error %d)."
			% [SAVE_PATH, FileAccess.get_open_error()])
		return {}
	var data = file.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data
