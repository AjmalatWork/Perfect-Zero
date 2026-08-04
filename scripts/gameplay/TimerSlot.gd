extends Panel
class_name TimerSlot

# Grade windows by absolute distance from true 0.00.
const PERFECT_MAX := 0.05
const GOOD_MAX := 0.30
const OKAY_MAX := 0.50
const MISS_MAX := 1.00       # beyond this a manual stop is a FAIL (ends the stage)
const EXPIRE_THRESHOLD := -1.00

# Neon accent per timer type. The panel fill is a very dark tint of this, with
# the bright accent used for the glowing border, shadow-glow, and digit outline.
const TYPE_COLORS := {
	TimerData.TimerType.NORMAL: Color("e6e9ff"),
	TimerData.TimerType.RED: Color("ff2e5e"),
	TimerData.TimerType.BLUE: Color("22d3ff"),
	TimerData.TimerType.GOLDEN: Color("ffd23f"),
	TimerData.TimerType.BLACKOUT: Color("5a5f70"),
	TimerData.TimerType.DECAY: Color("b06bff"),
}

# Blackout is the type that's supposed to recede - so on top of its darker
# accent it gets a deeper panel fill and a dimmed glow, making it read as a hole
# in the board rather than just another grey panel. Kept as a presentation-only
# treatment: nothing here touches its countdown, grading or audio.
#
# The accent itself can't go much darker than it already has - TimerTypeInfo
# uses the same colour as raw font_color for the Help screen legend and the
# tutorial popup, where it stops being legible against the near-black
# background. These two do the rest of the work in-game instead.
const BLACKOUT_FILL_DARKEN := 0.94   # vs. 0.86 for every other type
const BLACKOUT_GLOW_SCALE := 0.5

# The opposite treatment for Decay: a fresh one blazes (>1.0 scales its halo
# well past any other timer's) and dims as its ceiling burns down, so "act on
# this first" and "this is draining" are the same visual signal. Indexed by
# tier, same order as TimerTypeInfo.DECAY_TIER_COLORS.
const DECAY_GLOW_SCALE := [2.2, 1.35, 0.85, 0.55]

# The spawn flash floods the whole panel, so it uses its own vivid purple rather
# than the tier-0 accent - that accent is tuned to be legible as a thin border
# and a digit outline, which makes it too pale to read as a purple flash when
# it's covering the entire slot.
const DECAY_SPAWN_FLASH := Color("c15cff")

# --- Decay (count-up) ------------------------------------------------------
# DECAY inverts the whole premise: it starts at 0.00 and counts UP, so the
# player wants it stopped as *early* as possible rather than at a precise
# instant. That means it can't be graded on distance-from-zero against the
# global PERFECT/GOOD/OKAY windows - those collapse from PERFECT to FAIL inside
# one second, which would make every Decay click a FAIL. It gets its own much
# wider windows instead (authored per-timer on TimerData), and the tier the
# elapsed time lands in *is* the grade.
const DECAY_TIER_GRADES := ["PERFECT", "GOOD", "OKAY", "MISS"]

# --- Golden rework (digit-blur, infinite duration) -------------------------
# Golden never counts down and never expires - see _process_golden() for the
# full rationale and the accepted Campaign-stall risk this creates.
const GOLDEN_BLUR_BASE_SPEED := 28.0     # digit-changes/sec at baseline
const GOLDEN_BLUR_STEP_PER_STACK := 8.0  # extra speed per permanent Red stack
const GOLDEN_BLUR_MAX_SPEED := 60.0      # cap so repeated Reds can't look glitched/broken

const RED_TINT := Color("ff2e5e")
const BLUE_TINT := Color("22d3ff")
const FROST_COLOR := Color("d8f4ff")  # icy border while paused by a Blue reaction

# Border glow grows with the live PERFECT streak ("the board is getting hot").
const GLOW_BASE := 14
const GLOW_HEAT_BONUS := 12
const GLOW_FROST := 24

# A stopped/expired slot stays fully visible for POST_STOP_HOLD (so the stop
# flash/grade-sign/shine finish reading clearly), then fades over
# FADE_OUT_DURATION. Endless waits for faded_out before freeing the cell, so a
# slot only counts as "empty" once it's actually gone, not the instant it's
# clicked.
const POST_STOP_HOLD := 0.4
const FADE_OUT_DURATION := 0.4

# Overclock's red, so the per-resolution badge ties back to the screen-edge
# treatment that's running at the same time rather than reading as loose text.
const MULTIPLIER_BADGE_COLOR := Color("ff1040")

# --- Zero-proximity urgency glow --------------------------------------------
# A border glow + pulse whose intensity tracks how close THIS INSTANT is to a
# good stop, so a busy board reads "which one needs me next" at a glance
# instead of making the player scan every digit. Driven off current_time -
# already recomputed every frame for the countdown itself - rather than a
# second, parallel distance metric that could quietly disagree with what a
# click would actually grade.
#
# Not to be confused with AudioManager's "tick urgency" (report_tick_urgency
# below): that's an unrelated, pre-existing system ranking timers for the
# audio-priority mix. This one is purely visual and has no audio component.
#
# urgency_of() is a plain linear ramp from 0.0 at |distance| == max_distance
# to 1.0 at distance 0 - NOT ScoreManager.base_points()'s own quadratic curve.
# That curve back-loads intensity near zero (urgency is only 0.25 at distance
# 0.5, since (1-0.5)^2 = 0.25) which reads as the glow doing almost nothing
# until the very last instant, then rushing to full brightness - fine for a
# SCORE curve, wrong for a glance-able "how close is this" cue, which wants an
# even, gradual climb the player can track continuously.
#
# max_distance is a VISUAL window, deliberately decoupled from MISS_MAX (the
# real 1.0 FAIL boundary grading actually uses) - see URGENCY_RANGE below for
# why the four countdown types widen it past that boundary, and Decay's own
# call site for why it stays at the 1.0 default instead.
#
# Two independent style axes, both fed by the SAME urgency value so they ramp
# in lockstep rather than as two separately-tuned curves:
#  - glow SIZE/ALPHA/BORDER WIDTH: how strong the effect is right now.
#  - pulse STYLE: a smooth breathing sine while current_time > 0 (still
#    approaching zero), switching to a sharper, faster flicker the instant
#    current_time crosses to <= 0 (past zero, still gradable up to MISS).
#    The style swap is what signals "this is now past zero" - NOT a jump in
#    brightness, which stays continuous across the crossing (a timer sitting
#    at -0.02 is still near-max urgency, correctly, since it's still near the
#    PERFECT distance).
#
# Explicit constraint: no colour/hue changes. Board timers already use colour
# as their primary type-identity signal, and the GDD already flags hue-only
# type encoding as a known colourblind-accessibility gap - a second, unrelated
# meaning riding on hue would make that worse. border_color/_accent are never
# touched by anything below; only size, alpha and width move.
# How far out, in seconds of current_time, the glow should start building -
# a user request for anticipation to begin earlier than the FAIL boundary
# itself (1.0/MISS_MAX), so a player scanning a busy board gets a bigger head
# start before a timer is even close to gradable. Only the visual window
# widens; MISS_MAX/the real grading boundary is untouched, so a timer sitting
# at distance 1.5 (well outside FAIL/MISS territory) now shows a faint,
# building glow rather than none at all. Applies to the four countdown types
# only (Normal/Red/Blue/Blackout) - Decay's own urgency input is already
# normalised to its own 0..1 window (see _process_decay()) and stays there,
# since widening it the same way would mean its urgency never reaches 0
# within the range it's actually fed.
#
# Note this also widens the POST-crossing (flicker) side by the same amount,
# but current_time can never actually reach -2.0 for a live timer - it's
# force-stopped at EXPIRE_THRESHOLD (-1.0) - so in practice the flicker phase
# now settles at urgency ~0.5 rather than fading fully to 0 before the timer
# disappears. If that reads as the flicker staying too bright right up to
# expiry, narrow this back down or split it into a separate forward/backward
# pair - flagged here rather than silently chosen.
const URGENCY_RANGE := 2.0

const URGENCY_GLOW_SIZE_BONUS := 18.0     # added to _glow_size() at full pulse
const URGENCY_ALPHA_BONUS := 0.35         # added to _glow_alpha() at full pulse (still clamped <=1)
const URGENCY_BORDER_WIDTH_BONUS := 3.0   # added to the base 3px border at full pulse
const URGENCY_BREATH_HZ_MIN := 0.4        # pre-crossing breathing pulse: slow at low urgency...
const URGENCY_BREATH_HZ_MAX := 2.2        # ...faster as urgency climbs, still reads as a breath
const URGENCY_FLICKER_HZ_MIN := 5.0       # post-crossing flicker: already sharp at low urgency...
const URGENCY_FLICKER_HZ_MAX := 11.0      # ...frantic at max urgency
# The pulse never dips all the way to 0 within an urgent window - it swings
# between this fraction of the current urgency and the full value, so a
# near-max-urgency timer never goes visually dark between beats.
const URGENCY_PULSE_FLOOR := 0.4

# Decay counts up, not down, and is graded by which elapsed-time window it
# lands in rather than distance-from-zero - so it doesn't get a second,
# separate glow system layered on top of its existing bright(at spawn)->dim
# (draining) tier stepping (see DECAY_GLOW_SCALE/_apply_decay_tier). Instead
# the SAME urgency()-shaped curve just drives the RATE/FEEL of what's already
# there: a small multiplicative breathing swing on top of the tier's own
# glow size/alpha, fed by elapsed-time-normalised-to-window (0 at spawn, 1 at
# the ceiling burning out) rather than |distance|. Deliberately small and
# size/alpha-only - Decay's border WIDTH stays flat; the tier colour stepping
# is already this type's dramatic "how close" signal, and pulsing a second
# channel on top of it would compete rather than complement.
const DECAY_URGENCY_PULSE_DEPTH := 0.16

# Blackout already has a purpose-built by-feel cue for this exact question
# (its own low heartbeat tick replacing the standard rising-pitch one, plus
# blank digits once inside blackout_duration) - so the default here is to
# suppress this glow entirely while inside that window, rather than fight a
# cue that's deliberately asking the player to stop looking and start
# listening. Left OUTSIDE the blackout window (a Blackout timer ticking
# normally, digits still visible), the glow behaves exactly like every other
# countdown type.
#
# DECISION POINT, not a settled default - flip BLACKOUT_URGENCY_SUPPRESSED to
# false to try the alternative instead (muted glow via BLACKOUT_URGENCY_SCALE,
# not full-strength - full-strength would just telegraph the exact moment and
# defeat the "time it by ear" point of the window in the first place). Both
# HelpDemoTile.play_countdown()'s Blackout demo and every real Blackout timer
# read this same constant, so toggling it here is the one place to change to
# compare the two versions.
const BLACKOUT_URGENCY_SUPPRESSED := true
const BLACKOUT_URGENCY_SCALE := 0.35   # only used when the flag above is false

signal faded_out

@onready var digit_label: Label = $DigitLabel

var data: TimerData
var current_time: float
var speed_multiplier: float = 1.0
var paused_for: float = 0.0
var stopped: bool = false
var speed_boost_stacks: int = 0  # +1 per Red reaction; also drives Golden's blur speed
var has_triggered_spawn: bool = false  # Endless: latched once this timer crosses the spawn threshold
# Latched alongside the faded_out signal, for waiters that poll rather than
# await it (see EndlessRunner._free_cell_after_delay, which has to survive the
# slot being freed out from under it without the signal ever firing). Plain
# state on the slot rather than a flag the waiter keeps for itself: a local
# captured by a lambda is copied by value in GDScript, so writing it from a
# signal handler updates the lambda's copy and leaves the waiter's own
# variable false forever.
var has_faded_out: bool = false
var _tick_accumulator: float = 0.0
var _panel_style: StyleBoxFlat
var _accent: Color
var _base_bg: Color
var _red_overlay: ColorRect
var _blue_overlay: ColorRect
var _blue_tween: Tween
var _click_global_pos: Vector2
var _has_click_pos: bool = false
var _frosted: bool = false
var _heat: float = 0.0
var _golden_blur_timer: float = 0.0
var _golden_blur_digit: int = 0
var _decay_tier_shown: int = -1   # -1 so the first _process always applies tier 0

# --- Zero-proximity urgency glow state --------------------------------------
var _urgency: float = 0.0             # 0..1, urgency_of() this frame - the pulse's ceiling
var _urgency_pulse: float = 0.0       # 0..1, _urgency modulated by the breathing/flicker envelope - what actually reaches the panel
var _urgency_envelope: float = 0.0    # 0..1, the raw oscillator output before urgency scales it - Decay reads this directly for its centred swing
var _urgency_phase: float = 0.0       # oscillator phase in seconds; reset on a style swap so a flicker never inherits a breath's position
var _urgency_past_zero: bool = false  # which pulse style is active - breathing (false) or flicker (true)
# True for the duration of a discrete panel-style tween (frost clearing, a
# Decay tier stepping) that's already animating shadow_size/shadow_color -
# without this, the per-frame urgency write below would fight that tween for
# the same StyleBoxFlat properties every frame, snapping the transition
# instead of letting it ease.
var _panel_transition_lock: bool = false

func _ready() -> void:
	EventBus.heat_changed.connect(_on_heat_changed)
	_heat = Juice.heat

# A slot freed mid-run (Endless clearing the board, Campaign clearing a stage)
# never reaches stop(), so the audio-priority registry would keep ranking a
# timer that no longer exists.
func _exit_tree() -> void:
	AudioManager.clear_tick_urgency(get_instance_id())

func setup(timer_data: TimerData) -> void:
	data = timer_data
	# DECAY is the one type that climbs away from zero instead of falling toward
	# it, so it ignores start_time and always opens on a full-value 0.00.
	current_time = 0.0 if _is_decay() else data.start_time
	_apply_type_color()
	_build_overlays()
	if _is_decay():
		digit_label.text = "0.00"

func _is_decay() -> bool:
	return data != null and data.timer_type == TimerData.TimerType.DECAY

# "Is a Blackout timer" - distinct from _in_blackout(), which is "is currently
# inside the window where its digits are hidden".
func _is_blackout_type() -> bool:
	return data != null and data.timer_type == TimerData.TimerType.BLACKOUT

# How close this timer is to resolving itself, expressed the way Endless's spawn
# scheduler wants it: a small number means "about to go". Types count in
# different directions (and GOLDEN never goes at all), so the comparison the
# scheduler makes has to come from here rather than from raw current_time.
func spawn_trigger_value() -> float:
	if data.timer_type == TimerData.TimerType.GOLDEN:
		return INF  # no expiry - never triggers a spawn on its own
	if _is_decay():
		return maxf(data.decay_miss_end() - current_time, 0.0)
	return current_time

func _apply_type_color() -> void:
	_accent = TYPE_COLORS.get(data.timer_type, Color.WHITE)
	# Near-black, faintly tinted by the accent - deeper still for Blackout.
	_base_bg = _accent.darkened(
		BLACKOUT_FILL_DARKEN if _is_blackout_type() else 0.86)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = _base_bg
	_panel_style.set_corner_radius_all(16)
	_panel_style.set_border_width_all(3)
	_panel_style.border_color = _accent
	_panel_style.set_content_margin_all(12)
	# Centered, colored drop-shadow reads as a neon outer glow.
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b, _glow_alpha())
	_panel_style.shadow_size = _glow_size()
	_panel_style.shadow_offset = Vector2.ZERO
	add_theme_stylebox_override("panel", _panel_style)

	# Bright digits with an accent-colored outline "glow" on the dark fill.
	digit_label.add_theme_font_size_override("font_size", 54)
	digit_label.add_theme_color_override("font_color", Color.WHITE)
	digit_label.add_theme_color_override("font_outline_color", _accent)
	digit_label.add_theme_constant_override("outline_size", 10)

func _build_overlays() -> void:
	# Reaction tints layered over the base panel color, independently controllable.
	_red_overlay = _make_overlay(RED_TINT)
	_blue_overlay = _make_overlay(BLUE_TINT)
	digit_label.z_index = 1  # keep digits above the tint overlays

func _make_overlay(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(color.r, color.g, color.b, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect

func _process(delta: float) -> void:
	if stopped:
		return

	# An animation has visually stopped the game (Nuke's cascade), so every clock
	# on this slot holds - countdown, Blue's pause, Golden's blur. Returning
	# before the tick-urgency report also keeps the audio ranking static, so a
	# frozen board can't reshuffle which timer is "most urgent" behind the scenes.
	if Juice.is_gameplay_frozen():
		return

	if data.timer_type == TimerData.TimerType.GOLDEN:
		_process_golden(delta)
		return

	if paused_for > 0.0:
		paused_for -= delta
		if paused_for <= 0.0 and _frosted:
			_set_frost(false)
		# A Blue-frozen timer's remaining time isn't moving, so it stops competing
		# in the audio priority ranking entirely rather than holding a rank it no
		# longer earns.
		AudioManager.clear_tick_urgency(get_instance_id())
		return

	if _is_decay():
		_process_decay(delta)
		return

	current_time -= delta * _effective_speed()
	# Blackout hides its digits once inside blackout_duration of zero - the ticking
	# audio is the player's only cue from there. Countdown/grading are unaffected.
	if _in_blackout():
		digit_label.text = "??.??"
	else:
		digit_label.text = "%.2f" % current_time

	# current_time IS the live distance-from-zero for every type that reaches
	# here (Normal/Red/Blue/Blackout) - signed, so the flicker-style swap is
	# just current_time's own sign, no second threshold check needed.
	# Suppressed/muted for Blackout while inside its own blank-digit window -
	# see BLACKOUT_URGENCY_SUPPRESSED above. URGENCY_RANGE widens the ramp's
	# window past MISS_MAX's own 1.0 - see that constant's own comment.
	_update_urgency(delta, current_time, current_time <= 0.0, URGENCY_RANGE)
	_apply_urgency_to_panel()

	# Ranked against every other live timer so a busy board doesn't stack N ticks
	# at full volume; the soonest-to-expire stays loudest. See AudioManager.
	AudioManager.report_tick_urgency(get_instance_id(), current_time - EXPIRE_THRESHOLD)

	_tick_accumulator += delta
	if _tick_accumulator >= 1.0:
		_tick_accumulator = 0.0
		if data.timer_type == TimerData.TimerType.BLACKOUT:
			# Blackout's own timbre for its whole life, not just once digits go
			# dark - the point is to train the player to listen to it before
			# they need to, not introduce a new sound right when they lose the
			# visual. Same cadence as the standard tick either way.
			AudioManager.play_blackout_tick(get_instance_id())
		else:
			# maxf guards the divisor: a hand-authored start_time of 0 would make
			# this 0/0 = NaN, and clamp() passes NaN straight through into
			# pitch_scale, which silences the voice rather than erroring.
			var progress: float = clamp(
				1.0 - (current_time / maxf(data.start_time, 0.0001)), 0.0, 1.0)
			var pitch_factor: float = lerp(1.0, 2.5, progress)
			AudioManager.play_tick(pitch_factor, get_instance_id())

	if current_time <= EXPIRE_THRESHOLD:
		stopped = true
		AudioManager.clear_tick_urgency(get_instance_id())
		# Shield is offered the fail HERE, at the single point the expiry
		# actually happens, exactly as _resolve_stop() does for a mistimed
		# click - so both fail paths run the same one filter call and every
		# listener downstream sees the same already-final grade. This used to
		# live in EndlessRunner._on_timer_expired(), i.e. after this emit, which
		# forced presentation listeners to predict the outcome instead of being
		# told it. Returns "FAIL" untouched outside an Endless run, so Arcade is
		# unaffected.
		var grade := Powerups.filter_grade("FAIL", global_position + size * 0.5)
		EventBus.timer_expired.emit(self, grade)
		_begin_post_stop_fade()

# DECAY climbs away from 0.00 instead of falling toward it. Red's permanent
# speed stacks make it climb faster (consistent with Red's "makes things worse"
# role - it burns the ceiling down sooner), and Blue's pause is handled by the
# shared paused_for early-return above, which freezes the climb outright.
func _process_decay(delta: float) -> void:
	current_time += delta * _effective_speed()
	digit_label.text = "%.2f" % current_time

	var tier := _decay_tier(current_time)
	if tier != _decay_tier_shown:
		# -1 means this is the first frame - the spawn, not a tier stepping down.
		var is_spawn := _decay_tier_shown < 0
		_decay_tier_shown = tier
		_apply_decay_tier(tier, not is_spawn)
		if is_spawn:
			_play_decay_spawn_pulse()

	# Decay has no zero to approach - it counts UP, graded by which elapsed-time
	# window it's currently in - so the urgency input here is elapsed time
	# normalised to the full window (0 at spawn, 1 at the ceiling burning out)
	# rather than |distance|. Same formula shape as every other type, just fed a
	# different quantity; not eligible for the flicker style (Decay never
	# re-crosses a boundary the way a countdown that overran zero does - it just
	# resolves the instant it runs out).
	var decay_progress := clampf(current_time / maxf(data.decay_miss_end(), 0.0001), 0.0, 1.0)
	_update_urgency(delta, decay_progress, false)
	_apply_urgency_to_panel()

	var life_left := data.decay_miss_end() - current_time
	AudioManager.report_tick_urgency(get_instance_id(), life_left)

	_tick_accumulator += delta
	if _tick_accumulator >= 1.0:
		_tick_accumulator = 0.0
		# Pitch climbs with how much of the ceiling has already burned off, so
		# Decay's tick reads as "value draining" on the same rising curve the
		# other types use for "about to expire".
		var progress: float = clamp(
			current_time / maxf(data.decay_miss_end(), 0.0001), 0.0, 1.0)
		AudioManager.play_tick(lerp(1.0, 2.5, progress), get_instance_id())

	# Ran out of ceiling: resolves as a MISS rather than the FAIL every other
	# type's expiry produces. Decay is deliberately the one type that can't cost
	# a life - it just drains to worthless.
	if current_time >= data.decay_miss_end():
		_resolve_stop("MISS", false)

# Red's stacks and Overclock's board-wide boost are separate axes: Red is
# permanent and per-timer, Overclock is temporary and global. Multiplying them
# means Overclock can be lifted later without disturbing accumulated Red stacks.
func _effective_speed() -> float:
	return speed_multiplier * Powerups.timer_speed_scale()

func _decay_tier(elapsed: float) -> int:
	if elapsed <= data.decay_perfect_end():
		return 0
	if elapsed <= data.decay_good_end():
		return 1
	if elapsed <= data.decay_okay_end():
		return 2
	return 3

# Steps the border, fill and glow to the tier's look so the current ceiling is
# readable without parsing the climbing digits. Skipped while frosted or stopped
# so it can't fight the frost tween or the stop flash for the same properties.
# `animate` is false on the spawn application, where the pulse below owns the
# transition instead.
func _apply_decay_tier(tier: int, animate: bool) -> void:
	_accent = TimerTypeInfo.decay_tier_color(tier)
	_base_bg = _accent.darkened(0.86)
	digit_label.add_theme_color_override("font_outline_color", _accent)
	if _panel_style == null or stopped or _frosted:
		return

	var glow := Color(_accent.r, _accent.g, _accent.b, _glow_alpha())
	if not animate:
		_panel_style.border_color = _accent
		_panel_style.shadow_color = glow
		_panel_style.shadow_size = _glow_size()
		return

	# Locked for the duration - the per-frame urgency writer targets these same
	# two properties every tick and would otherwise fight this tween for them,
	# snapping the tier transition instead of letting it ease.
	_panel_transition_lock = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel_style, "border_color", _accent, 0.18)
	tween.tween_property(_panel_style, "bg_color", _base_bg, 0.18)
	tween.tween_property(_panel_style, "shadow_color", glow, 0.18)
	# Tweened too, since the halo shrinks with each tier as well as dimming.
	tween.tween_property(_panel_style, "shadow_size", _glow_size(), 0.18)
	tween.finished.connect(func(): _panel_transition_lock = false)

# A Decay arrives on a board where every other timer has already been running
# for seconds, so it announces itself: a scale pop plus a bright flood settling
# into the tier-0 colour. Reuses the same idiom as the PERFECT stop flash, and
# _pop() already scales its amplitude down under "reduce screen effects".
func _play_decay_spawn_pulse() -> void:
	_pop(1.35)
	if _panel_style == null:
		return
	_panel_style.bg_color = DECAY_SPAWN_FLASH
	var tween := create_tween()
	tween.tween_property(_panel_style, "bg_color", _base_bg, 0.45)

# Golden holds its slot indefinitely rather than counting down - a diegetic
# fix for players who kept aiming for 0.00 despite the tutorial explaining
# Golden guarantees a PERFECT at any distance. It never reaches EXPIRE_THRESHOLD
# and never emits timer_expired; current_time is left untouched from setup()
# and is unused here (stop() already hardcodes distance to 0.0 for GOLDEN).
#
# ACCEPTED RISK: StageController._check_stage_clear() requires every active
# slot to be stopped, so a Campaign player who never clicks an active Golden
# stalls the stage indefinitely. No auto-resolve/forced-timeout is added here
# by design (spec'd this way) - revisit if playtesting shows it's a real
# problem, not a hypothetical one.
func _process_golden(delta: float) -> void:
	if paused_for > 0.0:
		paused_for -= delta
		# Exception to normal Blue behavior (which freezes at whatever value was
		# already showing): Golden freezes at a fixed 0.00 while paused. This is
		# deliberate, not a bug - watch for it re-introducing the "0.00 is the
		# moment" misconception during playtesting; it should read as "everything
		# on the board just froze" since every other running timer visibly stops
		# at the same moment, not as "here's my window."
		digit_label.text = "0.00"
		if paused_for <= 0.0 and _frosted:
			_set_frost(false)
		return

	# Blur speed reuses speed_boost_stacks - the same permanent, stacking counter
	# Red already drives on every other timer type - rather than tracking a
	# second stack count. Purely cosmetic: it never touches duration or
	# resolution, since Golden has neither.
	var blur_speed: float = minf(
		GOLDEN_BLUR_BASE_SPEED + GOLDEN_BLUR_STEP_PER_STACK * float(speed_boost_stacks),
		GOLDEN_BLUR_MAX_SPEED)

	# Random digit per tick rather than a sequential 0-9 counter - a counter is
	# still readable as "counting" no matter how fast it goes; noise reads as
	# blur/flicker immediately.
	var interval: float = 1.0 / blur_speed
	_golden_blur_timer += delta
	while _golden_blur_timer >= interval:
		_golden_blur_timer -= interval
		_golden_blur_digit = randi() % 10
	digit_label.text = "0.0%d" % _golden_blur_digit

func stop() -> void:
	_resolve_stop("", true)

# Resolutions the player didn't click for: Nuke cashes every live timer in
# at a flat PERFECT, and a fully-drained Decay resolves itself as a MISS.
func force_resolve(grade: String) -> void:
	_resolve_stop(grade, false)

func _resolve_stop(forced_grade: String, from_click: bool) -> void:
	if stopped:
		return
	stopped = true
	AudioManager.clear_tick_urgency(get_instance_id())

	# Blackout hides its digits near zero - reveal the true stopped value now
	# that the player has committed to a click.
	if data.timer_type == TimerData.TimerType.BLACKOUT:
		digit_label.text = "%.2f" % current_time
	# Golden always resolves as a clean 0.00 on click, regardless of whatever
	# random blur digit happened to be showing the instant it was clicked -
	# the "guaranteed PERFECT" needs to land on the same digit every time.
	elif data.timer_type == TimerData.TimerType.GOLDEN:
		digit_label.text = "0.00"

	var distance: float
	var grade: String
	if forced_grade != "":
		grade = forced_grade
		# Nuke is a full-value resolution by definition; a Decay that ran
		# out of ceiling still scores on how far it actually climbed.
		distance = 0.0 if grade == "PERFECT" else _stop_distance()
	else:
		distance = _stop_distance()
		grade = _grade_for_distance(distance)

	# Debug-only test override (Options menu, debug builds only): forces every
	# real click to grade as PERFECT or GOOD, regardless of actual timing or
	# timer type. Distance is overridden to match (0.0 for PERFECT, GOOD_MAX for
	# GOOD) so scoring reflects the forced grade instead of the real click's raw
	# distance. Gated to from_click/forced_grade=="" so it never touches Nuke's
	# force_resolve() or an expiry's own forced grade.
	if from_click and forced_grade == "" and OS.is_debug_build() and Settings.dev_force_grade != "":
		grade = Settings.dev_force_grade
		distance = 0.0 if grade == "PERFECT" else GOOD_MAX

	# Shield downgrades the first FAIL inside its window to a MISS. Filtering
	# here - ahead of the flash, the grade sign and the EventBus emit - means the
	# player sees the MISS they actually got rather than a FAIL that silently
	# scores as something else. Returns grade untouched outside Endless.
	grade = Powerups.filter_grade(grade, global_position + size * 0.5)

	# Clearing frost first lets the stop flash win the properties they share.
	if _frosted:
		_set_frost(false)
	_play_stop_flash(grade)
	_spawn_grade_sign(grade)
	if TimerTypeInfo.has_shine(data.timer_type):
		_play_shine()
	# Burst at the cursor, not the panel centre - layered on top of the stop
	# flash. A forced resolution has no cursor to speak of, so it bursts centred.
	var burst_at := global_position + size * 0.5
	if from_click and _has_click_pos:
		burst_at = _click_global_pos
	Juice.click_burst(burst_at, grade, data.timer_type)
	EventBus.timer_stopped.emit(self, grade, data.timer_type, distance)
	_begin_post_stop_fade()

# Rounded to the same 2 decimal places the digit display shows, so grading and
# scoring can never disagree with what the player actually saw - a raw 0.051
# would grade as GOOD while the label (formatted with "%.2f") shows "0.05",
# which reads as PERFECT.
func _stop_distance() -> float:
	# GOLDEN is a guaranteed PERFECT, so it scores as a perfect (distance 0) no
	# matter when it's clicked.
	if data.timer_type == TimerData.TimerType.GOLDEN:
		return 0.0
	# DECAY has no "zero moment" to be near - it scores on how far it climbed,
	# normalised over its own full lifetime so it feeds the same 0..1 proximity
	# curve (and therefore the same points formula) as every other type.
	if _is_decay():
		return clampf(current_time / maxf(data.decay_miss_end(), 0.0001), 0.0, 1.0)
	return stop_distance_for(current_time)

# Fire-and-forget: holds the slot fully visible, fades it out, then signals
# faded_out. Campaign doesn't listen for this (it frees every slot at once
# when the stage ends via _clear_slots) - the fade there is purely visual.
# Endless awaits it directly so a cell isn't reused until the old timer has
# actually finished disappearing.
func _begin_post_stop_fade() -> void:
	await get_tree().create_timer(POST_STOP_HOLD, true, false, true).timeout
	if not is_instance_valid(self):
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	await tween.finished
	if not is_instance_valid(self):
		return
	has_faded_out = true
	faded_out.emit()

func _spawn_grade_sign(grade: String) -> void:
	# A punchy floating label that pops above the timer for ~0.8s.
	var sign_label := Label.new()
	sign_label.text = grade
	sign_label.add_theme_font_size_override("font_size", 40)
	sign_label.add_theme_color_override("font_color", ScoreManager.grade_color(grade))
	sign_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sign_label.add_theme_constant_override("outline_size", 8)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign_label.z_index = 20
	sign_label.size = Vector2(size.x, 56)
	sign_label.position = Vector2(0, -72)
	sign_label.pivot_offset = sign_label.size * 0.5
	sign_label.scale = Vector2(1.9, 1.9)
	add_child(sign_label)
	_add_multiplier_badge(sign_label, grade)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sign_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sign_label, "position:y", sign_label.position.y - 34.0, 0.8)
	tw.tween_property(sign_label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tw.finished.connect(sign_label.queue_free)

# Shows what a stop was actually worth while Overclock is up, so the doubling is
# visible per-resolution rather than only as a faster-climbing total.
#
# Parented to the grade sign rather than to the slot: it then inherits the sign's
# pop, rise and fade for free and can never drift out of sync with it.
#
# Suppressed on FAIL because ScoreManager.register_result() returns before
# bonus_factor is ever applied there - a FAIL scores zero flat, so badging it
# "2x" would be advertising a doubling that didn't happen. Every other grade
# genuinely receives the multiplier, MISS included.
func _add_multiplier_badge(sign_label: Label, grade: String) -> void:
	if grade == "FAIL" or Powerups.score_scale() <= 1.0:
		return

	var badge := Label.new()
	badge.text = Powerups.score_scale_text()
	badge.add_theme_font_size_override("font_size", 24)
	badge.add_theme_color_override("font_color", MULTIPLIER_BADGE_COLOR)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	badge.add_theme_constant_override("outline_size", 6)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(0, 42)
	badge.size = Vector2(sign_label.size.x, 30)
	sign_label.add_child(badge)

# Blackout is the type registered as having its own audio cue; the window it
# applies over is the type's own blackout_duration.
func _in_blackout() -> bool:
	return (TimerTypeInfo.has_audio_cue(data.timer_type)
		and current_time <= data.blackout_duration)

# Golden is a guaranteed PERFECT, so it gets a coin-shine sweep to read as a
# rewarded freebie rather than a precisely-earned stop.
func _play_shine() -> void:
	# Clipped to the panel by its own wrapper, so the sweep can't spill over the
	# grade sign or the digits the way clip_contents on the slot itself would.
	var clip := Control.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.z_index = 4
	add_child(clip)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)

	var band := TextureRect.new()
	band.texture = tex
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(size.x * 0.5, size.y * 2.0)
	band.pivot_offset = band.size * 0.5
	band.rotation = deg_to_rad(20.0)
	band.position = Vector2(-size.x * 0.9, -size.y * 0.5)
	clip.add_child(band)

	var tween := create_tween()
	tween.tween_property(band, "position:x", size.x * 1.1, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(clip.queue_free)

# The global distance->grade windows, with no dependence on any instance state,
# so the Help screen's practice tiles can grade a real tap against the exact
# same boundaries without instancing a TimerSlot - which would drag EventBus,
# ScoreManager and AudioManager's tick-urgency registry in with it, the whole
# reason HelpDemoTile exists as a separate cosmetic replica in the first place.
# Sharing the function rather than the four constants is what stops the Help
# screen's idea of PERFECT from drifting away from the board's.
#
# GOLDEN and DECAY are deliberately NOT handled here: neither grades off a
# distance at all (GOLDEN is unconditionally PERFECT, DECAY reads its own tier
# windows off TimerData), so folding them in would mean taking a type and a
# TimerData as well and inventing a second grading entry point. Callers that
# can produce those types special-case them ahead of this, exactly as
# _grade_for_distance() below does.
#
# <= at every tier: the upper bound belongs to the stricter grade, so an
# exact 0.05 is PERFECT, not GOOD; an exact 0.30 is GOOD, not OKAY; etc.
static func grade_for_distance(distance: float) -> String:
	if distance <= PERFECT_MAX:
		return "PERFECT"
	elif distance <= GOOD_MAX:
		return "GOOD"
	elif distance <= OKAY_MAX:
		return "OKAY"
	elif distance <= MISS_MAX:
		return "MISS"
	return "FAIL"  # too early / too late - StageController ends the stage

# Rounded to the same 2 decimal places the digit display shows - see
# _stop_distance()'s own comment for why that rounding is load-bearing rather
# than cosmetic. Static for the same sharing reason as grade_for_distance():
# the rounding rule and the boundary checks only agree if both sides use both.
static func stop_distance_for(displayed_value: float) -> float:
	return snappedf(absf(displayed_value), 0.01)

# distance must already be rounded to 2 decimals (see stop()) so the boundary
# checks below agree with the displayed digits.
func _grade_for_distance(distance: float) -> String:
	# GOLDEN is a guaranteed PERFECT at any distance - it never FAILs on a click.
	if data.timer_type == TimerData.TimerType.GOLDEN:
		return "PERFECT"

	# DECAY ignores the distance argument entirely: its grade is whichever
	# ceiling tier the climb is currently in, against its own windows rather
	# than the global ones below. (The global windows span a single second in
	# total, so a Decay timer measured against them would always read FAIL.)
	if _is_decay():
		return DECAY_TIER_GRADES[_decay_tier(current_time)]

	return grade_for_distance(distance)

func _play_stop_flash(grade: String) -> void:
	var flash_tween := create_tween()
	flash_tween.set_parallel(true)
	match grade:
		"PERFECT":
			# Full bright flood on the accent color + a punchy center-pivot pop.
			_panel_style.bg_color = _accent
			_panel_style.shadow_size = 30
			flash_tween.tween_property(_panel_style, "bg_color", _base_bg, 0.35)
			flash_tween.tween_property(_panel_style, "shadow_size", _glow_size(), 0.35)
			_pop(1.3)
		"GOOD":
			_panel_style.bg_color = _accent.darkened(0.35)
			flash_tween.tween_property(_panel_style, "bg_color", _base_bg, 0.25)
			_pop(1.15)
		"OKAY":
			_panel_style.bg_color = _accent.darkened(0.6)
			flash_tween.tween_property(_panel_style, "bg_color", _base_bg, 0.2)
			_pop(1.06)
		"MISS":
			# Orange: bad (0 points, halves your multiplier) but not fatal.
			var miss := Color("ff8a3d")
			_panel_style.bg_color = miss
			flash_tween.tween_property(_panel_style, "bg_color", _base_bg, 0.3)
		_:
			# FAIL: hard red flood + red border - the stage is over.
			var fail := Color("ff2e5e")
			_panel_style.bg_color = fail
			_panel_style.border_color = fail
			_panel_style.shadow_color = Color(fail.r, fail.g, fail.b, 0.7)
			_panel_style.shadow_size = 30
			flash_tween.tween_property(_panel_style, "bg_color", _base_bg, 0.4)
			flash_tween.tween_property(_panel_style, "border_color", _accent, 0.4)
			flash_tween.tween_property(_panel_style, "shadow_size", _glow_size(), 0.4)

func _pop(scale_to: float) -> void:
	# "Reduce visual intensity" scales the pop amplitude down toward 1.0.
	var target := 1.0 + (scale_to - 1.0) * Settings.effect_scale()
	pivot_offset = size * 0.5  # scale from the center, not the top-left corner
	scale = Vector2.ONE
	var pop_tween := create_tween()
	pop_tween.tween_property(self, "scale", Vector2(target, target), 0.08)
	pop_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func apply_speedup(pct: float) -> void:
	speed_multiplier += pct
	speed_boost_stacks += 1
	_update_red_tint()

func _update_red_tint() -> void:
	# Persistent red overlay, opacity growing with each stack (the speedup is
	# permanent, so this never fades) - doubles as "this timer is worth more now".
	if _red_overlay != null:
		_red_overlay.color.a = minf(0.15 * speed_boost_stacks, 0.75)

func apply_pause(duration: float) -> void:
	paused_for += duration
	# Temporary blue overlay that fades out over the (accumulated) pause duration.
	if _blue_overlay != null:
		if _blue_tween != null and _blue_tween.is_valid():
			_blue_tween.kill()
		_blue_overlay.color.a = 0.45
		_blue_tween = create_tween()
		_blue_tween.tween_property(_blue_overlay, "color:a", 0.0, paused_for)
	_set_frost(true)

# Blue's pause is already felt in motion (the digits stop updating in _process);
# this adds the "frozen solid" read on top of the existing tint.
func _set_frost(on: bool) -> void:
	if _panel_style == null:
		return
	_frosted = on
	var tween := create_tween()
	tween.set_parallel(true)
	if on:
		tween.tween_property(_panel_style, "border_color", FROST_COLOR, 0.12)
		tween.tween_property(_panel_style, "shadow_size", GLOW_FROST, 0.12)
		tween.tween_property(digit_label, "modulate:a", 0.55, 0.12)
	else:
		# Same lock as the Decay tier tween above, for the same reason - this
		# tween's own target property, shadow_size, is otherwise being
		# overwritten every frame by the urgency writer the instant _frosted
		# flips back to false (which happens synchronously, above, before this
		# tween even starts).
		_panel_transition_lock = true
		tween.tween_property(_panel_style, "border_color", _accent, 0.25)
		tween.tween_property(_panel_style, "shadow_size", _glow_size(), 0.25)
		tween.tween_property(digit_label, "modulate:a", 1.0, 0.25)
		tween.finished.connect(func(): _panel_transition_lock = false)

func _on_heat_changed(heat: float) -> void:
	_heat = heat
	# Don't fight the stop flash, the frost tween, a Decay tier tween, or the
	# per-frame urgency writer's own claim on these same properties.
	if _panel_style == null or stopped or _frosted or _panel_transition_lock:
		return
	_panel_style.shadow_size = _glow_size()
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b, _glow_alpha())

# Every path that restores the glow (frost clearing, heat changes, the stop
# flash tweening back) routes through these two, so scaling Blackout down here
# keeps it dimmed in all of them rather than only on spawn. Also where the
# zero-proximity urgency glow's own contribution lives - see the constants
# block above for the full explanation of what's being added and why.
#
# The urgency bonus is added AFTER _type_glow_scale() multiplies, deliberately
# NOT folded into that same multiply - so Blackout's own recede treatment
# (BLACKOUT_GLOW_SCALE dimming the heat-driven baseline) never dims the
# urgency signal riding on top of it. Outside its own blackout_duration window,
# a Blackout timer's panel is stylistically recessive but this cue still needs
# to read at full clarity - muting it there would undermine the exact problem
# it exists to solve on a panel that's already the hardest of the six types to
# spot on a busy board.
func _glow_size() -> int:
	var size_px := GLOW_BASE + GLOW_HEAT_BONUS * _heat
	size_px *= _type_glow_scale()
	if _is_decay():
		size_px *= _decay_urgency_glow_scale()
	else:
		size_px += URGENCY_GLOW_SIZE_BONUS * _urgency_bonus_scale()
	return int(round(size_px))

func _glow_alpha() -> float:
	var a := lerpf(0.5, 0.85, _heat) * _type_glow_scale()
	if _is_decay():
		a *= _decay_urgency_glow_scale()
	else:
		a += URGENCY_ALPHA_BONUS * _urgency_bonus_scale()
	# Clamped: tier 0's >1.0 scale, plus a maxed-out urgency bonus, would
	# otherwise push alpha past opaque.
	return clampf(a, 0.0, 1.0)

# The border-width channel, separate from _glow_size()/_glow_alpha() since it's
# additive-only (no existing per-type baseline to compose with the way the
# shadow already has) and Decay deliberately opts out of it - see
# DECAY_URGENCY_PULSE_DEPTH's own comment for why.
func _border_width() -> int:
	if _is_decay():
		return 3
	return int(round(3.0 + URGENCY_BORDER_WIDTH_BONUS * _urgency_bonus_scale()))

# Blackout recedes, Decay blazes and fades; everything else sits at 1.0.
func _type_glow_scale() -> float:
	if _is_blackout_type():
		return BLACKOUT_GLOW_SCALE
	if _is_decay():
		# _decay_tier_shown is -1 until the first _process frame, which includes
		# the initial _apply_type_color() during setup() - tier 0 is the right
		# answer there, since that's the state it's about to be in.
		var t := maxi(_decay_tier_shown, 0)
		return DECAY_GLOW_SCALE[mini(t, DECAY_GLOW_SCALE.size() - 1)]
	return 1.0

# --- Zero-proximity urgency glow --------------------------------------------
# See the constants block near the top of the file for the full design
# rationale; this section is just the machinery.

# Linear, not ScoreManager.base_points()'s quadratic curve - see the doc
# comment above the constants block for why a glance-able "how close" cue
# wants an even ramp rather than the score curve's back-loaded one. 1.0 at
# distance 0, sloping evenly down to 0.0 at |distance| == max_distance either
# side of zero. Defaults to 1.0 (the FAIL boundary) rather than
# URGENCY_RANGE - Decay's own call site relies on that default, since its
# input is already normalised to its own 0..1 window; only the four countdown
# types pass URGENCY_RANGE explicitly.
static func urgency_of(distance: float, max_distance: float = 1.0) -> float:
	return 1.0 - clampf(absf(distance) / maxf(max_distance, 0.0001), 0.0, 1.0)

# Recomputes _urgency/_urgency_pulse from whatever distance-like quantity this
# frame's caller has (current_time itself for the four countdown types, or
# Decay's elapsed/window ratio - see the two call sites in _process()/
# _process_decay()). Never called for GOLDEN (see _process_golden(), which has
# no distance-to-zero to speak of and never reaches this), which is the whole
# reason Golden needs no special-casing in the render functions above:
# _urgency_pulse simply stays at its initial 0.0 forever, contributing nothing.
#
# Not called at all while paused_for > 0.0 either (the general Blue-freeze
# early-return in _process() sits ahead of every call site below) - so a
# frozen timer's urgency glow holds at exactly whatever it was the instant the
# freeze started, for free, without this function needing to know freeze state
# exists. `distance_like` itself is also frozen for the same reason: it's
# current_time, which _process() already isn't advancing while paused.
#
# `past_zero` is the caller's call, not derived from distance_like's sign in
# here - current_time is genuinely signed for the four countdown types (so
# callers just pass `current_time <= 0.0` straight through), but Decay is never
# eligible at all (always false) and HelpDemoTile.play_overrun() represents
# "already past zero" as a positive MAGNITUDE rather than a signed value, which
# a sign check here could never read correctly. Simpler for every call site to
# just say what style it wants than to keep the sign convention consistent
# everywhere that might ever call this.
func _update_urgency(delta: float, distance_like: float, past_zero: bool,
		max_distance: float = 1.0) -> void:
	_urgency = urgency_of(distance_like, max_distance)

	# A style swap resets phase so the flicker never inherits a breath's
	# position mid-cycle - it should read as a new pattern starting fresh, not
	# a breath that suddenly got choppy.
	if past_zero != _urgency_past_zero:
		_urgency_past_zero = past_zero
		_urgency_phase = 0.0

	var hz: float = lerpf(URGENCY_FLICKER_HZ_MIN, URGENCY_FLICKER_HZ_MAX, _urgency) if past_zero \
		else lerpf(URGENCY_BREATH_HZ_MIN, URGENCY_BREATH_HZ_MAX, _urgency)
	_urgency_phase += delta * hz
	_urgency_envelope = _pulse_envelope(_urgency_phase, past_zero)
	_urgency_pulse = _urgency * lerpf(URGENCY_PULSE_FLOOR, 1.0, _urgency_envelope)

# 0..1. Breathing is a plain sine - slow, organic, reads as anticipation.
# Flicker sharpens a rectified sine toward its peaks (the pow() spends more of
# the cycle near 1.0 and snaps through the trough quickly) rather than
# smoothing through it, which is what makes it read as a tremor/flicker
# instead of a faster breath - a genuinely different character, not just a
# sped-up version of the same wave.
func _pulse_envelope(phase: float, flicker: bool) -> float:
	if flicker:
		return pow(absf(sin(phase * TAU * 0.5)), 0.35)
	return 0.5 + 0.5 * sin(phase * TAU)

# The fraction of URGENCY_*_BONUS that should actually land on the panel this
# frame: the live pulse, scaled by Blackout's suppression/mute (1.0 for every
# other type - see _urgency_visual_scale()) and by "Reduce screen effects".
#
# Unfloored (unlike Overclock/Shield's own effect_scale() use in Juice.gd,
# which is deliberately floored at 0.7 because those edge treatments are the
# ONLY indication that state is active). This glow is a peripheral-vision AID
# for scanning a busy board, not the sole source of the information it
# carries - the digit readout is, and reduce-intensity never touches that - so
# it's free to fade all the way down to Settings.REDUCED_EFFECT_SCALE like the
# Endless low-life vignette does, rather than being floored like a primary
# state tell.
func _urgency_bonus_scale() -> float:
	return _urgency_pulse * _urgency_visual_scale() * Settings.effect_scale()

# 1.0 for every type except Blackout inside its own blackout_duration window,
# where it's either fully suppressed (the default) or muted - see
# BLACKOUT_URGENCY_SUPPRESSED's own comment for why this is a one-constant
# decision point rather than a settled default.
func _urgency_visual_scale() -> float:
	if _is_blackout_type() and _in_blackout():
		return 0.0 if BLACKOUT_URGENCY_SUPPRESSED else BLACKOUT_URGENCY_SCALE
	return 1.0

# Decay's own multiplicative modulation - see DECAY_URGENCY_PULSE_DEPTH's
# comment. _urgency_envelope (0..1) is recentred around 0 here so the swing
# genuinely breathes both brighter AND dimmer than the tier's own baseline,
# rather than only ever adding shine on top of it; weighted by _urgency itself
# so the swing narrows to near-nothing as the ceiling burns down, matching the
# same calming-down direction DECAY_GLOW_SCALE already dims in.
func _decay_urgency_glow_scale() -> float:
	var swing := DECAY_URGENCY_PULSE_DEPTH * _urgency * (_urgency_envelope - 0.5) * 2.0
	return 1.0 + swing * Settings.effect_scale()

# Applies this frame's computed glow to the panel. Guarded exactly like
# _on_heat_changed() - stopped/_frosted/_panel_transition_lock all mean
# something else already owns these properties right now.
func _apply_urgency_to_panel() -> void:
	if _panel_style == null or stopped or _frosted or _panel_transition_lock:
		return
	_panel_style.shadow_size = _glow_size()
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b, _glow_alpha())
	if not _is_decay():
		_panel_style.set_border_width_all(_border_width())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click_global_pos = event.global_position
		_has_click_pos = true
		stop()
