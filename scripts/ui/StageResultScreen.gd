extends Control
class_name StageResultScreen

# --- Reveal tuning --------------------------------------------------------
const STEP_TWEEN_TIME := 0.32     # seconds to tick the tally up per result
const STEP_GAP := 0.14            # pause between results
const FINALE_DELAY := 0.3         # beat before the finale multiply
const FINALE_HITSTOP_MULT := 3.0  # vs 1.0 everywhere in live play
const FINALE_PUNCH_MULT := 4.0    # vs 2.0 at a streak-8 PERFECT

# --- Skip / fast-forward --------------------------------------------------
# Replaying a stage to chase a score means sitting through this reveal many
# times, so the tally beat is skippable. The finale deliberately is NOT - it is
# the entire payoff of a mode whose scoring is otherwise fully deferred, so skip
# only ever shortens the road to it.
#
# One press serves both behaviours rather than needing two bindings: the press
# starts fast-forwarding immediately (so any input feels instant), and releasing
# it inside HOLD_THRESHOLD is what promotes it to a full skip. Holding longer is
# read as a deliberate fast-forward and simply returns to normal speed on
# release. Tap and hold therefore can't be ambiguous with each other.
const FF_PACE_SCALE := 0.35       # per-stop timing multiplier while held
const HOLD_THRESHOLD := 0.25      # release inside this = tap = skip to finale

var _skip_armed: bool = false     # true only across the skippable tally beat
var _skip_requested: bool = false
var _fast_forward: bool = false
var _press_start_ms: int = 0

# --- Anticipation tint ----------------------------------------------------
# A quiet pre-signal of how the stage went, set before a single tally number
# appears. Deliberately subordinate to the finale's colour wash: lower alpha, no
# flash, and it simply holds rather than pulsing, so it reads as the background
# the reveal happens on rather than as an effect competing with it.
const ANTICIPATION_ALPHA_MIN := 0.04   # a scrape-by clear still gets a faint bed
const ANTICIPATION_ALPHA_MAX := 0.14   # vs the wash's 0.10/0.18/0.30 transient peaks
const ANTICIPATION_FADE_IN := 0.35

# --- New-personal-best badge ----------------------------------------------
# Glowing text, not a bordered box - a StyleBoxFlat panel reads as a clickable
# button everywhere else in this UI (every actual button uses exactly that
# shape), so this deliberately borrows the *other* established idiom instead:
# plain outlined text, the same language the grade signs and streak popups
# already use for "celebratory, not interactive".
#
# It sits in its own reserved lane directly above the score, and its halo blooms
# from the score's centre rather than from the badge - a record belongs to a
# number, so the two have to read as one object rather than as a label parked
# somewhere near one.
const BADGE_SIZE := Vector2(300, 44)
const BADGE_GLOW_SIZE := Vector2(520, 300)
const BADGE_LANE_HEIGHT := 44.0   # reserved up front so a record can't reflow the column

# Countup escalation. 0.16 puts a stage at full intensity after ~6 PERFECTs,
# which is most of the way through a typical stage's stop count - so the ceiling
# is reachable but only by playing most of the stage cleanly.
const REVEAL_INTENSITY_STEP := 0.16
const RING_ESCALATION_MAX := 1.6

const FLAME_SPREAD := 35.0        # per-stop default; the finale widens past it

# --- "Holding breath" beat ------------------------------------------------
# A deliberate pause between the stage ending and the tally starting. The
# ambient bed is already silent by this point - AudioManager stops it on any
# state change out of PLAYING - so this only has to supply the dim and the
# wait, and the near-silence comes for free.
#
# BREATH_IN + BREATH_HOLD is the actual wait before the tally starts (BREATH_OUT
# isn't awaited - see _hold_breath).

# Idle pulse on the settled result. Shallow and slow on purpose - see
# _start_final_idle.
const IDLE_PULSE_SCALE := 1.035
const IDLE_PULSE_SEC := 1.1

const BREATH_DIM_ALPHA := 0.38
const BREATH_IN := 0.1
const BREATH_HOLD := 0.3
const BREATH_OUT := 0.3

# --- Palette --------------------------------------------------------------
# One colour, one job. The screen settles into five roles and nothing borrows
# another's:
#   CLEAR/FAIL - did you pass. Headline only.
#   GOLD       - the outcome. The final score, and the record it may have set.
#   NEON       - interactive. Buttons, matching the cyan every other screen
#                already uses for "you can press this".
#   MUTED      - supporting. The arithmetic, the record line, the way out.
#   TEXT_FILL  - the fill under all of it.
# The tally line sits in MUTED rather than NEON specifically so gold arrives
# unshared at the finale and so no static text wears the button colour.
const CLEAR_COLOR := Color("39ff9e")   # green headline on clear
const FAIL_COLOR := Color("ff2e5e")    # red headline on fail
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const MUTED := Color("8b90a8")
const HEAT := Color("ff5a1e")          # flames and heat flashes, never text

# --- Type scale -----------------------------------------------------------
# Steps far enough apart that rank is readable at a glance. The hero is a clean
# 2x the tally, which is what keeps the countup from competing with the number
# it resolves into.
const FS_HERO := 92        # final score
const FS_HEADLINE := 60    # STAGE CLEAR! / FAILED
const FS_SIGN := 44        # transient grade signs, own lane
const FS_TALLY := 46       # "tally x mult"
const FS_STREAK := 40      # transient streak popup
const FS_BADGE := 28
const FS_BUTTON := 28
const FS_SUPPORT := 24     # record line, tertiary button
const FS_COMPLETE := 32    # campaign-complete message

# --- Zone rules -----------------------------------------------------------
# The column runs headline / score / actions. Without a separator those read as
# one undifferentiated stack, so each boundary gets a hairline that fades out at
# both ends rather than a hard edge-to-edge rule.
const DIVIDER_WIDTH := 620.0
const DIVIDER_THICKNESS := 2.0
const DIVIDER_ALPHA := 0.5
const DIVIDER_TINT_TIME := 0.6

const COMPLETE_TEXT := "PERFECT ZERO, ACHIEVED.\nReady to see how long you can last? Try Endless Mode."

# Matches the project's viewport. Controls nested under a Node2D (Main) don't
# reliably inherit viewport-relative anchors, so full-screen rects are sized
# explicitly rather than anchor-based.
const VIEWPORT_SIZE := Vector2(1600, 900)

@export var stage_controller: StageController
@export var campaign_navigator: CampaignNavigator

var _headline: Label
var _sign_anchor: Control         # empty lane between headline and score line for grade signs
var _score_line: HBoxContainer   # holds "tally x mult" on one line
var _score_digits: DigitCounter
var _times_label: Label
var _mult_label: Label
var _final_label: Label          # the product, revealed in the finale
var _badge_lane: Control         # reserved space above the score for the NEW BEST badge
var _record_label: Label         # the one supporting line - see _show_summary
var _divider_top: TextureRect
var _divider_bottom: TextureRect
var _button_row: HBoxContainer
var _title_row: HBoxContainer
var _streak_label: Label
var _streak_tween: Tween
var _flash: ColorRect
var _dim: ColorRect
var _wash: ColorRect
var _anticipation: TextureRect
var _badge: Label
var _badge_glow: TextureRect

# The finale's tier, kept so the outro transition can echo it without
# recomputing a second, separately-tuned quality metric. Reset per reveal, so a
# FAIL (whose finale never runs) leaves at tier 0 rather than inheriting the
# tier of whatever was cleared before it.
var _outro_tier: int = 0
var _flames: CPUParticles2D
var _flame_grad_default: Gradient   # restored by _erupt; see the finale branch
var _sign_ring: CPUParticles2D
var _idle_tween: Tween
var _transitioning: bool = false

var _reveal_streak: int = 0       # PERFECT-only; drives the "Nx PERFECT!" popup
var _reveal_grade_streak: int = 0 # any grade repeating; drives the audio pitch climb
var _reveal_last_grade: String = ""

# A third, deliberately different counter from the two above. Both of those are
# *streaks* and reset the moment the grade changes; this accumulates across the
# whole stage and only resets between stages. That's what lets a stage keep
# building even when its PERFECTs are interrupted - a streak counter would drop
# the escalation back to nothing on a single GOOD halfway through.
var _reveal_intensity: float = 0.0

var _revealing: bool = false

func _ready() -> void:
	_build_ui()
	_build_flames()
	_build_sign_ring()
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int) -> void:
	if _revealing:
		return
	if new_state == GameManager.GameState.STAGE_CLEAR:
		_run_reveal(true)
	elif new_state == GameManager.GameState.FAIL:
		_run_reveal(false)
	else:
		# Leaving the result screen. The idle pulse loops forever by design, so
		# it has to be stopped explicitly or it keeps ticking on a hidden label
		# for the rest of the session.
		_stop_final_idle()

# --- Reveal sequence ------------------------------------------------------

func _run_reveal(cleared: bool) -> void:
	_revealing = true
	_reset_display(cleared)

	if not cleared:
		# FAIL scores 0 - no tally to animate, just the FAILED summary + RETRY.
		_score_line.visible = false
		_final_label.visible = false
		# Both reserved lanes exist to hold reveal content - grade signs and the
		# record badge - and a fail runs no reveal, so neither can ever be filled
		# on this path. Left visible they are ~130px of guaranteed-empty column in
		# the middle of an already-sparse screen, with the dividers ruling off
		# almost nothing. Hiding drops them out of the layout entirely.
		_sign_anchor.visible = false
		_badge_lane.visible = false
		_show_fail_summary()
		_revealing = false
		return

	# Let the just-shown screen lay out before we read label rects for signs/flames.
	await get_tree().process_frame

	var eval: Dictionary = ScoreManager.evaluate_stage(stage_controller.pending_results)
	var steps: Array = eval["steps"]
	var tally: int = eval["tally"]
	var final_mult: float = eval["final_mult"]
	var stage_score: int = eval["stage_score"]

	# Computed once, up front, and read three ways: the anticipation tint below,
	# the finale's colour wash, and the outro transition. All three are meant to
	# be the same judgement of the same stage, so they share one aggregate rather
	# than each deriving its own.
	var quality: float = _stage_quality(steps)
	var tier: int = _quality_tier(quality)
	_outro_tier = tier

	_set_score_display(0.0)
	_set_mult_display(1.0)
	_reveal_streak = 0
	_reveal_grade_streak = 0
	_reveal_last_grade = ""
	_reveal_intensity = 0.0

	# Raised alongside the breath rather than after it, so the run's character is
	# already on screen before the first tally number appears.
	_begin_anticipation(quality)

	# Armed from here rather than at the loop below, so a player already mashing
	# through the breath beat has that press honoured instead of dropped - it
	# lands as a skip on the loop's first check. Disarmed before the finale,
	# which is never skippable either way.
	_skip_armed = true
	await _hold_breath()

	# Phase 1: tally the base points and build the multiplier, one stop at a time.
	for step in steps:
		if _skip_requested:
			break
		await _animate_step(step)
		# Checked after the step rather than mid-tween: breaking only at a step
		# boundary means no countup tween is ever left in flight, which is what
		# lets the settle below simply assert the final values.
		if _skip_requested:
			break
		await get_tree().create_timer(STEP_GAP * _pace_scale(), true, false, true).timeout
	_skip_armed = false
	if _skip_requested:
		_settle_tally(tally, final_mult)

	# Phase 2: the finale - the multiplier slams the tally into the final score.
	await get_tree().create_timer(FINALE_DELAY, true, false, true).timeout
	await _animate_finale(final_mult, stage_score, tier)

	_finish_clear(stage_score)
	_revealing = false

# --- Skip / fast-forward --------------------------------------------------

# Accepts mouse and keyboard alike, matching the dual-input handling everywhere
# else in the project. `ui_accept` is Godot's built-in Enter/Space action, so
# this needs no addition to the (currently empty) input map.
#
# Gated entirely on _skip_armed, which is only ever true across the tally loop:
# outside that window this handler is inert and consumes nothing, so it can't
# interfere with the buttons that appear once the reveal settles, with the pause
# menu, or with the FAIL summary (which never arms it at all).
func _input(event: InputEvent) -> void:
	if not _skip_armed:
		return

	if _is_skip_press(event, true):
		_fast_forward = true
		_press_start_ms = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()
	elif _is_skip_press(event, false):
		_fast_forward = false
		if Time.get_ticks_msec() - _press_start_ms <= int(HOLD_THRESHOLD * 1000.0):
			_skip_requested = true
		get_viewport().set_input_as_handled()

func _is_skip_press(event: InputEvent, pressed: bool) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return event.pressed == pressed
	if event.is_action("ui_accept"):
		return event.is_pressed() == pressed and not event.is_echo()
	return false

func _pace_scale() -> float:
	return FF_PACE_SCALE if _fast_forward else 1.0

# Asserts the end state of the tally the instant a skip lands, so nothing
# partial or mid-interpolation is ever left on screen. Both values come from
# ScoreManager.evaluate_stage()'s own totals rather than from wherever the
# countup happened to stop, so a skipped reveal and a watched one arrive at
# identical numbers - and the finale, which reads those same totals, is
# unaffected either way.
func _settle_tally(tally: int, final_mult: float) -> void:
	_set_score_display(float(tally))
	_set_mult_display(final_mult)
	_score_digits.punch_all(1.2)

# --- Anticipation tint ------------------------------------------------------

# Scaled by effect_scale() rather than exempted or hard-killed. It sits between
# the two existing conventions - it is a persistent, non-flashing background
# state indicator like the Overclock/Shield edge treatments (which the toggle
# leaves alone), but it is also a full-screen colour wash like _wash_screen()
# (which the toggle kills outright). Scaling keeps the signal legible for
# players who need the intensity down without removing the read entirely.
func _begin_anticipation(quality: float) -> void:
	if _anticipation == null:
		return
	var tint: Color = _anticipation_color(quality)
	var target_a: float = lerpf(ANTICIPATION_ALPHA_MIN, ANTICIPATION_ALPHA_MAX, quality) \
		* Settings.effect_scale()
	_anticipation.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	_anticipation.visible = true
	var tween := create_tween()
	tween.tween_property(_anticipation, "modulate:a", target_a, ANTICIPATION_FADE_IN)

# A continuous walk of the same palette the finale steps through discretely.
# Continuous on purpose: the finale's job is to announce a tier, this one's is
# to be a gradient of mood the player reads without being told a number.
func _anticipation_color(quality: float) -> Color:
	if quality < 0.5:
		return TIER_COLORS[0].lerp(TIER_COLORS[1], quality * 2.0)
	return TIER_COLORS[1].lerp(TIER_COLORS[2], (quality - 0.5) * 2.0)

# --- Stage quality tier -----------------------------------------------------
# How well the stage was played, 0..1, derived from the counted stops.
#
# Deliberately NOT scored against StageData.target_score: that field is optional
# and left at 0 on most stages, so anything dividing by it would report a
# meaningless tier wherever a designer hadn't filled it in. The grades are always
# present, so this can't be wrong.
const GRADE_QUALITY := {
	"PERFECT": 1.0,
	"GOOD": 0.6,
	"OKAY": 0.3,
	"MISS": 0.0,
	"FAIL": 0.0,
}

