extends Node

const SAVE_PATH := "user://savegame.dat"

# The whole save is one small Dictionary, so it's held in memory and written
# through on change rather than re-read on every call.
#
# This is not merely an optimisation. load_high_score() used to open and
# deserialize the file on every single call, and HelpBubble's unseen-type badge
# check runs from _process() - that worked out to one FileAccess.open + get_var
# per eligible timer type, every frame, for the entire run. On desktop that's
# wasteful; on Android that volume of main-thread file I/O is precisely what
# trips an ANR. Reads now never touch the disk after the first one.
#
# Consequence worth knowing: the file is no longer re-read mid-session, so an
# external edit while the game is running won't be picked up. Nothing in the
# game does that, and clear_all() resets the cache explicitly.
var _cache: Dictionary = {}
var _cache_loaded: bool = false

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
	# Cache is emptied and left marked loaded: the cleared state is the truth
	# now, and re-reading the file we just deleted would be pointless.
	_cache = {}
	_cache_loaded = true
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.dat"):
		dir.remove("savegame.dat")

# FileAccess.open() returns null on failure (read-only location, disk full, and
# notably IndexedDB hiccups on the Web export) - the original code dereferenced
# it unchecked, which would hard-crash the game on any save/load failure rather
# than degrading to "progress not saved".
func _write_all(data: Dictionary) -> void:
	# The in-memory state is updated even if the disk write fails, so the rest
	# of the session stays coherent and only persistence is lost - that's the
	# "warning + not saved" behaviour, not "warning + the session forgets too".
	_cache = data
	_cache_loaded = true

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		ErrorLog.report("save", "could not open %s for writing (error %d) - progress not saved."
			% [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_var(data)
	# Android's scoped storage can fail a write *after* a successful open (quota
	# exhausted, permission revoked mid-session), which store_var() doesn't
	# report on its own - so success can't be assumed from the open alone.
	var err := file.get_error()
	if err != OK:
		ErrorLog.report("save", "write to %s failed (error %d) - progress not saved." % [SAVE_PATH, err])

func _load_all() -> Dictionary:
	if _cache_loaded:
		return _cache
	_cache = _read_from_disk()
	_cache_loaded = true
	return _cache

func _read_from_disk() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		ErrorLog.report("save", "could not open %s for reading (error %d) - starting from defaults."
			% [SAVE_PATH, FileAccess.get_open_error()])
		return {}
	var data = file.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		# Recoverable by design (the player restarts from defaults rather than
		# the game refusing to boot), but previously it happened silently - on a
		# phone that's indistinguishable from "the game ate my progress".
		ErrorLog.report("save", "%s is malformed (expected Dictionary, got type %d) - starting from defaults."
			% [SAVE_PATH, typeof(data)])
		return {}
	return data
