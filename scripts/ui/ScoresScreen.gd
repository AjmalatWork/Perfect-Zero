extends Control
class_name ScoresScreen

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const MUTED := Color("8b90a8")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")
# Matches EndlessModeSelect.NEON/RED exactly (same hex) - the hero card's two
# pages borrow the mode-select screen's own colour coding rather than inventing
# a second one, so "cyan" and "red" already mean Normal/Hardcore before the
# player reads either label.
const RED := Color("ff2e5e")

@export var campaign: Campaign
# Only needed for the pending-reveal reuse below (take_pending_all_perfect()) -
# `earned` itself still reads the flag directly via SaveManager, matching every
# other read on this screen.
@export var campaign_navigator: CampaignNavigator

var _col: VBoxContainer


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact.
#
# History behind the exact value: originally capped by a 3-column table row
# (300+150+150 cells) at 1.04, then re-measured to 1.2 (858 of 900, 42px margin)
# once the base cell font grew. The table dropped to 2 columns and its rows
# widened to fill the whole column afterward, which loosened this constraint
# further - width was never the reason to revisit 1.2 again, so it has stayed
# put across all three changes rather than being retuned each time.
const PORTRAIT_SCALE := 1.2

# Shrinks in portrait rather than growing with the type scale. At _fs(80) these
# ate 208 units of a 900-wide canvas, which pushed the table's third column
# ("Perfect") clean off the right edge.
func _side_margin() -> int:
	return 40 if Layout.is_portrait() else 80

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel),
# confirmed with the user 2026-07-31 - this used to be its own smaller size and
# read inconsistent against screens reached from the same title-screen row.
const PAGE_HEADING_SIZE := 56

# Table body text. _fs(24) measured 11.6dp on device, well under the 14sp floor
# for body copy - and this table *is* the screen, so it was the smallest text on
# the one screen made entirely of text. 30 lands at 14.4dp.
const CELL_FONT_SIZE := 30

# 1 canvas unit = 0.4dp, so this lands at 144 units / 57.6dp, matching the BACK
# button on the Help and Options screens. It measured 30.7dp before this pass.
const TOUCH_BACK := 120.0

# Every increase above is portrait-only. Landscape is desktop/web with a mouse,
# where the dp minimums do not apply - and it is the *tighter* axis for this
# screen, not the roomier one: 820 units of height against portrait's 1504, with
# the same twelve stage rows to fit. Measured, applying the portrait sizes there
# overflowed the column by 172 units.
const CELL_FONT_LANDSCAPE := 24
const BACK_HEIGHT_LANDSCAPE := 64.0

func _cell_font() -> int:
	return CELL_FONT_SIZE if Layout.is_portrait() else CELL_FONT_LANDSCAPE

func _back_height() -> float:
	return TOUCH_BACK if Layout.is_portrait() else BACK_HEIGHT_LANDSCAPE

# Table geometry, raw units (x _s()). Two columns now, not three: the Target
# column was dropped once the per-row All-PERFECT mark took over telling the
# player whether a stage is fully cleared - a player who wants the exact target
# number can already see it as the ring's own "goal, not met" state, and having
# both a mark AND a number for the same fact was redundant. LABEL_CELL shrank
# to match - stage labels are now bare numbers ("1", not "STAGE 1"), so the wide
# cell that used to hold "STAGE 12" would just be spare width again, the same
# mistake the Target column removal is fixing. The freed width went to BEST,
# which is now the screen's only per-stage number and reads as the hero of the
# row rather than one of three competing columns.
const MARK_CELL := 34.0
const LABEL_CELL := 70.0
const VALUE_CELL := 220.0
const CELL_SEP := 16.0
# Reserved space on the right of the scroll area, for the vertical scrollbar
# that ScrollContainer draws over the content rather than beside it - see the
# comment where this is used for the measured overlap it fixes.
const SCROLLBAR_GUTTER := 24.0
# 62 x 1.2 = 74.4 units = 29.8dp of row pitch, up from a measured 22.8dp. Rows
# are not interactive, so this is a scanning-density number rather than a touch
# target - Material's dense-list floor rather than the 48dp one.
const ROW_HEIGHT := 62.0

# 26 lands at 12.5dp - an uppercase eyebrow, deliberately under body size, with
# colour and case carrying the hierarchy instead. 20 was tried first and measured
# 9.6dp, which is too small to be a useful heading at arm's length.
const SECTION_LABEL_SIZE := 26
const HERO_LABEL_SIZE := 26
# The perfected count is a headline stat, not scaffolding, so it sits at body
# size (14.4dp) rather than eyebrow size.
const SUMMARY_SIZE := 30
const HERO_NUMBER_SIZE := 64

# --- Endless hero card: swipeable Normal <-> Hardcore ------------------------
#
# Replaces the old static "Endless Best" card plus a separate NORMAL/HARDCORE
# pair of rows further down the screen - both showed the same two numbers, once
# combined into a single "whichever is higher" figure and once broken out, and
# a player had to scroll past the whole stage table to see the second version.
# One swipeable card now carries both, colour-coded to EndlessModeSelect's own
# NEON/RED so a player who already knows that screen recognises which mode
# they're looking at before reading either label.
const ENDLESS_KEYS := ["highscore_endless_normal", "highscore_endless_hardcore"]
const ENDLESS_NAMES := ["ENDLESS - NORMAL", "ENDLESS - HARDCORE"]
var _endless_accents: Array[Color]:
	get:
		return [NEON, RED]

# Same tap-vs-swipe split HelpScreen uses, reused verbatim rather than
# reinvented: SWIPE_TAP_SLOP is touch jitter, SWIPE_COMMIT_RATIO is intent.
const SWIPE_TAP_SLOP := 14.0
const SWIPE_COMMIT_RATIO := 0.18

const HERO_DOT_SIZE := 8.0
const HERO_DOT_ACTIVE_WIDTH := 22.0
const HERO_DOT_ROW_HEIGHT := 20.0

var _hero_frame: PanelContainer
var _hero_area: Control
var _hero_track: Control
var _hero_pages: Array[Control] = []
var _hero_index: int = 0
var _hero_tween: Tween
var _hero_drag_from: Vector2 = Vector2.ZERO
var _hero_dragging: bool = false
var _hero_swipe_active: bool = false
var _hero_dots: Array[Panel] = []
var _hero_dot_tween: Tween

# Grouped thousands. The Best column exists to be compared down its length, and
# five unbroken digits are measurably slower to read than "36,000".
#
# The implementation moved to ScoreManager.thousands() - being private here is
# what made this screen the only one in the game that separated its numbers.
# Kept as a thin forwarder so this screen's own call sites read unchanged.
static func _thousands(n: int) -> String:
	return ScoreManager.thousands(n)

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

var _backdrop: ColorRect
var _margin: MarginContainer
var _built_portrait: bool = false

func _ready() -> void:
	_build_shell()
	GameManager.state_changed.connect(_on_state_changed)
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

func _on_state_changed(new_state: int) -> void:
	# Rebuild each time the screen is shown so freshly-set bests appear.
	if new_state == GameManager.GameState.SCORES:
		_populate()


# A plain resize is a re-measure; an orientation change rebuilds, because the
# portrait scale feeds every font size and a Label's is fixed once created.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _margin != null:
		_margin.size = Layout.canvas_size
	_apply_overscan()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_margin = null
	_col = null
	_build_shell()
	_apply_overscan()

func _apply_overscan() -> void:
	ScreenLayout.cover(_backdrop)

func _build_shell() -> void:
	_built_portrait = Layout.is_portrait()
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_backdrop = ColorRect.new()
	var backdrop := _backdrop
	backdrop.position = Layout.overscan_position
	backdrop.size = Layout.overscan_size
	backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_margin = MarginContainer.new()
	var margin := _margin
	margin.position = Vector2.ZERO
	margin.size = Layout.canvas_size
	margin.add_theme_constant_override("margin_left", _side_margin())
	margin.add_theme_constant_override("margin_right", _side_margin())
	margin.add_theme_constant_override("margin_top", _fs(40))
	margin.add_theme_constant_override("margin_bottom", _fs(40))
	add_child(margin)

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", _fs(8))
	# BEGIN, not CENTER: the scroll area between the title and BACK is what
	# takes up the slack now, so the column fills top-to-bottom.
	_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(_col)

func _populate() -> void:
	for child in _col.get_children():
		child.queue_free()
	_hero_pages.clear()
	_hero_dots.clear()

	var title := WaveHeading.new()
	_col.add_child(title)
	title.configure("HIGH SCORES", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NEON)

	# Summary before detail. Both of these stay put while the table scrolls: the
	# screen used to open straight into fourteen rows of raw numbers, so a player
	# had to read and compare every row themselves to answer "how far through am
	# I" or "what is my best".
	_col.add_child(_spacer(10))
	_col.add_child(_hero_card())
	_col.add_child(_spacer(8))
	_col.add_child(_build_hero_dot_row())
	_style_hero_dots()
	_col.add_child(_spacer(10))
	_col.add_child(_perfected_summary())
	_col.add_child(_spacer(12))

	# The table scrolls; title and BACK do not, so the way out is always on
	# screen and always in thumb reach. A scroll container is also the overflow
	# fallback this screen never had - it has silently overflowed twice before
	# when its content grew, and a hero card plus twelve rows no longer fits a
	# fixed column at all.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col.add_child(scroll)

	# ScrollContainer doesn't reserve a gutter for its own vertical scrollbar -
	# measured, the row content's right edge and the scrollbar's own left edge
	# land at the exact same x, and the scrollbar's rendered thumb/hit-padding
	# extends slightly past that on a real device, overlapping the BEST column.
	# A small fixed margin on the right only (SIZE_EXPAND_FILL still owns the
	# rest) reserves just enough room for it without narrowing the table from
	# both sides.
	var inner_margin := MarginContainer.new()
	inner_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_margin.add_theme_constant_override("margin_right", _fs(SCROLLBAR_GUTTER))
	scroll.add_child(inner_margin)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 0)
	inner_margin.add_child(inner)

	# No section eyebrow above this any more - the stage table is the only thing
	# left in the scroll area now that Endless moved into the hero card, so
	# "ARCADE STAGES" labelled a list that was the screen's only list anyway.
	if campaign != null:
		inner.add_child(_header_row("STAGE", "BEST"))
		inner.add_child(_row_rule(0.35))
		inner.add_child(_spacer(8))
		# Consumed once per visit, up front - matching LevelSelect's own
		# _populate(), which documents why clearing it here (rather than only
		# after the reveal finishes) is the right call: this screen stays in the
		# tree hidden rather than freed when the player backs out, so a stale
		# in-flight reveal from a previous visit could otherwise linger.
		#
		# take_pending_all_perfect() CONSUMES the flag - whichever screen (this
		# one or Level Select) the player checks FIRST after earning a stage
		# plays the reveal; the other, visited after, just shows the already-
		# settled filled state with no animation. That's a deliberate shared
		# read, not a bug - the "you just earned this" moment plays exactly once,
		# wherever the player happens to look first.
		var pending: Array[int] = campaign_navigator.take_pending_all_perfect() \
			if campaign_navigator != null else []
		var reveal_entries: Array = []
		for i in range(campaign.stages.size()):
			var stage: StageData = campaign.stages[i]
			var best: int = SaveManager.load_high_score("highscore_stage_%d" % i)
			# The same flag Level Select's badge reads, not an inference from
			# best >= target - they are different facts and only this one means
			# "every stop in the stage was a PERFECT".
			var earned: bool = SaveManager.load_high_score(CampaignNavigator.ALL_PERFECT_KEY % i) != 0
			var is_pending := pending.has(i)
			# Bare stage_name ("1", not "STAGE 1") - the mark plus the STAGE
			# column header already say what this number is, so the row itself
			# doesn't need to repeat it.
			inner.add_child(_stage_row(stage.stage_name, best, earned, is_pending, reveal_entries))
			inner.add_child(_spacer(6))
		if not reveal_entries.is_empty():
			_play_pending_reveals(reveal_entries)

	_col.add_child(_spacer(12))
	var back := _button("BACK", BACK_ACCENT)
	back.pressed.connect(_on_back)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	_col.add_child(back_wrap)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses. Guarded
# on the current state because hidden screens stay in the tree and would
# otherwise all answer the same press - see LevelSelect for the full note.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.SCORES:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)

# --- All-PERFECT reveal (reused from LevelSelect) --------------------------
#
# LevelSelect's own pending-reveal system - a freshly-earned stage sits hollow
# and animates in a beat after the screen settles - was previously only ever
# played there. Reusing the same take_pending_all_perfect() flag here means a
# stage perfected last run visibly "arrives" the first time the player checks
# High Scores too, not only Level Select, using an animation that already
# exists and is already correct rather than a new one invented for this screen.

func _play_pending_reveals(entries: Array) -> void:
	await get_tree().create_timer(LevelSelect.ALL_PERFECT_REVEAL_DELAY, true, false, true).timeout
	for entry in entries:
		# This screen stays in the tree hidden rather than freed when the player
		# backs out - MainScreenRouter only toggles `visible` - so without this a
		# fast BACK press mid-sequence would leave this await chain running
		# invisibly, same as LevelSelect's own guard.
		if GameManager.current_state != GameManager.GameState.SCORES:
			return
		# A quick back-out-and-back-in re-enters this screen and calls
		# _populate() again, which frees the whole scroll list (and every mark
		# on it, including ones a still-running earlier sequence hasn't reached).
		if not is_instance_valid(entry["mark"]):
			continue
		_reveal_stage_entry(entry)
		await get_tree().create_timer(LevelSelect.ALL_PERFECT_REVEAL_STAGGER, true, false, true).timeout

# Same idiom as LevelSelect._reveal_all_perfect_mark(): a pop scaling in with
# TRANS_BACK/EASE_OUT rather than a plain fade, the exact same sound and burst
# StageResultScreen's own ALL PERFECT celebration uses. The row's own panel
# (see _row_panel_style()) tweens its bg/border colour in parallel, from the
# same hollow grey to the same bronze-gold the mark itself lerps through, so
# the ring and the row it sits in visibly "arrive" together rather than the
# ring alone updating inside an already-gold row.
func _reveal_stage_entry(entry: Dictionary) -> void:
	var mark: LevelSelect.AllPerfectMark = entry["mark"]
	var sb: StyleBoxFlat = entry["stylebox"]
	mark.pivot_offset = mark.size * 0.5
	mark.scale = Vector2(1.6, 1.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mark, "fill", 1.0, LevelSelect.ALL_PERFECT_REVEAL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, "scale", Vector2.ONE, LevelSelect.ALL_PERFECT_REVEAL_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var earned_accent := LevelSelect.AllPerfectMark.ACCENT
	tween.tween_property(sb, "bg_color", Color(earned_accent.r, earned_accent.g, earned_accent.b, 0.08),
		LevelSelect.ALL_PERFECT_REVEAL_TIME)
	tween.tween_property(sb, "border_color", Color(earned_accent.r, earned_accent.g, earned_accent.b, 0.55),
		LevelSelect.ALL_PERFECT_REVEAL_TIME)
	Juice.click_burst(mark.global_position + mark.size * 0.5, "PERFECT", -1, 0.8)
	AudioManager.play_all_perfect()

# --- builders -------------------------------------------------------------

# The headline card, above the detail. Two pages - NORMAL then HARDCORE, sliding
# like HelpScreen's own pages - rather than a single "whichever is higher"
# figure plus a separate pair of rows further down: this is the one change that
# lets the whole Endless story live in one place instead of two.
func _hero_card() -> Control:
	var scores: Array[int] = []
	for key in ENDLESS_KEYS:
		scores.append(SaveManager.load_high_score(key))
	# Opens on whichever mode actually has the bigger number - a player who has
	# only ever played Hardcore shouldn't have to swipe past an empty Normal page
	# to see their one real score.
	_hero_index = 1 if scores[1] > scores[0] else 0

	_hero_frame = PanelContainer.new()
	_hero_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_hero_frame(_endless_accents[_hero_index])

	# Clipped viewport + a track twice its width holding both pages side by side
	# - the same construction HelpScreen's page area uses, scaled down to two
	# pages instead of three.
	_hero_area = Control.new()
	_hero_area.clip_contents = true
	_hero_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_hero_frame.add_child(_hero_area)

	_hero_track = Control.new()
	_hero_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_area.add_child(_hero_track)

	_hero_pages.clear()
	for i in range(2):
		var page := _build_hero_page(scores[i], ENDLESS_NAMES[i], _endless_accents[i])
		_hero_track.add_child(page)
		_hero_pages.append(page)

	_hero_area.gui_input.connect(_on_hero_gui_input)
	_hero_area.resized.connect(_layout_hero_pages)
	call_deferred("_size_hero_area")
	return _hero_frame

func _build_hero_page(score: int, mode_name: String, accent: Color) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(2))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var caption := Label.new()
	caption.text = mode_name
	caption.add_theme_font_size_override("font_size", _fs(HERO_LABEL_SIZE))
	caption.add_theme_color_override("font_color", accent)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(caption)

	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if score > 0:
		value.text = _thousands(score)
		value.add_theme_font_size_override("font_size", _fs(HERO_NUMBER_SIZE))
		value.add_theme_color_override("font_color", TEXT_FILL)
	else:
		# A deliberate empty state rather than a big "0", which would read as a
		# score that had actually been set.
		value.text = "NO RUN YET"
		value.add_theme_font_size_override("font_size", _fs(HERO_LABEL_SIZE + 8))
		value.add_theme_color_override("font_color", MUTED)
	col.add_child(value)

	# A CenterContainer, not the VBox itself, is what gets manually positioned
	# and sized by _layout_hero_pages() - it centres `col` (at its own natural
	# minimum size) within whatever fixed rect that assigns, the same way every
	# HelpScreen tile/group centres inside a container-managed size instead of
	# each label needing its own EXPAND_FILL + alignment flags.
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	return center

# The reserved height comes from the taller of the two pages' own measured
# content, matching HelpScreen's _size_page_area() - both pages share the exact
# same label structure so they should already match, but this measures rather
# than assumes it.
func _size_hero_area() -> void:
	if _hero_area == null:
		return
	var tallest := 0.0
	for p in _hero_pages:
		tallest = maxf(tallest, p.get_combined_minimum_size().y)
	_hero_area.custom_minimum_size = Vector2(0, tallest)
	_layout_hero_pages()

func _layout_hero_pages() -> void:
	if _hero_area == null or _hero_track == null:
		return
	var w: float = _hero_area.size.x
	var h: float = _hero_area.size.y
	if w <= 0.0:
		return
	_hero_track.size = Vector2(w * 2.0, h)
	for i in range(_hero_pages.size()):
		_hero_pages[i].position = Vector2(w * float(i), 0)
		_hero_pages[i].size = Vector2(w, h)
	_hero_track.position.x = -w * float(_hero_index)

func _style_hero_frame(accent: Color) -> void:
	if _hero_frame == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.06)
	sb.set_corner_radius_all(roundi(14 * _s()))
	sb.set_border_width_all(maxi(roundi(2 * _s()), 2))
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	sb.set_content_margin_all(_fs(16))
	_hero_frame.add_theme_stylebox_override("panel", sb)

func _show_hero_page(index: int, animate: bool) -> void:
	_hero_index = clampi(index, 0, 1)
	_style_hero_frame(_endless_accents[_hero_index])
	_style_hero_dots()
	if _hero_area == null or _hero_track == null:
		return
	var target: float = -_hero_area.size.x * float(_hero_index)
	if _hero_tween != null and _hero_tween.is_valid():
		_hero_tween.kill()
	if not animate:
		_hero_track.position.x = target
		return
	_hero_tween = create_tween()
	_hero_tween.tween_property(_hero_track, "position:x", target, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Single Control.gui_input handler rather than HelpScreen's whole-screen _input
# override - HelpScreen needed that ordering trick because tiles nested inside
# its swipe area have their own tap handlers to arbitrate against; nothing
# inside this card is independently tappable, so a plain gui_input on the one
# interactive control is enough.
func _on_hero_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hero_begin_drag(event.position)
		else:
			_hero_end_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_hero_begin_drag(event.position)
		else:
			_hero_end_drag(event.position)
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		_hero_update_drag(event.position)

func _hero_begin_drag(pos: Vector2) -> void:
	_hero_drag_from = pos
	_hero_dragging = true
	_hero_swipe_active = false

func _hero_update_drag(pos: Vector2) -> void:
	if not _hero_dragging:
		return
	var dx: float = pos.x - _hero_drag_from.x
	if absf(dx) > SWIPE_TAP_SLOP:
		_hero_swipe_active = true
	if _hero_swipe_active:
		if _hero_tween != null and _hero_tween.is_valid():
			_hero_tween.kill()
		var base: float = -_hero_area.size.x * float(_hero_index)
		# Resistance at both ends - only two pages exist, so there is no
		# wraparound, the strip just pushes back past either edge.
		var at_edge := (_hero_index == 0 and dx > 0.0) or (_hero_index == 1 and dx < 0.0)
		_hero_track.position.x = base + (dx * 0.35 if at_edge else dx)

func _hero_end_drag(pos: Vector2) -> void:
	if not _hero_dragging:
		return
	_hero_dragging = false
	if not _hero_swipe_active:
		return
	var dx: float = pos.x - _hero_drag_from.x
	var commit: float = _hero_area.size.x * SWIPE_COMMIT_RATIO
	if dx <= -commit:
		_show_hero_page(_hero_index + 1, true)
	elif dx >= commit:
		_show_hero_page(_hero_index - 1, true)
	else:
		_show_hero_page(_hero_index, true)

# Dots advertise the swipe rather than gating it - a tappable dot would need a
# real 48dp hit box the space here doesn't have, so these are indicator-only,
# same call HelpScreen made for its own page dots.
func _build_hero_dot_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(8))
	row.custom_minimum_size = Vector2(0, HERO_DOT_ROW_HEIGHT * _s())
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(2):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(HERO_DOT_SIZE, HERO_DOT_SIZE) * _s()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		_hero_dots.append(dot)
	var wrap := CenterContainer.new()
	wrap.add_child(row)
	return wrap

# Each dot carries its own page's accent rather than one neutral hue for both -
# the dot for the page you're on tells you which mode that is, on top of just
# marking position, echoing the card's own colour coding.
func _style_hero_dots() -> void:
	if _hero_dot_tween != null and _hero_dot_tween.is_valid():
		_hero_dot_tween.kill()
	var animate := is_inside_tree()
	if animate:
		_hero_dot_tween = create_tween()
		_hero_dot_tween.set_parallel(true)
	for i in range(_hero_dots.size()):
		var dot := _hero_dots[i]
		var active := i == _hero_index
		var accent: Color = _endless_accents[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = accent if active else Color(MUTED.r, MUTED.g, MUTED.b, 0.4)
		sb.set_corner_radius_all(roundi(HERO_DOT_SIZE * _s() * 0.5))
		dot.add_theme_stylebox_override("panel", sb)
		var target_w: float = (HERO_DOT_ACTIVE_WIDTH if active else HERO_DOT_SIZE) * _s()
		if not animate:
			dot.custom_minimum_size.x = target_w
			continue
		_hero_dot_tween.tween_property(dot, "custom_minimum_size:x", target_w, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Campaign's counterpart to the hero number, off the same flag the row marks use.
func _perfected_summary() -> Control:
	var total: int = campaign.stages.size() if campaign != null else 0
	var earned := 0
	for i in range(total):
		if SaveManager.load_high_score(CampaignNavigator.ALL_PERFECT_KEY % i) != 0:
			earned += 1
	var l := Label.new()
	l.text = "NO STAGES PERFECTED YET" if earned == 0 		else "%d OF %d STAGES PERFECTED" % [earned, total]
	l.add_theme_font_size_override("font_size", _fs(SUMMARY_SIZE))
	l.add_theme_color_override("font_color", GOLD if earned > 0 else MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

# Muted, not gold. Gold is the outcome/record role in this project's colour
# system, and spending it on column scaffolding is what left nothing to mark the
# actual achievement with.
func _header_row(a: String, b: String) -> Control:
	var row := _row_shell()
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(MARK_CELL * _s(), 0)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot)
	row.add_child(_cell(a, LABEL_CELL, HORIZONTAL_ALIGNMENT_LEFT, MUTED, SECTION_LABEL_SIZE))
	row.add_child(_row_spacer())
	row.add_child(_cell(b, VALUE_CELL, HORIZONTAL_ALIGNMENT_RIGHT, MUTED, SECTION_LABEL_SIZE))
	return row

# Every call is a real campaign stage now that Endless lives in the hero card
# instead of its own pair of rows here, so the mark is no longer optional.
#
# `is_pending`/`reveal_entries`: a stage whose All-PERFECT flag was just earned
# (and not yet shown anywhere) is built in the hollow/neutral state regardless
# of `earned`, and its mark + panel stylebox are appended to `reveal_entries`
# for _populate() to animate a beat after the screen settles - see
# _play_pending_reveals(). Mirrors LevelSelect's own is_pending handling.
func _stage_row(label: String, best: int, earned: bool, is_pending: bool,
		reveal_entries: Array) -> Control:
	var row := _row_shell()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT * _s())

	# Level Select's own mark, instanced rather than redrawn as a second shape
	# for the same fact - one achievement, one visual language. fill 1.0 is the
	# earned bronze-gold ring and tick; 0.0 is its hollow grey "goal, not met"
	# state, which is why an unearned stage still gets a mark rather than an
	# empty gap. This is also what replaces the old Target column: the ring
	# already tells the player whether the stage is fully cleared, so a second
	# number stating the same target score alongside it was redundant.
	var mark := LevelSelect.AllPerfectMark.new()
	mark.fill = 0.0 if is_pending else (1.0 if earned else 0.0)
	mark.custom_minimum_size = Vector2(MARK_CELL, MARK_CELL) * _s()
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)

	row.add_child(_cell(label, LABEL_CELL, HORIZONTAL_ALIGNMENT_LEFT, TEXT_FILL))
	row.add_child(_row_spacer())
	# Gold on the score itself: this is the record, which is what that colour is
	# reserved for.
	row.add_child(_cell(_thousands(best) if best > 0 else "-",
		VALUE_CELL, HORIZONTAL_ALIGNMENT_RIGHT, GOLD))

	# Every other panel-shaped surface in this game (HelpDemoTile, the mark's
	# own plate, Options' card) is a dark-tinted rounded rect with a bright
	# border - the stage list was the one place left as bare hairline-separated
	# text. Wrapping the row in one turns each stage into its own small chip
	# instead of a spreadsheet row, and an earned stage gets the mark's own
	# bronze-gold rather than a second, unrelated accent.
	var settled_t := 0.0 if is_pending else (1.0 if earned else 0.0)
	var sb := _row_panel_style(settled_t)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(row)

	if is_pending:
		reveal_entries.append({"mark": mark, "stylebox": sb})

	return panel

# `t` is the same 0 (hollow/unearned) -> 1 (earned) axis AllPerfectMark's own
# `fill` uses, and shares its two colours (HOLLOW_ACCENT/ACCENT) rather than
# introducing a third accent for what is the same fact - a settled row calls
# this once with its final t; a pending one starts at t=0 and is tweened to
# t=1 by _reveal_stage_entry() alongside the mark's own fill/scale.
func _row_panel_style(t: float) -> StyleBoxFlat:
	var hollow := LevelSelect.AllPerfectMark.HOLLOW_ACCENT
	var earned_accent := LevelSelect.AllPerfectMark.ACCENT
	var c := hollow.lerp(earned_accent, t)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c.r, c.g, c.b, lerpf(0.03, 0.08, t))
	sb.border_color = Color(c.r, c.g, c.b, lerpf(0.22, 0.55, t))
	sb.set_corner_radius_all(roundi(10 * _s()))
	sb.set_border_width_all(maxi(roundi(1.5 * _s()), 1))
	sb.set_content_margin_all(_fs(12))
	return sb

func _row_shell() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# BEGIN, not CENTER: _row_spacer() (an EXPAND_FILL child between the label
	# and value cells) is what does the actual distribution now - it absorbs
	# all the row's spare width, pinning mark+label to the left edge and the
	# score to the right, edge to edge across the device rather than the whole
	# group sitting centred with empty margins either side.
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", _fs(CELL_SEP))
	return row

# The stretchable gap between a row's label and its value - see _row_shell().
func _row_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# A plain faint line, distinct from _make_divider()'s fading hairline: that idiom
# marks a boundary between zones, this one separates items inside one list. The
# separator is what lets the eye cross a row without a label-to-value guide.
# Stretched to the column's own width, matching the rows themselves now that
# they fill it too, rather than the narrower fixed width both used to share.
func _row_rule(alpha: float) -> Control:
	var line := ColorRect.new()
	line.color = Color(MUTED.r, MUTED.g, MUTED.b, alpha)
	line.custom_minimum_size = Vector2(0, maxf(_s(), 1.0))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _cell(text: String, width: float, align: int, color: Color, font_size: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",
		_fs(_cell_font()) if font_size < 0 else _fs(font_size))
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(width * _s(), 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h * _s())
	return c

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, _back_height()) * _s()
	button.add_theme_font_size_override("font_size", _fs(28))
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
	sb.set_content_margin_all(10)
	return sb




