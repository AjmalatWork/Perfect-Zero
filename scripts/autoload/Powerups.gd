extends Node
# Autoloaded as `Powerups`; the class_name exists so the Kind enum can be
# referenced statically (const expressions, @export hints) where the autoload
# singleton isn't resolvable yet.
class_name PowerupSystem

# Endless-only powerups: Shield, Nuke, Overclock.
#
# This is an autoload rather than a node under EndlessRunner because two of the
# three are consulted from places that don't own the board: TimerSlot needs
# Shield's grade filter at the exact moment it resolves a stop, and every slot
# reads Overclock's speed scale every frame. Everything here returns a neutral
# value while disarmed, so Campaign play is completely unaffected.
#
# It's autoloaded as a *scene* (scenes/Powerups.tscn) specifically so the
# tunables below stay editable in the Inspector - a plain script autoload has no
# scene to open and would have made every value code-only.

signal state_changed        # any charge/window/cooldown movement - UI repaint
signal clear_all_fired      # EndlessRunner resolves the whole board
signal overclock_started
signal overclock_ended

# Shield's window has three distinct moments, and the presentation layer needs
# to tell them apart: a player should be able to say in hindsight whether a
# given Shield actually did anything, purely from how it ended.
signal shield_armed                          # window opened
signal shield_expired                        # window closed having caught nothing
signal shield_absorbed(origin_global: Vector2)  # window closed by catching a FAIL


enum Kind { SHIELD, CLEAR_ALL, OVERCLOCK }

# --- Shared presentation data ---------------------------------------------
# Same role TimerTypeInfo plays for timer types: one source of names, colours,
# keys and copy for the buttons, the Help screen and the first-run tutorial, so
# the three can't drift apart.

const ORDER := [Kind.SHIELD, Kind.CLEAR_ALL, Kind.OVERCLOCK]

const NAMES := {
	Kind.SHIELD: "Shield",
	Kind.CLEAR_ALL: "Nuke",
	Kind.OVERCLOCK: "Overclock",
}

const KEY_HINTS := {
	Kind.SHIELD: "A",
	Kind.CLEAR_ALL: "S",
	Kind.OVERCLOCK: "D",
}

const COLORS := {
	Kind.SHIELD: Color("22d3ff"),
	Kind.CLEAR_ALL: Color("ffd23f"),
	Kind.OVERCLOCK: Color("ff2e5e"),
}

static func name_of(k: int) -> String:
	return NAMES.get(k, "?")

static func key_of(k: int) -> String:
	return KEY_HINTS.get(k, "")

# Bracketed keybind hint ("[A]"), or "" on Android/mobile builds where there's
# no keyboard to bind - the buttons are still activated by tap there, so a
# hint pointing at a key that doesn't exist would just be confusing. Returns
# the empty string rather than "[]" so every caller can decide whether to omit
# it entirely (skip a label, drop a separator) with one is_empty() check
# instead of each reimplementing the mobile guard itself.
static func key_hint(k: int) -> String:
	if OS.has_feature("mobile"):
		return ""
	var key := key_of(k)
	if key.is_empty():
		return ""
	return "[%s]" % key

static func color_of(k: int) -> Color:
	return COLORS.get(k, Color.WHITE)

# --- Button origins ---------------------------------------------------------
# PowerupBar registers each button's centre so an activation's visuals can
# expand outward from the button the player actually pressed, making the
# causality readable even in peripheral vision. Kept here rather than looked up
# through the scene tree because this autoload is what fires the effects and it
# holds no reference to the UI.

var _button_origins: Dictionary = {}

func register_button_origin(kind: int, global_centre: Vector2) -> void:
	_button_origins[kind] = global_centre

# Falls back to the screen centre when the bar hasn't registered - Campaign
# never builds one - so callers never need to null-check.
func button_origin(kind: int) -> Vector2:
	return _button_origins.get(kind, Layout.canvas_size * 0.5)

# --- Shield ---------------------------------------------------------------
@export var shield_window_duration: float = 10.0
@export var shield_cooldown: float = 20.0

# --- Nuke -------------------------------------------------------------------
@export var clear_all_cooldown: float = 30.0
# Nuke resolves instantly, so it has no natural "effect duration" of its own.
# This is a nominal one, long enough to cover the board's resolve-and-fade so
# the UI doesn't show it as "active" for zero visible time.
@export var clear_all_lockout: float = 0.9

# --- Overclock ------------------------------------------------------------
@export var overclock_duration: float = 10.0
@export var overclock_speed_multiplier: float = 1.5
@export var overclock_score_multiplier: float = 2.0
@export var overclock_cooldown: float = 25.0

# --- Opening charge -------------------------------------------------------
# Every powerup starts a run already on a short flat cooldown, so the first
# stretch is played on the timers alone and powerups read as a mid-run relief
# valve rather than an opening move. Flat rather than scaled off each kind's
# own (now differing) cooldown, so the opening wait stays the same regardless
# of how the three get retuned relative to each other.
@export var initial_cooldown: float = 5.0

var _armed: bool = false      # only true during an Endless run

var shield_window_left: float = 0.0
var shield_cd_left: float = 0.0
var clear_cd_left: float = 0.0
var clear_active_left: float = 0.0
var overclock_left: float = 0.0
var overclock_cd_left: float = 0.0

func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	_reset()

func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.ENDLESS_PLAYING:
		# Pausing/resuming and the in-run Options overlay never call
		# GameManager.set_state() at all (they toggle Control visibility or
		# tree.paused instead), so every ENDLESS_PLAYING transition we see here
		# comes from EndlessRunner.start_run() - a fresh run, a pause-menu
		# restart, or "play again" - and should always rearm.
		_arm()
		state_changed.emit()
	elif new_state != GameManager.GameState.OPTIONS:
		# Leaving play for anything but the options overlay ends the run's charges.
		if _armed:
			_armed = false
			_reset()
			state_changed.emit()

func _reset() -> void:
	shield_window_left = 0.0
	shield_cd_left = 0.0
	clear_cd_left = 0.0
	clear_active_left = 0.0
	if overclock_left > 0.0:
		overclock_ended.emit()
	overclock_left = 0.0
	overclock_cd_left = 0.0

# Start-of-run state: cleared, then put straight onto a shared flat opening
# cooldown (not each kind's own recurring cooldown - those now differ per kind
# and the opening wait is meant to stay uniform).
func _arm() -> void:
	_reset()
	var initial := maxf(initial_cooldown, 0.0)
	shield_cd_left = initial
	clear_cd_left = initial
	overclock_cd_left = initial
	_armed = true

# Countdowns run on unscaled time so a PERFECT's hit-stop (which dips
# Engine.time_scale to 0.05) can't stretch a cooldown. The node stays
# PROCESS_MODE_PAUSABLE, though, so the pause menu does freeze them.
func _process(delta: float) -> void:
	if not _armed:
		return
	# A screen-freezing animation holds effect windows and cooldowns alike. This
	# is what stops an Overclock from expiring partway through Nuke's cascade and
	# silently dropping the later resolutions to a lower multiplier.
	if Juice.is_gameplay_frozen():
		return
	var real := delta / maxf(Engine.time_scale, 0.0001)
	var changed := false

	if shield_window_left > 0.0:
		shield_window_left -= real
		if shield_window_left <= 0.0:
			shield_window_left = 0.0
			# Cooldown starts when the window closes, whether it caught a FAIL or
			# simply elapsed with nothing to catch.
			shield_cd_left = shield_cooldown
			# Nothing happened - the quiet ending. filter_grade() owns the other
			# one, and having shut the window itself will never reach this branch.
			shield_expired.emit()
		changed = true

	if shield_cd_left > 0.0:
		shield_cd_left = maxf(shield_cd_left - real, 0.0)
		changed = true

	if clear_active_left > 0.0:
		clear_active_left = maxf(clear_active_left - real, 0.0)
		changed = true

	if clear_cd_left > 0.0:
		clear_cd_left = maxf(clear_cd_left - real, 0.0)
		changed = true

	if overclock_left > 0.0:
		overclock_left -= real
		if overclock_left <= 0.0:
			overclock_left = 0.0
			overclock_cd_left = overclock_cooldown
			overclock_ended.emit()
		changed = true

	if overclock_cd_left > 0.0:
		overclock_cd_left = maxf(overclock_cd_left - real, 0.0)
		changed = true

	if changed:
		state_changed.emit()

# --- Activation -----------------------------------------------------------

# No mutual exclusion between the three - each is gated only by its own charge,
# so the player can freely stack Shield/Nuke/Overclock however they like.
func can_activate(kind: int) -> bool:
	if not _armed:
		return false
	match kind:
		Kind.SHIELD:
			return shield_cd_left <= 0.0 and shield_window_left <= 0.0
		Kind.CLEAR_ALL:
			return clear_cd_left <= 0.0
		Kind.OVERCLOCK:
			return overclock_cd_left <= 0.0 and overclock_left <= 0.0
	return false

func activate(kind: int) -> bool:
	if not can_activate(kind):
		return false

	# Anticipation beat. Purely visual, and deliberately NOT a gate on the
	# mechanics below - those still commit this same frame. Delaying them would
	# mean a Shield popped in a panic fails to catch a FAIL landing inside its
	# own wind-up, which would be a rules change dressed up as juice.
	Juice.powerup_windup(button_origin(kind), color_of(kind))

	match kind:
		Kind.SHIELD:
			# The charge is spent the instant the button is pressed, whether or
			# not a FAIL ever shows up to be caught.
			shield_window_left = shield_window_duration
			AudioManager.play_powerup_activate(Kind.SHIELD)
			shield_armed.emit()
		Kind.CLEAR_ALL:
			clear_cd_left = clear_all_cooldown
			clear_active_left = clear_all_lockout
			AudioManager.play_powerup_activate(Kind.CLEAR_ALL)
			clear_all_fired.emit()
		Kind.OVERCLOCK:
			overclock_left = overclock_duration
			AudioManager.play_powerup_activate(Kind.OVERCLOCK)
			overclock_started.emit()
	state_changed.emit()
	return true

# --- Effects --------------------------------------------------------------

# Shield's only job: the first FAIL anywhere on the board inside the window
# becomes a MISS, and the window shuts immediately at that point. Called by
# TimerSlot before it flashes or emits, so the downgrade is what the player
# actually sees.
#
# `origin_global` is where the caught FAIL happened - the interrupt animation
# needs it so the absorbed burst visibly travels from the offending timer to the
# shield boundary rather than appearing from nowhere.
# True when a FAIL arriving right now would be caught. Juice consults this on
# expiry because it reacts to timer_expired, which fires *before* EndlessRunner
# gets a chance to offer the FAIL to filter_grade() - without this it would run
# a full-strength FAIL reaction for a fail that is about to be absorbed, and the
# expired catch would look nothing like the clicked one.
func will_absorb_fail() -> bool:
	return _armed and shield_window_left > 0.0

func filter_grade(grade: String, origin_global: Vector2 = Vector2.ZERO) -> String:
	if not _armed or grade != "FAIL" or shield_window_left <= 0.0:
		return grade
	shield_window_left = 0.0
	shield_cd_left = shield_cooldown
	AudioManager.play_shield_block()
	shield_absorbed.emit(origin_global)
	state_changed.emit()
	return "MISS"

# Read every frame by every live TimerSlot.
func timer_speed_scale() -> float:
	if _armed and overclock_left > 0.0:
		return overclock_speed_multiplier
	return 1.0

# Folded into the bonus factor EndlessRunner already computes, so it rides on
# top of the existing tally x multiplier model rather than being a second,
# parallel score calculation.
func score_scale() -> float:
	if _armed and overclock_left > 0.0:
		return overclock_score_multiplier
	return 1.0

func is_active(kind: int) -> bool:
	match kind:
		Kind.SHIELD:
			return shield_window_left > 0.0
		Kind.OVERCLOCK:
			return overclock_left > 0.0
		Kind.CLEAR_ALL:
			return clear_active_left > 0.0
	return false

# 0.0 = ready, 1.0 = just went on cooldown. Drives the radial sweep on the button.
func cooldown_fraction(kind: int) -> float:
	match kind:
		Kind.SHIELD:
			return _fraction(shield_cd_left, shield_cooldown)
		Kind.CLEAR_ALL:
			return _fraction(clear_cd_left, clear_all_cooldown)
		Kind.OVERCLOCK:
			return _fraction(overclock_cd_left, overclock_cooldown)
	return 0.0

func cooldown_seconds(kind: int) -> float:
	match kind:
		Kind.SHIELD:
			return shield_cd_left
		Kind.CLEAR_ALL:
			return clear_cd_left
		Kind.OVERCLOCK:
			return overclock_cd_left
	return 0.0

# Remaining seconds on an active effect window (Shield's guard, Overclock's
# boost), so the button can show the window draining as well as the cooldown.
func active_fraction(kind: int) -> float:
	match kind:
		Kind.SHIELD:
			return _fraction(shield_window_left, shield_window_duration)
		Kind.OVERCLOCK:
			return _fraction(overclock_left, overclock_duration)
	return 0.0

func _fraction(left: float, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return clampf(left / total, 0.0, 1.0)

# --- Copy -----------------------------------------------------------------
# An instance method rather than a const table, so the numbers shown to the
# player always come from the live @export values and can't go stale when these
# get retuned.
func describe(kind: int) -> String:
	match kind:
		Kind.SHIELD:
			return ("Turns your next fail into a safe miss. Lasts %ds."
				% int(shield_window_duration))
		Kind.CLEAR_ALL:
			return "Instantly clears every timer on screen with a PERFECT."
		Kind.OVERCLOCK:
			return ("Everything runs %s faster and every score is worth %s. Lasts %ds."
				% [_mult_text(overclock_speed_multiplier),
					_mult_text(overclock_score_multiplier),
					int(overclock_duration)])
	return ""

func cooldown_text(kind: int) -> String:
	match kind:
		Kind.SHIELD:
			return "%ds cooldown" % int(shield_cooldown)
		Kind.CLEAR_ALL:
			return "%ds cooldown" % int(clear_all_cooldown)
		Kind.OVERCLOCK:
			return "%ds cooldown" % int(overclock_cooldown)
	return ""

# The live score multiplier as player-facing text ("2x"), for the per-resolution
# badge. Reads the real value rather than hardcoding 2x, so it stays honest if
# overclock_score_multiplier is ever retuned.
func score_scale_text() -> String:
	return _mult_text(score_scale())

# 1.5 -> "1.5x", 2.0 -> "2x" - no trailing ".0" in player-facing copy.
func _mult_text(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%dx" % int(roundf(v))
	return "%.1fx" % v