# Colour is a discrete step rather than a lerp across the quality value: a
# continuously interpolated tint just reads as "some colour", where the point is
# that a player should recognise a top-tier finish by its colour alone.
const TIER_CUTS := [0.55, 0.85]                                    # -> tier 1, tier 2
const TIER_COLORS := [Color("6b7080"), Color("39ff9e"), Color("ffd23f")]
const TIER_WASH_ALPHA := [0.10, 0.18, 0.30]
const WASH_IN := 0.12
const WASH_OUT := 0.85

func _stage_quality(steps: Array) -> float:
	if steps.is_empty():
		return 0.0
	var total: float = 0.0
	for step in steps:
		total += float(GRADE_QUALITY.get(step["grade"], 0.0))
	return clampf(total / float(steps.size()), 0.0, 1.0)

func _quality_tier(quality: float) -> int:
	var tier: int = 0
	for cut in TIER_CUTS:
		if quality >= cut:
			tier += 1
	return tier

# A sustained full-screen grade on the final slam, distinct from _flash_screen's
# quick punctuation - different duration, different job, so a separate rect
# rather than an overload of the same one.
func _wash_screen(tier: int) -> void:
	if not Settings.motion_effects_enabled():
		return
	var color: Color = TIER_COLORS[tier]
	_wash.color = Color(color.r, color.g, color.b, 0.0)
	var tween := create_tween()
	tween.tween_property(_wash, "color:a", TIER_WASH_ALPHA[tier], WASH_IN)
	tween.tween_property(_wash, "color:a", 0.0, WASH_OUT)

# Silence right before a big beat does more for how it lands than anything
# downstream of it, so the reveal deliberately stalls here rather than starting
# the moment the stage ends.
func _hold_breath() -> void:
	_dim.color.a = 0.0
	var into := create_tween()
	into.tween_property(_dim, "color:a", BREATH_DIM_ALPHA, BREATH_IN)
	await into.finished

	await get_tree().create_timer(BREATH_HOLD, true, false, true).timeout

	# Not awaited: the tally starts as the dim is still lifting, so the countup
	# arrives *into* the recovery rather than after a second dead pause.
	var out := create_tween()
	out.tween_property(_dim, "color:a", 0.0, BREATH_OUT)

func _animate_step(step: Dictionary) -> void:
	var grade: String = step["grade"]
	var gain: int = int(step["gain"])
	var mult_before: float = step["mult_before"]
	var mult_after: float = step["mult_after"]

	# Sampled once per step rather than per frame: fast-forward compresses the
	# pacing, it doesn't rubber-band the countup mid-tween if the player lets go
	# halfway through one.
	var tween := create_tween()
	tween.tween_method(_set_score_display, float(step["tally_before"]),
		float(step["tally_after"]), STEP_TWEEN_TIME * _pace_scale())

	_set_mult_display(mult_after)

	# Raised before anything reads it, so the PERFECT that earns the escalation
	# is itself the one that shows it - crediting it to the *next* stop would
	# make the build lag a beat behind what the player is watching.
	if grade == "PERFECT":
		_reveal_intensity = minf(_reveal_intensity + REVEAL_INTENSITY_STEP, 1.0)

	_spawn_sign(grade, _sign_center())
	# Same radial burst the live board uses on a click, fired at the sign as the
	# stop is counted - it already sizes and colours itself by grade, so a
	# PERFECT blooms and a MISS/FAIL only fizzles.
	Juice.click_burst(_sign_anchor.global_position + _sign_anchor.size * 0.5, grade,
		-1, _reveal_intensity)

	# Consecutive-PERFECT streak popup (any other grade breaks it).
	if grade == "PERFECT":
		_reveal_streak += 1
		if _reveal_streak >= 2:
			_show_streak_popup(_reveal_streak)
	else:
		_reveal_streak = 0

	# Separate general streak for the audio pitch climb - any grade repeating,
	# not just PERFECT, so GOOD/OKAY/MISS get their own real streak instead of
	# inheriting whatever the PERFECT-only counter above happens to be at.
	if grade == _reveal_last_grade:
		_reveal_grade_streak += 1
	else:
		_reveal_grade_streak = 0
		_reveal_last_grade = grade

	# One stinger per stop counted, so the reveal is heard as well as watched.
	AudioManager.play_reveal_step(grade, _reveal_grade_streak, _reveal_intensity)

	if mult_after > mult_before:
		_pop(_mult_label, 1.4)
	elif mult_after < mult_before:
		_pop(_mult_label, 0.7)             # a MISS halving the multiplier
		_flash_screen(FAIL_COLOR, 0.2)

	if gain > 0:
		var intensity: float = clampf(float(gain) / 200.0, 0.0, 1.0)
		_erupt(intensity * 0.55, _score_line)
		# Punching every digit rather than the container: a whole-counter pop on
		# top of the per-digit countup pops read as two effects fighting.
		_score_digits.punch_all(lerpf(0.7, 1.6, intensity))
		AudioManager.play_big_score(intensity * 0.5)

	await tween.finished

func _animate_finale(final_mult: float, stage_score: int, tier: int) -> void:
	_set_mult_display(final_mult)
	_pop(_mult_label, 1.7)

	# Dim the "tally x mult" line to a record, then bloom the product big.
	var dim := create_tween()
	dim.tween_property(_score_line, "modulate:a", 0.4, 0.3)

	_set_final_display(0.0)
	_final_label.modulate.a = 1.0
	_erupt(1.0, _final_label, tier)
	_wash_screen(tier)
	# The wash, the flames and the outro all announce the tier and then take it
	# away with them. The dividers keep it: they are structure, so tinting them
	# leaves a tier read on the settled screen without adding a fourth colour to
	# the text or competing with gold for the score.
	_tint_dividers(TIER_COLORS[tier], DIVIDER_TINT_TIME)

	# The one moment in a stage explicitly allowed to be the biggest beat on
	# screen - Campaign defers all its scoring, so this is the entire payoff.
	# Both are deliberately past anything live play reaches: the streak-8 punch
	# tops out at 2.0 and Nuke's full-board finish at ~3.75.
	Juice.hit_stop(FINALE_HITSTOP_MULT)
	Juice.punch(FINALE_PUNCH_MULT * lerpf(0.8, 1.15, float(tier) / 2.0))
	AudioManager.play_final_slam()

	var tween := create_tween()
	tween.tween_method(_set_final_display, 0.0, float(stage_score), 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop(_final_label, 1.45)
	await tween.finished

func _finish_clear(stage_score: int) -> void:
	var index: int = campaign_navigator.current_index
	var best_key: String = "highscore_stage_%d" % index
	var best: int = SaveManager.load_high_score(best_key)
	# Captured before `best` is overwritten below: the flourish has to know
	# whether THIS attempt set the record, not merely what the record now is, and
	# the summary line reports the mark that was beaten. No schema change is
	# involved - the stored value is a plain score and this is the same comparison
	# the screen already made to decide whether to write.
	var previous_best: int = best
	var is_new_best: bool = stage_score > best
	if is_new_best:
		best = stage_score
		# SaveManager degrades to a push_warning and "not saved" if the write
		# fails, so a failed save costs the record but never the run.
		SaveManager.save_high_score(best_key, best)
	# Commit the campaign total as base + best. Best only ever rises, so a retry
	# that beats your previous best updates the total too; a worse retry leaves it.
	ScoreManager.set_score(stage_controller.stage_start_score + best, 1.0)

	_show_summary(best, previous_best, is_new_best)
	_build_buttons(true)
	_start_final_idle()

	if is_new_best:
		_play_new_best_flourish()

	# Fires once ever, the moment Stage 3 (CampaignNavigator.ENDLESS_UNLOCK_STAGE)
	# is cleared - layered on top of the normal reveal exactly like NEW BEST is,
	# rather than replacing anything above. Staggered behind it (not simultaneous)
	# since Stage 3 being cleared for the first time is very plausibly also this
	# stage's first-ever best, and the two flourishes would otherwise land on the
	# same beat and blur together.
	if index + 1 == CampaignNavigator.ENDLESS_UNLOCK_STAGE \
			and SaveManager.load_high_score("endless_unlock_seen") == 0:
		SaveManager.save_high_score("endless_unlock_seen", 1)
		if is_new_best:
			await get_tree().create_timer(0.9, true, false, true).timeout
		_play_unlock_banner("ENDLESS MODE UNLOCKED!")

# A secondary "oh, and also" beat, deliberately kept out of the finale's
# package: no hit-stop, no camera punch, no colour wash. Those belong to the
# score reveal itself, and folding this into them would make a record read as
# part of the slam rather than as its own separate piece of news.
#
# The sound is the same one Endless's run-summary record uses - a different
# event in a different mode, but the same thing happening to the player, so it
# should sound like it. It is not the finale stinger (play_final_slam), which is
# what the brief rules out reusing.
func _play_new_best_flourish() -> void:
	if _badge == null:
		return
	_position_badge()
	# The record belongs to the number, so the number itself takes the change and
	# keeps it for as long as the result is on screen. The badge announces it;
	# this is the mark it leaves.
	_final_label.add_theme_color_override("font_outline_color", GOLD.lightened(0.3))
	for node in [_badge, _badge_glow]:
		node.visible = true
		node.modulate.a = 0.0
	_badge.pivot_offset = BADGE_SIZE * 0.5
	_badge.scale = Vector2(0.6, 0.6)
	_badge.rotation = deg_to_rad(-7.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_badge, "modulate:a", 1.0, 0.16)
	# The glow settles well under full strength: it sits behind the 92px score,
	# which is the brightest thing on the screen, and a stronger bloom flattens
	# the digits instead of lifting them - confirmed visually at 0.3, which
	# visibly softened the hero number's edges next to a non-record clear.
	tween.tween_property(_badge_glow, "modulate:a", 0.2, 0.25)
	tween.tween_property(_badge, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Settles level from a slight tilt - a ribbon being pinned on, rather than a
	# label that simply appeared.
	tween.tween_property(_badge, "rotation", 0.0, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	AudioManager.play_new_best()

# A one-time, whole-mode announcement (Endless at Stage 3, Hardcore at full
# completion) - deliberately its own popup rather than reusing the small corner
# NEW BEST badge above (the two can legitimately fire on the same clear - see
# the caller), since unlocking a mode is a bigger deal than one stage's record.
#
# A closable modal rather than a transient banner: an earlier version was a
# floating label that auto-faded over the score/buttons underneath, which had
# nowhere else to sit on a screen already using that space and gave the player
# no way to linger on it or dismiss it early. Same dim+panel+button language
# TutorialManager/PowerupTutorial already use elsewhere, which also means it
# naturally blocks clicks to RETRY/NEXT STAGE underneath while it's up, instead
# of the two overlapping.
func _play_unlock_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 35  # above this screen's own content, below PauseMenu (100)
	add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f1118")
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = GOLD
	sb.set_content_margin_all(32)
	sb.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.4)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.custom_minimum_size = Vector2(560, 0)
	panel.add_child(col)

	var label := _make_label(38, GOLD.darkened(0.15))
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)

	var nice := Button.new()
	nice.text = "OKAY!"
	nice.custom_minimum_size = Vector2(200, 64)
	nice.add_theme_font_size_override("font_size", 28)
	nice.add_theme_color_override("font_color", Color.WHITE)
	nice.add_theme_color_override("font_outline_color", GOLD)
	nice.add_theme_constant_override("outline_size", 4)
	nice.add_theme_stylebox_override("normal", _make_box(GOLD, 0.85, 0.35, 8))
	nice.add_theme_stylebox_override("hover", _make_box(GOLD, 0.7, 0.5, 12))
	nice.add_theme_stylebox_override("pressed", _make_box(GOLD, 0.6, 0.4, 6))
	PressFeedback.apply(nice)
	nice.pressed.connect(layer.queue_free)
	var nice_wrap := CenterContainer.new()
	nice_wrap.add_child(nice)
	col.add_child(nice_wrap)

	AudioManager.play_unlock()
	Juice.punch(1.6)

# Centred in its reserved lane, which sits immediately above the score - a
# kicker on the number rather than a label floating beside it. The lane and the
# score are both full-width children of the same centred column, so sharing the
# lane's centre line puts the badge dead over the digits no matter how many
# there are.
#
# The halo is centred on the score, not on the badge, so one bloom covers both
# and reads as a single lit object.
func _position_badge() -> void:
	var lane: Vector2 = _badge_lane.global_position - global_position
	_badge.position = Vector2(lane.x + _badge_lane.size.x * 0.5 - BADGE_SIZE.x * 0.5, lane.y)

	var score: Vector2 = _final_label.global_position - global_position
	var score_center := score + _final_label.size * 0.5
	_badge_glow.position = score_center - BADGE_GLOW_SIZE * 0.5

# Keeps the screen from going completely static while the player reads the
# result. Applied to the final score rather than to a grade sign: the per-stop
# signs are transient (each fades in ~0.65s) and there is no single stage-grade
# sign in this game, so the score is the thing that's actually still on screen
# once the reveal settles.
#
# Deliberately slow and shallow - this sits under text the player is reading,
# so it has to register as "alive" without pulling the eye or making the digits
# harder to parse.
func _start_final_idle() -> void:
	_stop_final_idle()
	_final_label.pivot_offset = _final_label.size * 0.5
	_idle_tween = create_tween().set_loops()
	_idle_tween.set_parallel(false)
	_idle_tween.tween_property(_final_label, "scale", Vector2.ONE * IDLE_PULSE_SCALE,
		IDLE_PULSE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_final_label, "scale", Vector2.ONE,
		IDLE_PULSE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_final_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
	_final_label.scale = Vector2.ONE

func _show_fail_summary() -> void:
	var best: int = SaveManager.load_high_score("highscore_stage_%d" % campaign_navigator.current_index)
	# A failed attempt scored 0 and there is no hero number to sit under, so the
	# only line worth printing is the mark still standing.
	_show_summary(best, best, false)
	_build_buttons(false)

# One supporting line, not two. The hero number directly above already IS this
# attempt's score, so a "This attempt" line only restates it, and on a record a
# "Best" line restates the same figure a third time. What is actually new
# depends on the outcome: after a record, the mark that was beaten; otherwise,
# the mark still to beat. A first-ever clear has neither, and gets nothing - the
# badge is already saying the only thing there is to say.
func _show_summary(best: int, previous_best: int, is_new_best: bool) -> void:
	var text := ""
	if is_new_best:
		if previous_best > 0:
			text = "PREVIOUS BEST   %d" % previous_best
	elif best > 0:
		text = "BEST   %d" % best

	_record_label.text = text
	if text.is_empty():
		return
	var fade := create_tween()
	fade.tween_property(_record_label, "modulate:a", 1.0, 0.25)

# --- Display helpers ------------------------------------------------------

func _reset_display(cleared: bool) -> void:
	for child in _button_row.get_children():
		child.queue_free()
	for child in _title_row.get_children():
		child.queue_free()
	# modulate.a (not `visible`) so the line keeps its layout space from the start
	# - otherwise the centered column grows as it appears and visibly shifts.
	_record_label.modulate.a = 0.0
	# `visible` is the campaign-complete screen's doing, so it has to be undone
	# here for a retry that lands back on a normal result.
	_record_label.visible = true

	# Cleared unconditionally: the FAIL path skips _hold_breath entirely, and a
	# reveal interrupted mid-breath would otherwise leave the screen dimmed.
	_dim.color.a = 0.0
	_wash.color.a = 0.0
	if _anticipation != null:
		_anticipation.modulate.a = 0.0
		_anticipation.visible = false
	if _badge != null:
		_badge.visible = false
		_badge.scale = Vector2.ONE
		_badge.rotation = 0.0
	if _badge_glow != null:
		_badge_glow.visible = false

	# A retry inherits the previous attempt's skip state otherwise, which would
	# skip the next reveal before the player had touched anything. Cleared for
	# the FAIL path too, which never arms skip at all.
	_skip_armed = false
	_skip_requested = false
	_fast_forward = false
	# A FAIL runs no finale, so it never sets a tier - leaving it at 0 gives the
	# plain outro rather than whatever the last clear happened to earn.
	_outro_tier = 0
	# The idle pulse loops forever by design, so a retry would otherwise start a
	# second one on top of the first.
	_stop_final_idle()

	# A FAIL hides these; cleared unconditionally so a retry after a fail (or vice
	# versa) doesn't inherit the previous attempt's collapsed layout.
	_sign_anchor.visible = true
	_badge_lane.visible = true

	_score_line.visible = true
	_score_line.modulate.a = 1.0
	_final_label.visible = true
	_final_label.modulate.a = 0.0
	# The record flourish brightens this and leaves it bright, which is the point
	# - so the next attempt has to put it back.
	_final_label.add_theme_color_override("font_outline_color", GOLD)
	_set_final_display(0.0)

	# Back to plain structure. The tier tint is earned per reveal in the finale,
	# and the completion screen hides these outright, so both have to be undone
	# before an attempt that may earn neither.
	_tint_dividers(MUTED, 0.0)
	for divider in [_divider_top, _divider_bottom]:
		if divider != null:
			divider.visible = true

	_headline.add_theme_font_size_override("font_size", FS_HEADLINE)  # reset (completion shrinks it)

	if cleared:
		_headline.text = "STAGE CLEAR!"
		_headline.add_theme_color_override("font_color", CLEAR_COLOR)
		_headline.add_theme_color_override("font_outline_color", CLEAR_COLOR.darkened(0.4))
	else:
		_headline.text = "FAILED"
		_headline.add_theme_color_override("font_color", FAIL_COLOR)
		_headline.add_theme_color_override("font_outline_color", FAIL_COLOR.darkened(0.4))
		_flash_screen(FAIL_COLOR, 0.4)

func _set_score_display(value: float) -> void:
	_score_digits.set_value(int(round(value)))

func _set_final_display(value: float) -> void:
	_final_label.text = "%d" % int(round(value))

func _set_mult_display(mult: float) -> void:
	_mult_label.text = "%.1f" % mult
	# Glow warms out of the muted line toward gold as the multiplier climbs
	# (uncapped). Ending on gold is the point: the multiplier heating up is the
	# screen previewing the colour the outcome is about to arrive in.
	var t: float = clampf((mult - 1.0) / 5.0, 0.0, 1.0)
	_mult_label.add_theme_color_override("font_outline_color", MUTED.lerp(GOLD, t))

func _sign_center() -> Vector2:
	return _sign_anchor.global_position - global_position + _sign_anchor.size * 0.5

func _spawn_sign(grade: String, at: Vector2) -> void:
	# Floating grade sign that pops with oomph, centered on `at` (its own lane).
	var sign_label := Label.new()
	sign_label.text = grade
	sign_label.add_theme_font_size_override("font_size", FS_SIGN)
	sign_label.add_theme_color_override("font_color", ScoreManager.grade_color(grade))
	sign_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sign_label.add_theme_constant_override("outline_size", 8)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign_label.z_index = 20
	sign_label.size = Vector2(320, 60)
	sign_label.position = at - sign_label.size * 0.5
	sign_label.pivot_offset = sign_label.size * 0.5
	sign_label.scale = Vector2(1.7, 1.7)
	add_child(sign_label)

	# Drift and fade, running alongside the squash chain below. Kept on its own
	# tween because that chain has to be sequential while these are parallel, and
	# set_parallel applies to every tweener added after it.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sign_label, "position:y", sign_label.position.y - 14.0, 0.6)
	tw.tween_property(sign_label, "modulate:a", 0.0, 0.3).set_delay(0.35)
	tw.finished.connect(sign_label.queue_free)

	# Squash and stretch: the sign arrives oversized, flattens on impact,
	# rebounds past its final size narrow-and-tall, then settles. Non-uniform
	# axes are the whole point - scaling both together reads as zooming in,
	# not as weight landing.
	var squash := create_tween()
	squash.tween_property(sign_label, "scale", Vector2(1.25, 0.78), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	squash.tween_property(sign_label, "scale", Vector2(0.92, 1.12), 0.10) \
		.set_trans(Tween.TRANS_SINE)
	squash.tween_property(sign_label, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_burst_sign_ring(grade, at)

# A radial spray thrown outward as the sign lands, giving the sign its own beat
# distinct from the tally's upward flames. Scaled by grade and skipped entirely
# below OKAY: this fires per counted stop, so ringing every one of a nine-stop
# stage - on top of the click burst and the flames already firing - would read
# as continuous mush rather than punctuation.
const SIGN_RING_STRENGTH := {
	"PERFECT": 1.0,
	"GOOD": 0.55,
	"OKAY": 0.35,
}

func _burst_sign_ring(grade: String, at: Vector2) -> void:
	if not SIGN_RING_STRENGTH.has(grade):
		return
	# Escalation rides on top of the per-grade strength rather than replacing it,
	# so a late GOOD still reads as smaller than an early PERFECT.
	var strength: float = SIGN_RING_STRENGTH[grade] * Settings.effect_scale() \
		* lerpf(1.0, RING_ESCALATION_MAX, _reveal_intensity)
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0:
		return

	_sign_ring.position = at
	_sign_ring.amount = int(lerpf(14.0, 46.0, strength))
	_sign_ring.initial_velocity_min = lerpf(90.0, 170.0, strength)
	_sign_ring.initial_velocity_max = lerpf(180.0, 340.0, strength)

	var tint: Color = ScoreManager.grade_color(grade)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(tint.r, tint.g, tint.b, 0.9),
		Color(tint.r, tint.g, tint.b, 0.0),
	])
	_sign_ring.color_ramp = grad

	_sign_ring.restart()
	_sign_ring.emitting = true

func _show_streak_popup(count: int) -> void:
	# A fast streak (e.g. Stage 6/9's back-to-back Goldens) can call this again
	# before the previous popup's delayed fade-out has fired. Without killing
	# that old tween, it stays armed and can blank the label out from under a
	# freshly-shown popup - the bug this guards against.
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()

	_streak_label.text = "%dx PERFECT!" % count
	_streak_label.pivot_offset = _streak_label.size * 0.5
	_streak_label.modulate.a = 1.0
	_streak_label.scale = Vector2(1.5, 1.5)
	_streak_tween = create_tween()
	_streak_tween.set_parallel(true)
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_property(_streak_label, "modulate:a", 0.0, 0.7).set_delay(0.4)

func _pop(node: Control, scale_to: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2.ONE * scale_to, 0.08)
	tween.tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Gated here rather than at each call site, so no caller can reintroduce a
# full-screen flash by forgetting to check.
func _flash_screen(color: Color, alpha: float) -> void:
	if not Settings.motion_effects_enabled():
		return
	_flash.color = Color(color.r, color.g, color.b, alpha)
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.4)

# `tier` >= 0 switches to the finale's screen-wide configuration, scaled by how
# well the stage was played. Both branches set spread and color_ramp explicitly
# rather than only the finale doing so: the emitter is shared, so leaving the
# finale's settings on it would have the *next* stage's per-stop erupts inherit
# a wide gold spray.
func _erupt(intensity: float, focus: Control, tier: int = -1) -> void:
	_flames.position = focus.global_position - global_position + focus.size * 0.5

	if tier >= 0:
		var t: float = float(tier) / float(TIER_COLORS.size() - 1)
		_flames.amount = int(lerpf(110.0, 300.0, t))
		_flames.spread = lerpf(50.0, 95.0, t)
		_flames.initial_velocity_max = lerpf(420.0, 700.0, t)
		_flames.color_ramp = _tier_flame_gradient(tier)
	else:
		_flames.amount = int(lerpf(30.0, 120.0, intensity))
		_flames.spread = FLAME_SPREAD
		_flames.initial_velocity_max = lerpf(220.0, 440.0, intensity)
		_flames.color_ramp = _flame_grad_default

	_flames.restart()
	_flames.emitting = true

	# Both of these skip themselves entirely under reduce-intensity, so no scaling
	# is applied here - the flames above are what carry the beat in that case.
	_flash_screen(HEAT, lerpf(0.15, 0.35, intensity))
	Juice.shake(Juice.ShakeProfile.DECAY, lerpf(0.5, 1.0, intensity))

# The finale's flames take the tier colour at their core and fade out through
# it, rather than the default fire ramp - a top-tier clear should not look like
# a mediocre one with more particles.
func _tier_flame_gradient(tier: int) -> Gradient:
	var tint: Color = TIER_COLORS[tier]
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(tint.r, tint.g, tint.b, 1.0),
		Color(tint.r, tint.g, tint.b, 0.75),
		Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 0.0),
	])
	return grad

# --- Buttons --------------------------------------------------------------

# Three weights of the same idea rather than three colours. NEXT STAGE is the
# forward path and carries the row; RETRY is the same cyan a step quieter, so
# the pair reads as one family with an obvious default instead of two equal
# choices arguing in gold and blue; BACK TO TITLE drops out of the family
# entirely into muted flat text, since leaving is the one thing nobody needs
# help finding.
func _build_buttons(cleared: bool) -> void:
	if cleared:
		_add_button(_button_row, "RETRY", NEON, _on_retry, Emphasis.SECONDARY)
		_add_button(_button_row, "NEXT STAGE", NEON, _on_next)
	else:
		# Nothing to be secondary to on a fail - RETRY is the whole row.
		_add_button(_button_row, "RETRY", NEON, _on_retry)
	_add_button(_title_row, "BACK TO TITLE", MUTED, _on_title, Emphasis.TERTIARY)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on _on_title(), the same handler the on-screen BACK TO TITLE
# button uses - including while the tally is still counting up and that button
# hasn't appeared yet. A back press that silently does nothing reads as a hung
# app, and "leave this screen" is a legitimate intent at any point in the
# reveal; _leave_with_outro() already guards against re-entry.
#
# Guarded on the current state because hidden screens stay in the tree - see
# LevelSelect for the full note. This does not collide with the tally's own
# skip handler (_input, above): that one only matches mouse-left and ui_accept,
# and is inert outside the tally window anyway.
func _unhandled_input(event: InputEvent) -> void:
	var s := GameManager.current_state
	if s != GameManager.GameState.STAGE_CLEAR and s != GameManager.GameState.FAIL:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_title()
		get_viewport().set_input_as_handled()

# Both non-RETRY exits play the tier outro: either is "leaving the result
# screen", which is what the effect is echoing. RETRY deliberately does not -
# see _on_retry.
func _on_title() -> void:
	await _leave_with_outro(func(): GameManager.set_state(GameManager.GameState.MENU))

func _on_next() -> void:
	# Total was already committed as base + best in _finish_clear.
	if campaign_navigator.is_last_stage():
		# Stays on this screen, so nothing is being left and no outro is played.
		_show_campaign_complete()
		return
	await _leave_with_outro(func(): campaign_navigator.advance_next())

# Shared by every exit that actually leaves the screen. The state change happens
# behind the sweep rather than at the same instant, so the wipe reads as covering
# the cut instead of landing on top of an already-swapped screen.
func _leave_with_outro(go: Callable) -> void:
	if _transitioning:
		return
	_transitioning = true
	_set_buttons_disabled(true)
	await Juice.stage_outro(_outro_tier, TIER_COLORS[clampi(_outro_tier, 0, TIER_COLORS.size() - 1)])
	go.call()
	_transitioning = false

# Same fade-to-black-and-back as Endless's RESTART/RETRY (shared via
# Juice.run_transition), so retrying a stage reads as the same beat as
# retrying an Endless run rather than a bare instant cut.
func _on_retry() -> void:
	if _transitioning:
		return
	_transitioning = true
	_set_buttons_disabled(true)

	var start := func(): campaign_navigator.retry()
	await Juice.run_transition(start)

	_transitioning = false
	_set_buttons_disabled(false)

func _set_buttons_disabled(disabled: bool) -> void:
	for child in _button_row.get_children():
		if child is Button:
			child.disabled = disabled
	for child in _title_row.get_children():
		if child is Button:
			child.disabled = disabled

func _show_campaign_complete() -> void:
	for child in _button_row.get_children():
		child.queue_free()
	for child in _title_row.get_children():
		child.queue_free()
	# The campaign-complete screen is just the message + one button - hide all the
	# score readouts, and stop the idle pulse driving a now-hidden label.
	_stop_final_idle()
	_score_line.visible = false
	_final_label.visible = false
	_record_label.visible = false
	# The dividers bracket the score zone, so with the score gone they would be
	# ruling off nothing.
	for divider in [_divider_top, _divider_bottom]:
		if divider != null:
			divider.visible = false
	# The flourish is positioned off _final_label and can still be mid-animation
	# (or simply sitting there) from the stage clear that triggered this screen -
	# without this it floats on screen, pinned to a label that just disappeared
	# out from under it.
	if _badge != null:
		_badge.visible = false
	if _badge_glow != null:
		_badge_glow.visible = false

	_headline.text = COMPLETE_TEXT
	_headline.add_theme_font_size_override("font_size", FS_COMPLETE)  # long text: smaller so it fits
	_headline.add_theme_color_override("font_color", GOLD)
	_headline.add_theme_color_override("font_outline_color", GOLD.darkened(0.4))

	# Full emphasis here rather than the tertiary treatment it gets on a normal
	# result: there is nothing else to press and nowhere else to go.
	_add_button(_title_row, "BACK TO TITLE", GOLD, _on_finish)

	# Fires once ever, the moment the full campaign is completed - layered onto
	# this screen the same way the Endless-unlock flourish layers onto Stage 3's
	# clear, confirmed with the designer as its own distinct beat rather than
	# folded silently into the completion message above.
	if SaveManager.load_high_score("hardcore_unlock_seen") == 0:
		SaveManager.save_high_score("hardcore_unlock_seen", 1)
		_play_unlock_banner("HARDCORE UNLOCKED!")

func _on_finish() -> void:
	print("Campaign complete!")
	await _leave_with_outro(func(): GameManager.set_state(GameManager.GameState.MENU))

# --- UI construction ------------------------------------------------------

func _build_ui() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEWPORT_SIZE
	backdrop.color = Color(0.02, 0.02, 0.04, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# Added between the backdrop and the content, so the tint is genuinely
	# behind the reveal rather than a colour filter laid over its text. Built
	# white and coloured via modulate, so one texture serves every run.
	_anticipation = TextureRect.new()
	_anticipation.texture = _radial_glow_texture()
	_anticipation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_anticipation.stretch_mode = TextureRect.STRETCH_SCALE
	_anticipation.position = Vector2.ZERO
	_anticipation.size = VIEWPORT_SIZE
	_anticipation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anticipation.modulate.a = 0.0
	_anticipation.visible = false
	add_child(_anticipation)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	_headline = _make_label(FS_HEADLINE, HEAT)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_headline)

	# A reserved lane so the grade signs pop between the headline and the score
	# line instead of overlapping "STAGE CLEAR!".
	_sign_anchor = Control.new()
	_sign_anchor.custom_minimum_size = Vector2(0, 88)
	_sign_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_sign_anchor)

	# Opens the score zone.
	_divider_top = _make_divider()
	col.add_child(_divider_top)

	# "tally x mult" - score and multiplier on one line, same size. Muted rather
	# than cyan: this is the working, and it has to stay clearly subordinate to
	# the number it resolves into.
	_score_line = HBoxContainer.new()
	_score_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_line.add_theme_constant_override("separation", 16)
	col.add_child(_score_line)

	_score_digits = DigitCounter.new()
	_score_digits.configure(FS_TALLY, TEXT_FILL, MUTED)
	_score_line.add_child(_score_digits)
	_times_label = _make_label(FS_TALLY, MUTED)
	_times_label.text = "×"
	_score_line.add_child(_times_label)
	_mult_label = _make_label(FS_TALLY, MUTED)
	_score_line.add_child(_mult_label)

	_badge_lane = Control.new()
	_badge_lane.custom_minimum_size = Vector2(0, BADGE_LANE_HEIGHT)
	_badge_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_badge_lane)

	_final_label = _make_label(FS_HERO, GOLD, 6)
	_final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_final_label)

	# Supporting text takes the muted fill directly, with a dark edge only for
	# legibility over the backdrop - the same idiom the grade signs use.
	_record_label = _make_label(FS_SUPPORT, Color(0, 0, 0, 0.6), 3)
	_record_label.add_theme_color_override("font_color", MUTED)
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Height pinned so the column's vertical layout is fixed from construction:
	# this line can legitimately end up empty, and _position_badge reads the
	# score's position on the frame the record lands.
	_record_label.custom_minimum_size = Vector2(0, 34)
	col.add_child(_record_label)

	# Closes the score zone and opens the actions.
	_divider_bottom = _make_divider()
	col.add_child(_divider_bottom)

	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 24)
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Reserve the row's final height up front (buttons don't exist until the end).
	_button_row.custom_minimum_size = Vector2(0, 84)
	col.add_child(_button_row)

	# Second row, below the RETRY/NEXT STAGE row, for the title button.
	_title_row = HBoxContainer.new()
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_title_row)

	# Free-floating, like the streak popup below: parking it in the centred
	# column would reflow the whole layout the moment a record lands, shifting
	# the score the player is still reading.
	#
	# Soft radial halo first (so it sits behind the text, not on top of it),
	# same white-texture-tinted-via-modulate approach as the anticipation tint -
	# a glow rather than a box is what keeps this from reading as a button.
	_badge_glow = TextureRect.new()
	_badge_glow.texture = _radial_bloom_texture()
	_badge_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_badge_glow.size = BADGE_GLOW_SIZE
	_badge_glow.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 0.0)
	_badge_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_glow.visible = false
	_badge_glow.z_index = 21
	add_child(_badge_glow)

	# Plain outlined text - the same idiom the grade signs and streak popups use,
	# which already reads throughout this game as "celebratory, not clickable".
	_badge = _make_label(FS_BADGE, GOLD.darkened(0.2))
	_badge.text = "NEW BEST!"
	_badge.size = BADGE_SIZE
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	_badge.z_index = 22
	add_child(_badge)

	# Free-floating streak popup near the top (not in the centered column).
	_streak_label = _make_label(FS_STREAK, GOLD)
	_streak_label.text = ""
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.position = Vector2(0, 70)
	_streak_label.size = Vector2(VIEWPORT_SIZE.x, 50)
	_streak_label.modulate.a = 0.0
	_streak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_streak_label)

	# Added before _flash so the flash still reads over the top of a dimmed
	# screen - the breath beat dims the result content, not the punctuation.
	_dim = ColorRect.new()
	_dim.position = Vector2.ZERO
	_dim.size = VIEWPORT_SIZE
	_dim.color = Color(0.01, 0.01, 0.02, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# Between the dim and the flash: the wash is a sustained grade on the result,
	# so it sits over the dim but must not swallow the flash's punctuation.
	_wash = ColorRect.new()
	_wash.position = Vector2.ZERO
	_wash.size = VIEWPORT_SIZE
	_wash.color = Color(1, 1, 1, 0)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wash)

	_flash = ColorRect.new()
	_flash.position = Vector2.ZERO
	_flash.size = VIEWPORT_SIZE
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

const TEXT_FILL := Color("dfe3ee")  # soft off-white, calmer than pure white


# The running tally, rendered one Label per digit so a countup can pop only the
# digits that actually rolled rather than heaving the whole number. Scaling a
# Control inside a container doesn't affect layout, so a digit pops in place
# without nudging its neighbours.
class DigitCounter extends HBoxContainer:
	const POP_SCALE := 0.15       # added on top of 1.0
	const POP_DECAY := 9.0        # how fast a pop settles back
	# Without this the ones digit changes on nearly every frame of the tween and
	# pops ~60x a second, which reads as a vibrating blur rather than ticking.
	# At 90ms it tops out around 11 pops a second - legible as motion. Higher
	# digits change rarely, so they're unaffected and pop crisply on rollover.
	const POP_COOLDOWN := 0.09

	var _font_size: int = 54
	var _fill: Color = Color.WHITE
	var _outline: Color = Color.WHITE
	var _labels: Array[Label] = []
	var _pops: Array[float] = []
	var _cooldowns: Array[float] = []
	var _shown: String = ""

	# Colours are passed in rather than read from the outer class, so the digits
	# can't drift from the label styling they replaced.
	func configure(font_size: int, fill: Color, outline: Color) -> void:
		_font_size = font_size
		_fill = fill
		_outline = outline
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(value: int) -> void:
		var text := "%d" % value
		if text == _shown:
			return
		_resize_to(text.length())
		for i in range(text.length()):
			var ch := text[i]
			if _labels[i].text == ch:
				continue
			_labels[i].text = ch
			# Digit count changing (99 -> 100) shifts every column, so the guard
			# above would fire a pop on all of them at once. That's wanted - a
			# rollover *should* register across the whole number.
			if _cooldowns[i] <= 0.0:
				_pops[i] = 1.0
				_cooldowns[i] = POP_COOLDOWN
		_shown = text

	# Re-tints every digit already on screen, for a record that lands after the
	# countup has finished - configure() alone only affects labels created after
	# the call, and by the time a record is confirmed every digit already exists.
	func set_outline(color: Color) -> void:
		_outline = color
		for label in _labels:
			label.add_theme_color_override("font_outline_color", color)

	# Every digit at once, for a per-stop gain where the whole number deserves
	# emphasis - expressed in the same digit-level language as the countup rather
	# than as a competing whole-label pop.
	func punch_all(strength: float = 1.0) -> void:
		for i in range(_pops.size()):
			_pops[i] = strength
			_cooldowns[i] = POP_COOLDOWN

	func _resize_to(count: int) -> void:
		while _labels.size() < count:
			var l := Label.new()
			l.add_theme_font_size_override("font_size", _font_size)
			l.add_theme_color_override("font_color", _fill)
			l.add_theme_color_override("font_outline_color", _outline)
			l.add_theme_constant_override("outline_size", 4)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
			_labels.append(l)
			_pops.append(0.0)
			_cooldowns.append(0.0)
		while _labels.size() > count:
			var last: Label = _labels.pop_back()
			_pops.pop_back()
			_cooldowns.pop_back()
			last.queue_free()

	func _process(delta: float) -> void:
		for i in range(_labels.size()):
			if _cooldowns[i] > 0.0:
				_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
			if _pops[i] <= 0.0:
				continue
			_pops[i] = maxf(_pops[i] - delta * POP_DECAY, 0.0)
			var l := _labels[i]
			l.pivot_offset = l.size * 0.5
			l.scale = Vector2.ONE * (1.0 + POP_SCALE * _pops[i])

# A hairline that fades to nothing at both ends rather than a hard rule. An
# edge-to-edge line would draw a box around the score and read as a table; this
# reads as a change of subject. Built white and coloured via modulate, so the
# same texture serves both the resting muted state and the finale's tier tint.
func _make_divider() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 1

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Also sets the centred column's minimum width, which is what keeps the rules
	# wider than the text they bracket instead of hugging it.
	rect.custom_minimum_size = Vector2(DIVIDER_WIDTH, DIVIDER_THICKNESS)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(MUTED.r, MUTED.g, MUTED.b, DIVIDER_ALPHA)
	return rect

# `duration` of 0 assigns outright - a reveal reset has to be instant, since a
# tween there would be visibly undoing the previous attempt's tier.
func _tint_dividers(color: Color, duration: float) -> void:
	var target := Color(color.r, color.g, color.b, DIVIDER_ALPHA)
	for divider in [_divider_top, _divider_bottom]:
		if divider == null:
			continue
		if duration <= 0.0:
			divider.modulate = target
			continue
		var tween := create_tween()
		tween.tween_property(divider, "modulate", target, duration)

func _make_label(font_size: int, outline_color: Color, outline_size: int = 4) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_FILL)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", outline_size)
	return label

# Built white so the tint colour can come entirely from modulate - one texture
# covers every quality value instead of rebuilding a gradient per reveal. Same
# procedural radial idiom as Juice's heat and low-life vignettes: no image asset,
# and it re-rasterizes cleanly at whatever the canvas is scaled to.
func _radial_glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.35),
		Color(1, 1, 1, 1.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

# The inverse shape of _radial_glow_texture() above: bright at the centre,
# fading OUT to fully transparent at the edge. That one is a vignette (built to
# cover the whole screen and darken/tint its corners), which is why reusing it
# for the badge's halo produced a filled-looking rectangle instead of a glow -
# at a small size, "opaque at the edge" just reads as a solid box. A genuine
# soft bloom needs the opposite falloff.
func _radial_bloom_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.35),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

func _build_flames() -> void:
	_flames = CPUParticles2D.new()
	_flames.emitting = false
	_flames.one_shot = true
	_flames.explosiveness = 0.85
	_flames.lifetime = 0.6
	_flames.amount = 60
	_flames.direction = Vector2(0, -1)
	_flames.spread = FLAME_SPREAD
	_flames.gravity = Vector2(0, -260)
	_flames.initial_velocity_min = 120.0
	_flames.initial_velocity_max = 320.0
	_flames.scale_amount_min = 3.0
	_flames.scale_amount_max = 6.0

	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_flames.scale_amount_curve = shrink

	# Kept as a member so _erupt can put it back after the finale swaps in a
	# tier-coloured ramp - the emitter is shared between the two.
	_flame_grad_default = Gradient.new()
	_flame_grad_default.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	_flame_grad_default.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),
		Color(1.0, 0.75, 0.2, 1.0),
		Color(1.0, 0.35, 0.1, 0.9),
		Color(0.7, 0.1, 0.05, 0.0),
	])
	_flames.color_ramp = _flame_grad_default

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flames.material = add_mat
	_flames.z_index = 5
	add_child(_flames)

# A second, separate emitter from _flames - not a reconfiguration of it. The
# flames rise (negative gravity, narrow spread) and belong to the tally; this
# throws outward evenly and belongs to the sign, and the two fire close enough
# together that sharing one node would mean each restart cancelled the other.
func _build_sign_ring() -> void:
	_sign_ring = CPUParticles2D.new()
	_sign_ring.emitting = false
	_sign_ring.one_shot = true
	_sign_ring.explosiveness = 1.0     # all at once - a ring, not a stream
	_sign_ring.lifetime = 0.45
	_sign_ring.amount = 32
	_sign_ring.spread = 180.0          # +/-180 = the full circle
	_sign_ring.gravity = Vector2.ZERO  # nothing pulls it, so it stays a ring
	_sign_ring.damping_min = 120.0     # ... but it decelerates, so it has an edge
	_sign_ring.damping_max = 220.0
	_sign_ring.scale_amount_min = 2.0
	_sign_ring.scale_amount_max = 4.0

	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_sign_ring.scale_amount_curve = shrink

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sign_ring.material = add_mat
	# Above the flames (5) and the sign labels (20) so it reads as a burst
	# in front of the sign rather than something happening behind it.
	_sign_ring.z_index = 21
	add_child(_sign_ring)

# Rank within a row, expressed as weight rather than hue. PRIMARY is a lit
# panel, SECONDARY the same accent with the fill and glow taken away, TERTIARY
# is bare text that only becomes a button under the cursor. All three keep the
# accent, so a row still reads as one set of related choices.
enum Emphasis { PRIMARY, SECONDARY, TERTIARY }

func _add_button(container: HBoxContainer, text: String, accent: Color, handler: Callable,
		emphasis: int = Emphasis.PRIMARY) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	PressFeedback.apply(button)

	match emphasis:
		Emphasis.SECONDARY:
			button.custom_minimum_size = Vector2(240, 84)
			button.add_theme_font_size_override("font_size", FS_BUTTON)
			button.add_theme_color_override("font_color", accent.lerp(TEXT_FILL, 0.5))
			button.add_theme_constant_override("outline_size", 0)
			button.add_theme_stylebox_override("normal", _make_box(accent, 0.93, 0.0, 0, 2, 0.55))
			button.add_theme_stylebox_override("hover", _make_box(accent, 0.82, 0.3, 8, 2, 0.9))
			button.add_theme_stylebox_override("pressed", _make_box(accent, 0.72, 0.25, 4, 2, 0.9))
		Emphasis.TERTIARY:
			button.custom_minimum_size = Vector2(200, 54)
			button.add_theme_font_size_override("font_size", FS_SUPPORT)
			button.add_theme_color_override("font_color", accent)
			button.add_theme_color_override("font_hover_color", TEXT_FILL)
			button.add_theme_color_override("font_pressed_color", TEXT_FILL)
			button.add_theme_constant_override("outline_size", 0)
			button.add_theme_stylebox_override("normal", _make_box(accent, 1.0, 0.0, 0, 0, 0.0))
			button.add_theme_stylebox_override("hover", _make_box(accent, 0.88, 0.0, 0, 0, 0.0))
			button.add_theme_stylebox_override("pressed", _make_box(accent, 0.8, 0.0, 0, 0, 0.0))
		_:
			button.custom_minimum_size = Vector2(240, 84)
			button.add_theme_font_size_override("font_size", FS_BUTTON)
			button.add_theme_color_override("font_color", Color.WHITE)
			button.add_theme_color_override("font_outline_color", accent)
			button.add_theme_constant_override("outline_size", 5)
			button.add_theme_stylebox_override("normal", _make_box(accent, 0.85, 0.35, 8))
			button.add_theme_stylebox_override("hover", _make_box(accent, 0.7, 0.5, 12))
			button.add_theme_stylebox_override("pressed", _make_box(accent, 0.6, 0.4, 6))

	container.add_child(button)

# `darken` of 1.0 plus a 0-alpha border is what makes a flat, invisible box for
# the tertiary state - the content margins still apply, so the label keeps the
# same padding as a real button and the row doesn't shift on hover.
func _make_box(accent: Color, darken: float, shadow_alpha: float, shadow_size: int,
		border_width: int = 3, border_alpha: float = 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.darkened(darken), 0.0 if darken >= 1.0 else 1.0)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(border_width)
	sb.border_color = Color(accent.r, accent.g, accent.b, border_alpha)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb
