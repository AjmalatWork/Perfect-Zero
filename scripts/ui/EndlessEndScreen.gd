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

# --- Palette ----------------------------------------------------------------
# Same five-role split as StageResultScreen, applied to this screen's own
# content: FAIL_RED stays headline-only ("RUN OVER" is a statement of fact, not
# a grade); GOLD is the outcome - the score and any record it set; NEON is
# reserved for the one interactive thing on screen (RETRY); MUTED carries the
# supporting stats (streak, time, the record line) so gold arrives unshared at
# the score. GREEN is kept only as a tier colour, not a static text colour.
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const GREEN := Color("39ff9e")
const FAIL_RED := Color("ff2e5e")
const MUTED := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")

# --- Type scale ---------------------------------------------------------------
const FS_HEADLINE := 60
const FS_HERO := 88        # the run's score - the equivalent of Stage's final_label
const FS_NEWBEST := 32
const FS_STAT := 28        # streak / survived
const FS_RECORD := 24      # the one supporting line for the score
const FS_BUTTON := 28
# Fixed so every row is the same overall width regardless of its own caption
# or value length - sized to fit the longest caption that can appear,
# "PREVIOUS BEST (Hardcore)", not the shortest.
const STAT_CAPTION_WIDTH := 270.0
const STAT_ROW_SEPARATION := 16.0

# --- Zone rules ---------------------------------------------------------------
# Matched to the stats table's own width (2 columns + the gap between them)
# rather than an independent constant, so the rule above it can't drift out of
# sync with a table that's wider or narrower than it used to be.
const DIVIDER_WIDTH := STAT_CAPTION_WIDTH * 2.0 + STAT_ROW_SEPARATION
const DIVIDER_THICKNESS := 2.0
const DIVIDER_ALPHA := 0.5

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

# --- New-best flourish -----------------------------------------------------
# A record is always the biggest beat this screen can produce, tier
# notwithstanding - these run unconditionally on any improved stat, layered on
# top of (not instead of) the punch/burst the flourish already had.
const NEWBEST_WASH_ALPHA := 0.22
const NEWBEST_WASH_IN := 0.12
const NEWBEST_WASH_OUT := 0.65
const NEWBEST_ECHO_DELAY := 0.24     # gap before the second burst - two beats, not one
const NEWBEST_HITSTOP_MULT := 1.6
const NEWBEST_IDLE_SCALE := 1.045    # shallow, same reasoning as StageResultScreen's idle pulse
const NEWBEST_IDLE_SEC := 1.05

@export var runner: EndlessRunner

var _newbest_label: Label
var _badge_lane: Control        # reserved space above the score for the NEW BEST label
var _divider_top: TextureRect
var _divider_bottom: TextureRect
# Typed as the inner class itself, not as its HBoxContainer base: configure()/
# set_value()/punch_all() are DigitCounter's own, and a base-typed variable
# would fail to resolve them at parse time.
var _score_digits: StageResultScreen.DigitCounter
# Each stat is caption + value in its own row so the two rows' colons can share
# one column width and land in the same place - a single centered "Best
# streak:  4" string has no way to guarantee that against "Survived:  24.8s".
# The row (not the label) carries the reveal fade, since the caption is static
# and has no countup of its own to gate its appearance on.
var _streak_row: HBoxContainer
var _streak_label: Label        # value cell only - see _count_stat
var _time_row: HBoxContainer
var _time_label: Label          # value cell only
var _record_row: HBoxContainer
var _record_caption: Label      # text varies at runtime ("BEST" vs "PREVIOUS BEST") - see _show_summary
var _record_label: Label        # value cell for the record row
var _button_row: HBoxContainer
var _retry_button: Button
var _back_button: Button
var _transitioning: bool = false
var _revealing: bool = false

