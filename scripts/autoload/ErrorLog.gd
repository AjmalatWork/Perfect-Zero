extends Node

# Last-resort log for conditions the game recovers from but that shouldn't
# vanish silently: a corrupt save, a failed write, an unexpected null. Extends
# the graceful-degradation approach SaveManager already takes - degrade, but
# leave a breadcrumb explaining why.
#
# This is deliberately NOT a global exception handler, and shouldn't be
# described as one: GDScript cannot intercept engine-level runtime errors or
# script crashes from script, so nothing here can promise to catch "any" error.
# What it provides is one place for the game's own recovery paths to record
# what happened on a device with no console attached - which is the actual gap
# on Android, where push_warning() goes nowhere the player or a bug report can
# reach.
#
# Everything here is best-effort and must never itself throw or block: a logger
# that can crash the game is worse than no logger.

const LOG_PATH := "user://error_log.txt"

# Rotated (truncated) past this so a fault repeating every frame can't quietly
# fill a phone's storage. Small on purpose - this is a breadcrumb trail, not
# telemetry.
const MAX_BYTES := 64 * 1024

# Identical messages are extremely likely here (a failing write retried on
# every save, a malformed save re-read on every load), and writing a line per
# occurrence is exactly how a log fills a disk. Consecutive repeats are
# collapsed - including the push_warning, which is just as noisy in a console.
var _last_entry: String = ""

func _notification(what: int) -> void:
	# Best-effort and platform-dependent, but when it does arrive it's the only
	# breadcrumb a field crash leaves behind.
	if what == NOTIFICATION_CRASH:
		report("engine", "NOTIFICATION_CRASH received.")

# `context` is a short tag for where this came from ("save", "engine", ...) so
# entries can be scanned without parsing prose.
func report(context: String, message: String) -> void:
	var entry := "[%s] %s" % [context, message]
	if entry == _last_entry:
		return
	_last_entry = entry
	push_warning(entry)
	_append("%s  %s" % [Time.get_datetime_string_from_system(), entry])

func _append(line: String) -> void:
	# READ_WRITE rather than WRITE: WRITE truncates, and it still creates the
	# file when missing, so this is the append path.
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return  # the log itself is best-effort - never escalate a logging failure
	if file.get_length() > MAX_BYTES:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)  # truncate and start fresh
		if file == null:
			return
	file.seek_end()
	file.store_line(line)
