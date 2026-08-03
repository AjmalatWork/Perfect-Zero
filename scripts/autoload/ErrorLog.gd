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
# occurrence is exactly how a log fills a disk. Recently-seen repeats are
# collapsed - including the push_warning, which is just as noisy in a console.
#
# A small recent-history list rather than a single "last entry" string, so two
# faults that happen to alternate (a failing read and a failing write, say)
# each still get collapsed once seen, instead of defeating the guard by taking
# turns. Bounded so an unbounded variety of distinct faults can't grow this
# without limit - it's still a breadcrumb trail, not telemetry.
const RECENT_LIMIT := 8
var _recent: Array[String] = []

func _notification(what: int) -> void:
	# Best-effort and platform-dependent, but when it does arrive it's the only
	# breadcrumb a field crash leaves behind.
	if what == NOTIFICATION_CRASH:
		report("engine", "NOTIFICATION_CRASH received.")

# `context` is a short tag for where this came from ("save", "engine", ...) so
# entries can be scanned without parsing prose.
func report(context: String, message: String) -> void:
	var entry := "[%s] %s" % [context, message]
	if _recent.has(entry):
		return
	_recent.append(entry)
	if _recent.size() > RECENT_LIMIT:
		_recent.pop_front()
	push_warning(entry)
	_append("%s  %s" % [Time.get_datetime_string_from_system(), entry])

func _append(line: String) -> void:
	# WRITE_READ creates the file if it's missing (READ_WRITE does not - it
	# fails outright on a first-ever write, which is why this log never wrote
	# anything before this fix). Once the file exists, READ_WRITE opens it
	# without truncating, which is what the append below needs.
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE_READ)
	if file == null:
		return  # the log itself is best-effort - never escalate a logging failure
	if file.get_length() > MAX_BYTES:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)  # truncate and start fresh
		if file == null:
			return
	file.seek_end()
	file.store_line(line)
