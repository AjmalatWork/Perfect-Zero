extends Control
class_name EndlessHUD

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const FAIL_RED := Color("ff2e5e")
const TEXT_FILL := Color("dfe3ee")

# Equation/total type scale. Bumped in portrait only, matching the mobile
# touch-target/type-size pass done elsewhere (Help/Options/Scores etc.);
# landscape (desktop/web) keeps the original sizes.
const EQUATION_FONT_LANDSCAPE := 56
const EQUATION_FONT_PORTRAIT := 78
const TOTAL_FONT_LANDSCAPE := 26
const TOTAL_FONT_PORTRAIT := 36
const EQUATION_HEIGHT_LANDSCAPE := 72.0
const EQUATION_HEIGHT_PORTRAIT := 100.0
const TOTAL_HEIGHT_LANDSCAPE := 34.0
const TOTAL_HEIGHT_PORTRAIT := 48.0
const EQUATION_TOP_LANDSCAPE := 14.0
# Below the pause/help icon row instead of beside/behind it (a user request) -
# icon row bottom is PAUSE_ICON_TOP_MARGIN_PORTRAIT (40) + icon height (120) =
# 160. Pushed further down a second time (180 -> 260) on a further user
# request for more clearance below the icons.
const EQUATION_TOP_PORTRAIT := 260.0
const TOTAL_GAP_LANDSCAPE := 4.0
const TOTAL_GAP_PORTRAIT := 8.0
# Gap between TOTAL and whichever transient popup (streak/milestone) follows -
# the two share almost the same slot (see _milestone_label below).
const POPUP_GAP := 10.0
const POPUP_TO_MILESTONE_GAP := 50.0

var _equation: Label
var _total: Label
var _streak_popup: Label
var _streak_tween: Tween
var _milestone_tween: Tween
var _crosses_row: HBoxContainer
var _cross_labels: Array = []
var _last_mult: float = 1.0
var _last_streak: int = 0
var _bottom_row: Control

# --- Live streak counter (persistent, distinct from the growth-pop above) ---
var _streak_counter: Label

# --- Pre-run target + live overtake/milestone reactions (Reward brief §5-7) -
# _target_best comes from EndlessRunner.start_run() (the record this run is
# chasing); 0 means no record exists yet, which suppresses both reactions
# entirely rather than firing against a meaningless baseline.
var _target_best: int = 0
var _overtake_fired: bool = false
var _milestone_label: Label

# Fixed anchors for the early run - untouched by the geometric scaling below,
# so a returning player's first three stingers land exactly where they always
# have.
const MILESTONE_BASE: Array[int] = [1000, 5000, 10000]

# GDD §7 left "do thresholds repeat/scale past 10000, or stop at three" as an
# open design question - answered: scale geometrically rather than stop, so a
# strong run keeps getting stingers instead of going quiet for good past the
# ten-minute mark. Repeating x2.5/x2/x2 multiplies by exactly 10 every three
# steps, which keeps every generated value a round number (10k -> 25k -> 50k
# -> 100k -> 250k -> ...) while averaging out to roughly doubling per step -
# in the same spirit as the score curve's own compounding multiplier, rather
# than a flat +N that would matter less and less as scores grow.
#
# These are a placeholder, not a measured curve: there was no real Hardcore
# score data available to calibrate against when this was written, so the
# ratios were picked by feel. Retune this array first if playtesting shows the
# late thresholds landing too close together (numbing) or too far apart
# (silent for too long) - nothing else here needs to change to retune it.
const GEOMETRIC_STEP := [2.5, 2.0, 2.0]

# Grows past MILESTONE_BASE on demand as a run's score climbs past the last
# generated value - see _check_milestones(). Reset to a fresh copy of
# MILESTONE_BASE by set_target() at the start of every run.
var _milestone_values: Array[int] = MILESTONE_BASE.duplicate()
var _milestone_step_index: int = 0
var _milestones_fired: Dictionary = {}

# Fail-cross row. Bumped in portrait to fit the bigger crosses (see
# _build_cross_icon) - landscape (desktop/web) is unaffected. Bumped a second
# time (64 -> 104) on a further user request ("much more").
const CROSS_BOX_SIZE_LANDSCAPE := 40.0
const CROSS_BOX_SIZE_PORTRAIT := 104.0
const CROSS_LINE_WIDTH_LANDSCAPE := 6.0
const CROSS_LINE_WIDTH_PORTRAIT := 16.0
const CROSS_SEPARATION_LANDSCAPE := 16
const CROSS_SEPARATION_PORTRAIT := 40
const BOTTOM_ROW_HEIGHT_LANDSCAPE := 50.0
const BOTTOM_ROW_HEIGHT_PORTRAIT := 140.0
# Distance from the row's own bottom edge to the true canvas bottom edge
# (before the safe-area lift in _apply_safe_area). PowerupBar.gd's
# CROSS_ROW_TOP_MARGIN_PORTRAIT mirrors margin+height so it can sit just above
# this row - keep the two in sync if either changes.
const BOTTOM_ROW_MARGIN_PORTRAIT := 30.0

func _bottom_row_height() -> float:
	return BOTTOM_ROW_HEIGHT_PORTRAIT if Layout.is_portrait() else BOTTOM_ROW_HEIGHT_LANDSCAPE

# Authored (inset-free) position; _apply_safe_area() offsets from this. A
# function rather than a const now that the canvas height differs by orientation.
func _bottom_row_pos() -> Vector2:
	if Layout.is_portrait():
		return Vector2(0, Layout.canvas_size.y - BOTTOM_ROW_MARGIN_PORTRAIT - _bottom_row_height())
	return Vector2(0, Layout.canvas_size.y - 60)

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	SafeArea.changed.connect(_apply_safe_area)
	# Repositioned rather than rebuilt on an orientation flip: these labels carry
	# live text and in-flight tweens (the streak popup especially), so tearing
	# them down mid-run would drop state the run still needs.
	Layout.changed.connect(_apply_canvas_metrics)
	_apply_canvas_metrics()

	ScoreManager.tally_changed.connect(_on_tally_changed)
	ScoreManager.campaign_total_changed.connect(_on_total_changed)
	ScoreManager.perfect_streak_changed.connect(_on_streak_changed)
	_on_tally_changed(ScoreManager.stage_tally, ScoreManager.multiplier)
	_on_total_changed(ScoreManager.campaign_total)

# --- Equation/total vertical stack (helpers shared by _build/_apply_canvas_metrics) ---

func _equation_top() -> float:
	return EQUATION_TOP_PORTRAIT if Layout.is_portrait() else EQUATION_TOP_LANDSCAPE

func _equation_font() -> int:
	return EQUATION_FONT_PORTRAIT if Layout.is_portrait() else EQUATION_FONT_LANDSCAPE

func _total_font() -> int:
	return TOTAL_FONT_PORTRAIT if Layout.is_portrait() else TOTAL_FONT_LANDSCAPE

func _equation_height() -> float:
	return EQUATION_HEIGHT_PORTRAIT if Layout.is_portrait() else EQUATION_HEIGHT_LANDSCAPE

func _total_height() -> float:
	return TOTAL_HEIGHT_PORTRAIT if Layout.is_portrait() else TOTAL_HEIGHT_LANDSCAPE

func _total_top() -> float:
	var gap: float = TOTAL_GAP_PORTRAIT if Layout.is_portrait() else TOTAL_GAP_LANDSCAPE
	return _equation_top() + _equation_height() + gap

# Where the streak popup/counter and milestone stinger start - right after
# TOTAL, where the combo meter used to sit before it was removed (it no longer
# served a purpose once the live streak counter and pre-run target/overtake
# reactions covered the same "how's this run going" question).
func _popup_top() -> float:
	return _total_top() + _total_height() + POPUP_GAP

func _build() -> void:
	_equation = _make_label(_equation_font(), NEON)
	_equation.position = Vector2(0, _equation_top())
	_equation.size = Vector2(Layout.canvas_size.x, _equation_height())
	add_child(_equation)

	_total = _make_label(_total_font(), GOLD.darkened(0.15))
	_total.position = Vector2(0, _total_top())
	_total.size = Vector2(Layout.canvas_size.x, _total_height())
	add_child(_total)

	_streak_popup = _make_label(38, GOLD)
	_streak_popup.position = Vector2(0, _popup_top())
	_streak_popup.size = Vector2(Layout.canvas_size.x, 46)
	_streak_popup.modulate.a = 0.0
	add_child(_streak_popup)

	# Persistent readout (unlike _streak_popup, which only flashes on growth) -
	# right-aligned so it doesn't compete with the centered equation/total
	# column. Sits at the same top as the popup/milestone slot, below the
	# pause/help icons in the top-right corner - previously at a fixed y=18,
	# which the touch-target pass's bigger corner icons now overlap. Hidden
	# below streak 2, same threshold the popup already celebrates at.
	_streak_counter = _make_label(24, GOLD)
	_streak_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_streak_counter.position = Vector2(Layout.canvas_size.x - 190, _popup_top())
	_streak_counter.size = Vector2(170, 34)
	_streak_counter.visible = false
	add_child(_streak_counter)

	# Milestone stinger - shares the streak popup's vertical slot but is its own
	# label so a milestone and a streak-growth pop landing on the same frame
	# don't overwrite each other's text.
	_milestone_label = _make_label(34, GOLD)
	_milestone_label.position = Vector2(0, _popup_top() + POPUP_TO_MILESTONE_GAP)
	_milestone_label.size = Vector2(Layout.canvas_size.x, 42)
	_milestone_label.modulate.a = 0.0
	add_child(_milestone_label)

	# Fail crosses, bottom-center. Held as a field because this row sits close
	# to the bottom edge - exactly where Android's gesture navigation bar
	# lands - so it gets lifted by the safe-area inset (see _apply_safe_area).
	var bottom_h := _bottom_row_height()
	_bottom_row = Control.new()
	_bottom_row.position = _bottom_row_pos()
	_bottom_row.size = Vector2(Layout.canvas_size.x, bottom_h)
	_bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_row)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = Vector2(Layout.canvas_size.x, bottom_h)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_row.add_child(center)

	_crosses_row = HBoxContainer.new()
	_crosses_row.add_theme_constant_override("separation",
		CROSS_SEPARATION_PORTRAIT if Layout.is_portrait() else CROSS_SEPARATION_LANDSCAPE)
	center.add_child(_crosses_row)

# Lifted clear of the gesture navigation bar. The top-of-screen readouts
# (equation, total, streak popup/counter, milestone) are horizontally centred
# and sit well inside the vertical extents, so a side cutout can't reach them.
func _apply_safe_area() -> void:
	if _bottom_row != null:
		_bottom_row.position = _bottom_row_pos() - Vector2(0, SafeArea.bottom)

# Every readout here is either full-canvas-width or centred on it, so an
# orientation flip is purely a re-measure - nothing moves to a different part of
# the screen the way the powerup cluster does.
func _apply_canvas_metrics() -> void:
	size = Layout.canvas_size
	var w: float = Layout.canvas_size.x
	if _equation != null:
		_equation.position = Vector2(0, _equation_top())
		_equation.size = Vector2(w, _equation_height())
	if _total != null:
		_total.position = Vector2(0, _total_top())
		_total.size = Vector2(w, _total_height())
	if _streak_popup != null:
		_streak_popup.position = Vector2(0, _popup_top())
		_streak_popup.size = Vector2(w, 46)
	if _streak_counter != null:
		_streak_counter.position = Vector2(w - 190, _popup_top())
	if _milestone_label != null:
		_milestone_label.position = Vector2(0, _popup_top() + POPUP_TO_MILESTONE_GAP)
		_milestone_label.size = Vector2(w, 42)
	if _bottom_row != null:
		var bottom_h := _bottom_row_height()
		_bottom_row.size = Vector2(w, bottom_h)
		for child in _bottom_row.get_children():
			if child is Control:
				child.size = Vector2(w, bottom_h)
		if _crosses_row != null:
			_crosses_row.add_theme_constant_override("separation",
				CROSS_SEPARATION_PORTRAIT if Layout.is_portrait() else CROSS_SEPARATION_LANDSCAPE)
	_apply_safe_area()

func _on_tally_changed(tally: int, mult: float) -> void:
	_equation.text = "%d   ×   %.1f" % [tally, mult]
	if mult > _last_mult:
		_pop(_equation)
	_last_mult = mult

	# campaign_total_changed (below) only fires when a segment BANKS, i.e. on a
	# fail - in Hardcore that's exactly once, right as the run ends, so an
	# overtake/milestone check gated on that alone would only ever fire too late
	# (or never, since the run is already over). tally_changed fires on every
	# click instead, so the check runs against a live projected total - banked
	# total plus the unbanked segment in flight - using the same int(tally*mult)
	# truncation resolve_stage() itself uses, so the number this fires against
	# matches what actually banks moments later.
	var live_total := ScoreManager.campaign_total + int(float(tally) * mult)
	_check_overtake(live_total)
	_check_milestones(live_total)

func _on_total_changed(total: int) -> void:
	_total.text = "TOTAL   %d" % total
	_check_overtake(total)
	_check_milestones(total)

# Called by EndlessRunner.start_run() with the record this run is chasing (0 if
# none exists yet). Resets both one-shot reaction trackers so a retry doesn't
# inherit the previous run's fired state.
func set_target(best: int) -> void:
	_target_best = best
	_overtake_fired = false
	_milestones_fired.clear()
	# A retry (or "play again") reuses this HUD instance, so the generated tail
	# from a previous long run has to be dropped along with the fired set -
	# otherwise a short retry would inherit a list that already runs into the
	# hundreds of thousands from the run before it.
	_milestone_values = MILESTONE_BASE.duplicate()
	_milestone_step_index = 0

# Fires once, the instant live score first crosses the record it's chasing.
# Score can dip back below via a later miss (multiplier resets, not the banked
# total, so this specifically can't happen from a resolve - kept guarded by
# _overtake_fired regardless, matching the "never re-fire" brief requirement).
func _check_overtake(total: int) -> void:
	if _overtake_fired or _target_best <= 0:
		return
	if total > _target_best:
		_overtake_fired = true
		_show_overtake_pulse()

func _show_overtake_pulse() -> void:
	# The crossing moment usually lands mid-segment (before the next bank), where
	# the live number lives on the equation - TOTAL alone wouldn't visibly change
	# yet at the instant this fires. Both get the pulse so it reads correctly
	# whether the crossing happened mid-segment or right on a bank.
	_pop(_equation)
	_pop(_total)
	for label in [_equation, _total]:
		var tween := create_tween()
		tween.tween_property(label, "modulate", Color(1.4, 1.3, 0.9, 1.0), 0.1)
		tween.tween_property(label, "modulate", Color.WHITE, 0.5)

func _check_milestones(total: int) -> void:
	# Extended on demand, one GEOMETRIC_STEP at a time, rather than precomputed
	# out to some arbitrary cap - a run has no fixed ceiling, so neither can
	# this list. The loop terminates because every step multiplies by > 1.
	while total >= _milestone_values[-1]:
		var step: float = GEOMETRIC_STEP[_milestone_step_index % GEOMETRIC_STEP.size()]
		_milestone_step_index += 1
		_milestone_values.append(int(round(_milestone_values[-1] * step)))

	# A single stop (an Overclocked Nuke, say) can cross more than one
	# threshold in the same frame. Mark every one of them fired - each still
	# only ever fires once per run - but show only the highest: it's strictly
	# better information than the lower one it subsumes, and showing both
	# meant the second call overwrote the first's text on the same label mid-
	# tween, so only the higher number was ever actually seen anyway.
	var highest := -1
	for m in _milestone_values:
		if total >= m and not _milestones_fired.has(m):
			_milestones_fired[m] = true
			highest = m
	if highest >= 0:
		_show_milestone(highest)

func _show_milestone(value: int) -> void:
	# Two thresholds landing on the same frame both call this with the tween
	# from the previous call still running (same fix _show_streak_popup below
	# already applies to its own tween) - without killing it here, the two
	# tweens fight over modulate:a and the label can be left stuck faded out.
	if _milestone_tween != null and _milestone_tween.is_valid():
		_milestone_tween.kill()

	_milestone_label.text = "%d!" % value
	_milestone_label.pivot_offset = _milestone_label.size * 0.5
	_milestone_label.modulate.a = 1.0
	_milestone_label.scale = Vector2(1.3, 1.3)
	_milestone_tween = create_tween()
	_milestone_tween.set_parallel(true)
	_milestone_tween.tween_property(_milestone_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_milestone_tween.tween_property(_milestone_label, "modulate:a", 0.0, 0.7).set_delay(0.7)

func _on_streak_changed(count: int) -> void:
	# Celebrate a growing streak (2+); don't announce it breaking.
	if count > _last_streak and count >= 2:
		_show_streak_popup(count)
	_last_streak = count
	_update_streak_counter(count)

# Live readout, unlike _show_streak_popup above - reflects the count on every
# change (growth, break, reset), not just the celebratory growth moments.
func _update_streak_counter(count: int) -> void:
	if _streak_counter == null:
		return
	_streak_counter.visible = count >= 2
	if count >= 2:
		_streak_counter.text = "STREAK %d" % count

func _show_streak_popup(count: int) -> void:
	# Same fix as StageResultScreen's version: a fast streak can retrigger this
	# before the previous popup's delayed fade-out has fired. Without killing
	# that old tween, it stays armed and blanks the label mid-streak.
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()

	_streak_popup.text = "%dx PERFECT!" % count
	_streak_popup.pivot_offset = _streak_popup.size * 0.5
	_streak_popup.modulate.a = 1.0
	_streak_popup.scale = Vector2(1.4, 1.4)
	_streak_tween = create_tween()
	_streak_tween.set_parallel(true)
	_streak_tween.tween_property(_streak_popup, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_property(_streak_popup, "modulate:a", 0.0, 0.7).set_delay(0.35)

const EMPTY_LIFE_COLOR := Color(1, 1, 1, 0.18)

func set_max_lives(lives: int) -> void:
	for c in _crosses_row.get_children():
		c.queue_free()
	_cross_labels.clear()
	# Hardcore is exactly one life - a single cross that's either absent (never
	# failed) or the run is already over, so it never gets seen filled in and
	# just clutters the bottom of the screen for no informational gain.
	_crosses_row.visible = lives > 1
	if lives <= 1:
		return
	for i in range(lives):
		var cross := _build_cross_icon(EMPTY_LIFE_COLOR)
		_crosses_row.add_child(cross)
		_cross_labels.append(cross)

func update_crosses(fail_count: int) -> void:
	for i in range(_cross_labels.size()):
		var filled := i < fail_count
		var color := FAIL_RED if filled else EMPTY_LIFE_COLOR
		for line in _cross_labels[i].get_children():
			line.default_color = color

# --- Life-loss reaction ---------------------------------------------------
# The cross that was just spent gets its own beat, so losing a life is
# distinguishable from any other FAIL rather than being just a recolour the
# player is unlikely to notice while looking at the board. A punch + flash
# rather than a shatter: the icon is two Line2Ds, so a shatter would mean
# animating the segments apart as a separate throwaway node, and this reads
# nearly as well for a fraction of the moving parts.
#
# EndlessRunner sequences the call itself, deliberately a beat AFTER the FAIL's
# own shake/aberration - "I failed", then "and that cost me a life", as two
# reads instead of one blurred moment.
const LIFE_LOSS_FLASH := Color(1, 1, 1, 1)
const LIFE_LOSS_PUNCH := 1.55

func react_life_lost(index: int) -> void:
	# Hardcore hides the row entirely (see set_max_lives), so there is nothing
	# to react with - the screen-wide FAIL feedback carries that case alone.
	if index < 0 or index >= _cross_labels.size():
		return
	var icon: Control = _cross_labels[index]
	if not is_instance_valid(icon):
		return

	# Blown out to white on impact, settling into the spent-life red - a flash
	# that resolves into the state change, rather than a flash on top of it.
	for line in icon.get_children():
		line.default_color = LIFE_LOSS_FLASH
	var recolor := create_tween()
	recolor.set_parallel(true)
	for line in icon.get_children():
		recolor.tween_property(line, "default_color", FAIL_RED, 0.3)

	# Scale only, no positional kick: the icon lives in an HBoxContainer, which
	# owns its children's positions and re-asserts them on every sort - a
	# position tween would be fighting the layout. Containers don't manage
	# scale, so this is free of that conflict (the same reason DigitCounter
	# pops its digits by scale rather than offset).
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2.ONE
	var hit := create_tween()
	# Hard snap outward, slow settle back through an overshoot - a struck
	# object, not a button press.
	hit.tween_property(icon, "scale", Vector2.ONE * LIFE_LOSS_PUNCH, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit.tween_property(icon, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Drawn as two diagonal Line2Ds rather than a "✕" text glyph - some exported
# builds' bundled font (notably HTML5/Web) lacks that Unicode character and
# shows tofu boxes. Bigger in portrait, per a user request - these are purely
# informational (not tappable), so this is a legibility change, not a
# touch-target one.
func _build_cross_icon(color: Color) -> Control:
	var portrait := Layout.is_portrait()
	var box_size: float = CROSS_BOX_SIZE_PORTRAIT if portrait else CROSS_BOX_SIZE_LANDSCAPE
	var line_width: float = CROSS_LINE_WIDTH_PORTRAIT if portrait else CROSS_LINE_WIDTH_LANDSCAPE
	# Keeps the same proportional inset (8/40 = 0.2 of the box) at any size,
	# rather than a fixed pixel inset that would look cramped at a bigger box.
	var inset := box_size * 0.2
	var far := box_size - inset
	var box := Control.new()
	box.custom_minimum_size = Vector2(box_size, box_size)
	for points in [[Vector2(inset, inset), Vector2(far, far)], [Vector2(far, inset), Vector2(inset, far)]]:
		var line := Line2D.new()
		line.width = line_width
		line.default_color = color
		line.points = PackedVector2Array(points)
		box.add_child(line)
	return box

func _pop(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(1.12, 1.12), 0.08)
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _make_label(font_size: int, outline_color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", outline_color)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
