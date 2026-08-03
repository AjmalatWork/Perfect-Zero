extends Node

# Player options, cached here (loaded once, applied on change) so gameplay code
# can read them cheaply instead of hitting the save file per frame. Persisted via
# SaveManager's generic value store.

signal changed

# The SFX key is still "opt_volume" - renaming it would silently reset every
# existing player's saved level, and the label changing to "SFX" is a UI concern
# rather than a reason to break saves.
const KEY_VOLUME := "opt_volume"
const KEY_MUSIC_VOLUME := "opt_music_volume"
const KEY_REDUCE_INTENSITY := "opt_reduce_intensity"

const REDUCED_EFFECT_SCALE := 0.4  # amplitude multiplier when reduce-intensity is on

# A dragged slider emits value_changed continuously, and persisting on each one
# meant a full save-file write per increment of the drag - on Android that's
# both an ANR risk and pointless flash wear. The value is still applied to the
# audio bus immediately (it has to stay live under the player's finger); only
# the write is coalesced until the drag settles.
const PERSIST_DEBOUNCE_SEC := 0.35

var volume: float = 1.0            # SFX
var music_volume: float = 1.0
var reduce_intensity: bool = false

var _pending_writes: Dictionary = {}
var _persist_timer: Timer

func _ready() -> void:
	volume = float(SaveManager.load_value(KEY_VOLUME, 1.0))
	music_volume = float(SaveManager.load_value(KEY_MUSIC_VOLUME, 1.0))
	reduce_intensity = bool(SaveManager.load_value(KEY_REDUCE_INTENSITY, false))
	_apply_volume()
	_apply_music_volume()

	_persist_timer = Timer.new()
	_persist_timer.one_shot = true
	_persist_timer.wait_time = PERSIST_DEBOUNCE_SEC
	_persist_timer.timeout.connect(_flush_pending)
	# The options panel is reachable from the pause menu, which sets
	# get_tree().paused - without ALWAYS the debounce timer would never fire
	# there and the setting would only persist on the flush below.
	_persist_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_persist_timer)

# Flush any debounced write before the app can be backgrounded (and possibly
# killed while backgrounded) or closed. Without this, a volume change made in
# the last fraction of a second before switching away would be silently lost.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_flush_pending()

# Called by OptionsPanel's RESET PROGRESS, immediately after
# SaveManager.clear_all(). The reset is deliberately scoped to progress (high
# scores, unlock flags, tutorial-seen flags) and not to the player's own
# preferences - but clear_all() has no notion of that distinction, it wipes
# the entire save file outright. set_volume()/set_music_volume()/
# set_reduce_intensity() already update these in-memory vars synchronously
# (the debounce in _queue_persist only delays the DISK write, not the live
# value), so within the current session "settings survive the reset" already
# looked correct with no fix at all. The gap was on the player's NEXT launch:
# with the file gone, _ready() would load_value() against defaults for every
# one of these keys, and the settings they'd already chosen would quietly
# revert without them ever having touched a slider again. Re-writing the
# current values right after the wipe closes that gap, and also naturally
# supersedes anything still sitting in a debounced write queued from just
# before the reset.
func persist_current_values() -> void:
	SaveManager.save_value(KEY_VOLUME, volume)
	SaveManager.save_value(KEY_MUSIC_VOLUME, music_volume)
	SaveManager.save_value(KEY_REDUCE_INTENSITY, reduce_intensity)

func _queue_persist(key: String, value: Variant) -> void:
	_pending_writes[key] = value
	if _persist_timer != null:
		_persist_timer.start()  # restarting resets the countdown for a continuing drag

func _flush_pending() -> void:
	if _pending_writes.is_empty():
		return
	if _persist_timer != null and not _persist_timer.is_stopped():
		_persist_timer.stop()
	for key in _pending_writes:
		SaveManager.save_value(key, _pending_writes[key])
	_pending_writes.clear()

