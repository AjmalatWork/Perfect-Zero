extends Control
class_name HUD

const SCORE_ACCENT := Color("22d3ff")   # cool cyan glow for the score
const MULT_LOW := Color("22d3ff")       # multiplier glow at x1.0 ...
const MULT_HIGH := Color("ff2e5e")      # ... shifting hot as the streak builds

# --- Big-score moment tuning ---------------------------------------------
# A single scoring hit at or above this many points erupts the "fire" moment.
# 200 => every GOLDEN stop (min 200) and every PERFECT at x2.0+ qualifies.
const BIG_SCORE_THRESHOLD := 200
const BIG_SCORE_MAX := 800               # delta mapped to full intensity here
const HEAT_COLOR := Color("ff5a1e")      # orange the score flashes to on a big hit

@onready var score_label: Label = $ScoreLabel
@onready var multiplier_label: Label = $MultiplierLabel
@onready var flash_rect: ColorRect = $FlashRect

var _last_multiplier: float = 1.0
var _last_score: int = 0

var _flames: CPUParticles2D

func _ready() -> void:
	_style_labels()
	_build_flames()

	# Scoring is deferred to the end-of-stage reveal, so in-game the score is frozen
	# and the multiplier is always x1.0 - nothing to show. Hidden here; the numbers
	# live on the StageResultScreen. The full-screen fail flash below stays active.
	score_label.hide()
	multiplier_label.hide()

	ScoreManager.score_changed.connect(_on_score_changed)
	EventBus.timer_expired.connect(_on_timer_expired)

	_last_score = ScoreManager.score
	_on_score_changed(ScoreManager.score, ScoreManager.multiplier)

func _style_labels() -> void:
	score_label.add_theme_font_size_override("font_size", 40)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_outline_color", SCORE_ACCENT)
	score_label.add_theme_constant_override("outline_size", 8)

	multiplier_label.add_theme_font_size_override("font_size", 52)
	multiplier_label.add_theme_color_override("font_color", Color.WHITE)
	multiplier_label.add_theme_constant_override("outline_size", 8)

func _build_flames() -> void:
	_flames = CPUParticles2D.new()
	_flames.emitting = false
	_flames.one_shot = true
	_flames.explosiveness = 0.85
	_flames.lifetime = 0.6
	_flames.amount = 60
	_flames.direction = Vector2(0, -1)
	_flames.spread = 35.0
	_flames.gravity = Vector2(0, -260)
	_flames.initial_velocity_min = 120.0
	_flames.initial_velocity_max = 300.0
	_flames.scale_amount_min = 3.0
	_flames.scale_amount_max = 6.0

	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_flames.scale_amount_curve = shrink

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),   # white-hot core
		Color(1.0, 0.75, 0.2, 1.0),   # yellow-orange
		Color(1.0, 0.35, 0.1, 0.9),   # orange-red
		Color(0.7, 0.1, 0.05, 0.0),   # red, fading out
	])
	_flames.color_ramp = grad

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flames.material = add_mat
	_flames.z_index = 5

	add_child(_flames)  # added last -> renders above the labels

func _on_score_changed(score: int, multiplier: float) -> void:
	score_label.text = "SCORE  %s" % ScoreManager.thousands(score)
	multiplier_label.text = "x%.1f" % multiplier

	# Glow shifts cyan -> hot pink and thickens as the multiplier climbs 1.0 -> 4.0.
	var t: float = clamp((multiplier - 1.0) / 3.0, 0.0, 1.0)
	multiplier_label.add_theme_color_override("font_outline_color", MULT_LOW.lerp(MULT_HIGH, t))
	multiplier_label.add_theme_constant_override("outline_size", int(round(lerp(8.0, 16.0, t))))

	if multiplier > _last_multiplier:
		_pop_multiplier_label()
	_last_multiplier = multiplier

	var delta: int = score - _last_score
	_last_score = score
	# Scoring is now revealed at end-of-stage (StageResultScreen), so this live path
	# stays dormant during play; the PLAYING guard also prevents the deferred commit
	# from erupting fire/shake behind the result screen.
	if delta >= BIG_SCORE_THRESHOLD and GameManager.current_state == GameManager.GameState.PLAYING:
		var intensity: float = clamp(
			float(delta - BIG_SCORE_THRESHOLD) / float(BIG_SCORE_MAX - BIG_SCORE_THRESHOLD), 0.0, 1.0)
		_big_score_moment(intensity)

func _big_score_moment(intensity: float) -> void:
	_emit_flames(intensity)
	# Shake/hit-stop are owned by Juice, which is the sole writer of Main's transform.
	Juice.shake(Juice.ShakeProfile.DECAY, lerp(0.7, 1.4, intensity))
	Juice.hit_stop()

	# Warm edge flash. A full-screen wash, so it's gated outright like every
	# other one - see Settings.motion_effects_enabled()'s own doc.
	if Settings.motion_effects_enabled():
		flash_rect.color = Color(1.0, 0.5, 0.1, lerp(0.2, 0.4, intensity))
		var flash_tween := create_tween()
		flash_tween.tween_property(flash_rect, "color:a", 0.0, 0.4)

	_pop_score_label(intensity)
	AudioManager.play_big_score(intensity)

func _emit_flames(intensity: float) -> void:
	_flames.position = score_label.position + score_label.size * 0.5
	_flames.amount = int(lerp(30.0, 120.0, intensity))
	_flames.initial_velocity_max = lerp(220.0, 420.0, intensity)
	_flames.restart()
	_flames.emitting = true

func _pop_score_label(intensity: float) -> void:
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2.ONE
	var pop := create_tween()
	pop.tween_property(score_label, "scale", Vector2.ONE * lerp(1.15, 1.4, intensity), 0.08)
	pop.tween_property(score_label, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Flash the score glow to hot orange, then ease it back to its cool cyan.
	var heat := create_tween()
	heat.tween_method(
		func(c: Color): score_label.add_theme_color_override("font_outline_color", c),
		HEAT_COLOR, SCORE_ACCENT, 0.5)

func _pop_multiplier_label() -> void:
	multiplier_label.pivot_offset = multiplier_label.size * 0.5
	multiplier_label.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(multiplier_label, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(multiplier_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_timer_expired(_source: Node, _grade: String) -> void:
	# Full-screen red wash - gated the same as the big-score flash above.
	if not Settings.motion_effects_enabled():
		return
	flash_rect.color = Color(1, 0, 0, 0.4)
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.4)
