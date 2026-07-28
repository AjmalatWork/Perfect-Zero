extends Node

# Screen-level "feel" effects: hit-stop, shake, board punch, click bursts,
# reaction ripples and the streak heat vignette.
#
# This is the single owner of the Main root's transform - HUD and
# StageResultScreen route their shake/punch requests through here instead of
# touching Main.position directly, so nothing fights over it.
#
# All timing is real-time (Time.get_ticks_msec), not delta-based, so effects
# stay correct while Engine.time_scale is dipped by hit-stop.

const VIEWPORT_SIZE := Vector2(1600, 900)

# --- Hit-stop (PERFECT only) ---------------------------------------------
const HITSTOP_SCALE := 0.05      # near-freeze
const HITSTOP_MS := 60.0         # real-time duration, then a hard snap back

# --- Board punch --------------------------------------------------------
const PUNCH_BASE := 0.045        # scale delta on a plain PERFECT
const PUNCH_MS := 150.0
const PUNCH_ATTACK := 0.28       # fraction of the duration spent rising
const BACK_C1 := 1.70158         # ease-out-back overshoot constants
const BACK_C3 := BACK_C1 + 1.0

# --- Shake --------------------------------------------------------------
enum ShakeProfile { DECAY, JOLT }
const SHAKE_DECAY_MAG := 7.0     # celebratory: modest so live timers stay readable
const SHAKE_DECAY_MS := 220.0
const SHAKE_JOLT_MAG := 17.0     # flinch: sharper and shorter
const SHAKE_JOLT_MS := 170.0

# --- Streak heat --------------------------------------------------------
const HEAT_STREAK_MAX := 6       # streak at which the heat visual is fully maxed
const HEAT_VIGNETTE_ALPHA := 0.30
const HEAT_COLOR := Color("ff5a1e")
const HEAT_FADE_SPEED := 1.2

# --- Bursts / ripples ---------------------------------------------------
const FIZZLE_COLOR := Color("6b7080")   # duller grey for MISS/FAIL

# Applied to any burst whose stop actually banked a score multiplier. Matches
# Overclock's edge treatment so the two read as one state.
const MULTIPLIER_BURST_TINT := Color("ff1040")
const MULTIPLIER_BURST_BLEND := 0.35    # partial - the grade colour must survive
const MULTIPLIER_BURST_GROWTH := 1.25

# Campaign reveal escalation - see click_burst's `intensity` parameter.
const ESCALATION_BURST_GROWTH := 1.5
const ESCALATION_BURST_WIDTH := 1.4
const ESCALATION_BURST_WHITEN := 0.3   # brighter, without losing the grade colour
const RIPPLE_RADIUS := 900.0            # reaches the board edges from any cell
const RIPPLE_DURATION := 0.22           # fast enough to read as simultaneous

# --- Fail flash (FAIL) ----------------------------------------------------
# A plain colour-flash pulse, not true chromatic aberration - reading the screen
# texture via BackBufferCopy caused a one-frame ghost glitch on Chrome/macOS's
# WebGL backend. A flat ColorRect fade needs no screen texture, so it can't.
const ABERRATION_ENABLED := true
const ABERRATION_MS := 200.0
const ABERRATION_COLOR := Color(0.9, 0.15, 0.2, 0.22)

# --- Low-life ambient (Endless) ---------------------------------------------
# The danger counterpart to the streak-heat vignette above, built on the same
# radial-gradient pattern so the two read as a matched pair of ambient state
# tells rather than unrelated effects. They can legitimately be on at once (a
# hot streak on your last life), so - exactly like Overclock vs. heat - they are
# separated by BEHAVIOUR as well as hue: heat is a steady warm bloom whose alpha
# simply tracks the streak, while this is a deeper red that never sits still. The
# slow pulse is the distinguishing signal, not the colour.
#
# Deliberately slow and moderate: this is a calm-but-present "you are one mistake
# from the end", not an alarm. A fast or high-alpha version of this reads as
# panic and makes the board harder to actually play.
const LOW_LIFE_COLOR := Color("ff1030")
const LOW_LIFE_ALPHA := 0.26
const LOW_LIFE_PULSE_HZ := 0.55      # ~1.8s per breath
const LOW_LIFE_PULSE_DEPTH := 0.45   # fraction of alpha the pulse swings
const LOW_LIFE_FADE := 1.6

# --- Run-over stillness (Endless) -------------------------------------------
# The beat between the final life being lost and the summary appearing. Sits in
# the same family as StageResultScreen's "holding breath" pause, but owned here
# because it spans a state change (live board -> end screen) rather than
# happening inside one screen. IN + HOLD is the wait the player actually feels;
# OUT plays under the already-swapped end screen as it emerges from the dark.
const STILLNESS_COLOR := Color(0.01, 0.01, 0.02, 1.0)
const STILLNESS_ALPHA := 0.62
const STILLNESS_IN := 0.18
const STILLNESS_HOLD := 0.45
const STILLNESS_OUT := 0.3

var _low_life_vignette: TextureRect
var _low_life_target: float = 0.0
var _low_life_level: float = 0.0

var _stillness_rect: ColorRect

var heat: float = 0.0            # 0..1, driven by the live PERFECT streak

var _target: Node2D              # the Main root
var _base_position: Vector2
var _has_base: bool = false

var _timescale_end_ms: int = 0

var _shake_profile: int = ShakeProfile.DECAY
var _shake_mag: float = 0.0
var _shake_start_ms: int = 0
var _shake_duration: float = 0.0
var _shake_dir: Vector2 = Vector2.RIGHT

var _punch_mag: float = 0.0
var _punch_start_ms: int = 0

var _vignette: TextureRect
var _streak: int = 0

var _aberration_rect: ColorRect
var _aberration_end_ms: int = 0

var _transition_rect: ColorRect
const TRANSITION_COLOR := Color(0.02, 0.02, 0.03, 1.0)
const TRANSITION_FADE_SEC := 0.3

# --- Powerup wind-up ------------------------------------------------------
const WINDUP_SEC := 0.12         # anticipation beat before the effect's payload
const WINDUP_RING_RADIUS := 140.0
const WINDUP_PULL := 0.6         # fraction of PUNCH_BASE, applied inward

var _freeze_count: int = 0

# --- Nuke completion flash --------------------------------------------------
# Gold rather than white so it reads as Nuke's own colour, and opaque enough to
# wash out whatever ambient powerup tint is underneath rather than tinting with
# it. Fast in, slower out - a detonation, not a fade-up.
const NUKE_FLASH_COLOR := Color("ffd23f")
const NUKE_FLASH_ALPHA := 0.55
const NUKE_FLASH_IN_SEC := 0.05
const NUKE_FLASH_OUT_SEC := 0.22

var _nuke_flash: ColorRect

# --- Shield -----------------------------------------------------------------
# One cool-toned edge overlay serves both of Shield's states: held at a low
# alpha while the window is open (calm, deliberately quieter than Overclock -
# "you're covered", not "danger"), and flared hard for the catch.
const SHIELD_COLOR := Color("22d3ff")
const SHIELD_AURA_ALPHA := 0.16       # ambient, must not compete for attention
const SHIELD_FLARE_ALPHA := 0.72      # the catch
const SHIELD_AURA_FADE_SPEED := 2.2
# How long the FAIL's harsh feedback is allowed to run before the block cuts it
# off. Long enough to register as "this was going to hurt", short enough that it
# never reads as a FAIL the player actually took.
const SHIELD_HARSH_MS := 70.0
const SHIELD_ABSORB_TRAVEL := 0.26    # red burst's flight out to the boundary

var _shield_edge: TextureRect
var _shield_aura_target: float = 0.0
var _shield_flare_until_ms: int = 0

# --- Overclock --------------------------------------------------------------
# The streak-heat vignette is already a warm radial wash (ff5a1e, soft, creeping
# inward from the corners), so Overclock deliberately differs in BOTH colour and
# geometry rather than only hue: a deeper red, and hard bands clamped to the
# screen edges instead of a bloom. That's what keeps "the board is hot" and
# "Overclock is running" separable when a high streak coincides with the window.
const OVERCLOCK_COLOR := Color("ff1040")
const OVERCLOCK_BAND_ALPHA := 0.34
const OVERCLOCK_BAND_THICKNESS := 46.0
const OVERCLOCK_PULSE_HZ := 3.4       # edge throb, synced to the faster tick feel
const OVERCLOCK_PULSE_DEPTH := 0.35   # fraction of alpha the throb swings
const OVERCLOCK_FADE_IN := 6.0
const OVERCLOCK_FADE_OUT := 2.4       # ~400ms settle, not an instant cut
const OVERCLOCK_AMBIENT_BOOST := 0.35

var _overclock_bands: Control
var _overclock_target: float = 0.0
var _overclock_level: float = 0.0

# --- Combined Overclock + Shield --------------------------------------------
# Nothing stops both windows being open at once, and simply letting the two
# overlays alpha-blend reads as neither - a muddy purple edge that says less
# than either state does alone. So the pair gets its own look: Shield's soft
# cool glow tightens into a near-white containment *line*, the red bands ease
# off so they sit outside it rather than washing over it, and the two pulse in
# opposition. Read: heat pressing in, a shell holding it out.
const SHIELD_CONTAIN_COLOR := Color("b8f4ff")
const SHIELD_CONTAIN_ALPHA := 0.30    # brighter than the calm solo aura
const SHIELD_CONTAIN_PULSE := 0.30
const OVERCLOCK_COMBINED_DIM := 0.72  # bands step back so the rim reads

var _shield_tex_solo: GradientTexture2D
var _shield_tex_contained: GradientTexture2D
var _combined_active: bool = false

func _ready() -> void:
	# ALWAYS so a hit-stop can never leave time_scale dipped across a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.timer_stopped.connect(_on_timer_stopped)
	EventBus.timer_expired.connect(_on_timer_expired)
	EventBus.reaction_fired.connect(_on_reaction_fired)
	ScoreManager.perfect_streak_changed.connect(set_streak)
	GameManager.state_changed.connect(_on_state_changed)
	# Powerups is autoloaded *after* this one, so it isn't in the tree yet at
	# _ready() - deferring is what makes the singleton resolvable.
	call_deferred("_connect_powerups")

func _connect_powerups() -> void:
	Powerups.shield_armed.connect(_on_shield_armed)
	Powerups.shield_expired.connect(_on_shield_expired)
	Powerups.shield_absorbed.connect(shield_interrupt)
	Powerups.overclock_started.connect(_on_overclock_started)
	Powerups.overclock_ended.connect(_on_overclock_ended)

# Called by MainScreenRouter (which lives on Main) so we know what to shake.
func register_stage(node: Node2D) -> void:
	_target = node
	_base_position = node.position
	_has_base = true
	_build_vignette()
	_build_low_life_vignette()
	_build_aberration()

# --- Public API -----------------------------------------------------------

# Freeze-frames are the most disorienting effect here, so reduce_intensity skips
# them outright rather than merely shortening them.
func hit_stop(duration_mult: float = 1.0) -> void:
	if not Settings.motion_effects_enabled():
		return
	Engine.time_scale = HITSTOP_SCALE
	# Overlapping PERFECTs extend the window; they never stack the dip deeper.
	_timescale_end_ms = maxi(
		_timescale_end_ms, Time.get_ticks_msec() + int(HITSTOP_MS * duration_mult))