# Amplitude multiplier for effects that can legitimately just be *softened* -
# particle counts, glow strengths, localized pops. Still returns a non-zero
# value when reduce-intensity is on, so these stay present but quieter.
func effect_scale() -> float:
	return REDUCED_EFFECT_SCALE if reduce_intensity else 1.0

# False when the player has asked for the motion-sickness-inducing effects to be
# off *entirely*. Deliberately separate from effect_scale(): scaling a
# full-screen flash to 40% still flashes the whole screen, and scaling a camera
# shake still moves the whole screen. Those can't be softened into comfort -
# they have to be skipped.
#
# Gates: screen shake, camera punch/pull, and every full-screen flash or wash.
# Deliberately does NOT gate localized effects (click bursts, particles, label
# pops), persistent state tells (the Overclock edge bands, the Shield aura - a
# player still needs to know those are running), or navigational transitions.
func motion_effects_enabled() -> bool:
	return not reduce_intensity

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_queue_persist(KEY_VOLUME, volume)
	_apply_volume()
	changed.emit()

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_queue_persist(KEY_MUSIC_VOLUME, music_volume)
	_apply_music_volume()
	changed.emit()

# Persisted immediately rather than debounced: a checkbox is a single discrete
# toggle, not a continuous stream, so there's nothing to coalesce and no reason
# to leave a window where it could be lost.
func set_reduce_intensity(v: bool) -> void:
	reduce_intensity = v
	SaveManager.save_value(KEY_REDUCE_INTENSITY, v)
	changed.emit()

# --- Debug-only test override ----------------------------------------------
# Forces every player click, on any timer, to grade as PERFECT or GOOD instead
# of whatever the real click timing would produce - a testing convenience for
# exercising scoring/UI reactions without needing precise clicks. "" means off.
# Deliberately NOT persisted: a fresh launch always starts at "" so a debug
# build can never silently carry a stuck override from a previous session, and
# there's no reason a testing toggle needs to survive a restart. Read by
# TimerSlot._resolve_stop(), which re-checks OS.is_debug_build() itself before
# honoring this - belt-and-suspenders against it ever affecting a release build.
var dev_force_grade: String = ""  # "", "PERFECT", "GOOD"

func set_dev_force_grade(v: String) -> void:
	dev_force_grade = v
	changed.emit()

# --- Orientation ----------------------------------------------------------

# No longer a player choice - mobile is portrait-only, locked at the manifest
# level (project.godot's window/handheld/orientation, see Layout's own doc).
# OS.has_feature("mobile") rather than a name check on "Android" so an iOS
# target would inherit this for free; the Web export reports "web" and not
# "mobile", so a phone browser stays landscape-only same as desktop.
func is_portrait() -> bool:
	return OS.has_feature("mobile")

func _apply_volume() -> void:
	_apply_bus_volume(AudioManager.BUS_SFX, volume)

func _apply_music_volume() -> void:
	_apply_bus_volume(AudioManager.BUS_MUSIC, music_volume)

# Master is deliberately left alone now that SFX and Music are separate buses -
# driving Master from one slider would have that slider quietly control both.
# AudioManager autoloads before Settings and creates the buses in its own
# _ready, so they exist by the time this first runs; the guard is only there so
# a future reorder degrades to "volume not applied" rather than an error.
func _apply_bus_volume(bus_name: String, level: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.001)))
	if bus_name == AudioManager.BUS_MUSIC:
		# Delegated rather than set directly here - a Help screen/bubble demo
		# can independently be ducking this same bus (see AudioManager's own
		# comment on refresh_music_mute()), and a bare
		# set_bus_mute(level <= 0.001) would silently cancel that duck, or the
		# reverse: get silently un-muted here even though the slider is at
		# zero, the next time a duck ends.
		AudioManager.refresh_music_mute()
	else:
		AudioServer.set_bus_mute(idx, level <= 0.001)
