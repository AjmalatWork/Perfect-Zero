extends Panel
class_name HelpDemoTile

# One live, tappable timer in the Help screen's legend - a cosmetic replica of a
# TimerSlot, deliberately NOT a real one.
#
# A real TimerSlot emits timer_stopped on EventBus, registers tick urgency with
# AudioManager, reads Juice's freeze/heat state and resolves through
# ScoreManager. Instancing those here would have a screen that only illustrates
# the rules quietly talking to the systems that enforce them - a Help screen
# could bank points or leave audio state behind. This owns nothing but its own
# digits, so there is no path from looking at the legend to changing the game.
#
# The visual treatment (dark accent-tinted fill, bright border, glow shadow,
# outlined digits) mirrors _apply_type_color() so the legend and the board read
# as the same object.
#
# Nothing here runs on its own - a tile sits idle at a static digit until
# HelpScreen calls one of the play_*() coroutines below to run a scripted
# demonstration. Six tiles all ticking down simultaneously (the first version
# of this screen) was reported as making it hard to tell which one to even
# look at; a single focused animation per tap is the fix.

signal tapped(tile: HelpDemoTile)

# Golden's digit blur, same idiom as TimerSlot._process_golden - random digits
# rather than a sequential counter, which reads as blur instead of counting.
const GOLDEN_BLUR_SPEED := 28.0

# --- Zero-proximity urgency glow --------------------------------------------
# Mirrors TimerSlot's own version of this feature (see that file's constants
# block for the full design rationale - formula, zero-crossing pulse-style
# swap, per-type handling) so the Help screen teaches the same visual language
# the real board uses rather than a lookalike with its own separately-tuned
# feel. Values are scaled down from TimerSlot's own (18/0.35/3.0) for this
# tile's smaller footprint (128-200px here vs. the board's own cell size) -
# proportionally similar strength, not an unrelated one.
const URGENCY_GLOW_SIZE_BONUS := 12.0
const URGENCY_ALPHA_BONUS := 0.35
const URGENCY_BORDER_WIDTH_BONUS := 2.0
const URGENCY_BREATH_HZ_MIN := 0.4
const URGENCY_BREATH_HZ_MAX := 2.2
const URGENCY_FLICKER_HZ_MIN := 5.0
const URGENCY_FLICKER_HZ_MAX := 11.0
const URGENCY_PULSE_FLOOR := 0.4
const DECAY_URGENCY_PULSE_DEPTH := 0.16

# The project's base text fill. Names are drawn in it with the type accent as
# outline - the same treatment the digits already use - rather than painting
# the accent straight onto the glyph. TimerTypeInfo.gd warns about exactly this
# hazard: several accents (Blackout's #5a5f70 above all) stop being legible as
# raw font_color on a near-black fill. Measured on-device, Blackout's name came
# out at 3.19:1 against its own panel, under the 4.5:1 AA floor; outlining
# instead puts every type at full contrast without touching the deliberately
# recessive panel colours.
const TEXT_FILL := Color("dfe3ee")

# configure()'s own baseline panel look, named so the urgency glow below can
# compose with it instead of assuming a duplicated literal.
const BASE_SHADOW_SIZE := 10.0
const BASE_SHADOW_ALPHA := 0.30
const BASE_BORDER_WIDTH := 3.0
# set_selected()'s own ring look, named for the same reason - the urgency glow
# still shows through while a tile is selected (composing with this elevated
# baseline instead), rather than either fighting it or going dark.
const SELECTED_SHADOW_SIZE := 20.0
const SELECTED_SHADOW_ALPHA := 0.55
const SELECTED_BORDER_WIDTH := 5.0

# --- Tap affordance -----------------------------------------------------------
# A practice tile looks identical to a scripted one while it runs, so nothing
# about it says the countdown is waiting on the player rather than about to
# resolve itself. This is that tell: a small pulsing "TAP" under the digit, up
# only while a run is genuinely stoppable, so it never promises interactivity a
# scripted demo won't honour.
#
# Sits low rather than centred because the digit label fills the whole tile and
# centres in it - at HelpScreen.TIMER_DIGIT_RATIO (0.27 of tile height) the
# glyphs occupy roughly the middle third, leaving the bottom quarter clear.
# Text, not an icon: this project's SVG rules forbid <text> in icons and the
# glyph would have to be hand-drawn, for a label three characters long.
const TAP_HINT_TEXT := "TAP"
const TAP_HINT_TOP_RATIO := 0.74
const TAP_HINT_HEIGHT_RATIO := 0.20
const TAP_HINT_FONT_RATIO := 0.6      # of this tile's own name font
const TAP_HINT_PULSE_SEC := 0.7
const TAP_HINT_ALPHA_MIN := 0.35
const TAP_HINT_ALPHA_MAX := 1.0

var timer_type: int = TimerData.TimerType.NORMAL
var value: float = 0.0

# Bystander/preview tiles are scenery, not choices. Set before the tile enters
# the tree; _ready applies it, because assigning mouse_filter directly at the
# call site would just be overwritten there.
var interactive: bool = true

var _accent: Color
var _base_bg: Color
var _panel_style: StyleBoxFlat
var _digit: Label
var _name_label: Label
var _selected: bool = false
var _dimmed: bool = false

# Permanent (Red) vs temporary (Blue) rate modifiers on whatever play_countdown
# loop is currently running - see react_speedup_permanent()/react_freeze().
var _rate_multiplier: float = 1.0
var _paused: bool = false

# Bumped by idle()/every new play_*() call so a stale coroutine (the tile got
# tapped again, or the screen rebuilt mid-animation) notices and stops touching
# nodes that have moved on to a new sequence - same pattern as EndlessEndScreen's
# _reveal_token.
var _play_token: int = 0

var _grade_sign: Label
var _grade_sign_tween: Tween
var _pop_tween: Tween
var _dim_tween: Tween

