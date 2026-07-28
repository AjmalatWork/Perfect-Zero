extends Control
class_name EndlessEndScreen

# Endless's run summary. A dedicated sequence rather than a reuse of Campaign's
# stage-end reveal: the trigger is running out of lives rather than completing
# authored content, there is no per-stop tally to replay (Endless scores live),
# and the stats worth reporting are "how far did I get" rather than "how well
# did I play this stage". The countup/punch *techniques* are shared with that
# screen - DigitCounter and its digit-level pops come straight from it - but the
# pacing and the content are this mode's own.
#
# EndlessRunner has already banked the records by the time this runs; everything
# here reads what it left behind and animates it.

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const GREEN := Color("39ff9e")
const FAIL_RED := Color("ff2e5e")
const TEXT_FILL := Color("dfe3ee")

# --- Reveal pacing --------------------------------------------------------
# The stillness beat before the state change already supplied the "holding
# breath" pause, so this opens promptly instead of stalling a second time.
const OPENING_BEAT := 0.25
const SCORE_COUNT_SEC := 0.9
const STAT_COUNT_SEC := 0.5
const STAT_GAP := 0.18
const FLOURISH_DELAY := 0.35

# Tier scaling, mirroring the stage-end reveal's approach: a discrete step
# rather than a continuous lerp, so a strong run is recognisable by how its
# summary looks and not merely by the number on it.
const TIER_CUTS := [0.45, 0.9]
const TIER_COLORS := [Color("6b7080"), Color("39ff9e"), Color("ffd23f")]
const TIER_PUNCH := [1.2, 2.0, 3.2]
const TIER_BURST_INTENSITY := [0.0, 0.45, 1.0]

@export var runner: EndlessRunner

var _newbest_label: Label
# Typed as the inner class itself, not as its HBoxContainer base: configure()/
# set_value()/punch_all() are DigitCounter's own, and a base-typed variable
# would fail to resolve them at parse time.
var _score_digits: StageResultScreen.DigitCounter
var _streak_label: Label
var _time_label: Label
var _best_label: Label
var _button_row: HBoxContainer
var _retry_button: Button
var _back_button: Button
var _transitioning: bool = false
var _revealing: bool = false

# Bumped on every entry into ENDLESS_END. An in-flight reveal compares against
# it after each await and stands down if a newer one has started, so a sequence
# can never animate over the run that replaced it.
var _reveal_token: int = 0

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.ENDLESS_END:
		_run_reveal()

# --- Reveal ---------------------------------------------------------------

func _run_reveal() -> void:
	if runner == null:
		return
	_reveal_token += 1
	var token: int = _reveal_token
	_revealing = true

	var tier: int = _quality_tier(runner.run_quality)

	_reset_display()
	# Let the freshly-shown screen lay out before reading label rects for the
	# bursts - global_position is not final until a layout pass has run.
	await get_tree().process_frame
	await get_tree().create_timer(OPENING_BEAT, true, false, true).timeout
	if not _still_current(token):
		return

	# Score first and biggest - it is the headline figure and the one with a
	# record the player is most likely chasing.
	await _count_score(runner.final_score, tier)
	await get_tree().create_timer(STAT_GAP, true, false, true).timeout
	if not _still_current(token):
		return

	await _count_stat(_streak_label, "Best streak", runner.run_best_streak, tier,
		func(v: int) -> String: return "%d" % v)
	await get_tree().create_timer(STAT_GAP, true, false, true).timeout
	if not _still_current(token):
		return

	await _count_stat(_time_label, "Survived", int(round(runner.run_time * 10.0)), tier,
		func(v: int) -> String: return _format_time(float(v) / 10.0))

	_best_label.text = "Best (%s):  %d" % [_mode_name(), runner.best_score]
	var best_fade := create_tween()
	best_fade.tween_property(_best_label, "modulate:a", 1.0, 0.25)

	# One combined flourish listing whichever records fell, rather than firing
	# the same badge once per stat - three in a row would read as a stutter.
	var improved := _improved_stats()
	if not improved.is_empty():
		await get_tree().create_timer(FLOURISH_DELAY, true, false, true).timeout
		if not _still_current(token):
			return
		_play_new_best_flourish(improved)

	_build_buttons()
	_revealing = false

# A retry (or a jump back to the title) can land mid-reveal, and every await
# above is a place the sequence can resume into a screen that is no longer the
# one being shown. Bailing out here stops it animating over the next run.
#
# Checked by token as well as by state: a run short enough to end while the
# previous reveal is still animating would otherwise pass the state check (it
# really is ENDLESS_END again) and leave two sequences writing the same labels.
func _still_current(token: int) -> bool:
	if token != _reveal_token:
		return false
	if GameManager.current_state != GameManager.GameState.ENDLESS_END:
		_revealing = false
		return false
	return true

func _count_score(target: int, tier: int) -> void:
	var tween := create_tween()
	tween.tween_method(_set_score_display, 0.0, float(target), SCORE_COUNT_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	_score_digits.punch_all(lerpf(0.8, 1.6, float(tier) / 2.0))
	_burst_at(_score_digits, tier)
	AudioManager.play_big_score(lerpf(0.3, 1.0, float(tier) / 2.0))
	Juice.punch(TIER_PUNCH[tier])

# `value` is a plain integer countup; `formatter` turns it into the displayed
# string, which is what lets survival time animate as tenths of a second while
# still ticking up through whole units like the streak does.
func _count_stat(label: Label, caption: String, value: int, tier: int,
		formatter: Callable) -> void:
	label.modulate.a = 1.0
	var apply := func(v: float) -> void:
		label.text = "%s:  %s" % [caption, formatter.call(int(round(v)))]
	var tween := create_tween()
	tween.tween_method(apply, 0.0, float(value), STAT_COUNT_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	_pop(label, lerpf(1.1, 1.3, float(tier) / 2.0))
	# The Campaign reveal's own per-step stinger rather than a repurposed
	# gameplay cue - this is the same event (a figure landing during a summary),
	# so it should sound like one.
	AudioManager.play_reveal_step("GOOD", 0, TIER_BURST_INTENSITY[tier])

# Which stored records this run actually beat. Order is fixed rather than
# discovery-ordered so the same combination always reads the same way.
func _improved_stats() -> PackedStringArray:
	var out := PackedStringArray()
	if runner.is_new_best:
		out.append("SCORE")
	if runner.is_new_best_streak:
		out.append("STREAK")
	if runner.is_new_best_time:
		out.append("TIME")
	return out

func _play_new_best_flourish(improved: PackedStringArray) -> void:
	_newbest_label.text = "NEW BEST:  %s" % "  +  ".join(improved)
	_newbest_label.visible = true
	_newbest_label.modulate.a = 0.0
	_newbest_label.pivot_offset = _newbest_label.size * 0.5
	_newbest_label.scale = Vector2(1.6, 1.6)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_newbest_label, "modulate:a", 1.0, 0.18)
	tween.tween_property(_newbest_label, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	AudioManager.play_new_best()
	# Always at full strength regardless of tier - a record is a record, and a
	# modest run that still beat a modest best has earned the whole moment.
	Juice.punch(3.0)
	Juice.click_burst(
		_newbest_label.global_position + _newbest_label.size * 0.5, "PERFECT", -1, 1.0)

# Tier 0 gets no burst at all: a weak run should feel quieter, not merely
# smaller, and a token spray on every result devalues the ones that earned it.
func _burst_at(node: Control, tier: int) -> void:
	if TIER_BURST_INTENSITY[tier] <= 0.0:
		return
	Juice.click_burst(node.global_position + node.size * 0.5, "PERFECT", -1,
		TIER_BURST_INTENSITY[tier])

func _quality_tier(quality: float) -> int:
	var tier: int = 0
	for cut in TIER_CUTS:
		if quality >= cut:
			tier += 1
	return tier

func _set_score_display(value: float) -> void:
	_score_digits.set_value(int(round(value)))

func _format_time(seconds: float) -> String:
	var total := maxf(seconds, 0.0)
	var mins := int(total) / 60
	var secs := total - float(mins * 60)
	if mins > 0:
		return "%d:%04.1f" % [mins, secs]
	return "%.1fs" % secs

func _mode_name() -> String:
	return "Hardcore" if runner.max_lives <= 1 else "Normal"

func _reset_display() -> void:
	for child in _button_row.get_children():
		child.queue_free()
	_newbest_label.visible = false
	_newbest_label.scale = Vector2.ONE
	_set_score_display(0.0)
	# modulate.a rather than `visible` so the centred column keeps its final
	# height from the start and doesn't visibly reflow as each stat appears.
	_streak_label.text = "Best streak:  0"
	_streak_label.modulate.a = 0.0
	_time_label.text = "Survived:  0.0s"
	_time_label.modulate.a = 0.0
	_best_label.modulate.a = 0.0

func _pop(node: Control, scale_to: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2.ONE * scale_to, 0.08)
	tween.tween_property(node, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- UI construction ------------------------------------------------------

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEWPORT_SIZE
	backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_label("RUN OVER", 64, FAIL_RED))

	_newbest_label = _label("NEW BEST", 34, GREEN)
	_newbest_label.visible = false
	col.add_child(_newbest_label)

	# The headline figure, rendered per-digit so the countup pops only the
	# columns that actually rolled - the same DigitCounter the Campaign reveal
	# uses, rather than a second implementation of the same idea.
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(score_row)
	_score_digits = StageResultScreen.DigitCounter.new()
	_score_digits.configure(56, TEXT_FILL, NEON)
	score_row.add_child(_score_digits)

	_streak_label = _label("Best streak:  0", 30, GOLD)
	col.add_child(_streak_label)

	_time_label = _label("Survived:  0.0s", 30, NEON)
	col.add_child(_time_label)

	_best_label = _label("Best:  0", 26, GOLD.darkened(0.15))
	col.add_child(_best_label)

	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 24)
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Reserve the row's height up front - the buttons don't exist until the
	# reveal finishes, and the column must not jump when they arrive.
	_button_row.custom_minimum_size = Vector2(0, 84)
	col.add_child(_button_row)

func _build_buttons() -> void:
	_retry_button = _button("RETRY", NEON)
	_retry_button.pressed.connect(_on_retry)
	_button_row.add_child(_retry_button)

	_back_button = _button("BACK TO TITLE", GOLD)
	_back_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.MENU))
	_button_row.add_child(_back_button)

# Same fade-to-black-and-back as the pause menu's RESTART (shared via
# Juice.run_transition), so "tear down this run and start a fresh one" reads
# as one consistent beat regardless of which screen it's triggered from.
func _on_retry() -> void:
	if _transitioning:
		return
	_transitioning = true
	_retry_button.disabled = true
	_back_button.disabled = true

	var start := func(): runner.start_run(runner.max_lives)
	await Juice.run_transition(start)

	_transitioning = false
	if is_instance_valid(_retry_button):
		_retry_button.disabled = false
	if is_instance_valid(_back_button):
		_back_button.disabled = false

func _label(text: String, font_size: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 76)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	return button

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(12)
	return sb
