extends Control
class_name LevelSelect

const NORMAL_ACCENT := Color("22d3ff")  # cyan, matches BLUE timer family
const BONUS_ACCENT := Color("ffd23f")   # gold, matches the GOLDEN timer color
const LOCKED_ACCENT := Color("8b90a8")  # muted grey
const TEXT_FILL := Color("dfe3ee")

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel).
# This screen previously had no heading at all - reached straight from the
# title screen's ARCADE button with nothing naming it, unlike every other
# screen in the game's own navigation. Base (landscape) value - see _s() below
# for how this scales in portrait.
const PAGE_HEADING_SIZE := 56

# Android is portrait-locked now (no toggle, see [[project_portrait_landscape]])
# and has hundreds of spare vertical units to spend on this screen; desktop/web
# are landscape-only and measured (not just calculated - see _apply_canvas())
# to have very little room before 900 overflows. One factor scales every size
# on this screen together in portrait, same idiom CreditsScreen/OptionsPanel/
# ScoresScreen/HelpScreen already use, rather than a second ad hoc size per
# element - 1.3 is calibrated against this screen's own measured headroom
# (verified via a deferred probe reading get_combined_minimum_size(), not just
# calculated), not copied from another screen's own separately-tuned factor.
const PORTRAIT_SCALE := 1.3

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

# Square rather than the original 220x120 rectangle - stage names are now just
# the bare number ("1".."12", see StageData.stage_name), which reads fine
# centred in a square and no longer needs the extra width a "Stage N" label did.
# Base (landscape) size - scaled by _s() at the one call site that builds them.
const STAGE_BUTTON_SIZE := Vector2(163, 163)
const STAGE_NUMBER_FONT_SIZE := 50

@export var campaign: Campaign
@export var campaign_navigator: CampaignNavigator

@onready var grid: GridContainer = $Center/Col/Grid
@onready var _col: VBoxContainer = $Center/Col
@onready var _center: CenterContainer = $Center

var _backdrop: ColorRect

func _ready() -> void:
	grid.add_theme_constant_override("h_separation", roundi(20 * _s()))
	# Tightened from 24 - the bigger square buttons need the vertical room more
	# than the gap between rows does; width has hundreds of spare units in both
	# orientations so h_separation barely moved.
	grid.add_theme_constant_override("v_separation", roundi(14 * _s()))
	GameManager.state_changed.connect(_on_state_changed)
	_add_heading()
	_add_back_button()
	_add_backdrop()
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

# Placed first in _col (ahead of Grid, which the scene file already parents
# there), so it reads as this screen's title the same way every other screen's
# WaveHeading does.
#
# "LEVEL SELECT" at the scaled portrait size measures 519 wide against the
# 900-wide canvas (381 to spare - verified via a deferred probe run under the
# dev `--portrait` flag, not just calculated), so this stays a single
# WaveHeading rather than splitting into two lines - unlike Title's
# "PERFECT"/"ZERO", which genuinely didn't fit at its own portrait size.
func _add_heading() -> void:
	var heading := WaveHeading.new()
	_col.add_child(heading)
	_col.move_child(heading, 0)
	heading.configure("LEVEL SELECT", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NORMAL_ACCENT)

# This screen is authored in LevelSelect.tscn rather than built procedurally, so
# its root and its centring container both carried the scene's hard-coded
# 1600x900 rect. On the 900-wide portrait canvas that put the centre at x=800
# instead of 450 and pushed the whole grid off the right edge - the one screen
# the rest of this pass missed, because it had no VIEWPORT_SIZE constant to find.
#
# Every size on this screen (grid, squares, heading, BACK) now scales through
# `_s()`/PORTRAIT_SCALE, same idiom Credits/Options/Scores/Help already use, so
# this only needs the centring - not a second, separate type-scale decision.
# Landscape is the tighter fit: measured (not just calculated, via a deferred
# probe) at 883 of 900 total column height with the heading and BACK row
# included, which is what calibrated PORTRAIT_SCALE's value - portrait itself
# measures 1131 of 1600 at that same scale, with hundreds of units to spare.
func _apply_canvas() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	if _center != null:
		_center.position = Vector2.ZERO
		_center.size = Layout.canvas_size
	ScreenLayout.cover(_backdrop)

# Added behind the content (as the first child) rather than in the scene, since
# this screen previously relied on the engine's clear colour showing through -
# which reads a shade lighter than every other screen's own backdrop.
func _add_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	move_child(_backdrop, 0)

# Centered below the grid, last item in the same column - matching where every
# other screen (Help/Scores/Credits/Endless Mode Select) puts BACK, rather than
# pinned to a fixed top-left corner on its own.
func _add_back_button() -> void:
	var back := Button.new()
	back.text = "BACK"
	# Base matches CreditsScreen's BACK specifically (220x64, font 26) rather
	# than the 200x64/font-28 convention most other screens' BACK buttons
	# share - an explicit call, since the bigger stage-number squares above
	# made this screen's own scale feel a size class up from the others. Scaled
	# by _s() the same as everything else here, same as Credits' own BACK
	# scales by its own PORTRAIT_SCALE.
	back.custom_minimum_size = Vector2(220, 64) * _s()
	_style_button(back, NORMAL_ACCENT, _fs(26))  # same cyan as the title screen's ARCADE button
	back.pressed.connect(_on_back)
	PressFeedback.apply(back)
	var wrap := CenterContainer.new()
	wrap.add_child(back)
	_col.add_child(wrap)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses.
#
# Guarded on the current state rather than on visibility: every screen stays in
# the tree while hidden - MainScreenRouter only toggles `visible` - and
# _unhandled_input still fires on hidden nodes, so without this guard a single
# back press would be answered by every screen in the game at once.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.LEVEL_SELECT:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)

func _on_state_changed(new_state: int) -> void:
	# Rebuild each time the screen is shown so unlock progress is always current.
	if new_state == GameManager.GameState.LEVEL_SELECT:
		_populate()

func _populate() -> void:
	for child in grid.get_children():
		child.queue_free()
	if campaign == null:
		push_error("LevelSelect: no campaign assigned.")
		return

	var highest: int = SaveManager.load_high_score("highest_stage_reached")
	# Consumed once per visit, up front - see take_pending_all_perfect()'s own
	# doc for why clearing it here (rather than only after the reveal finishes)
	# is the right call.
	var pending: Array[int] = campaign_navigator.take_pending_all_perfect() \
		if campaign_navigator != null else []
	var reveal_marks: Array[AllPerfectMark] = []

	var button_size: Vector2 = STAGE_BUTTON_SIZE * _s()
	var number_font: int = _fs(STAGE_NUMBER_FONT_SIZE)

	for i in range(campaign.stages.size()):
		var stage: StageData = campaign.stages[i]
		var button := Button.new()
		button.text = stage.stage_name
		button.custom_minimum_size = button_size

		var locked: bool = i > highest
		if locked:
			button.disabled = true
			button.modulate = Color(1, 1, 1, 0.45)
			_style_button(button, LOCKED_ACCENT, number_font)
		else:
			var accent: Color = BONUS_ACCENT if stage.is_bonus_stage else NORMAL_ACCENT
			_style_button(button, accent, number_font)
			var index := i  # fresh binding so the lambda captures this stage's index
			button.pressed.connect(func(): campaign_navigator.enter_campaign(index))
			PressFeedback.apply(button)

		# What turns this screen from a list of what's unlocked into a record of
		# what's actually been mastered. A locked stage shows neither state - there
		# is nothing to earn yet where there's nothing to play - but every unlocked
		# one shows either the filled mark or, if not earned yet, a hollow outline
		# of the same shape: a visible slot waiting to be filled, not just an
		# absence, so the badge system reads as a standing goal on every stage
		# rather than a surprise that only appears once you've already earned it.
		#
		# A stage that just earned the flag (still pending its reveal) is built
		# in the hollow state regardless of `earned` - _play_pending_reveals()
		# below is what animates it to the filled state a moment after the
		# screen settles, rather than it simply appearing already complete.
		if not locked and campaign_navigator != null:
			var earned := campaign_navigator.has_all_perfect(i)
			var is_pending := pending.has(i)
			var mark := _add_all_perfect_mark(button, earned, 0.0 if is_pending else float(earned))
			if is_pending:
				reveal_marks.append(mark)

		grid.add_child(button)

	if not reveal_marks.is_empty():
		_play_pending_reveals(reveal_marks)

# Pinned to the button's top-right via anchors rather than a fixed offset,
# since the GridContainer is free to hand these buttons more than their
# minimum size. IGNORE so the mark never swallows a press meant for the stage
# itself.
func _add_all_perfect_mark(button: Button, earned: bool, initial_fill: float) -> AllPerfectMark:
	var mark := AllPerfectMark.new()
	mark.fill = initial_fill
	var mark_size := ALL_PERFECT_MARK_SIZE * _s()
	var mark_margin := ALL_PERFECT_MARK_MARGIN * _s()
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.offset_left = -(mark_size + mark_margin)
	mark.offset_right = -mark_margin
	mark.offset_top = mark_margin
	mark.offset_bottom = mark_margin + mark_size
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(mark)
	button.tooltip_text = "Cleared with every timer PERFECT" if earned \
		else "Not yet cleared with every timer PERFECT"
	return mark

const ALL_PERFECT_MARK_SIZE := 30.0
const ALL_PERFECT_MARK_MARGIN := 9.0

# How long a newly-earned badge waits before its own "filling in" animation
# starts, and how far apart consecutive reveals in the same visit land. A
# player who clears several stages before ever checking back on Level Select
# gets a rolling sequence of good news instead of every mark on the grid
# flashing at once.
const ALL_PERFECT_REVEAL_DELAY := 0.5    # before the first reveal starts
const ALL_PERFECT_REVEAL_STAGGER := 0.4  # gap between each subsequent one
const ALL_PERFECT_REVEAL_TIME := 0.5

func _play_pending_reveals(marks: Array[AllPerfectMark]) -> void:
	await get_tree().create_timer(ALL_PERFECT_REVEAL_DELAY, true, false, true).timeout
	for mark in marks:
		# This screen stays in the tree hidden rather than freed when the player
		# backs out - MainScreenRouter only toggles `visible` - so without this a
		# fast BACK press mid-sequence would leave this await chain running
		# invisibly, and its burst/sound would still fire (both reach Main
		# directly, independent of this screen's own visibility) over whatever
		# screen the player is actually looking at by then.
		if GameManager.current_state != GameManager.GameState.LEVEL_SELECT:
			return
		# A quick back-out-and-back-in re-enters this screen and calls
		# _populate() again, which frees the whole grid (and every mark on it,
		# including ones a still-running earlier sequence hasn't gotten to yet).
		if not is_instance_valid(mark):
			continue
		_reveal_all_perfect_mark(mark)
		await get_tree().create_timer(ALL_PERFECT_REVEAL_STAGGER, true, false, true).timeout

# Same idiom StageResultScreen's own badges use: a pop scaling in with
# TRANS_BACK/EASE_OUT rather than a plain fade, so it reads as landing rather
# than merely materialising. `fill` rides its own cubic ease alongside the pop -
# the ring/plate/tick genuinely draw themselves in over the same beat, not just
# scale up already complete. Reuses the exact sound and burst grade
# StageResultScreen's own ALL PERFECT celebration does, so the badge finishing
# construction here plays as the same achievement, not a lesser echo of it.
func _reveal_all_perfect_mark(mark: AllPerfectMark) -> void:
	mark.pivot_offset = mark.size * 0.5
	mark.scale = Vector2(1.6, 1.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mark, "fill", 1.0, ALL_PERFECT_REVEAL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, "scale", Vector2.ONE, ALL_PERFECT_REVEAL_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Juice.click_burst(mark.global_position + mark.size * 0.5, "PERFECT", -1, 0.8)
	AudioManager.play_all_perfect()

# Drawn rather than set as a font glyph or loaded as an SVG, matching this
# project's icon house style: Godot's SVG rasterizer drops <text> outright, a
# Unicode tick renders as tofu in some exported builds' bundled font, and a
# procedural mark re-rasterizes cleanly at whatever the canvas is scaled to.
#
# Carries StageResultScreen's ALL PERFECT bronze-gold deliberately - the badge
# here and the celebration there are the same achievement, so they are the
# same colour rather than two separate visual languages for one idea.
#
# `fill` set by the caller before this is added to the tree for the settled
# (non-animated) cases, so the very first _draw() already renders the correct
# resting state. For a stage whose reveal is about to play, the caller instead
# starts it at 0.0 and tweens it up to 1.0 - see LevelSelect._reveal_all_perfect_mark().
class AllPerfectMark extends Control:
	const ACCENT := Color("c8862e")
	# Matches LevelSelect.LOCKED_ACCENT (duplicated rather than referenced
	# cross-scope, to keep this inner class self-contained) - the same muted
	# grey this screen already uses for "not available yet" elsewhere, so the
	# hollow ring reads as "goal, not earned" rather than as a faint version of
	# the gold itself, which read as gold at low alpha rather than as grey.
	const HOLLOW_ACCENT := Color("8b90a8")

	# 0.0 is the hollow "goal, not yet met" state; 1.0 is fully earned. A plain
	# float rather than the boolean this started as, specifically so a
	# newly-earned stage can animate continuously between the two instead of
	# only ever popping into existence already complete - the setter's own
	# queue_redraw() is what makes tweening this property actually animate.
	var fill: float = 1.0:
		set(v):
			fill = v
			queue_redraw()

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		var c := Vector2(size.x, size.y) * 0.5
		var t := clampf(fill, 0.0, 1.0)

		# Dark plate fades in with `t` rather than snapping - this sits on top of
		# a lit, coloured button face, and the ring alone reads as noise against
		# a bright one once it's bright enough itself to need the backing.
		var plate_alpha := lerpf(0.0, 0.92, t)
		if plate_alpha > 0.01:
			draw_circle(c, r, Color(0.04, 0.03, 0.07, plate_alpha))

		# The ring is present at every `t` (down to a muted grey outline at 0.0 -
		# a visible slot waiting to be filled, not just an absence) and both
		# brightens AND shifts hue toward the gold as `t` climbs, rather than the
		# earned ring's colour simply fading in - a low-alpha gold still reads as
		# gold, just faint, which is what made the hollow state look tinted gold
		# instead of genuinely grey.
		var ring_color := HOLLOW_ACCENT.lerp(ACCENT, t)
		var ring_alpha := lerpf(0.6, 1.0, t)
		var ring_width := lerpf(2.0, 2.5, t)
		draw_arc(c, r - 2.0, 0.0, TAU, 32, Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha),
			ring_width, true)

		# The tick only belongs to the fully-earned state - there's no such thing
		# as partial credit here, the flag is binary - so it fades in over the
		# back half of the reveal instead of tracking `t` from the start, which
		# is what makes the ring read as "filling" before the tick lands on top
		# of it rather than both arriving at once.
		var tick_alpha := clampf((t - 0.5) * 2.0, 0.0, 1.0)
		if tick_alpha > 0.01:
			var tick_color := ACCENT.lightened(0.4)
			# Tick struck off the radius rather than fixed pixel offsets, so the
			# mark stays correct at whatever size the caller anchors it to.
			draw_polyline(PackedVector2Array([
				c + Vector2(-0.36, 0.02) * r,
				c + Vector2(-0.10, 0.30) * r,
				c + Vector2(0.38, -0.32) * r,
			]), Color(tick_color.r, tick_color.g, tick_color.b, tick_alpha), 3.0, true)

func _style_button(button: Button, accent: Color, font_size: int = 28) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 5)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	button.add_theme_stylebox_override("normal", _make_box(accent, 0.85, 0.35, 8))
	button.add_theme_stylebox_override("hover", _make_box(accent, 0.7, 0.5, 12))
	button.add_theme_stylebox_override("pressed", _make_box(accent, 0.6, 0.4, 6))
	button.add_theme_stylebox_override("disabled", _make_box(accent, 0.9, 0.15, 4))

func _make_box(accent: Color, darken: float, shadow_alpha: float, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb
