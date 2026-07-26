extends Control
class_name StageResultScreen

# --- Reveal tuning --------------------------------------------------------
const STEP_TWEEN_TIME := 0.32     # seconds to tick the tally up per result
const STEP_GAP := 0.14            # pause between results
const FINALE_DELAY := 0.3         # beat before the finale multiply
const FINALE_HITSTOP_MULT := 3.0  # vs 1.0 everywhere in live play
const FINALE_PUNCH_MULT := 4.0    # vs 2.0 at a streak-8 PERFECT

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

const CLEAR_COLOR := Color("39ff9e")   # green headline on clear
const FAIL_COLOR := Color("ff2e5e")    # red headline on fail
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const HEAT := Color("ff5a1e")

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
var _attempt_label: Label
var _best_label: Label
var _button_row: HBoxContainer
var _title_row: HBoxContainer
var _streak_label: Label
var _streak_tween: Tween
var _flash: ColorRect
var _dim: ColorRect
var _wash: ColorRect
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

	_set_score_display(0.0)
	_set_mult_display(1.0)
	_reveal_streak = 0
	_reveal_grade_streak = 0
	_reveal_last_grade = ""
	_reveal_intensity = 0.0

	await _hold_breath()

	# Phase 1: tally the base points and build the multiplier, one stop at a time.
	for step in steps:
		await _animate_step(step)
		await get_tree().create_timer(STEP_GAP, true, false, true).timeout

	# Phase 2: the finale - the multiplier slams the tally into the final score.
	await get_tree().create_timer(FINALE_DELAY, true, false, true).timeout
	await _animate_finale(final_mult, stage_score, _quality_tier(_stage_quality(steps)))

	_finish_clear(stage_score)
	_revealing = false

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

	var tween := create_tween()
	tween.tween_method(_set_score_display, float(step["tally_before"]), float(step["tally_after"]), STEP_TWEEN_TIME)

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
	if stage_score > best:
		best = stage_score
		SaveManager.save_high_score(best_key, best)
	# Commit the campaign total as base + best. Best only ever rises, so a retry
	# that beats your previous best updates the total too; a worse retry leaves it.
	ScoreManager.set_score(stage_controller.stage_start_score + best, 1.0)

	_show_summary(stage_score, best)
	_build_buttons(true)
	_start_final_idle()

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
	_show_summary(0, best)
	_build_buttons(false)

func _show_summary(earned: int, best: int) -> void:
	_attempt_label.text = "This attempt:  %d" % earned
	_best_label.text = "Best for this stage:  %d" % best
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_attempt_label, "modulate:a", 1.0, 0.25)
	fade.tween_property(_best_label, "modulate:a", 1.0, 0.25)

# --- Display helpers ------------------------------------------------------

func _reset_display(cleared: bool) -> void:
	for child in _button_row.get_children():
		child.queue_free()
	for child in _title_row.get_children():
		child.queue_free()
	# modulate.a (not `visible`) so labels keep their layout space from the start
	# - otherwise the centered column grows as they appear and visibly shifts.
	_attempt_label.modulate.a = 0.0
	_best_label.modulate.a = 0.0

	# Cleared unconditionally: the FAIL path skips _hold_breath entirely, and a
	# reveal interrupted mid-breath would otherwise leave the screen dimmed.
	_dim.color.a = 0.0
	_wash.color.a = 0.0
	# The idle pulse loops forever by design, so a retry would otherwise start a
	# second one on top of the first.
	_stop_final_idle()

	_score_line.visible = true
	_score_line.modulate.a = 1.0
	_final_label.visible = true
	_final_label.modulate.a = 0.0
	_set_final_display(0.0)

	_headline.add_theme_font_size_override("font_size", 64)  # reset (completion shrinks it)

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
	# Glow warms from cyan toward gold as the multiplier climbs (uncapped).
	var t: float = clampf((mult - 1.0) / 5.0, 0.0, 1.0)
	_mult_label.add_theme_color_override("font_outline_color", NEON.lerp(GOLD, t))

func _sign_center() -> Vector2:
	return _sign_anchor.global_position - global_position + _sign_anchor.size * 0.5

func _spawn_sign(grade: String, at: Vector2) -> void:
	# Floating grade sign that pops with oomph, centered on `at` (its own lane).
	var sign_label := Label.new()
	sign_label.text = grade
	sign_label.add_theme_font_size_override("font_size", 44)
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

func _build_buttons(cleared: bool) -> void:
	if cleared:
		_add_button(_button_row, "RETRY", GOLD, _on_retry)
		_add_button(_button_row, "NEXT STAGE", NEON, _on_next)
	else:
		_add_button(_button_row, "RETRY", NEON, _on_retry)
	_add_button(_title_row, "BACK TO TITLE", Color("8b90a8"), _on_title)

func _on_title() -> void:
	GameManager.set_state(GameManager.GameState.MENU)

func _on_next() -> void:
	# Total was already committed as base + best in _finish_clear.
	if campaign_navigator.is_last_stage():
		_show_campaign_complete()  # stays on this screen - only Back to Title changes state
	else:
		campaign_navigator.advance_next()

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
	_attempt_label.visible = false
	_best_label.visible = false

	_headline.text = COMPLETE_TEXT
	_headline.add_theme_font_size_override("font_size", 32)  # long text: smaller so it fits
	_headline.add_theme_color_override("font_color", GOLD)
	_headline.add_theme_color_override("font_outline_color", GOLD.darkened(0.4))

	_add_button(_title_row, "BACK TO TITLE", GOLD, _on_finish)

func _on_finish() -> void:
	print("Campaign complete!")
	GameManager.set_state(GameManager.GameState.MENU)

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

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	_headline = _make_label(64, HEAT)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_headline)

	# A reserved lane so the grade signs pop between the headline and the score
	# line instead of overlapping "STAGE CLEAR!".
	_sign_anchor = Control.new()
	_sign_anchor.custom_minimum_size = Vector2(0, 88)
	_sign_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_sign_anchor)

	# "tally x mult" - score and multiplier on one line, same size.
	_score_line = HBoxContainer.new()
	_score_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_line.add_theme_constant_override("separation", 16)
	col.add_child(_score_line)

	_score_digits = DigitCounter.new()
	_score_digits.configure(54, TEXT_FILL, NEON)
	_score_line.add_child(_score_digits)
	_times_label = _make_label(54, Color(0.7, 0.72, 0.82))
	_times_label.text = "×"
	_score_line.add_child(_times_label)
	_mult_label = _make_label(54, NEON)
	_score_line.add_child(_mult_label)

	_final_label = _make_label(84, GOLD)
	_final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_final_label)

	_attempt_label = _make_label(28, Color(0, 0, 0, 0.55))  # subtle dark edge, not a white halo
	_attempt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_attempt_label)

	_best_label = _make_label(28, GOLD.darkened(0.35))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_best_label)

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

	# Free-floating streak popup near the top (not in the centered column).
	_streak_label = _make_label(40, GOLD)
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

func _make_label(font_size: int, outline_color: Color, outline_size: int = 4) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_FILL)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", outline_size)
	return label

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

func _add_button(container: HBoxContainer, text: String, accent: Color, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 84)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 5)
	button.add_theme_stylebox_override("normal", _make_box(accent, 0.85, 0.35, 8))
	button.add_theme_stylebox_override("hover", _make_box(accent, 0.7, 0.5, 12))
	button.add_theme_stylebox_override("pressed", _make_box(accent, 0.6, 0.4, 6))
	button.pressed.connect(handler)
	PressFeedback.apply(button)
	container.add_child(button)

func _make_box(accent: Color, darken: float, shadow_alpha: float, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb
