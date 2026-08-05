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

# Drives the button, its procedurally-drawn icon (PowerupIcon reads these via
# color_of) and the wind-up flash. Overclock is ff1040 to match
# Juice.OVERCLOCK_COLOR exactly - same hex, duplicated as a literal because
# Juice.gd carries no class_name, so it isn't resolvable inside a const
# initializer. Keep the two in sync.
#
# It was ff2e5e, which is this project's shared destructive/FAIL/Red-timer red,
# and it meant Overclock was two different reds depending on which part of it
# you looked at: the button you pressed and the screen-edge bands that fired
# were visibly not the same colour. ff1040 is also the value the edge treatment
# was deliberately tuned to so it reads apart from streak heat's ff5a1e - so
# moving the button to meet it (rather than the reverse) is what keeps that
# separation intact.
const COLORS := {
	Kind.SHIELD: Color("22d3ff"),
	Kind.CLEAR_ALL: Color("ffd23f"),
	Kind.OVERCLOCK: Color("ff1040"),
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

# --- Input suspension -------------------------------------------------------
# Deliberately NOT the same thing as Juice's gameplay freeze, and the
# distinction is load-bearing. Juice.freeze_gameplay() means "an animation has
# visually stopped the board, so no clock may advance behind it" - and a Nuke
# fired *during* another Nuke's cascade is explicitly allowed (GDD 11), so
# gating activation on is_gameplay_frozen() would break a documented rule.
#
# This means something narrower: "a modal overlay owns the screen, so the
# player is not currently playing at all." The in-game Help bubble is the only
# thing that sets it. Its dim already blocks mouse/touch from reaching the
# powerup buttons, but the tree is NOT paused (the bubble freezes clocks
# instead), so PowerupBar's A/S/D keyboard handler stayed live underneath it -
# pressing S while reading the Help panel fired a real Nuke that resolved and
# banked the whole board behind the overlay, and D banked a full-length
# Overclock window that couldn't drain while frozen. Desktop/web only, since
# touch builds have no keyboard, but both are shipping platforms.
var _input_suspended: bool = false

func set_input_suspended(suspended: bool) -> void:
	_input_suspended = suspended

func is_input_suspended() -> bool:
	return _input_suspended

# --- Practice mode (Help screen) --------------------------------------------
# Lets the Help screen's powerup page fire REAL activations - the same signals,
# the same Juice reactions, the same Shield grade filtering - without the
# run-state bookkeeping that would make those taps cost the player something.
# Exactly two things differ from a live run:
#
#   Cooldowns are never written (see _cooldown below), so someone exploring the
#   page can re-fire anything immediately instead of sitting out a 25s Overclock
#   cooldown they have no run to spend it in.
#
#   Effect DURATIONS stay real - shield_window_left, overclock_left and
#   clear_active_left all count down normally - because those are what emit
#   shield_expired/overclock_ended, and those signals are how Juice takes its
#   screen-edge bands back down again. Suppressing them the way cooldowns are
#   suppressed would leave the Overclock bands burning permanently over a
#   screen with no Overclock running.
#
# Deliberately refuses to engage while a run is armed, which makes practice and
# armed mutually exclusive by construction rather than by call-site discipline.
# That is what guarantees the in-game HelpBubble - which is only ever open
# DURING a live run, and has a powerups page of its own - can never reach in
# and clobber that run's real charges.
var _practice_mode: bool = false

func set_practice_mode(on: bool) -> void:
	if on and _armed:
		return
	if _practice_mode == on:
		return
	_practice_mode = on
	var had_shield := shield_window_left > 0.0
	# Cleared on the way IN as well as out: no leftover window from a previous
	# visit is still live when the page opens, and nothing the page started is
	# still counting once it closes.
	_reset()
	# _reset() emits overclock_ended for a live Overclock but has no equivalent
	# for Shield - in a real run Juice.reset_run_effects() takes that aura down
	# on the same state change that resets this. Practice mode has no such state
	# change to ride on, so an aura armed here would otherwise outlive the
	# screen that armed it.
	if had_shield:
		shield_expired.emit()
	state_changed.emit()

func is_practice_mode() -> bool:
	return _practice_mode

# "Powerups are live" - true during a real run, and during Help-screen practice.
# Everything that used to test _armed on its own tests this instead, so practice
# mode inherits the real behaviour rather than reimplementing a parallel copy of
# it that could drift.
func _active() -> bool:
	return _armed or _practice_mode

# Zero in practice mode: not spending charge is the single thing that separates
# a practice tap from a real one, so every cooldown assignment routes through
# here rather than each site remembering to check.
func _cooldown(base: float) -> float:
	return 0.0 if _practice_mode else base

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
	# Belt-and-braces against a stuck flag outliving the overlay that set it
	# (quitting to Title mid-bubble, say). HelpBubble clears it on both its own
	# close path and its leaving-play reset, so this should already be false -
	# but a fresh run must never start with input silently dead.
	_input_suspended = false
	# Same reasoning for practice mode: set_practice_mode() already refuses to
	# engage while armed and the Help screen clears it on close, so this should
	# be false already - but if it ever weren't, a real run would silently stop
	# charging any cooldown at all, which is a far worse failure than the Help
	# screen briefly not practising.
	_practice_mode = false

# Countdowns run on unscaled time so a PERFECT's hit-stop (which dips
# Engine.time_scale to 0.05) can't stretch a cooldown. The node stays
# PROCESS_MODE_PAUSABLE, though, so the pause menu does freeze them.
func _process(delta: float) -> void:
	if not _active():
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
			shield_cd_left = _cooldown(shield_cooldown)
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
			overclock_cd_left = _cooldown(overclock_cooldown)
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
	if not _active():
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
	# Checked here rather than in can_activate() above: the powerup genuinely
	# IS charged while a modal overlay is up, and can_activate() is what paints
	# the button's charged/ready state and drives its came-off-cooldown pulse.
	# Folding suspension into that would make the button lie about its charge
	# and re-fire the pulse on every overlay close. It's the commit that must
	# not land, not the charge that should read as spent.
	if _input_suspended:
		return false
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
			clear_cd_left = _cooldown(clear_all_cooldown)
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
# becomes a MISS, and the window shuts immediately at that point.
#
# Called by TimerSlot on BOTH fail paths - from _resolve_stop() for a mistimed
# click, and at the expiry check for a timer that ran out the clock - always
# before that slot flashes or emits anything, so the downgrade is what the
# player actually sees and every listener downstream receives one final grade.
# There is deliberately exactly one call per fail; a second call would consume
# a second Shield window for the same event.
#
# (This used to be paired with a `will_absorb_fail()` predicate, which existed
# solely so Juice could guess the outcome of an expiry it was notified about
# before anyone had decided it. EventBus.timer_expired now carries the resolved
# grade instead, so there is nothing left to predict and the predicate is gone.)
#
# `origin_global` is where the caught FAIL happened - the interrupt animation
# needs it so the absorbed burst visibly travels from the offending timer to the
# shield boundary rather than appearing from nowhere.
func filter_grade(grade: String, origin_global: Vector2 = Vector2.ZERO) -> String:
	if not _active() or grade != "FAIL" or shield_window_left <= 0.0:
		return grade
	shield_window_left = 0.0
	shield_cd_left = _cooldown(shield_cooldown)
	AudioManager.play_shield_block()
	shield_absorbed.emit(origin_global)
	state_changed.emit()
	return "MISS"

# Read every frame by every live TimerSlot.
func timer_speed_scale() -> float:
	if _active() and overclock_left > 0.0:
		return overclock_speed_multiplier
	return 1.0

# Folded into the bonus factor EndlessRunner already computes, so it rides on
# top of the existing tally x multiplier model rather than being a second,
# parallel score calculation.
func score_scale() -> float:
	if _active() and overclock_left > 0.0:
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