# Zooms the whole board, so it's gated outright rather than scaled. It can reach
# 4x on Campaign's finale and ~3.75x on a full-board Nuke - a ~18% zoom of the
# entire screen. That's real motion, and a fraction of it is still motion.
func punch(magnitude_mult: float = 1.0) -> void:
	if not Settings.motion_effects_enabled():
		return
	_punch_mag = PUNCH_BASE * magnitude_mult
	_punch_start_ms = Time.get_ticks_msec()

# Inverse of punch(): eases the board slightly *inward* rather than out. Shares
# the punch machinery - and therefore its curve and its sole ownership of Main's
# transform - rather than introducing a second competing transform source.
func pull(magnitude_mult: float = 1.0) -> void:
	if not Settings.motion_effects_enabled():
		return
	_punch_mag = -PUNCH_BASE * magnitude_mult
	_punch_start_ms = Time.get_ticks_msec()

# --- Gameplay freeze --------------------------------------------------------
# Suspends every gameplay clock - timer countdowns, Blue's pause, Golden's blur,
# powerup effect windows AND powerup cooldowns - while an animation has visually
# stopped the game. The rule is that nothing may quietly advance behind a frozen
# screen: without this, Nuke's cascade would let an Overclock expire mid-way and
# silently drop the later resolutions to a lower multiplier.
#
# Deliberately NOT get_tree().paused, which would also freeze the very tweens
# and RadialBursts the animation is made of. Deliberately not Engine.time_scale
# either - hit-stop owns that, and Powerups explicitly divides it back out.
#
# Counted rather than a bool so overlapping freezes can't have the first one to
# finish thaw the board out from under the second.
func freeze_gameplay() -> void:
	_freeze_count += 1

func release_gameplay() -> void:
	_freeze_count = maxi(_freeze_count - 1, 0)

func is_gameplay_frozen() -> bool:
	return _freeze_count > 0

# --- Powerup activation ---------------------------------------------------

# The anticipation beat shared by all three powerups: a ring collapsing onto the
# pressed button, plus a slight inward pull on the board. Called by
# Powerups.activate() *alongside* the mechanic, never as a gate on it.
func powerup_windup(origin_global: Vector2, accent: Color) -> void:
	if _target == null:
		return
	var ring := RadialBurst.new()
	_target.add_child(ring)
	ring.global_position = origin_global
	ring.configure(accent, WINDUP_RING_RADIUS, WINDUP_SEC, 5.0, true, true)
	pull(WINDUP_PULL)

# Nuke's payoff, fired when the cascade *finishes* rather than when the button
# is pressed - it punctuates the end of the chain. Lives on its own CanvasLayer
# above the ambient powerup tints so it overrides them outright instead of
# blending: the cascade has to read cleanly whatever else is running underneath.
func nuke_completion_flash() -> void:
	# A full-screen flash at 40% alpha is still a full-screen flash, so this is
	# skipped outright. The cascade's per-timer bursts and its arpeggio still land
	# the moment, so nothing about Nuke becomes unreadable without it.
	if not Settings.motion_effects_enabled():
		return
	_build_nuke_flash()
	if _nuke_flash == null:
		return
	_nuke_flash.visible = true
	_nuke_flash.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_nuke_flash, "modulate:a", NUKE_FLASH_ALPHA,
		NUKE_FLASH_IN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_nuke_flash, "modulate:a", 0.0, NUKE_FLASH_OUT_SEC)
	tween.tween_callback(func(): _nuke_flash.visible = false)

# --- Shield -----------------------------------------------------------------

# Both overlays are built together, whichever powerup triggers first. They are
# siblings under _target, so build order *is* draw order - building them lazily
# and independently made the stacking depend on which window the player happened
# to open first, i.e. Shield's rim would sometimes land over Overclock's bands
# and sometimes under. The combined state depends on that order being fixed:
# rim inboard and underneath, red bands outermost and on top.
func _build_powerup_overlays() -> void:
	_build_shield_edge()
	_build_overclock_bands()

func _on_shield_armed() -> void:
	_build_powerup_overlays()
	_shield_aura_target = SHIELD_AURA_ALPHA

# The window elapsed having caught nothing. Deliberately undramatic - the aura
# just fades. A player looking back should be able to tell this apart from a
# real catch purely by how it ended.
func _on_shield_expired() -> void:
	_shield_aura_target = 0.0

# The catch. The FAIL's harsh feedback visibly *begins* and is then cut off,
# rather than the game silently swapping which grade's feedback plays - the
# interruption is what sells the save.
#
# Both fail paths (clicked and expired) converge here. _on_timer_expired stands
# down when a catch is pending, since timer_expired fires before Endless offers
# the grade to Shield - without that, an expired catch would run the full harsh
# reaction on top of this one.
func shield_interrupt(origin_global: Vector2) -> void:
	_build_powerup_overlays()

	# 1. The harsh beat, cut short. reduce_intensity users get no aberration at
	#    all (aberration_pulse refuses outright there), so for them the jolt and
	#    the boundary flare below carry the moment on their own.
	shake(ShakeProfile.JOLT, 0.85)
	if ABERRATION_ENABLED and _aberration_rect != null \
			and Settings.motion_effects_enabled():
		_aberration_rect.visible = true
		_aberration_end_ms = Time.get_ticks_msec() + int(SHIELD_HARSH_MS)

	# 2. The FAIL's own red, thrown outward from the offending timer - it leaves
	#    rather than resolving where it happened.
	if _target != null:
		var thrown := RadialBurst.new()
		_target.add_child(thrown)
		thrown.global_position = origin_global
		thrown.configure(ScoreManager.grade_color("FAIL"), RIPPLE_RADIUS * 0.75,
			SHIELD_ABSORB_TRAVEL, 7.0, false)

	# 3. It dissipates against the boundary: the edge flares as it absorbs.
	await get_tree().create_timer(SHIELD_HARSH_MS / 1000.0, false, false, true).timeout
	_shield_flare_until_ms = Time.get_ticks_msec() + int(SHIELD_ABSORB_TRAVEL * 1000.0)
	# The window is spent, so the aura goes with it - but only after the flare
	# has had its moment, which _process handles via _shield_flare_until_ms.
	_shield_aura_target = 0.0

func _build_shield_edge() -> void:
	if _shield_edge != null or _target == null:
		return

	# Two looks, built up front and swapped by _process - see the combined-state
	# note on SHIELD_CONTAIN_COLOR. The contained variant peaks *inboard* of the
	# frame and fades again toward it, leaving the outermost sliver to Overclock's
	# red: that separation in space is what makes the pair read as heat outside a
	# shell rather than as two tints sharing an edge.
	_shield_tex_solo = _radial_edge_texture(SHIELD_COLOR, 0.78)
	_shield_tex_contained = _radial_rim_texture(SHIELD_CONTAIN_COLOR, 0.86, 0.10)

	_shield_edge = TextureRect.new()
	_shield_edge.texture = _shield_tex_solo
	_shield_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shield_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_shield_edge.position = Vector2.ZERO
	_shield_edge.size = VIEWPORT_SIZE
	_shield_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_edge.modulate.a = 0.0
	_target.add_child(_shield_edge)

# Same procedural radial-gradient technique as the heat vignette - no shader, no
# imported image. `inner_offset` is where the colour starts ramping up: the
# higher it is, the tighter the band, so 0.78 reads as a glow at the boundary
# and 0.90 as a drawn line.
func _radial_edge_texture(color: Color, inner_offset: float) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, inner_offset, 1.0])
	grad.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 1.0),
	])

	return _radial_texture(grad)

# A discrete band that peaks at `peak` and falls away on both sides, rather than
# ramping to maximum at the frame the way _radial_edge_texture does. Reads as a
# drawn line standing off the edge instead of a glow bleeding off it.
func _radial_rim_texture(color: Color, peak: float, half_width: float) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, peak - half_width, peak, 1.0])
	grad.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 1.0),
		Color(color.r, color.g, color.b, 0.15),
	])
	return _radial_texture(grad)

func _radial_texture(grad: Gradient) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

# --- Overclock --------------------------------------------------------------

func _on_overclock_started() -> void:
	_build_powerup_overlays()
	_overclock_target = 1.0
	AudioManager.set_ambient_boost(OVERCLOCK_AMBIENT_BOOST)

func _on_overclock_ended() -> void:
	_overclock_target = 0.0
	AudioManager.set_ambient_boost(0.0)
	# Powerups._reset() re-emits this when a run is abandoned mid-window, so the
	# cue would otherwise fire over the title screen.
	if GameManager.current_state == GameManager.GameState.ENDLESS_PLAYING:
		AudioManager.play_overclock_end()

func _build_overclock_bands() -> void:
	if _overclock_bands != null or _target == null:
		return

	_overclock_bands = Control.new()
	_overclock_bands.position = Vector2.ZERO
	_overclock_bands.size = VIEWPORT_SIZE
	_overclock_bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overclock_bands.visible = false
	_target.add_child(_overclock_bands)

	var t := OVERCLOCK_BAND_THICKNESS
	# Four hard-edged bands clamped to the frame. Four separate linear gradients
	# rather than one radial texture is the whole point - it's the *geometry*
	# that distinguishes this from the heat vignette, not just the colour.
	_add_band(Rect2(0, 0, VIEWPORT_SIZE.x, t), Vector2(0.5, 0.0), Vector2(0.5, 1.0))
	_add_band(Rect2(0, VIEWPORT_SIZE.y - t, VIEWPORT_SIZE.x, t),
		Vector2(0.5, 1.0), Vector2(0.5, 0.0))
	_add_band(Rect2(0, 0, t, VIEWPORT_SIZE.y), Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	_add_band(Rect2(VIEWPORT_SIZE.x - t, 0, t, VIEWPORT_SIZE.y),
		Vector2(1.0, 0.5), Vector2(0.0, 0.5))

func _add_band(rect: Rect2, from: Vector2, to: Vector2) -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(OVERCLOCK_COLOR.r, OVERCLOCK_COLOR.g, OVERCLOCK_COLOR.b, 1.0),
		Color(OVERCLOCK_COLOR.r, OVERCLOCK_COLOR.g, OVERCLOCK_COLOR.b, 0.0),
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 64
	tex.height = 64

	var band := TextureRect.new()
	band.texture = tex
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.position = rect.position
	band.size = rect.size
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overclock_bands.add_child(band)

func _build_nuke_flash() -> void:
	if _nuke_flash != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 55  # above the fail flash (50), below the run transition (60)
	add_child(layer)

	_nuke_flash = ColorRect.new()
	_nuke_flash.color = NUKE_FLASH_COLOR
	_nuke_flash.position = Vector2.ZERO
	_nuke_flash.size = VIEWPORT_SIZE
	_nuke_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nuke_flash.visible = false
	_nuke_flash.modulate.a = 0.0
	layer.add_child(_nuke_flash)

# Skipped rather than scaled when reduce-intensity is on. A 40%-amplitude shake
# is still the entire screen moving, which is precisely what the option exists to
# stop; everything that calls this has a non-moving companion effect (bursts,
# particles, flashes on the timer itself) carrying the same information.
func shake(profile: int = ShakeProfile.DECAY, magnitude_mult: float = 1.0) -> void:
	if not Settings.motion_effects_enabled():
		return
	_shake_profile = profile
	if profile == ShakeProfile.JOLT:
		_shake_mag = SHAKE_JOLT_MAG * magnitude_mult
		_shake_duration = SHAKE_JOLT_MS
		_shake_dir = Vector2.from_angle(randf() * TAU)  # jolt direction is fixed per hit
	else:
		_shake_mag = SHAKE_DECAY_MAG * magnitude_mult
		_shake_duration = SHAKE_DECAY_MS
	_shake_start_ms = Time.get_ticks_msec()

# `intensity` (0..1) is an optional escalation knob used by Campaign's reveal so
# each successive PERFECT counted blooms bigger than the last. Live play leaves
# it at zero - a click's burst should read the same on the first stop of a stage
# as on the ninth.
func click_burst(global_pos: Vector2, grade: String, type: int = -1,
		intensity: float = 0.0) -> void:
	if _target == null:
		return
	var burst := RadialBurst.new()
	_target.add_child(burst)
	burst.global_position = global_pos

	var tint: Color
	var radius: float
	var duration: float
	var width: float
	var double_ring: bool

	match grade:
		"PERFECT":
			tint = ScoreManager.grade_color("PERFECT")
			radius = 96.0
			duration = 0.44
			width = 6.5
			double_ring = true
			if type >= 0:
				tint = TimerTypeInfo.burst_tint_of(type, tint)
				# Golden's guaranteed PERFECT blooms bigger and warmer than one
				# the player actually had to time.
				if type == TimerData.TimerType.GOLDEN:
					radius = 124.0
		"GOOD", "OKAY":
			tint = ScoreManager.grade_color(grade)
			radius = 64.0
			duration = 0.32
			width = 4.0
			double_ring = false
		_:
			# MISS/FAIL: small, fast, no bright flash - a fizzle, not a celebration.
			tint = FIZZLE_COLOR
			radius = 40.0
			duration = 0.22
			width = 3.0
			double_ring = false

	# A stop that actually banked the multiplier bursts bigger and bleeds toward
	# Overclock's red, so the doubling is legible in peripheral vision without
	# having to read the badge. Only a partial blend - pushing all the way to red
	# would cost the grade colour, which is the more important signal.
	#
	# FAIL is excluded for the same reason it gets no badge: register_result()
	# returns before bonus_factor applies, so nothing was doubled.
	if grade != "FAIL" and Powerups.score_scale() > 1.0:
		tint = tint.lerp(MULTIPLIER_BURST_TINT, MULTIPLIER_BURST_BLEND)
		radius *= MULTIPLIER_BURST_GROWTH
		double_ring = true

	if intensity > 0.0:
		var esc: float = clampf(intensity, 0.0, 1.0)
		radius *= lerpf(1.0, ESCALATION_BURST_GROWTH, esc)
		width *= lerpf(1.0, ESCALATION_BURST_WIDTH, esc)
		tint = tint.lerp(Color.WHITE, esc * ESCALATION_BURST_WHITEN)

	burst.configure(tint, radius, duration, width, double_ring)

# FAIL only (not MISS) - a punctuation mark on the harsher outcome.
func aberration_pulse() -> void:
	if not ABERRATION_ENABLED or _aberration_rect == null:
		return
	if not Settings.motion_effects_enabled():
		return
	_aberration_rect.visible = true
	_aberration_end_ms = Time.get_ticks_msec() + int(ABERRATION_MS)

func reaction_ripple(origin_global: Vector2, type: int) -> void:
	if _target == null:
		return
	var ripple := RadialBurst.new()
	_target.add_child(ripple)
	ripple.global_position = origin_global
	ripple.configure(TimerTypeInfo.color_of(type), RIPPLE_RADIUS, RIPPLE_DURATION, 5.0, false)

# Low-life state source. Driven by EndlessRunner off its own lives bookkeeping
# rather than derived here, since "low" is a tunable threshold that belongs with
# the mode that owns lives. Campaign never calls this.
func set_low_life(active: bool) -> void:
	_low_life_target = 1.0 if active else 0.0

# Heat source. Campaign pushes a presentation-only streak from StageController;
# Endless arrives here via ScoreManager.perfect_streak_changed.
func set_streak(count: int) -> void:
	# _streak always updates (it drives punch milestones past the heat cap), but
	# only notify listeners when the derived heat actually moves.
	_streak = maxi(count, 0)
	var new_heat := clampf(float(_streak) / float(HEAT_STREAK_MAX), 0.0, 1.0)
	if is_equal_approx(new_heat, heat):
		return
	heat = new_heat
	EventBus.heat_changed.emit(heat)

# --- Event reactions ------------------------------------------------------

func _on_timer_stopped(_source: Node, grade: String, _type: int, _distance: float) -> void:
	# Suppressed inside a frozen presentation beat (Nuke's cascade): eight
	# PERFECTs' worth of hit-stop back to back would read as a stutter, not a
	# climax, and a hit-stop dipping time_scale mid-cascade would fight the
	# cascade's own pacing. The cascade lands one punch at the end instead,
	# scaled by how much it actually cleared. Per-slot click bursts are
	# unaffected - those are fired by TimerSlot, not from here.
	if is_gameplay_frozen():
		return
	match grade:
		"PERFECT":
			hit_stop()
			# Our handler runs before StageController/EndlessRunner update the
			# streak, so punch off the prospective value rather than the stale one.
			punch(_punch_mult_for_streak(_streak + 1))
			shake(ShakeProfile.DECAY)
		"MISS":
			shake(ShakeProfile.JOLT, 0.7)
		"FAIL":
			shake(ShakeProfile.JOLT, 1.0)
			aberration_pulse()

func _on_timer_expired(_source: Node) -> void:
	if is_gameplay_frozen():
		return
	# This runs *before* EndlessRunner offers the FAIL to Shield, so a
	# full-strength reaction here would beat the interrupt to the punch and make
	# an absorbed expiry look nothing like an absorbed click. Stand down and let
	# shield_interrupt() own the whole beat instead.
	if Powerups.will_absorb_fail():
		return
	# An unclicked expiry is a FAIL, so it gets the same punctuation.
	shake(ShakeProfile.JOLT, 1.0)
	aberration_pulse()

func _on_reaction_fired(source: Node, type: int, _affected: Array) -> void:
	if source is Control:
		reaction_ripple(source.global_position + source.size * 0.5, type)
	elif source is Node2D:
		reaction_ripple(source.global_position, type)

func _on_state_changed(new_state: int) -> void:
	var in_game := (new_state == GameManager.GameState.PLAYING
		or new_state == GameManager.GameState.ENDLESS_PLAYING)
	if _vignette != null:
		_vignette.visible = in_game
	if _shield_edge != null:
		_shield_edge.visible = in_game
	if not in_game:
		# A run left with Shield or Overclock still running would otherwise hand
		# its overlay to the next one, since nothing closes those windows on an
		# abandoned run.
		_shield_aura_target = 0.0
		_shield_flare_until_ms = 0
		if _shield_edge != null:
			_shield_edge.modulate.a = 0.0
		_overclock_target = 0.0
		_overclock_level = 0.0
		if _overclock_bands != null:
			_overclock_bands.visible = false
		# A run left on its last life would otherwise hand the danger vignette to
		# the next screen (and to the next run, which starts at full lives).
		_low_life_target = 0.0
		_low_life_level = 0.0
		if _low_life_vignette != null:
			_low_life_vignette.visible = false
		# Leaving play: drop heat and make sure no effect leaves Main displaced.
		set_streak(0)
		_reset_transform()
		# A run abandoned mid-cascade (restart, back to title) would otherwise
		# leave the next run's board frozen with no one left to release it.
		_freeze_count = 0

func _punch_mult_for_streak(streak: int) -> float:
	if streak >= 8:
		return 2.0
	if streak >= 5:
		return 1.7
	if streak >= 3:
		return 1.4
	return 1.0

# --- Per-frame application ------------------------------------------------

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()

	if not is_equal_approx(Engine.time_scale, 1.0) and now >= _timescale_end_ms:
		Engine.time_scale = 1.0

	if _vignette != null:
		_vignette.modulate.a = move_toward(
			_vignette.modulate.a, heat * HEAT_VIGNETTE_ALPHA, delta * HEAT_FADE_SPEED)

	if _low_life_vignette != null:
		_low_life_level = move_toward(_low_life_level, _low_life_target, delta * LOW_LIFE_FADE)
		_low_life_vignette.visible = _low_life_level > 0.001
		if _low_life_vignette.visible:
			# Scaled by effect_scale() rather than killed by
			# motion_effects_enabled(): a persistent pulsing red vignette is
			# squarely in the "aggressive" category the intensity policy covers,
			# but the authoritative life count is the cross row at the bottom of
			# the HUD, so softening this loses atmosphere and never loses
			# information.
			var breath: float = 1.0 - LOW_LIFE_PULSE_DEPTH \
				* (0.5 + 0.5 * cos(float(now) / 1000.0 * TAU * LOW_LIFE_PULSE_HZ))
			_low_life_vignette.modulate.a = LOW_LIFE_ALPHA * _low_life_level \
				* breath * Settings.effect_scale()

	# One phase drives both edge treatments, which is what lets the combined
	# state pulse in opposition rather than the two drifting against each other.
	var edge_phase := float(now) / 1000.0 * TAU * OVERCLOCK_PULSE_HZ
	# Floored rather than scaled by effect_scale(): these are the primary "this
	# is running" tells, so reduce_intensity may soften them but must not make
	# them unreadable the way it can with pure spectacle.
	var legibility := maxf(Settings.effect_scale(), 0.7)

	# Keyed off the windows being open, not off the faded levels, so the swap
	# happens once on entry/exit instead of flickering during a crossfade.
	var combined: bool = _shield_aura_target > 0.0 and _overclock_target > 0.0
	if combined != _combined_active:
		_combined_active = combined
		if _shield_edge != null:
			_shield_edge.texture = _shield_tex_contained if combined else _shield_tex_solo

	if _shield_edge != null:
		var shield_goal := _shield_aura_target
		if _combined_active:
			# The containment rim, brighter than the calm solo aura and pulsing
			# in counter-phase to the heat: as the red swells the rim rises to
			# meet it. Two overlays throbbing independently would just look busy.
			var rim := 1.0 - SHIELD_CONTAIN_PULSE * (0.5 + 0.5 * cos(edge_phase + PI))
			shield_goal = SHIELD_CONTAIN_ALPHA * rim * legibility
		# A catch flare outranks both - it has to punch through the combined
		# state as cleanly as it does the solo one.
		if now < _shield_flare_until_ms:
			shield_goal = SHIELD_FLARE_ALPHA
		# Flaring up is near-instant; settling back is not - an absorb should
		# read as a hard hit that then relaxes.
		var speed := 24.0 if shield_goal > _shield_edge.modulate.a else SHIELD_AURA_FADE_SPEED
		_shield_edge.modulate.a = move_toward(
			_shield_edge.modulate.a, shield_goal, delta * speed)

	if _overclock_bands != null:
		var oc_speed := OVERCLOCK_FADE_IN if _overclock_target > _overclock_level \
			else OVERCLOCK_FADE_OUT
		_overclock_level = move_toward(_overclock_level, _overclock_target, delta * oc_speed)
		_overclock_bands.visible = _overclock_level > 0.001
		if _overclock_bands.visible:
			# Throbbing edge, not a flat hold - the window should feel like it's
			# running hot the whole time, not like a static filter was switched on.
			var throb := 1.0 - OVERCLOCK_PULSE_DEPTH * (0.5 + 0.5 * cos(edge_phase))
			var dim := OVERCLOCK_COMBINED_DIM if _combined_active else 1.0
			_overclock_bands.modulate.a = (_overclock_level * OVERCLOCK_BAND_ALPHA
				* throb * legibility * dim)

	if _aberration_rect != null and _aberration_rect.visible:
		var remaining := float(_aberration_end_ms - now)
		if remaining <= 0.0:
			_aberration_rect.visible = false
			_aberration_rect.modulate.a = 0.0
		else:
			_aberration_rect.modulate.a = remaining / ABERRATION_MS

	if _target == null or not _has_base:
		return

	var punch_scale := _punch_value(now)
	# Compensate position so the scale reads as a zoom about the viewport centre
	# rather than about Main's top-left origin.
	_target.scale = Vector2.ONE * punch_scale
	_target.position = (_base_position + _shake_offset(now)
		- VIEWPORT_SIZE * 0.5 * (punch_scale - 1.0))

func _shake_offset(now: int) -> Vector2:
	if _shake_duration <= 0.0:
		return Vector2.ZERO
	var elapsed := float(now - _shake_start_ms)
	if elapsed >= _shake_duration:
		_shake_duration = 0.0
		return Vector2.ZERO
	var remaining := 1.0 - elapsed / _shake_duration
	if _shake_profile == ShakeProfile.JOLT:
		# One sharp directional hit with a fast cubic falloff - a flinch.
		return _shake_dir * _shake_mag * pow(remaining, 3.0) * cos(elapsed * 0.075)
	# Smooth decaying oscillation - celebratory.
	return Vector2(sin(elapsed * 0.055), cos(elapsed * 0.048)) * (_shake_mag * remaining)

func _punch_value(now: int) -> float:
	# Zero, not "<= 0" - a negative magnitude is a legitimate inward pull() and
	# must not be discarded here the way an unset punch is.
	if is_zero_approx(_punch_mag):
		return 1.0
	var elapsed := float(now - _punch_start_ms)
	if elapsed >= PUNCH_MS:
		_punch_mag = 0.0
		return 1.0
	var u := elapsed / PUNCH_MS
	var amp: float
	if u < PUNCH_ATTACK:
		amp = u / PUNCH_ATTACK
	else:
		# Ease-out-back on the release, matching the project's pop-in convention.
		amp = 1.0 - _ease_out_back((u - PUNCH_ATTACK) / (1.0 - PUNCH_ATTACK))
	return 1.0 + _punch_mag * amp

func _ease_out_back(v: float) -> float:
	return 1.0 + BACK_C3 * pow(v - 1.0, 3.0) + BACK_C1 * pow(v - 1.0, 2.0)

func _reset_transform() -> void:
	_shake_duration = 0.0
	_punch_mag = 0.0
	Engine.time_scale = 1.0
	_timescale_end_ms = 0
	if _target != null and _has_base:
		_target.position = _base_position
		_target.scale = Vector2.ONE

# --- Heat vignette --------------------------------------------------------

func _build_vignette() -> void:
	if _vignette != null or _target == null:
		return

	# Radial GradientTexture2D: transparent centre warming to HEAT_COLOR at the
	# edges. Procedural, so it needs no shader and no imported image.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(HEAT_COLOR.r, HEAT_COLOR.g, HEAT_COLOR.b, 0.0),
		Color(HEAT_COLOR.r, HEAT_COLOR.g, HEAT_COLOR.b, 0.0),
		Color(HEAT_COLOR.r, HEAT_COLOR.g, HEAT_COLOR.b, 1.0),
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.position = Vector2.ZERO
	_vignette.size = VIEWPORT_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_vignette.visible = false
	_target.add_child(_vignette)

# Same construction as the heat vignette, with the gradient's transparent core
# held wider (0.62 vs 0.55) so the red stays clear of the 3x3 grid and hugs the
# frame instead of creeping over the timers - this one is on continuously for
# potentially minutes at a time, where heat only spikes for a few seconds.
func _build_low_life_vignette() -> void:
	if _low_life_vignette != null or _target == null:
		return

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(LOW_LIFE_COLOR.r, LOW_LIFE_COLOR.g, LOW_LIFE_COLOR.b, 0.0),
		Color(LOW_LIFE_COLOR.r, LOW_LIFE_COLOR.g, LOW_LIFE_COLOR.b, 0.0),
		Color(LOW_LIFE_COLOR.r, LOW_LIFE_COLOR.g, LOW_LIFE_COLOR.b, 1.0),
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	_low_life_vignette = TextureRect.new()
	_low_life_vignette.texture = tex
	_low_life_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_low_life_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_low_life_vignette.position = Vector2.ZERO
	_low_life_vignette.size = VIEWPORT_SIZE
	_low_life_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_life_vignette.modulate.a = 0.0
	_low_life_vignette.visible = false
	_target.add_child(_low_life_vignette)

# --- Run-over stillness -----------------------------------------------------

func _build_stillness_rect() -> void:
	if _stillness_rect != null:
		return
	# Below the fail flash (50) and the run transition (60): the final FAIL's
	# own punctuation has to still read over this dim, and a RETRY fading to
	# black afterwards has to cover it.
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)

	_stillness_rect = ColorRect.new()
	_stillness_rect.color = STILLNESS_COLOR
	_stillness_rect.position = Vector2.ZERO
	_stillness_rect.size = VIEWPORT_SIZE
	_stillness_rect.visible = false
	_stillness_rect.modulate.a = 0.0
	layer.add_child(_stillness_rect)

# Dims the board and holds, calls `on_dark` (expected to swap in the end screen),
# then lifts the dim so the summary emerges out of it. Deliberately NOT gated by
# reduce_intensity: this is a navigational transition in the same family as
# run_transition() and the pause fades, not a flash or a shake.
#
# Awaiting it is what keeps the caller's teardown ordered behind the beat.
func run_over_stillness(on_dark: Callable) -> void:
	_build_stillness_rect()
	# STOP while the board is still visible underneath, so a player mashing
	# through the last FAIL can't click a live timer during the beat.
	_stillness_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_stillness_rect.visible = true
	_stillness_rect.modulate.a = 0.0

	var into := create_tween()
	into.tween_property(_stillness_rect, "modulate:a", STILLNESS_ALPHA, STILLNESS_IN)
	await into.finished

	await get_tree().create_timer(STILLNESS_HOLD, true, false, true).timeout

	on_dark.call()
	# The end screen owns input from here - keep the fading dim out of its way.
	_stillness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var out := create_tween()
	out.tween_property(_stillness_rect, "modulate:a", 0.0, STILLNESS_OUT)
	await out.finished
	_stillness_rect.visible = false

# --- Stage outro ------------------------------------------------------------
# Leaving the Arcade result screen echoes how the stage actually went: a strong
# clear wipes brighter and faster, a mediocre one is a plainer, slower cut.
# Keyed purely off the tier the reveal already computed - this owns no state and
# derives no quality metric of its own.
#
# Deliberately separate from run_transition(): that one is the shared
# fade-to-black used by RETRY and PauseMenu's RESTART, and is meant to read
# identically from every entry point. This one exists precisely to differ.
const OUTRO_DURATION := [0.34, 0.26, 0.2]   # higher tier = faster
const OUTRO_ALPHA := [0.45, 0.72, 0.95]     # higher tier = brighter
const OUTRO_BAND_WIDTH := 0.55              # fraction of the screen the sweep spans

var _outro_layer: CanvasLayer
var _outro_band: TextureRect

func _build_outro() -> void:
	if _outro_band != null:
		return
	# Below run_transition's layer (60) so a RETRY fading to black still covers
	# a sweep that happens to be mid-flight.
	_outro_layer = CanvasLayer.new()
	_outro_layer.layer = 55
	add_child(_outro_layer)

	# White gradient tinted per tier via modulate, same approach as the
	# anticipation tint - one texture, every variant.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 128
	tex.height = 4

	_outro_band = TextureRect.new()
	_outro_band.texture = tex
	_outro_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_outro_band.stretch_mode = TextureRect.STRETCH_SCALE
	_outro_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outro_band.size = Vector2(VIEWPORT_SIZE.x * OUTRO_BAND_WIDTH, VIEWPORT_SIZE.y)
	_outro_band.visible = false
	_outro_layer.add_child(_outro_band)

# Sweeps a tier-coloured band across the screen. Awaitable, so the caller can
# change state behind it rather than cutting mid-sweep.
#
# The tint is passed in rather than looked up here: the tier palette belongs to
# the screen that computes the tier, and copying it into this file would be a
# second source of truth for the same colours.
func stage_outro(tier: int, tint: Color) -> void:
	_build_outro()
	var t: int = clampi(tier, 0, OUTRO_DURATION.size() - 1)
	var duration: float = OUTRO_DURATION[t]

	_outro_band.modulate = Color(tint.r, tint.g, tint.b, OUTRO_ALPHA[t] * Settings.effect_scale())
	_outro_band.position = Vector2(-_outro_band.size.x, 0)
	_outro_band.visible = true

	var tween := create_tween()
	tween.tween_property(_outro_band, "position:x", VIEWPORT_SIZE.x, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_outro_band.visible = false

# --- Fail flash ------------------------------------------------------------

func _build_aberration() -> void:
	if not ABERRATION_ENABLED or _aberration_rect != null:
		return

	# Its own CanvasLayer, above everything and outside Main's shake/punch
	# transform so the flash doesn't inherit the very motion it punctuates.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	_aberration_rect = ColorRect.new()
	_aberration_rect.color = ABERRATION_COLOR
	_aberration_rect.position = Vector2.ZERO
	_aberration_rect.size = VIEWPORT_SIZE
	_aberration_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aberration_rect.visible = false
	_aberration_rect.modulate.a = 0.0
	layer.add_child(_aberration_rect)

# --- Run transition (restart / play-again) ---------------------------------
# A shared fade-to-black-and-back for any "tear down the current run and start
# a fresh one" moment - used by the pause menu's RESTART and the Endless end
# screen's RETRY, so both read as the same beat instead of two hand-rolled
# fades drifting apart. Solid black (not the fail flash's translucent tint) and
# on its own CanvasLayer above everything, including that flash - a restart
# can land right on top of a FAIL's aberration pulse and must win.
func _build_transition_rect() -> void:
	if _transition_rect != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	_transition_rect = ColorRect.new()
	_transition_rect.color = TRANSITION_COLOR
	_transition_rect.position = Vector2.ZERO
	_transition_rect.size = VIEWPORT_SIZE
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_rect.visible = false
	_transition_rect.modulate.a = 0.0
	layer.add_child(_transition_rect)

# Fades to black, calls `on_black` (expected to swap in the new run - hide any
# caller-side menu, unpause, start_run()/retry()), then fades back in. Runs on
# this autoload rather than the caller so the tween keeps advancing even while
# `get_tree().paused` is true (PROCESS_MODE_ALWAYS, same reason hit-stop works
# under a dipped time_scale). Await the returned value to know when it's done.
func run_transition(on_black: Callable) -> void:
	_build_transition_rect()
	_transition_rect.visible = true
	_transition_rect.modulate.a = 0.0

	var out_tween := create_tween()
	out_tween.tween_property(_transition_rect, "modulate:a", 1.0, TRANSITION_FADE_SEC)
	await out_tween.finished

	on_black.call()

	var in_tween := create_tween()
	in_tween.tween_property(_transition_rect, "modulate:a", 0.0, TRANSITION_FADE_SEC)
	await in_tween.finished
	_transition_rect.visible = false