# --- Zero-proximity urgency glow state --------------------------------------
# Mirrors TimerSlot's own fields exactly - see that file's constants block for
# the full design rationale. This tile drives the SAME formula off its own
# local `value`, never through EventBus/AudioManager's tick-urgency ranking or
# any other live-gameplay path, keeping the cosmetic-only isolation every other
# system on this tile already has intact.
var _urgency: float = 0.0
var _urgency_pulse: float = 0.0
var _urgency_envelope: float = 0.0
var _urgency_phase: float = 0.0
var _urgency_past_zero: bool = false

# --- Tap capture (practice runs only) ----------------------------------------
# True only while a run_tappable_*() coroutine is in flight. Outside one, taps
# are purely a "the player picked this tile" notification for the host and this
# whole block stays inert, so the scripted play_*() demos are unaffected.
var _awaiting_tap: bool = false
var _tap_pressed: bool = false
var _tap_consumed: bool = false
# `value` sampled at the instant the finger went DOWN, which is when the player
# actually committed to their timing.
#
# A run only RESOLVES on release, so that a swipe starting on a tile can still
# be classified as a swipe rather than stopping the timer under it (see
# _gui_input's own note on why this tile reports taps on release at all). But
# grading an ~80ms-long tap off the release instant would score every practice
# stop that much later than the identical tap on the real board, where
# TimerSlot._gui_input() resolves on press. The PERFECT window is 0.05s wide -
# so that gap is not a rounding difference, it is wider than the window being
# practised. Sampling on press and resolving on release gets both properties.
var _tap_value: float = 0.0

# Whether the most recently finished run ended on a player tap rather than on
# running the clock out. Hosts pick their replay delay from this: "I never got
# to it" and "I stopped it and got a grade" are different beats, and the grade
# alone cannot separate them - a late enough tap grades FAIL too, exactly like
# never tapping at all.
var last_run_was_tapped: bool = false

var _tap_hint: Label
var _tap_hint_tween: Tween
var _flash_tween: Tween

func configure(p_type: int, display_name: String, digit_size: int, name_size: int) -> void:
	timer_type = p_type
	_accent = TimerTypeInfo.color_of(p_type)
	# Blackout gets the same deeper fill the real board gives it, so it still
	# reads as a hole rather than just another grey panel.
	var darken := 0.94 if p_type == TimerData.TimerType.BLACKOUT else 0.86
	_base_bg = _accent.darkened(darken)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = _base_bg
	_panel_style.set_corner_radius_all(14)
	_panel_style.set_border_width_all(int(BASE_BORDER_WIDTH))
	_panel_style.border_color = _accent
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b, BASE_SHADOW_ALPHA)
	_panel_style.shadow_size = int(BASE_SHADOW_SIZE)
	_panel_style.shadow_offset = Vector2.ZERO
	add_theme_stylebox_override("panel", _panel_style)

	_digit = Label.new()
	_digit.add_theme_font_size_override("font_size", digit_size)
	_digit.add_theme_color_override("font_color", Color.WHITE)
	_digit.add_theme_color_override("font_outline_color", _accent)
	_digit.add_theme_constant_override("outline_size", 6)
	_digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_digit)

	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.add_theme_font_size_override("font_size", name_size)
	_name_label.add_theme_color_override("font_color", TEXT_FILL)
	_name_label.add_theme_color_override("font_outline_color", _accent)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_name_label)

	_tap_hint = Label.new()
	_tap_hint.text = TAP_HINT_TEXT
	# Floored so the smallest tile still clears the project's readability bar
	# rather than scaling this into an illegible smudge.
	_tap_hint.add_theme_font_size_override("font_size",
		maxi(roundi(name_size * TAP_HINT_FONT_RATIO), 12))
	_tap_hint.add_theme_color_override("font_color", TEXT_FILL)
	_tap_hint.add_theme_color_override("font_outline_color", _accent)
	_tap_hint.add_theme_constant_override("outline_size", 5)
	_tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tap_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_hint.visible = false
	add_child(_tap_hint)

	_layout_children()
	_set_digit_mode(false)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_children)

# Digit and name both fill the whole tile, centred - only one is ever visible
# at a time (see _set_digit_mode), so they don't need to share the tile the
# way a permanently-visible pair would.
#
# Deliberately measured off custom_minimum_size, not `size`: configure() calls
# this once immediately, before the tile has been added to a container (its own
# real `size` is still (0,0) at that point), which used to leave the name label
# pinned to a degenerate top-left rect for the tile's entire life - the
# `resized` signal connected in _ready() should in principle have re-run this
# once the container assigned a real size, but empirically it did not (name and
# digit overlapping at the top-left on-device is exactly what a stale
# size=(0,0) layout looks like). custom_minimum_size is known correctly at
# configure() time and never changes afterwards (nothing in this screen grows a
# tile past what it asks for), so building off it sidesteps the timing question
# entirely instead of chasing exactly why the signal didn't fire.
func _layout_children() -> void:
	if _digit == null:
		return
	var s: Vector2 = custom_minimum_size
	_digit.position = Vector2.ZERO
	_digit.size = s
	_name_label.position = Vector2.ZERO
	_name_label.size = s
	if _tap_hint != null:
		_tap_hint.position = Vector2(0.0, s.y * TAP_HINT_TOP_RATIO)
		_tap_hint.size = Vector2(s.x, s.y * TAP_HINT_HEIGHT_RATIO)

# Toggles between the two mutually-exclusive faces of a tile: its name (idle,
# nothing running yet) and its live digit (a play_*() sequence is active).
# `.visible` rather than modulate/opacity - neither label ever needs to be
# partially shown, and a plain bool skips a tween for a swap that happens
# exactly when the countdown already gives the eye something else to follow.
func _set_digit_mode(on: bool) -> void:
	if _digit != null:
		_digit.visible = on
	if _name_label != null:
		_name_label.visible = not on

# Emitted on release rather than press, matching Button's own behaviour - the
# swipe handler on HelpScreen classifies the gesture from the motion events in
# between, and a press-time signal would fire before it could tell a tap from
# the start of a swipe.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		# Press only samples the timing - see _tap_value. Deliberately does not
		# emit `tapped`, preserving this tile's release-reports-a-tap contract.
		if _awaiting_tap:
			_tap_pressed = true
			_tap_value = value
		return
	# _tap_pressed gates this so a run that STARTS with a finger already down
	# can't be resolved by that finger coming up: without it the release would
	# grade against a _tap_value belonging to no run at all (a stale 0.0, which
	# reads as a free PERFECT).
	if _awaiting_tap and _tap_pressed and not _tap_consumed:
		_tap_consumed = true
	tapped.emit(self)

# --- Idle state -------------------------------------------------------------

# Resets to a static, non-animating look - name only, no digit. A running
# number on every tile before anything is even tapped was reported as making
# it hard to tell which one to look at in the first place, so nothing here
# shows a value until its own play_*() sequence actually starts it counting.
# Called on build and whenever a sequence finishes. Cancels any in-flight
# coroutine via the token bump, and any in-flight tween via kill(), so a tap
# that interrupts a running demo can't leave a stray callback writing to the
# tile after it's been reset.
func idle() -> void:
	_play_token += 1
	_clear_tap_capture()
	_rate_multiplier = 1.0
	_paused = false
	value = 0.0
	if _digit != null:
		_digit.text = ""
		_digit.modulate.a = 1.0
	_set_digit_mode(false)
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _grade_sign_tween != null and _grade_sign_tween.is_valid():
		_grade_sign_tween.kill()
	if _grade_sign != null and is_instance_valid(_grade_sign):
		_grade_sign.queue_free()
	scale = Vector2.ONE
	set_selected(false)

# Stops whatever play_*() coroutine is currently running without resetting the
# tile's look - used when the caller needs to freeze the tile exactly where it
# is (Nuke force-resolving whatever value each preview timer happens to be
# showing) rather than snap it back to idle first.
func cancel_playback() -> void:
	_play_token += 1
	_clear_tap_capture()

# --- Presence (bystander/preview tiles that shouldn't exist until the timer
# they demonstrate is actually tapped) ---------------------------------------

# A Normal timer sitting on screen from the moment the page opens - before Red,
# Blue, a powerup, or a grade has ever been tapped - has nothing to say yet;
# it's scenery for a demo that hasn't started. `present(false)` keeps the
# tile's layout slot reserved (so the grid/row around it doesn't reflow) while
# making it invisible and untappable, the same "reserved lane" trick
# StageResultScreen's badge uses.
func set_present(on: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if (not on or not interactive) \
		else Control.MOUSE_FILTER_STOP
	# modulate.a, not `visible` - GridContainer/HBoxContainer both skip
	# invisible children when sizing, which would collapse the reserved slot
	# and shove its siblings sideways every time a demo starts or ends.
	#
	# The very first call happens during _build_type_group()/etc., while this
	# tile is still part of an off-tree subtree being assembled (the whole page
	# isn't attached to _track until _build() finishes) - create_tween() would
	# error on a node outside the SceneTree, so that call sets modulate directly
	# instead of animating. Every later call, once the tile is live, animates.
	if not is_inside_tree():
		modulate.a = 1.0 if on else 0.0
		return
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.15)

# --- Dimming (driven by HelpScreen while another tile's demo is playing) ----

func set_dimmed(on: bool) -> void:
	if _dimmed == on:
		return
	_dimmed = on
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate:a", 0.25 if on else 1.0, 0.18)
	# Dimmed tiles can't be tapped mid-demo, same as a disabled button - but a
	# non-interactive tile (a bystander) was never tappable anyway, so this must
	# not accidentally make one STOP-filtered by clearing `on` at the wrong time.
	mouse_filter = Control.MOUSE_FILTER_IGNORE if (on or not interactive) \
		else Control.MOUSE_FILTER_STOP

# --- Playback primitives -----------------------------------------------------
# Each of these is a coroutine HelpScreen awaits to sequence a full demo. All
# of them poll `_play_token` every frame so a new idle()/play_*() call (the
# tile got re-tapped, or the screen rebuilt) makes any still-running one bail
# instead of fighting the new state.

# Counts `value` down from `start` to `stop_at` (default a clean 0.00) in real
# seconds, honouring the permanent Red rate boost and the temporary Blue pause.
# `blackout_at`, if >= 0, blanks the digits to "??.??" once value drops to or
# below it - the real TimerSlot's own threshold check, not an approximation.
# Ticks once a second exactly like TimerSlot._process does, pitching up as it
# nears `stop_at`. A Blackout tile (blackout_at >= 0) uses its real timbre for
# its WHOLE life, not just once digits go dark - matching TimerSlot's own
# comment on this exact point: the sound is there to train the player to
# listen before they need to, so it can't only start once the visual is gone.
func play_countdown(start: float, stop_at: float = 0.0, blackout_at: float = -1.0) -> void:
	var token := _play_token
	value = start
	_set_digit_mode(true)
	_render_countdown(blackout_at)
	var tick_accum := 0.0
	while value > stop_at:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return
		if _paused:
			continue
		var dt := get_process_delta_time()
		value = maxf(value - dt * _rate_multiplier, stop_at)
		_render_countdown(blackout_at)
		# `value` mirrors TimerSlot.current_time exactly for this coroutine - a
		# signed distance-from-zero, clamped at stop_at rather than continuing
		# negative (play_overrun below is the coroutine for that territory) - so
		# `value <= 0.0` is the correct flicker-style trigger even though it
		# practically only ever fires on this loop's very last frame.
		_update_urgency(dt, value, value <= 0.0, TimerSlot.URGENCY_RANGE)
		_apply_urgency_to_panel(blackout_at >= 0.0 and value <= blackout_at)
		tick_accum += dt
		if tick_accum >= 1.0:
			tick_accum = 0.0
			if blackout_at >= 0.0:
				AudioManager.play_blackout_tick(get_instance_id())
			else:
				var progress: float = clampf(1.0 - value / maxf(start, 0.0001), 0.0, 1.0)
				AudioManager.play_tick(lerpf(1.0, 2.5, progress), get_instance_id())

func _render_countdown(blackout_at: float) -> void:
	if _digit == null:
		return
	_digit.text = "??.??" if (blackout_at >= 0.0 and value <= blackout_at) else "%.2f" % value

# Counts `value` up from 0.00 to `limit`, which is what a timer nobody clicked
# actually does: it does not stop at zero, it overruns, and the grade is read off
# how far past zero it got. Distinct from play_decay_climb - no tier colours, the
# tile keeps its own accent, because this is an ordinary timer running out rather
# than a Decay working through its windows.
#
# The Shield demo needs this: a FAIL is a stop more than TimerSlot.MISS_MAX from
# zero, so the demo that showed one frozen at "0.00" was displaying a distance
# that actually grades PERFECT.
func play_overrun(limit: float) -> void:
	var token := _play_token
	value = 0.0
	_set_digit_mode(true)
	var tick_accum := 0.0
	while value < limit:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return
		if _paused:
			continue
		var dt := get_process_delta_time()
		value = minf(value + dt * _rate_multiplier, limit)
		if _digit != null:
			_digit.text = "%.2f" % value
		# Always the flicker/past-zero style, hardcoded rather than derived from
		# value's sign: this coroutine ONLY EVER represents a timer that's
		# already run past its zero moment (see the doc comment above), and
		# `value` here is a positive MAGNITUDE of time-past-zero rather than a
		# signed current_time - a sign check would never trigger past frame one.
		_update_urgency(dt, value, true, TimerSlot.URGENCY_RANGE)
		_apply_urgency_to_panel()
		tick_accum += dt
		if tick_accum >= 1.0:
			tick_accum = 0.0
			# Pinned at the top of the pitch ramp play_countdown climbs toward -
			# past zero there is no "approaching" left to convey, only urgency.
			AudioManager.play_tick(2.5, get_instance_id())

# Counts `value` up from 0.00, stepping the panel's border/fill/glow through
# TimerTypeInfo's four Decay tier colours at `perfect_end`/`good_end`/
# `okay_end`, and stops the instant it reaches `miss_end` - the real Decay's
# own ceiling, at which point it auto-resolves as a MISS (see TimerSlot -
# Decay can never FAIL or cost a life, a locked-in design rule, not an
# oversight, so this coroutine has no FAIL exit at all).
func play_decay_climb(perfect_end: float, good_end: float, okay_end: float, miss_end: float) -> void:
	var token := _play_token
	value = 0.0
	_set_digit_mode(true)
	var shown_tier := -1
	var tick_accum := 0.0
	while value < miss_end:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return
		if not _paused:
			var dt := get_process_delta_time()
			value = minf(value + dt * _rate_multiplier, miss_end)
			tick_accum += dt
			if tick_accum >= 1.0:
				tick_accum = 0.0
				var progress: float = clampf(value / maxf(miss_end, 0.0001), 0.0, 1.0)
				AudioManager.play_tick(lerpf(1.0, 2.5, progress), get_instance_id())
			# Same input TimerSlot._process_decay() feeds its own urgency update:
			# elapsed time normalised to the full window (0 at spawn, 1 at the
			# ceiling burning out), not |distance| - Decay has no zero to
			# approach. Inside the `not _paused` guard so a Blue-freeze reaction
			# on this tile holds the glow exactly where it was, same as the real
			# board.
			_update_urgency(dt, clampf(value / maxf(miss_end, 0.0001), 0.0, 1.0), false)
			_apply_urgency_to_panel()
		if _digit != null:
			_digit.text = "%.2f" % value
		var tier := _decay_tier_for(value, perfect_end, good_end, okay_end)
		if tier != shown_tier:
			shown_tier = tier
			var tier_color := TimerTypeInfo.decay_tier_color(tier)
			_set_border(tier_color)
			if _panel_style != null:
				_panel_style.bg_color = tier_color.darkened(0.86)
			# _accent has to track the tier too, matching
			# TimerSlot._apply_decay_tier()'s own reassignment - the urgency
			# glow above reads _accent for its shadow colour's RGB, and without
			# this it would stay frozen at configure()'s tier-0 hue for the
			# whole climb while the border correctly steps through all four.
			_accent = tier_color

func _decay_tier_for(v: float, perfect_end: float, good_end: float, okay_end: float) -> int:
	if v <= perfect_end:
		return 0
	if v <= good_end:
		return 1
	if v <= okay_end:
		return 2
	return 3

# --- Zero-proximity urgency glow --------------------------------------------
# See TimerSlot's own constants block for the full design rationale - this is
# the same machinery, called from this tile's own play_countdown()/
# play_overrun()/play_decay_climb() loops rather than from play_blur()
# (GOLDEN gets no effect - see the brief), keeping this tile's isolation from
# the real gameplay event bus intact: everything here reads only `value`,
# `timer_type` and `_selected`, all local to the tile itself.

func _update_urgency(delta: float, distance_like: float, past_zero: bool,
		max_distance: float = 1.0) -> void:
	_urgency = TimerSlot.urgency_of(distance_like, max_distance)
	if past_zero != _urgency_past_zero:
		_urgency_past_zero = past_zero
		_urgency_phase = 0.0
	var hz: float = lerpf(URGENCY_FLICKER_HZ_MIN, URGENCY_FLICKER_HZ_MAX, _urgency) if past_zero \
		else lerpf(URGENCY_BREATH_HZ_MIN, URGENCY_BREATH_HZ_MAX, _urgency)
	_urgency_phase += delta * hz
	_urgency_envelope = _pulse_envelope(_urgency_phase, past_zero)
	_urgency_pulse = _urgency * lerpf(URGENCY_PULSE_FLOOR, 1.0, _urgency_envelope)

func _pulse_envelope(phase: float, flicker: bool) -> float:
	if flicker:
		return pow(absf(sin(phase * TAU * 0.5)), 0.35)
	return 0.5 + 0.5 * sin(phase * TAU)

# One shared toggle with the real board - TimerSlot.BLACKOUT_URGENCY_SUPPRESSED -
# so the Help screen's Blackout demo and the actual game always agree on which
# version is currently being tested, rather than needing a second flag flipped
# in lockstep.
func _urgency_visual_scale(in_blackout_window: bool) -> float:
	if in_blackout_window:
		return 0.0 if TimerSlot.BLACKOUT_URGENCY_SUPPRESSED else TimerSlot.BLACKOUT_URGENCY_SCALE
	return 1.0

# Same centred-swing modulation as TimerSlot._decay_urgency_glow_scale() -
# see that function's comment for why _urgency_envelope is recentred here
# rather than used directly.
func _decay_urgency_glow_scale() -> float:
	var swing := DECAY_URGENCY_PULSE_DEPTH * _urgency * (_urgency_envelope - 0.5) * 2.0
	return 1.0 + swing * Settings.effect_scale()

# Applies this frame's computed glow to the panel, composing with whichever
# baseline currently applies (the plain idle look, or set_selected()'s ring)
# rather than assuming one or the other - a tile is USUALLY selected for the
# whole time it's also playing a demo (tapping one is what starts both), so
# skipping the glow entirely while selected would mean it's almost never
# actually visible during the one moment a player is watching it play out.
# Border width is the one property left alone while selected - the ring's
# fixed width is a deliberate, separate "this tile is currently tapped"
# signal, and pulsing it too would make the ring jitter instead of hold.
func _apply_urgency_to_panel(in_blackout_window: bool = false) -> void:
	if _panel_style == null:
		return
	var base_size: float = SELECTED_SHADOW_SIZE if _selected else BASE_SHADOW_SIZE
	var base_alpha: float = SELECTED_SHADOW_ALPHA if _selected else BASE_SHADOW_ALPHA

	if timer_type == TimerData.TimerType.DECAY:
		var scale := _decay_urgency_glow_scale()
		_panel_style.shadow_size = int(round(base_size * scale))
		_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b,
			clampf(base_alpha * scale, 0.0, 1.0))
		return

	var bonus := _urgency_pulse * Settings.effect_scale() * _urgency_visual_scale(in_blackout_window)
	_panel_style.shadow_size = int(round(base_size + URGENCY_GLOW_SIZE_BONUS * bonus))
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b,
		clampf(base_alpha + URGENCY_ALPHA_BONUS * bonus, 0.0, 1.0))
	if not _selected:
		_panel_style.set_border_width_all(
			int(round(BASE_BORDER_WIDTH + URGENCY_BORDER_WIDTH_BONUS * bonus)))

# Golden's digits never count - they just churn - so this is time-based, not
# value-based, matching TimerSlot._process_golden exactly.
func play_blur(duration: float) -> void:
	var token := _play_token
	_set_digit_mode(true)
	var elapsed := 0.0
	var interval := 1.0 / GOLDEN_BLUR_SPEED
	var accumulator := 0.0
	var digit := 0
	while elapsed < duration:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return
		var dt := get_process_delta_time()
		elapsed += dt
		accumulator += dt
		while accumulator >= interval:
			accumulator -= interval
			digit = randi() % 10
		if _digit != null:
			_digit.text = "0.0%d" % digit

# --- Tappable practice runs ---------------------------------------------------
# The Help screen's practice mode. Where the scripted play_*() demos above tap
# themselves at a pre-chosen moment to illustrate a rule, these run a real
# countdown that the PLAYER stops, graded against TimerSlot's own windows via
# the shared TimerSlot.grade_for_distance()/stop_distance_for() statics - so
# practising a PERFECT here is practising the same 0.05s the board asks for,
# not a lookalike with its own boundaries.
#
# Practice mode does NOT make every tile tick at once. The header's rule still
# holds: a tile sits idle showing its name until it is tapped, that first tap
# starts its run, and only then is it live and stoppable. Everything else on
# the page stays idle. So the fix recorded up there - one focused animation per
# tap, after six simultaneous ones were reported as making it hard to tell
# where to even look - survives practice mode rather than being undone by it.
# The only thing that changes is who stops the running tile: the player, over
# and over, instead of a script tapping it once at a pre-chosen moment.
#
# That the STARTING tap cannot also resolve the run it just started falls out
# of the _tap_pressed guard for free: at the moment that tap's release lands,
# _awaiting_tap is still false (no run yet), so nothing is consumed, and
# _begin_tappable_run() then clears the flag anyway. Worth knowing before
# anyone decides that guard looks redundant.
#
# Each of these is ONE run: it resolves, plays the same feedback a real stop
# gets, and returns its grade rather than looping. Restart policy is
# deliberately left to the host, because it differs by page - page 1 restarts
# each tile independently on its own delay, while the powerups page restarts
# its whole 2x2 grid only once all four tiles have resolved. Neither is a
# property of a tile.
#
# Returns "" if the run was cancelled mid-flight (idle(), cancel_playback(), or
# a new play_*() call bumped the token). Callers MUST check for that before
# treating the result as a grade - an empty string is not a valid grade and
# will not match any branch of ScoreManager.grade_color()/play_grade().

# True while a run is live and waiting for the player's stop. Hosts branch on
# this to tell a "start this tile's practice loop" tap from a "this tap IS the
# stop" one, both of which arrive as the same `tapped` signal. A host that
# restarted on every `tapped` would cancel the very run the player was trying
# to stop, and would do it on the exact frame their timing mattered most.
#
# Exposed rather than left to the host to track alongside its own idea of
# which tile is running: that second copy would have to be kept in step with
# every cancel/idle/rebuild path in here, and the one that matters is this one.
func is_practice_run_active() -> bool:
	return _awaiting_tap

func _begin_tappable_run() -> void:
	# The previous run's grade flash may still be animating bg_color/shadow_size
	# (see _flash_grade) - stop it and put the panel back to its resting look,
	# or it spends the start of this run overwriting the urgency glow with the
	# tail of the last stop's flash.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _panel_style != null:
		_panel_style.bg_color = _base_bg
		_panel_style.border_color = _accent
	_clear_tap_capture()
	_awaiting_tap = true
	_set_tap_hint(true)

func _clear_tap_capture() -> void:
	_awaiting_tap = false
	_tap_pressed = false
	_tap_consumed = false
	_tap_value = 0.0
	_set_tap_hint(false)

# Pulse depth (not presence) rides Settings.effect_scale(), the same treatment
# every other softenable local effect on this tile gets. Reduce-screen-effects
# damps the throb without taking the hint away - it is the only thing telling a
# player the tile is waiting on them, so removing it outright would cost them
# the interaction rather than just the motion.
func _set_tap_hint(on: bool) -> void:
	if _tap_hint == null:
		return
	if _tap_hint_tween != null and _tap_hint_tween.is_valid():
		_tap_hint_tween.kill()
	_tap_hint.visible = on
	if not on:
		return
	_tap_hint.modulate.a = TAP_HINT_ALPHA_MAX
	if not is_inside_tree():
		return
	var min_a: float = lerpf(TAP_HINT_ALPHA_MAX, TAP_HINT_ALPHA_MIN, Settings.effect_scale())
	_tap_hint_tween = create_tween()
	_tap_hint_tween.set_loops()
	_tap_hint_tween.tween_property(_tap_hint, "modulate:a", min_a, TAP_HINT_PULSE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tap_hint_tween.tween_property(_tap_hint, "modulate:a", TAP_HINT_ALPHA_MAX, TAP_HINT_PULSE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Shared exit for all three runs below: same resolution feedback a scripted
# demo gets, tap state cleared, grade handed back to the awaiting host. Each
# caller passes its own frozen-digit text because that is the only part of
# resolving that genuinely differs between the types.
func _finish_tappable_run(grade: String, frozen_digit: String, bonus_text: String) -> String:
	# Read before _clear_tap_capture() wipes it - this is the only moment the
	# tapped/expired distinction still exists.
	last_run_was_tapped = _tap_consumed
	_clear_tap_capture()
	play_grade(grade, frozen_digit, 0.0, bonus_text)
	return grade

# Normal/Red/Blue/Blackout. Counts down from `start` through zero and on to
# TimerSlot.EXPIRE_THRESHOLD, which is where the real board gives up on a timer
# nobody clicked - so "I did nothing" reaches the same FAIL verdict here as it
# does in a run. `blackout_at` behaves exactly as in play_countdown().
func run_tappable_countdown(start: float, blackout_at: float = -1.0,
		bonus_text: String = "") -> String:
	var token := _play_token
	value = start
	_begin_tappable_run()
	_set_digit_mode(true)
	_render_countdown(blackout_at)
	var tick_accum := 0.0
	var grade := ""
	while true:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return ""
		if _tap_consumed:
			grade = TimerSlot.grade_for_distance(TimerSlot.stop_distance_for(_tap_value))
			break
		if value <= TimerSlot.EXPIRE_THRESHOLD:
			grade = "FAIL"
			break
		if _paused:
			continue
		var dt := get_process_delta_time()
		value = maxf(value - dt * _rate_multiplier, TimerSlot.EXPIRE_THRESHOLD)
		_render_countdown(blackout_at)
		_update_urgency(dt, value, value <= 0.0, TimerSlot.URGENCY_RANGE)
		_apply_urgency_to_panel(blackout_at >= 0.0 and value <= blackout_at)
		tick_accum += dt
		if tick_accum >= 1.0:
			tick_accum = 0.0
			if blackout_at >= 0.0:
				AudioManager.play_blackout_tick(get_instance_id())
			else:
				var progress: float = clampf(1.0 - value / maxf(start, 0.0001), 0.0, 1.0)
				AudioManager.play_tick(lerpf(1.0, 2.5, progress), get_instance_id())
	# The digits freeze at the value the finger went down on, not wherever the
	# countdown drifted to by the release frame - that is the number being
	# graded, so showing anything else would have the tile report a grade its
	# own display contradicts. For a Blackout this also overwrites the "??.??"
	# it was hiding behind, which is the whole point: the real board reveals the
	# true stopped value on resolution too, otherwise a player can never learn
	# what they were actually hitting.
	var frozen: String = "%.2f" % (_tap_value if _tap_consumed else value)
	return _finish_tappable_run(grade, frozen, bonus_text)

# Golden. Never counts and never expires - it just churns until the player
# takes it, which is exactly what the real one does (see
# TimerSlot._process_golden). No urgency glow: there is no zero being
# approached for one to signal, the same reason play_blur() has none.
func run_tappable_golden(bonus_text: String = "") -> String:
	var token := _play_token
	_begin_tappable_run()
	_set_digit_mode(true)
	var interval := 1.0 / GOLDEN_BLUR_SPEED
	var accumulator := 0.0
	var digit := 0
	while not _tap_consumed:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return ""
		var dt := get_process_delta_time()
		accumulator += dt
		while accumulator >= interval:
			accumulator -= interval
			digit = randi() % 10
		if _digit != null:
			_digit.text = "0.0%d" % digit
	# Guaranteed PERFECT at any moment, landing on a clean 0.00 rather than
	# whichever blur digit happened to be up - TimerSlot._resolve_stop() does
	# the same, so the payoff digit is identical every time.
	return _finish_tappable_run("PERFECT", "0.00", bonus_text)

# Decay. Climbs from 0.00 and grades on which ceiling tier it was stopped in,
# reaching `miss_end` as a MISS. Decay can never FAIL or cost a life - a
# locked-in rule, see play_decay_climb() - so there is no expiry branch here
# beyond that MISS.
func run_tappable_decay(perfect_end: float, good_end: float, okay_end: float,
		miss_end: float) -> String:
	var token := _play_token
	value = 0.0
	_begin_tappable_run()
	_set_digit_mode(true)
	var shown_tier := -1
	var tick_accum := 0.0
	var grade := ""
	while true:
		await get_tree().process_frame
		if token != _play_token or not is_instance_valid(self):
			return ""
		if _tap_consumed:
			grade = TimerSlot.DECAY_TIER_GRADES[
				_decay_tier_for(_tap_value, perfect_end, good_end, okay_end)]
			break
		if value >= miss_end:
			grade = "MISS"
			break
		if not _paused:
			var dt := get_process_delta_time()
			value = minf(value + dt * _rate_multiplier, miss_end)
			tick_accum += dt
			if tick_accum >= 1.0:
				tick_accum = 0.0
				var progress: float = clampf(value / maxf(miss_end, 0.0001), 0.0, 1.0)
				AudioManager.play_tick(lerpf(1.0, 2.5, progress), get_instance_id())
			_update_urgency(dt, clampf(value / maxf(miss_end, 0.0001), 0.0, 1.0), false)
			_apply_urgency_to_panel()
		if _digit != null:
			_digit.text = "%.2f" % value
		var tier := _decay_tier_for(value, perfect_end, good_end, okay_end)
		if tier != shown_tier:
			shown_tier = tier
			var tier_color := TimerTypeInfo.decay_tier_color(tier)
			_set_border(tier_color)
			if _panel_style != null:
				_panel_style.bg_color = tier_color.darkened(0.86)
			# Keeps the urgency glow's shadow hue on the current tier - see
			# play_decay_climb()'s own comment on this exact assignment.
			_accent = tier_color
	var frozen: String = "%.2f" % (_tap_value if _tap_consumed else value)
	return _finish_tappable_run(grade, frozen, "")

# --- Reactions (bystander tiles, driven by a Red/Blue tile resolving) -------

# Permanent: never reverts, matching TimerSlot.apply_speedup(). Whatever
# play_countdown loop is currently running on this tile reads the bumped
# _rate_multiplier on its very next frame, so the speed-up takes effect
# immediately mid-flight rather than needing to be re-triggered.
func react_speedup_permanent() -> void:
	_rate_multiplier += 0.25
	_set_border(TimerTypeInfo.color_of(TimerData.TimerType.RED))
	if _panel_style != null:
		var red := TimerTypeInfo.color_of(TimerData.TimerType.RED)
		_panel_style.bg_color = _base_bg.lerp(red.darkened(0.55), 0.3)
	_punch(1.15)

# Temporary: pauses whatever play_countdown loop is running for exactly
# `duration` seconds (matching TimerSlot.apply_pause's real 1.0s), with the
# same frost border + dimmed digit treatment as _set_frost(true), then
# restores both. Awaited by the caller if it needs to know when the freeze
# actually lifts; fire-and-forget is fine too since this tile's own state is
# self-contained.
const FROST_COLOR := Color("d8f4ff")

func react_freeze(duration: float) -> void:
	var token := _play_token
	_paused = true
	_set_border(FROST_COLOR)
	if _digit != null:
		var t := create_tween()
		t.tween_property(_digit, "modulate:a", 0.55, 0.12)
	await get_tree().create_timer(duration, true, false, true).timeout
	if token != _play_token or not is_instance_valid(self):
		return
	_paused = false
	_set_border(_accent)
	if _digit != null:
		var t2 := create_tween()
		t2.tween_property(_digit, "modulate:a", 1.0, 0.25)

# Overclock's board-wide effect, temporary and reverting after `duration` -
# distinct from Red's permanent boost even though both speed up ticking,
# because Overclock's real duration (Powerups.overclock_duration) genuinely
# ends and Red's stacks genuinely never do.
func react_overclock(duration: float) -> void:
	var token := _play_token
	_rate_multiplier += 1.5
	_set_border(TimerTypeInfo.color_of(TimerData.TimerType.RED))
	_punch(1.15)
	await get_tree().create_timer(duration, true, false, true).timeout
	if token != _play_token or not is_instance_valid(self):
		return
	_rate_multiplier = maxf(_rate_multiplier - 1.5, 1.0)
	_set_border(_accent)

# --- Click resolution --------------------------------------------------------

# Reproduces an actual click resolution: the digit freezes at `frozen_digit`
# (matching what the real TimerSlot leaves showing - GOLDEN always "0.00", a
# forced Nuke PERFECT keeps whatever value was already up, Shield's fail/save
# keeps the same overrun value throughout), while the flash/pop/grade-sign/burst
# below reproduce _play_stop_flash()/_spawn_grade_sign()/click_burst() from
# TimerSlot - the same feedback a real stop gets, not a Help-screen invention.
# `bonus_text`, if non-empty, adds a small badge under the sign - mirrors
# TimerSlot._add_multiplier_badge for the cases where a type/stack bonus is
# genuinely part of what's being taught (Golden's x2, Blackout's x2.5, a
# Red-boosted bystander's x1.25).
func play_grade(grade: String, frozen_digit: String, hold: float, bonus_text: String = "") -> void:
	if _digit != null:
		_digit.text = frozen_digit
	_flash_grade(grade)
	_punch(_POP_SCALE.get(grade, 1.0))
	_show_grade_sign(grade, bonus_text)
	# Juice.click_burst and AudioManager's grade sounds are both pure playback -
	# no EventBus/ScoreManager touched, no save data, nothing that reaches the
	# systems a real TimerSlot's resolution would - so both are safe to call
	# directly rather than needing a cosmetic-only stand-in.
	if is_inside_tree():
		Juice.click_burst(global_position + size * 0.5, grade, timer_type, 0.0)
	match grade:
		"PERFECT":
			AudioManager.play_perfect(1.0)
		"GOOD":
			AudioManager.play_good(0)
		"OKAY":
			AudioManager.play_ok(0)
		"MISS":
			AudioManager.play_miss(0)
		_:
			AudioManager.play_expire()

# Same match-on-grade panel treatment as TimerSlot._play_stop_flash().
#
# Held in a field rather than a local because it animates shadow_size, which the
# urgency glow also writes every frame. A practice tile replays, so the next run
# can begin while this is still in flight (the flash runs 0.35s; the replay
# delays are Inspector-tunable and can be set shorter), and the two would then
# fight over the same property - the flash winning, because a Tween's
# interpolation overwrites whatever the per-frame write just put there. Same
# class of conflict TimerSlot._panel_transition_lock exists for.
func _flash_grade(grade: String) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var tween := create_tween()
	_flash_tween = tween
	tween.set_parallel(true)
	match grade:
		"PERFECT":
			_panel_style.bg_color = _accent
			_panel_style.shadow_size = 22
			tween.tween_property(_panel_style, "bg_color", _base_bg, 0.35)
			tween.tween_property(_panel_style, "shadow_size", 10.0, 0.35)
		"GOOD":
			_panel_style.bg_color = _accent.darkened(0.35)
			tween.tween_property(_panel_style, "bg_color", _base_bg, 0.25)
		"OKAY":
			_panel_style.bg_color = _accent.darkened(0.6)
			tween.tween_property(_panel_style, "bg_color", _base_bg, 0.2)
		"MISS":
			var miss := Color("ff8a3d")
			_panel_style.bg_color = miss
			tween.tween_property(_panel_style, "bg_color", _base_bg, 0.3)
		_:
			var fail := Color("ff2e5e")
			_panel_style.bg_color = fail
			_panel_style.border_color = fail
			tween.tween_property(_panel_style, "bg_color", _base_bg, 0.4)
			tween.tween_property(_panel_style, "border_color", _accent, 0.4)

# Same per-grade pop amplitude as TimerSlot._pop() - MISS/FAIL get no pop there
# either, since a punch reads as a celebration and neither grade is one.
const _POP_SCALE := {"PERFECT": 1.25, "GOOD": 1.13, "OKAY": 1.06}

func _punch(scale_to: float) -> void:
	if scale_to <= 1.0:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	var target: float = 1.0 + (scale_to - 1.0) * Settings.effect_scale()
	pivot_offset = size * 0.5
	scale = Vector2.ONE
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "scale", Vector2(target, target), 0.08)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# A smaller sibling of TimerSlot._spawn_grade_sign() - font sized to guarantee
# it fits inside even the 160px landscape tile ("PERFECT" measures 131px at
# 32pt, confirmed via Font.get_string_size), and kept inside the tile's own
# vertical bounds rather than rising above it: this screen's page area clips
# its contents for the swipe track, and a sign rising above a top-row tile
# risked being cut off by that clip - unlike the real board, which has no such
# viewport above its timers to clip against.
const GRADE_SIGN_FONT := 32
const BONUS_BADGE_FONT := 16
const GRADE_SIGN_HOLD := 0.7
const GRADE_SIGN_FADE := 0.35

func _show_grade_sign(grade: String, bonus_text: String) -> void:
	if _grade_sign_tween != null and _grade_sign_tween.is_valid():
		_grade_sign_tween.kill()
	if _grade_sign != null and is_instance_valid(_grade_sign):
		_grade_sign.queue_free()

	_grade_sign = Label.new()
	_grade_sign.text = grade
	_grade_sign.add_theme_font_size_override("font_size", GRADE_SIGN_FONT)
	_grade_sign.add_theme_color_override("font_color", ScoreManager.grade_color(grade))
	_grade_sign.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_grade_sign.add_theme_constant_override("outline_size", 6)
	_grade_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_sign.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grade_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_sign.z_index = 5
	_grade_sign.size = size
	_grade_sign.position = Vector2.ZERO
	_grade_sign.pivot_offset = size * 0.5
	_grade_sign.scale = Vector2(1.6, 1.6)
	_grade_sign.modulate.a = 0.0
	add_child(_grade_sign)

	if not bonus_text.is_empty():
		var badge := Label.new()
		badge.text = bonus_text
		badge.add_theme_font_size_override("font_size", BONUS_BADGE_FONT)
		badge.add_theme_color_override("font_color", Color("ff1040"))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		badge.add_theme_constant_override("outline_size", 5)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(0, size.y * 0.62)
		badge.size = Vector2(size.x, size.y * 0.2)
		_grade_sign.add_child(badge)

	_grade_sign_tween = create_tween()
	_grade_sign_tween.set_parallel(true)
	_grade_sign_tween.tween_property(_grade_sign, "modulate:a", 1.0, 0.12)
	_grade_sign_tween.tween_property(_grade_sign, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_grade_sign_tween.chain().tween_property(_grade_sign, "modulate:a", 0.0, GRADE_SIGN_FADE) \
		.set_delay(GRADE_SIGN_HOLD)
	_grade_sign_tween.chain().tween_callback(_grade_sign.queue_free)

# --- Selection (page 1's tapped-tile ring, independent of dimming) ----------

func set_selected(on: bool) -> void:
	_selected = on
	if _panel_style == null:
		return
	var width := int(SELECTED_BORDER_WIDTH if on else BASE_BORDER_WIDTH)
	_panel_style.border_width_left = width
	_panel_style.border_width_right = width
	_panel_style.border_width_top = width
	_panel_style.border_width_bottom = width
	_panel_style.shadow_size = int(SELECTED_SHADOW_SIZE if on else BASE_SHADOW_SIZE)
	_panel_style.shadow_color = Color(_accent.r, _accent.g, _accent.b,
		SELECTED_SHADOW_ALPHA if on else BASE_SHADOW_ALPHA)
	if not on:
		_set_border(_accent)

func _set_border(c: Color) -> void:
	if _panel_style != null:
		_panel_style.border_color = c