# A full-screen tint for the record flourish and a slow idle shimmer on the
# score while a record's summary sits on screen - both exist only for the
# new-best case, layered on top of the punch/burst the flourish already had.
var _wash: ColorRect
var _score_idle_tween: Tween

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
	else:
		# The idle shimmer loops forever by design, so it has to be stopped
		# explicitly or it keeps ticking on a hidden score for the rest of the
		# session - screens stay in the tree here, only `visible` toggles.
		_stop_score_idle()

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

	await _count_stat(_streak_row, _streak_label, runner.run_best_streak, tier,
		func(v: int) -> String: return "%d" % v)
	await get_tree().create_timer(STAT_GAP, true, false, true).timeout
	if not _still_current(token):
		return

	await _count_stat(_time_row, _time_label, int(round(runner.run_time * 10.0)), tier,
		func(v: int) -> String: return _format_time(float(v) / 10.0))

	_show_summary()

	# One combined flourish listing whichever records fell, rather than firing
	# the same badge once per stat - three in a row would read as a stutter.
	var improved := _improved_stats()
	if not improved.is_empty():
		await get_tree().create_timer(FLOURISH_DELAY, true, false, true).timeout
		if not _still_current(token):
			return
		# Fire-and-forget: the flourish's own echo burst and idle shimmer are
		# guarded by `token` internally, so a retry landing mid-flourish can't
		# animate over the run that replaced it.
		_play_new_best_flourish(improved, token)

	# Tier is a run-quality read, same idiom as the Campaign reveal: earned in
	# the moment, then left on the structure so it persists on the settled
	# screen rather than fading with the punches and bursts above.
	_tint_dividers(TIER_COLORS[tier])

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
#
# Only writes the value now - the caption is a separate, static Label sharing
# `row` with it (see _build), which is what lets the two rows' colons line up.
# The row's own modulate (not the value label's) gates the reveal, since the
# caption has no countup of its own to hide behind otherwise.
func _count_stat(row: HBoxContainer, label: Label, value: int, tier: int,
		formatter: Callable) -> void:
	row.modulate.a = 1.0
	var apply := func(v: float) -> void:
		label.text = formatter.call(int(round(v)))
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

# One supporting line under the score, same rule as StageResultScreen: the
# hero digits already ARE this run's score, so a "Best: N" line only restates
# it the moment N == final_score (i.e. exactly when this run set the record).
# What's worth printing depends on the outcome - the mark that was beaten after
# a record, otherwise the mark still standing. A first-ever run (no prior best)
# gets neither; the flourish already says the only thing there is to say.
func _show_summary() -> void:
	var caption := ""
	var value := ""
	if runner.is_new_best:
		if runner.previous_best_score > 0:
			caption = "PREVIOUS BEST (%s)" % _mode_name()
			value = "%d" % runner.previous_best_score
	elif runner.best_score > 0:
		caption = "BEST (%s)" % _mode_name()
		value = "%d" % runner.best_score

	_record_caption.text = caption
	_record_label.text = value
	if value.is_empty():
		return
	var fade := create_tween()
	fade.tween_property(_record_row, "modulate:a", 1.0, 0.25)

# Centred over the reserved lane, which sits immediately above the score - the
# label is a free-floating sibling (not a child of the centred column) so
# showing it can't nudge the column's own layout, the same reasoning
# StageResultScreen's badge follows.
func _position_newbest() -> void:
	var lane: Vector2 = _badge_lane.global_position - global_position
	_newbest_label.size = Vector2(_badge_lane.size.x, _newbest_label.size.y)
	_newbest_label.position = Vector2(lane.x, lane.y + _badge_lane.size.y * 0.5 - _newbest_label.size.y * 0.5)

func _play_new_best_flourish(improved: PackedStringArray, token: int) -> void:
	_position_newbest()
	_newbest_label.text = "NEW BEST:  %s" % "  +  ".join(improved)
	_newbest_label.visible = true
	_newbest_label.modulate.a = 0.0
	_newbest_label.pivot_offset = _newbest_label.size * 0.5
	_newbest_label.scale = Vector2(1.6, 1.6)
	# The record belongs to the number, same idiom as StageResultScreen's badge:
	# the score keeps a brightened outline for as long as the summary is on
	# screen rather than the flourish being the only trace of it.
	_score_digits.set_outline(GOLD.lightened(0.3))

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_newbest_label, "modulate:a", 1.0, 0.18)
	tween.tween_property(_newbest_label, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# A warm wash across the whole screen - the same convention StageResultScreen's
	# finale uses (_wash_screen) to make a top result read as a whole-screen
	# event rather than something happening only inside one label.
	if Settings.motion_effects_enabled():
		_wash.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.0)
		var wash_tween := create_tween()
		wash_tween.tween_property(_wash, "color:a", NEWBEST_WASH_ALPHA, NEWBEST_WASH_IN)
		wash_tween.tween_property(_wash, "color:a", 0.0, NEWBEST_WASH_OUT)

	AudioManager.play_new_best()
	# Always at full strength regardless of tier - a record is a record, and a
	# modest run that still beat a modest best has earned the whole moment. The
	# hit-stop is new: a brief freeze-frame is the one thing punch/burst alone
	# don't give, and it's what Campaign's own finale uses for the same reason -
	# a record is the one moment this screen is allowed to be its biggest beat.
	Juice.hit_stop(NEWBEST_HITSTOP_MULT)
	Juice.punch(3.0)
	Juice.click_burst(
		_newbest_label.global_position + _newbest_label.size * 0.5, "PERFECT", -1, 1.0)

	# A second burst square on the score itself, staggered slightly behind the
	# first - two beats read as a bigger event than one. Guarded by token: a
	# fast retry can outlive this delay and land on a screen already reset for
	# the next run.
	await get_tree().create_timer(NEWBEST_ECHO_DELAY, true, false, true).timeout
	if not _still_current(token):
		return
	Juice.click_burst(
		_score_digits.global_position + _score_digits.size * 0.5, "PERFECT", -1, 1.0)

	# A slow, shallow idle shimmer keeps the record breathing while the player
	# reads the summary, instead of the flourish being the last thing that ever
	# moves on screen - same reasoning as StageResultScreen's idle pulse on its
	# settled final score.
	_start_score_idle()

func _start_score_idle() -> void:
	_stop_score_idle()
	_score_digits.pivot_offset = _score_digits.size * 0.5
	_score_idle_tween = create_tween().set_loops()
	_score_idle_tween.set_parallel(false)
	_score_idle_tween.tween_property(_score_digits, "scale",
		Vector2.ONE * NEWBEST_IDLE_SCALE, NEWBEST_IDLE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_score_idle_tween.tween_property(_score_digits, "scale", Vector2.ONE, NEWBEST_IDLE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_score_idle() -> void:
	if _score_idle_tween != null and _score_idle_tween.is_valid():
		_score_idle_tween.kill()
	_score_idle_tween = null
	if _score_digits != null:
		_score_digits.scale = Vector2.ONE

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
	# The idle shimmer loops forever by design, so a retry would otherwise start
	# a second one layered on the first.
	_stop_score_idle()
	if _wash != null:
		_wash.color.a = 0.0
	_set_score_display(0.0)
	# The flourish brightens this and leaves it bright, which is the point - so
	# a retry has to put it back.
	_score_digits.set_outline(GOLD)
	# modulate.a on the row (not `visible`) so the centred column keeps its final
	# height from the start and doesn't visibly reflow as each stat appears.
	# Captions are static now (see _build) - only the value text resets here.
	_streak_label.text = "0"
	_streak_row.modulate.a = 0.0
	_time_label.text = "0.0s"
	_time_row.modulate.a = 0.0
	_record_caption.text = ""
	_record_label.text = ""
	_record_row.modulate.a = 0.0
	# Tier tint is earned per reveal in the finale, so it has to be undone before
	# an attempt that may earn a different one (or none, if it never reaches the
	# tint call below because of a mid-reveal exit).
	_tint_dividers(MUTED, 0.0)

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

	col.add_child(_label("RUN OVER", FS_HEADLINE, FAIL_RED))

	# Opens the results zone.
	_divider_top = _make_divider()
	col.add_child(_divider_top)

	# Reserved lane so a late-arriving record can't reflow the column under it -
	# same trick StageResultScreen's badge lane uses.
	_badge_lane = Control.new()
	_badge_lane.custom_minimum_size = Vector2(0, 40)
	_badge_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_badge_lane)

	_newbest_label = _label("NEW BEST", FS_NEWBEST, GOLD)
	_newbest_label.visible = false
	add_child(_newbest_label)   # free-floating over the lane - see _position_newbest

	# The headline figure, rendered per-digit so the countup pops only the
	# columns that actually rolled - the same DigitCounter the Campaign reveal
	# uses, rather than a second implementation of the same idea. Outlined in
	# gold: this is the outcome, and nothing else on the screen shares that role.
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(score_row)
	_score_digits = StageResultScreen.DigitCounter.new()
	_score_digits.configure(FS_HERO, TEXT_FILL, GOLD)
	score_row.add_child(_score_digits)

	# Three supporting lines - the record, then two more stats - all sharing one
	# caption column so every line's gap sits at the same x, not just the
	# streak/survived pair. Wrapped in a CenterContainer so the whole block
	# centers together while each row's own alignment stays left internally -
	# that's what lets every caption share a left edge (and therefore a gap
	# position) instead of each row centering independently, which would let
	# them drift apart the moment any caption or value's width differs.
	var stats_wrap := CenterContainer.new()
	stats_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stats_wrap)
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 6)
	stats_wrap.add_child(stats_col)

	# Read a size smaller than the two below it - it's the mark this run is
	# measured against, not one of the two things the run itself did.
	var record_parts := _build_stat_row("BEST", FS_RECORD)
	_record_row = record_parts[0]
	_record_caption = record_parts[1]
	_record_label = record_parts[2]
	# A dimmer fill than the streak/survived rows below it (which keep the
	# default bright TEXT_FILL) - the record is a quieter, secondary fact next
	# to two lines reporting what THIS run actually did.
	for label in [_record_caption, _record_label]:
		label.add_theme_color_override("font_color", MUTED)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 3)
	# Legitimately blank on a first-ever run - see _show_summary - so the row's
	# height is reserved explicitly rather than left to its (empty) text.
	_record_row.custom_minimum_size = Vector2(0, 30)
	stats_col.add_child(_record_row)

	var streak_parts := _build_stat_row("BEST STREAK")
	_streak_row = streak_parts[0]
	_streak_label = streak_parts[2]
	stats_col.add_child(_streak_row)

	var time_parts := _build_stat_row("SURVIVED")
	_time_row = time_parts[0]
	_time_label = time_parts[2]
	stats_col.add_child(_time_row)

	# Closes the results zone.
	_divider_bottom = _make_divider()
	col.add_child(_divider_bottom)

	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 24)
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Reserve the row's height up front - the buttons don't exist until the
	# reveal finishes, and the column must not jump when they arrive.
	_button_row.custom_minimum_size = Vector2(0, 84)
	col.add_child(_button_row)

	# On top of everything else (self, not `col`) so the record flourish's wash
	# tints the whole screen rather than sitting behind the UI it's meant to
	# wash over - same ordering StageResultScreen's own _wash uses.
	_wash = ColorRect.new()
	_wash.position = Vector2.ZERO
	_wash.size = VIEWPORT_SIZE
	_wash.color = Color(1, 1, 1, 0)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wash)

# RETRY is the entire forward path on this screen - unlike Stage's cleared
# result, there is no "next" to be secondary to - so it takes the full NEON
# treatment. BACK TO TITLE drops out of that family into flat muted text, the
# same weighting Stage's fail state uses for the same reason: leaving is the
# one thing nobody needs help finding.
func _build_buttons() -> void:
	_retry_button = _button("RETRY", NEON)
	_retry_button.pressed.connect(_on_retry)
	_button_row.add_child(_retry_button)

	_back_button = _button("BACK TO TITLE", MUTED, true)
	_back_button.pressed.connect(_on_back)
	_button_row.add_child(_back_button)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK TO TITLE button uses.
# Guarded on the current state because hidden screens stay in the tree (see
# LevelSelect for the full note), and on _transitioning so a back press can't
# race a RETRY that is already tearing the run down behind the fade.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.ENDLESS_END:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	if _transitioning:
		return
	GameManager.set_state(GameManager.GameState.MENU)

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

# Returns [row, caption_label, value_label]. Caps, no colon - the same label
# idiom StageResultScreen's record line uses ("BEST   1152"), so the two
# screens' supporting text reads as one convention rather than two.
#
# Caption left-aligned, value right-aligned - a label/value table, not a
# colon-and-string sentence. Both cells get the SAME fixed width so every
# row's overall width is identical regardless of how long its own caption or
# value happens to be; without that, a row's width would vary with its
# content and the whole block would no longer centre consistently under the
# score above it.
func _build_stat_row(caption_text: String, font_size: int = FS_STAT) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(STAT_ROW_SEPARATION))

	var caption := _label(caption_text, font_size, MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.custom_minimum_size = Vector2(STAT_CAPTION_WIDTH, 0)
	row.add_child(caption)

	var value := _label("0", font_size, MUTED)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(STAT_CAPTION_WIDTH, 0)
	row.add_child(value)

	return [row, caption, value]

func _label(text: String, font_size: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# `flat` drops the lit-panel treatment for bare outlined text that only
# becomes a visible button under the cursor - the same de-emphasis
# StageResultScreen gives BACK TO TITLE, for the same reason.
func _button(text: String, accent: Color, flat: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	PressFeedback.apply(button)

	if flat:
		button.custom_minimum_size = Vector2(200, 54)
		button.add_theme_font_size_override("font_size", FS_RECORD)
		button.add_theme_color_override("font_color", accent)
		button.add_theme_color_override("font_hover_color", TEXT_FILL)
		button.add_theme_color_override("font_pressed_color", TEXT_FILL)
		button.add_theme_constant_override("outline_size", 0)
		button.add_theme_stylebox_override("normal", _box(accent, 1.0, 0))
		button.add_theme_stylebox_override("hover", _box(accent, 0.88, 0))
		button.add_theme_stylebox_override("pressed", _box(accent, 0.8, 0))
	else:
		button.custom_minimum_size = Vector2(240, 76)
		button.add_theme_font_size_override("font_size", FS_BUTTON)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", accent)
		button.add_theme_constant_override("outline_size", 4)
		button.add_theme_stylebox_override("normal", _box(accent, 0.85))
		button.add_theme_stylebox_override("hover", _box(accent, 0.7))
		button.add_theme_stylebox_override("pressed", _box(accent, 0.6))

	return button

# `border_width` 0 plus a fully-transparent fill is what makes a flat,
# invisible box for the tertiary state - content margins still apply, so the
# label keeps the same padding as a real button and the row doesn't shift.
func _box(accent: Color, darken: float, border_width: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.darkened(darken), 0.0 if darken >= 1.0 else 1.0)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(border_width)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.0 if border_width == 0 else 1.0)
	sb.set_content_margin_all(12)
	return sb

# Same fading hairline StageResultScreen uses - centre-bright, transparent at
# both ends, so it reads as a change of subject rather than a ruled-off table.
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
	rect.custom_minimum_size = Vector2(DIVIDER_WIDTH, DIVIDER_THICKNESS)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(MUTED.r, MUTED.g, MUTED.b, DIVIDER_ALPHA)
	return rect

# `duration` of 0 assigns outright - a reveal reset has to be instant, since a
# tween there would visibly undo the previous run's tier.
func _tint_dividers(color: Color, duration: float = 0.5) -> void:
	var target := Color(color.r, color.g, color.b, DIVIDER_ALPHA)
	for divider in [_divider_top, _divider_bottom]:
		if divider == null:
			continue
		if duration <= 0.0:
			divider.modulate = target
			continue
		var tween := create_tween()
		tween.tween_property(divider, "modulate", target, duration)
