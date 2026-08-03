extends Control
class_name HelpScreen

# Three swipeable pages of live, tappable demos rather than a text legend.
#
# The organising idea: every rule on this screen is *shown* on a real-looking
# timer instead of described. Page 1 splits the types by whether they affect
# only themselves or the whole board - Red and Blue are the only two that reach
# other timers, so they are the only two that need bystanders to demonstrate
# against. Pages 2 and 3 follow the same tap-to-see-it pattern.
#
# Every demo tile is a HelpDemoTile (cosmetic-only) rather than a real
# TimerSlot - see that script for why the distinction matters.

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const MUTED := Color("8b90a8")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")

const PAGE_COUNT := 3

# Portrait is a 900-wide canvas rather than 1600, so landscape type sizes leave
# this reading as a small block adrift in the middle of a phone screen. One
# factor scales type, spacing and control footprints together.
const PORTRAIT_SCALE := 1.5

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel).
const PAGE_HEADING_SIZE := 56
const SECTION_LABEL_SIZE := 20
const TAB_FONT_SIZE := 22
const DESC_FONT_SIZE := 22
const TILE_NAME_SIZE := 14

# Demo tiles are square and sized to match the real board's own timers exactly
# (EndlessRunner.PORTRAIT_CELL_SIZE / cell_size) - not a Help-screen-specific
# proportion - so they read as actual timers rather than a redesigned rectangle.
const TIMER_TILE_LANDSCAPE := 160.0
const TIMER_TILE_PORTRAIT := 200.0
# Digit and name are mutually exclusive faces of the same tile (see
# HelpDemoTile._set_digit_mode), so the name gets to be as big as the digit
# was - "Blackout", the longest type name, measures 152px at a 36pt-equivalent
# ratio in the 200px portrait tile (Font.get_string_size, not eyeballed),
# comfortably inside the tile with margin to spare.
const TIMER_DIGIT_RATIO := 0.27  # matches the real slot's 54pt digit in a 200 tile
const TIMER_NAME_RATIO := 0.18

func _timer_tile_size() -> float:
	return TIMER_TILE_PORTRAIT if Layout.is_portrait() else TIMER_TILE_LANDSCAPE

# Heights of 80 (chips/tabs) and 96 (BACK, in _button()'s override below) are
# deliberately picked so raw * PORTRAIT_SCALE (1.5) * 0.4 dp-per-canvas-unit
# clears the 48dp/56dp touch-target floors on the actual device - measured
# on-device at 32.4/33.7/38.3dp before this fix (Font/Control size sampled
# directly off a captured screenshot, not estimated), all under Android's
# minimum. Landscape isn't the constrained platform (desktop mouse use), so
# raising these here doesn't cost it anything.
const CHIP_SIZE := Vector2(132, 80)
# The powerup activation buttons aren't timers, so they keep their own
# Help-screen-scaled rectangle rather than the real board's square cell size.
const POWERUP_BUTTON_SIZE := Vector2(150, 92)
# Width sized from the longest label actually on a tab: "POWERUPS" measures 180
# at the portrait font size (Font.get_string_size, not estimated), and the
# button's own stylebox adds 8 either side - so 140 x 1.5 = 210 clears 196 with
# real slack. The tab row is the widest fixed-width thing on this screen, so
# over-reserving here is what squeezes the side margins in portrait.
const TAB_SIZE := Vector2(140, 80)
# Reserved so the description swapping between a one-line and a three-line
# string can't reflow the page under the player's finger mid-read. 88 still
# clears 3 wrapped lines at DESC_FONT_SIZE with room to spare (132 canvas units
# in portrait vs. ~119 needed) - trimmed from 96 to claw back the 11 units the
# touch-target increases above pushed `outer` past its 1540-unit portrait
# budget, confirmed via the same measurement probe used for the rest of this
# pass.
const DESC_HEIGHT := 88.0

# Page 1's description used to sit in flow at the bottom of the page. On a tall
# phone that put it ~300px - 13% of screen height - from a tile tapped in the
# upper grid, so the tile and the text explaining it were never in the same
# glance. It is now a panel anchored directly beside the tapped tile.
#
# The panel is a child of _page_area rather than of a page's own VBox
# deliberately: an absolutely-positioned overlay contributes nothing to
# get_combined_minimum_size(), so anchoring the explanation to its tile costs
# the page zero reserved height. That is what made this affordable at all -
# measured, this screen had exactly 1 unit of vertical headroom left, so a
# second in-flow label (DESC_HEIGHT again) was never going to fit.
const CAPTION_GAP := 10.0
const CAPTION_PAD := 14.0
# Body text is TEXT_FILL with the type accent carried on the panel border, not
# painted onto the glyph - the same rule the tile names follow, and for the same
# measured reason (Blackout's #5a5f70 reads 3.19:1 as body text on a near-black
# fill, under the 4.5:1 AA floor). The old flow label set font_color to the type
# colour directly and had this exact failure for Blackout.
const CAPTION_FONT_SIZE := 22

# The tap prompt stays in flow: it is the only thing telling a first-time player
# the tiles are interactive at all, so it can't itself be an on-tap overlay.
# One line rather than DESC_HEIGHT's reserved three, since it no longer has to
# hold a full type description - that is where the height for the dots below
# comes from.
const PROMPT_HEIGHT := 30.0

# Swipe between pages worked and felt good, but nothing on screen advertised it,
# so the tabs read as the only way to move - and they sit in the top ~25% of a
# 6.6" panel, the hardest region to reach one-handed. Dots under the content are
# the convention that says "this strip swipes", which is what makes reaching the
# tabs optional rather than required. Kept as an indicator rather than a control:
# a tappable dot would need a 120-unit (48dp) hit box, and the vertical budget
# for that does not exist on this screen.
const DOT_ROW_HEIGHT := 28.0
const DOT_SIZE := 10.0
const DOT_ACTIVE_WIDTH := 26.0

# How far a drag has to travel before it stops counting as a tap on whatever
# tile it started on, and how far before releasing commits to a page change.
# Deliberately separate values: the first is touch jitter, the second is intent.
const SWIPE_TAP_SLOP := 14.0
const SWIPE_COMMIT_RATIO := 0.18   # of page width

# One baseline for every grade on the scoring page, so the five transitions are
# directly comparable instead of each starting somewhere different.
const DEMO_BASE_MULT := 2.0
const GRADE_ORDER := ["PERFECT", "GOOD", "OKAY", "MISS", "FAIL"]

# The real windows, read straight off TimerSlot's own thresholds rather than
# transcribed, so this page cannot quietly disagree with what the board grades.
# Each demo stops at a random point inside its grade's band and scores from that
# actual distance - a fixed representative number per grade meant the digit on
# the tile and the points beside it were only ever one example of the grade, and
# always the same one.
const GRADE_RANGES := {
	"PERFECT": [0.0, TimerSlot.PERFECT_MAX],
	"GOOD": [TimerSlot.PERFECT_MAX, TimerSlot.GOOD_MAX],
	"OKAY": [TimerSlot.GOOD_MAX, TimerSlot.OKAY_MAX],
	"MISS": [TimerSlot.OKAY_MAX, TimerSlot.MISS_MAX],
	# Open-ended in the real rules; the upper bound here only bounds the demo.
	"FAIL": [TimerSlot.MISS_MAX, TimerSlot.MISS_MAX + 0.5],
}
# Every grade demos from a real countdown now, so the number is arrived at rather
# than asserted. FAIL has to start higher than the rest: it is by definition a
# stop further than MISS_MAX from zero, which a 1.00 start can never reach.
const SCORE_START := 1.0
const SCORE_START_FAIL := 1.6

# How long each demonstrated effect runs before the board returns to idle.
const EFFECT_SEC := 2.0
const RESULT_HOLD_SEC := 1.6
# Shield's catch needs two distinct reads - the fail landing, then the save -
# so it holds the FAIL noticeably before converting and holds the MISS well
# past it. A single quick flip read as a glitch rather than a rescue.
const SHIELD_FAIL_SEC := 0.6
const SHIELD_SAVED_SEC := 2.0
# Where the unclicked timer is caught, comfortably past TimerSlot.MISS_MAX (1.00)
# so it reads unambiguously as the FAIL it is rather than as a borderline MISS.
const SHIELD_FAIL_DISTANCE := 1.25

# --- Page 1 demo timing -------------------------------------------------------
# Every value below is either a real game constant (cited per-line) or a
# deliberately-picked demo number chosen for pacing, not derived from anything.
const NORMAL_START := 3.0
const GOLDEN_BLUR_SEC := 1.8
const BLACKOUT_START := 3.0
const BLACKOUT_THRESHOLD := 1.5   # TimerData.blackout_duration's real default
# Real Decay windows are 0.6/1.8/3.6/6.0s cumulative (TimerData.decay_*_end()) -
# compressed 2.5x here so the full climb doesn't drag, same proportions.
const DECAY_PERFECT_END := 0.24
const DECAY_GOOD_END := 0.72
const DECAY_OKAY_END := 1.44
const DECAY_MISS_END := 2.4
const REACT_TILE_START := 1.2     # Red/Blue's own tile before it resolves
const BYSTANDER_STARTS := [2.0, 2.6]
const RED_SETTLE_SEC := 1.5       # how long the sped-up bystanders run before ending
const BLUE_FREEZE_SEC := 1.0      # matches EndlessRunner's apply_pause(1.0) exactly
const BLUE_SETTLE_SEC := 2.5

var _demo_token: int = 0

func _still_demo(token: int) -> bool:
	return token == _demo_token

# A fresh random landing point inside the real PERFECT window every time a demo
# auto-clicks, instead of a single fixed 0.03 every run - the actual game never
# lands on the exact same distance twice either.
func _random_perfect_stop() -> float:
	return randf_range(0.0, TimerSlot.PERFECT_MAX)

# --- Page 2 demo timing --------------------------------------------------------
const PREVIEW_STARTS := [1.9, 2.5, 3.1]
const NUKE_RUN_SEC := 0.6         # how long the preview timers run before Nuke hits
# Overclock gets its own, much wider spread than Nuke's. At PREVIEW_STARTS' 0.6s
# spacing all three digits sit close enough together that the boost reads as
# "these were always fast" - there is no baseline to compare the change against.
# Spread this far apart, the three visibly finish in sequence while boosted.
const OVERCLOCK_STARTS := [2.5, 4.0, 5.5]
const OVERCLOCK_LEAD_SEC := 1.0   # baseline speed shown before the boost lands

var _powerup_demo_token: int = 0

func _still_powerup_demo(token: int) -> bool:
	return token == _powerup_demo_token

var _score_token: int = 0

# --- Music ducking during a demo ---------------------------------------------
# Reference-counted (not a plain bool) because two independent demos can
# legitimately overlap - a page-1 sequence still finishing while the player has
# already swiped to page 2 and tapped a powerup. Each _duck_music(true) is
# matched by exactly one _duck_music(false), placed at every exit point of
# every demo function (both early-bail guards and natural completion), so the
# count only reaches zero once nothing is actually still animating.
var _duck_count: int = 0

func _duck_music(on: bool) -> void:
	_duck_count = maxi(_duck_count + (1 if on else -1), 0)
	var idx := AudioServer.get_bus_index(AudioManager.BUS_MUSIC)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, _duck_count > 0)

func _force_unduck_music() -> void:
	_duck_count = 0
	var idx := AudioServer.get_bus_index(AudioManager.BUS_MUSIC)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, false)

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

func _side_margin() -> int:
	return 40 if Layout.is_portrait() else 80

var _backdrop: ColorRect
var _margin: MarginContainer
var _built_portrait: bool = false

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _page_area: Control
var _track: Control
var _page_index: int = 0
var _track_tween: Tween

# Swipe state. `_swipe_active` latches the moment a drag passes the tap slop and
# is deliberately NOT cleared on release - the tile/button under the finger
# fires its own pressed signal *after* _input sees that release, and checks this
# flag to decide whether the gesture was a tap or the tail of a swipe.
var _drag_from: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _swipe_active: bool = false

# Keyed by page index rather than a flat array: page 1 no longer registers one
# (it uses the anchored caption instead), and an array would silently shift
# pages 2 and 3 down an index the moment that changed.
var _desc_by_page: Dictionary = {}
var _dots: Array[Panel] = []
var _dot_tween: Tween
var _caption: Panel
var _caption_label: Label
var _caption_tile: HelpDemoTile
var _caption_token: int = 0
var _type_tiles: Array[HelpDemoTile] = []      # page 1, selectable
var _bystander_tiles: Array[HelpDemoTile] = [] # page 1, react to Red/Blue
var _bystander_row: HBoxContainer              # always reserved; tiles fade via set_present
var _powerup_tiles: Array[HelpDemoTile] = []   # page 2, react to the three powerups
var _powerup_buttons: Array[Button] = []
var _grade_buttons: Array[Button] = []
var _score_tile: HelpDemoTile
var _score_readout: Label

func _ready() -> void:
	_build()
	Layout.changed.connect(_apply_canvas)
	GameManager.state_changed.connect(_on_game_state_changed)
	_apply_canvas()

# Screens in this game stay in the tree with only `visible` toggled (see
# MainScreenRouter), so leaving HELP was never actually stopping anything - a
# demo's tick coroutines, its dim state, and its Juice.click_burst rings all
# kept running (and appearing) on top of whatever screen the player navigated
# to. Every tile's idle() bumps its own _play_token, which is what actually
# halts an in-flight play_countdown()/play_decay_climb()/play_blur() loop -
# bumping HelpScreen's own _demo_token alone wouldn't reach into the tile-level
# coroutines those loops are driving.
func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.HELP:
		# Always land on page 1 (Timer Types) - the screen stays in the tree
		# hidden rather than freed (MainScreenRouter only toggles `visible`), so
		# without this a player who last left on, say, Scoring would silently
		# reopen there next visit instead of the intended entry point. Instant,
		# not animated - the screen is only just becoming visible, so a slide
		# transition here would be seen mid-appearance rather than as a real page
		# change.
		_show_page(0, false)
		return
	_cancel_all_demos()

# Stops every in-flight type/powerup/scoring demo and its caption, resetting
# every tile touched back to idle - shared between leaving the screen entirely
# (state_changed, below) and tapping anywhere on it mid-demo (_end_drag()),
# since both need exactly the same reset.
func _cancel_all_demos() -> void:
	_demo_token += 1
	_powerup_demo_token += 1
	_score_token += 1
	_force_unduck_music()
	AudioManager.stop_all_sfx()
	for t in _type_tiles:
		if is_instance_valid(t):
			t.idle()
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.idle()
			b.set_present(false)
	for p in _powerup_tiles:
		if is_instance_valid(p):
			p.idle()
			p.set_present(false)
	if _score_tile != null and is_instance_valid(_score_tile):
		_score_tile.idle()
		_score_tile.set_present(false)
	_hide_caption()
	_undim_page1()
	_undim_powerup_buttons()

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
	_layout_pages()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_margin = null
	_page_area = null
	_track = null
	_score_tile = null
	_score_readout = null
	# Every one of these holds references into the tree being freed above. A
	# rebuild that left them populated would have the handlers below writing to
	# freed nodes (a silent no-op) instead of the new ones - the same class of
	# bug that once left this screen blank after an orientation flip.
	_pages.clear()
	_tabs.clear()
	_dots.clear()
	_dot_tween = null
	_desc_by_page.clear()
	_caption = null
	_caption_label = null
	_caption_tile = null
	_type_tiles.clear()
	_bystander_tiles.clear()
	_bystander_row = null
	_powerup_tiles.clear()
	_powerup_buttons.clear()
	_grade_buttons.clear()
	_build()
	_apply_overscan()

func _apply_overscan() -> void:
	ScreenLayout.cover(_backdrop)

func _build() -> void:
	_built_portrait = Layout.is_portrait()
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_backdrop = ColorRect.new()
	_backdrop.position = Layout.overscan_position
	_backdrop.size = Layout.overscan_size
	_backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_margin = MarginContainer.new()
	_margin.position = Vector2.ZERO
	_margin.size = Layout.canvas_size
	_margin.add_theme_constant_override("margin_left", _side_margin())
	_margin.add_theme_constant_override("margin_right", _side_margin())
	_margin.add_theme_constant_override("margin_top", _fs(20))
	_margin.add_theme_constant_override("margin_bottom", _fs(20))
	add_child(_margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", _fs(14))
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	_margin.add_child(outer)

	var title := WaveHeading.new()
	outer.add_child(title)
	title.configure("HOW TO PLAY", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NEON)

	outer.add_child(_build_tab_row())

	# Pages sit side by side inside a clipped viewport and the whole strip
	# slides - that is what lets a drag track the finger continuously rather
	# than snapping between discrete pages on release.
	_page_area = Control.new()
	_page_area.clip_contents = true
	_page_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_page_area)

	_track = Control.new()
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_area.add_child(_track)

	_pages.append(_build_page_types())
	_pages.append(_build_page_powerups())
	_pages.append(_build_page_scoring())
	for p in _pages:
		_track.add_child(p)
		# Any reflow inside a page - the bystander row expanding, an orientation
		# change - moves the tile an open caption is anchored to. Waiting a fixed
		# number of frames instead was measured wrong: one frame after the row is
		# shown, the tiles still report their pre-expansion rects, which put a
		# Red/Blue caption straight over the bystanders it exists to make room for.
		if p is Container:
			(p as Container).sort_children.connect(_on_page_sorted)

	# Added after _track so it draws over the pages, and parented to _page_area
	# so it is clipped to the same viewport the swipe strip is - a caption
	# anchored to a top-row tile must not be able to paint over the tab row.
	if Layout.is_portrait():
		_build_caption()

	outer.add_child(_build_dot_row())

	var back := _button("BACK", BACK_ACCENT)
	# 96 raw -> 144 canvas units in portrait (57.6dp), clearing the 56dp target -
	# measured at 38.3dp before this fix. See the CHIP_SIZE/TAB_SIZE comment for
	# the same dp-per-canvas-unit derivation.
	back.custom_minimum_size = Vector2(200, 96) * _s()
	back.pressed.connect(_on_back)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	outer.add_child(back_wrap)

	_page_area.resized.connect(_layout_pages)
	# The reserved height comes from the tallest page's own measured content
	# rather than a hand-tuned constant. The old fixed value overflowed twice
	# (each time a font bump wrapped a description to another line) and painted
	# over the nav row below it, because a page's children are not clipped to an
	# undersized reservation - they just spill.
	call_deferred("_size_page_area")
	_show_page(0, false)

func _build_tab_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(10))
	for i in range(PAGE_COUNT):
		var tab := Button.new()
		tab.text = ["TIMERS", "POWERUPS", "SCORING"][i]
		tab.custom_minimum_size = TAB_SIZE * _s()
		tab.add_theme_font_size_override("font_size", _fs(TAB_FONT_SIZE))
		tab.add_theme_constant_override("outline_size", 4)
		PressFeedback.apply(tab)
		tab.pressed.connect(_on_tab_pressed.bind(i))
		row.add_child(tab)
		_tabs.append(tab)
	var wrap := CenterContainer.new()
	wrap.add_child(row)
	return wrap

# Active tab carries the interactive cyan at full strength; the others drop to
# muted flat text. Weight, not hue - the same emphasis idiom the result screens
# use for their button rows.
func _build_dot_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(10))
	row.custom_minimum_size = Vector2(0, DOT_ROW_HEIGHT * _s())
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(PAGE_COUNT):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE) * _s()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		_dots.append(dot)
	var wrap := CenterContainer.new()
	wrap.add_child(row)
	return wrap

# The active dot stretches into a short pill rather than just brightening, so
# the current page is readable without relying on a colour difference alone.
# One parallel tween for the whole row, killed on re-entry: a fast swipe can call
# this again mid-animation, and a per-dot tween would leave two of them driving
# the same custom_minimum_size:x against each other.
func _style_dots() -> void:
	if _dot_tween != null and _dot_tween.is_valid():
		_dot_tween.kill()
	var animate := is_inside_tree()
	if animate:
		_dot_tween = create_tween()
		_dot_tween.set_parallel(true)
	for i in range(_dots.size()):
		var dot := _dots[i]
		var active := i == _page_index
		var sb := StyleBoxFlat.new()
		sb.bg_color = NEON if active else Color(MUTED.r, MUTED.g, MUTED.b, 0.45)
		sb.set_corner_radius_all(roundi(DOT_SIZE * _s() * 0.5))
		dot.add_theme_stylebox_override("panel", sb)
		var target_w: float = (DOT_ACTIVE_WIDTH if active else DOT_SIZE) * _s()
		if not animate:
			dot.custom_minimum_size.x = target_w
			continue
		_dot_tween.tween_property(dot, "custom_minimum_size:x", target_w, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _style_tabs() -> void:
	for i in range(_tabs.size()):
		var tab := _tabs[i]
		var active := i == _page_index
		var accent: Color = NEON if active else MUTED
		tab.add_theme_color_override("font_color", Color.WHITE if active else MUTED)
		tab.add_theme_color_override("font_outline_color", accent if active else Color(0, 0, 0, 0.6))
		for state in ["normal", "hover", "pressed"]:
			tab.add_theme_stylebox_override(state, _tab_box(accent, active))

func _tab_box(accent: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.78) if active else Color(1, 1, 1, 0.03)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(3 if active else 1)
	sb.border_color = accent if active else Color(accent.r, accent.g, accent.b, 0.35)
	sb.set_content_margin_all(8)
	return sb

# --- Anchored caption ---------------------------------------------------------

func _build_caption() -> void:
	# Panel, not PanelContainer - deliberately, same reason HelpDemoTile is a
	# Panel with manually-positioned children rather than a Container: a
	# Container's get_combined_minimum_size() bubbles up its children's own
	# minimum sizes, and Control.size= always clamps up to at least that value
	# on assignment. An AUTOWRAP_WORD_SMART label's wrap-height computation is
	# degenerate (multi-thousand units) the very first time it is ever given a
	# real width - which for this label is the very first _show_caption() call,
	# since it starts at width 0 and nothing has ever queried its layout before
	# then. A bare Panel's own minimum size is just custom_minimum_size (never
	# set here, so (0,0)) regardless of what its children report, so _caption's
	# size can never be silently inflated by the label inside it - the label's
	# own rect is set directly in _show_caption() instead of relying on
	# PanelContainer's automatic single-child-fits-content-area behaviour.
	_caption = Panel.new()
	# STOP, not IGNORE: the panel is dismissed by tapping it. That also means it
	# swallows taps on whatever tile it happens to be covering, which is the
	# behaviour we want - the thing under your finger is the caption.
	_caption.mouse_filter = Control.MOUSE_FILTER_STOP
	_caption.gui_input.connect(_on_caption_input)
	_caption.z_index = 10
	_caption.visible = false
	_caption.modulate.a = 0.0

	_caption_label = Label.new()
	_caption_label.add_theme_font_size_override("font_size", _fs(CAPTION_FONT_SIZE))
	_caption_label.add_theme_color_override("font_color", TEXT_FILL)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_caption_label)

	# One-time warm-up, while invisible, never shown to the player. This is the
	# real fix for a bug that survived switching _caption to a plain Panel above:
	# a Control's size= clamps up to at least get_combined_minimum_size(), and
	# that clamp check reads the label's CURRENT shaping state, evaluated
	# *before* whatever new width is being assigned in the same call takes
	# effect - so a label that has never had a real width has no correct
	# shaping to fall back on, and the very first real assignment (in
	# _show_caption(), whichever tile the player taps first) gets its own
	# height clamped to a multi-thousand-unit value from wrapping into a
	# near-zero-width column. Confirmed via a headless probe: the label's
	# internally-shaped size self-corrects within the same/next frame
	# regardless (read back correctly a few frames later), it just isn't
	# reflected in the clamp that already happened - so priming it here, well
	# before the player can possibly tap anything, means the very first real
	# call already has correct shaping to clamp against instead of none at all.
	# Text and width both matter here, not just "any nonzero size" - a first
	# pass using a single space at width 400 measurably reduced the effect
	# (multi-thousand units down to ~144) but didn't fully match a real call's
	# ~95, so the shaping this primes is closer to "wrap this exact text at
	# this exact width" than a generic escape from an uninitialised state. Using
	# the longest real caption (Red's) at a generously wide, real-looking width
	# is what actually closed the remaining gap in a headless probe.
	_caption_label.text = "Red - " + TimerTypeInfo.desc_of(TimerData.TimerType.RED)
	_caption_label.size = Vector2(900.0, 200.0)
	_caption_label.text = " "

	_page_area.add_child(_caption)

func _caption_box(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# Near-opaque rather than a light tint: this panel lands on top of tiles that
	# are dimmed but still drawn, and a translucent fill would put their borders
	# and digits through the text.
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.96)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 8
	# content_margin only matters for PanelContainer's automatic child-fit,
	# which _caption no longer uses - CAPTION_PAD is applied directly to the
	# label's own manually-assigned rect in _show_caption() instead.
	return sb

# Cached the first time _measured_caption_height() actually needs it - see that
# function for why DESC_HEIGHT itself (a different reservation, still used by
# the landscape in-flow prompt label) turned out wrong for this box specifically.
var _caption_box_height: float = 0.0

# A fixed height, not one recomputed per tap - "a constant height stops the
# panel resizing as the player moves between types" is still the right call,
# it was just measured against the wrong thing. DESC_HEIGHT (88 raw) was
# calibrated for the OLD in-flow flow-label, which was both WIDER (no
# CAPTION_GAP/CAPTION_PAD subtracted from it) and had no box padding eating
# into its own reservation - carrying that same number over to this narrower,
# padded overlay box left Red's and Decay's descriptions (the two longest,
# each wrapping to 3 lines at this width) overflowing the visible border by 54
# units - confirmed on-device and reproduced headlessly. custom_minimum_size()
# can't be queried at _build_caption() time either: _page_area.size reads
# (0,0) there, before its own deferred sizing pass has run - so this measures
# lazily against every real timer description, at the real width, the first
# time a caption is actually shown, rather than guessing a number up front.
func _measured_caption_height() -> float:
	if _caption_box_height > 0.0:
		return _caption_box_height
	var pad := CAPTION_PAD * _s()
	var width: float = maxf(_page_area.size.x - CAPTION_GAP * _s() * 2.0 - pad * 2.0, 1.0)
	var tallest := 0.0
	for t in TimerTypeInfo.ORDER:
		_caption_label.text = "%s - %s" % [TimerTypeInfo.name_of(t), TimerTypeInfo.desc_of(t)]
		_caption_label.size = Vector2(width, 0.0)
		tallest = maxf(tallest, _caption_label.get_combined_minimum_size().y)
	_caption_box_height = tallest + pad * 2.0
	return _caption_box_height

func _show_caption(tile: HelpDemoTile, text: String, accent: Color) -> void:
	if _caption == null or _page_area == null or not is_instance_valid(tile):
		return
	_caption_token += 1
	var token := _caption_token
	_caption_tile = tile
	_caption.add_theme_stylebox_override("panel", _caption_box(accent))
	var width: float = maxf(_page_area.size.x - CAPTION_GAP * _s() * 2.0, 1.0)
	var height: float = _measured_caption_height()
	_caption_label.text = text
	_caption.size = Vector2(width, height)
	# Positioned directly rather than left to PanelContainer's automatic
	# single-child-fit (see _build_caption() for why _caption is a plain Panel
	# now, not a PanelContainer) - this assigns the label's real rect
	# synchronously, in this same frame, so its AUTOWRAP_WORD_SMART wrap-height
	# computation has a correct width to work with immediately rather than
	# depending on a deferred layout pass that hasn't run yet.
	var pad: float = CAPTION_PAD * _s()
	_caption_label.position = Vector2(pad, pad)
	_caption_label.size = Vector2(width, height) - Vector2(pad, pad) * 2.0
	_caption.modulate.a = 0.0
	_caption.visible = true
	# Placed a frame later: on a Red or Blue tap the bystander row has just been
	# expanded, and this page re-centres around it - so the tile being anchored
	# to has not finished moving yet at this point.
	await get_tree().process_frame
	if token != _caption_token or not is_instance_valid(_caption):
		return
	_position_caption()
	var tween := create_tween()
	tween.tween_property(_caption, "modulate:a", 1.0, 0.18)

# Deferred rather than immediate: a page's own sort resizes its nested
# CenterContainers, which queue sorts of their own, so a tile's final rect is
# not settled until every pending sort in the frame has run.
func _on_page_sorted() -> void:
	if _caption_tile != null:
		call_deferred("_position_caption")

func _position_caption() -> void:
	if _caption == null or _page_area == null:
		return
	if _caption_tile == null or not is_instance_valid(_caption_tile):
		return
	var gap: float = CAPTION_GAP * _s()
	var h: float = _caption.size.y
	var area := _page_area.get_global_rect()
	var tile_rect := _caption_tile.get_global_rect()
	var top: float = tile_rect.position.y - area.position.y
	var bottom: float = top + tile_rect.size.y
	# Below the tile by preference, flipped above when that would either overrun
	# the page viewport or land on the bystander row.
	#
	# The bystander test is not redundant with the viewport one: measured, a Red
	# caption placed below sits at 753-885 while the expanded bystander row spans
	# 747-947, so it fits the page perfectly well and still covers the exact
	# reaction it is describing. Red and Blue are the only types with bystanders,
	# so they are the only ones that take this flip.
	var y: float = bottom + gap
	var blocked: bool = y + h > area.size.y
	if not blocked and _bystander_row != null and _bystander_row.is_visible_in_tree():
		var brect := _bystander_row.get_global_rect()
		var b_top: float = brect.position.y - area.position.y
		blocked = y < b_top + brect.size.y and y + h > b_top
	if blocked:
		y = top - gap - h
	_caption.position = Vector2(gap, clampf(y, 0.0, maxf(area.size.y - h, 0.0)))

# Tapped to dismiss. Release rather than press, and gated on _swipe_active, for
# the same reason HelpDemoTile emits on release: a press-time handler fires
# before the gesture can be told apart from the start of a swipe.
func _on_caption_input(event: InputEvent) -> void:
	if _swipe_active:
		return
	var released: bool = (event is InputEventMouseButton \
		and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and not event.pressed)
	if released:
		_hide_caption()

func _hide_caption() -> void:
	_caption_token += 1
	_caption_tile = null
	if _caption != null and is_instance_valid(_caption):
		_caption.visible = false
		_caption.modulate.a = 0.0

# --- Page 1: timer types ------------------------------------------------------

func _build_page_types() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(12))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var self_group := _build_type_group("AFFECTS ONLY ITSELF", [
		TimerData.TimerType.NORMAL, TimerData.TimerType.GOLDEN,
		TimerData.TimerType.BLACKOUT, TimerData.TimerType.DECAY,
	], false)
	var board_group := _build_type_group("AFFECTS THE WHOLE BOARD", [
		TimerData.TimerType.RED, TimerData.TimerType.BLUE,
	], true)

	# Portrait stacks the two groups; landscape sets them side by side, which is
	# the one place the extra width is genuinely worth using - everything else on
	# this screen is the same shape in both orientations.
	if Layout.is_portrait():
		col.add_child(self_group)
		col.add_child(board_group)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _fs(56))
		row.add_child(self_group)
		row.add_child(board_group)
		var wrap := CenterContainer.new()
		wrap.add_child(row)
		col.add_child(wrap)

	# Portrait binds the description to the tapped tile and keeps only the standing
	# prompt in flow; landscape keeps the original in-flow label. The distance this
	# fixes is a tall-phone problem - measured at ~300px there against 114 units of
	# spare height here - and landscape sets the two groups side by side, so a
	# full-width panel under a tile would cover the other group. Measured, Red and
	# Blue also have no room above them in that layout: the flip lands at -64.
	if Layout.is_portrait():
		col.add_child(_make_prompt_label("Tap any timer to see what it does."))
	else:
		col.add_child(_make_desc_label(0, "Tap any timer to see what it does."))
	return col

# `with_bystanders` fills the lower half of the 2x2 with plain Normal timers, so
# Red and Blue have something to visibly act on. They are the only two types
# whose rule mentions other timers at all, which is exactly why they are the
# only two that get them.
func _build_type_group(heading: String, types: Array, with_bystanders: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(6))

	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _fs(12))
	grid.add_theme_constant_override("v_separation", _fs(12))
	for t in types:
		var tile := _make_tile(t, TimerTypeInfo.name_of(t))
		tile.tapped.connect(_on_type_tapped)
		_type_tiles.append(tile)
		grid.add_child(tile)

	var wrap := CenterContainer.new()
	wrap.add_child(grid)
	col.add_child(wrap)

	# The bystander row holds its space permanently and the tiles inside it fade
	# via set_present() (modulate), which a Container does not treat as a size
	# change. Collapsing the row's `visible` instead was tried and reverted: it
	# reclaimed the idle blank space, but because this page's column is centred
	# inside a fixed-height page area, expanding the row on every Red/Blue tap
	# shifted every other timer on the page upward by 100 units for the duration
	# of the demo, which was reported as looking broken. Stationary timers win.
	#
	# It costs no net height either way, which is the part worth knowing before
	# anyone "reclaims" it again: _size_page_area reserves the tallest page, and
	# that measurement has always included this row expanded. Collapsing it never
	# shrank the reservation - it only moved the same 200 units of blank from
	# below Red/Blue out to the page's top and bottom edges.
	if with_bystanders:
		_bystander_row = HBoxContainer.new()
		_bystander_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_bystander_row.add_theme_constant_override("separation", _fs(12))
		for i in range(2):
			var b := _make_tile(TimerData.TimerType.NORMAL,
				TimerTypeInfo.name_of(TimerData.TimerType.NORMAL))
			# Bystanders are scenery, not choices - tapping one would select a
			# second "Normal" that already has its own tile in the group above.
			b.interactive = false
			# Starts invisible so set_present(true) still gets to fade them in
			# the first time the row is shown, rather than the row's own
			# visible=true snap making them appear at full opacity instantly.
			b.modulate.a = 0.0
			_bystander_tiles.append(b)
			_bystander_row.add_child(b)
		var row_wrap := CenterContainer.new()
		row_wrap.add_child(_bystander_row)
		col.add_child(row_wrap)

	return col

# Dispatches to one scripted, complete demonstration per type - a tile no
# longer just reacts, it plays out its entire rule end to end (spawn through
# resolution) while every tile not involved dims out of the way. Bumping
# _demo_token first is what lets a second tap (same tile or a different one)
# cleanly interrupt whatever's still playing: every step below checks
# _still_demo(token) and quietly stops touching nodes the instant it goes
# stale, rather than needing a separate "is something running" flag that could
# get stuck true if a sequence is ever interrupted mid-await.
func _on_type_tapped(tile: HelpDemoTile) -> void:
	if _swipe_active:
		return
	_demo_token += 1
	var token := _demo_token
	var text := "%s - %s" % [TimerTypeInfo.name_of(tile.timer_type),
		TimerTypeInfo.desc_of(tile.timer_type)]
	var accent: Color = TimerTypeInfo.color_of(tile.timer_type)
	if Layout.is_portrait():
		_show_caption(tile, text, accent)
	else:
		_set_desc(0, text, accent)

	match tile.timer_type:
		TimerData.TimerType.NORMAL:
			_play_normal_demo(tile, token)
		TimerData.TimerType.GOLDEN:
			_play_golden_demo(tile, token)
		TimerData.TimerType.BLACKOUT:
			_play_blackout_demo(tile, token)
		TimerData.TimerType.DECAY:
			_play_decay_demo(tile, token)
		TimerData.TimerType.RED:
			_play_red_demo(tile, token)
		TimerData.TimerType.BLUE:
			_play_blue_demo(tile, token)

# Bystanders are deliberately left out of the dim sweep: they're either fully
# present and already in `keep` (a Red/Blue demo always keeps them) or fully
# absent (set_present(false)), and set_dimmed()/set_present() both animate the
# same modulate:a - dimming an absent bystander would tween it partway toward
# visible for no reason, and undimming one on every demo's exit would fade a
# tile back in that was never supposed to be seen.
func _dim_page1_except(keep: Array) -> void:
	for t in _type_tiles:
		t.set_dimmed(not keep.has(t))

func _undim_page1() -> void:
	for t in _type_tiles:
		t.set_dimmed(false)

# NORMAL - the baseline every other demo is read against: counts down, an
# auto-click near 0.00 lands a PERFECT.
func _play_normal_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	var stop := _random_perfect_stop()
	await tile.play_countdown(NORMAL_START, stop)
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("PERFECT", "%.2f" % stop, RESULT_HOLD_SEC)
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token)

# GOLDEN - never counts down on the real board either, so this shows the blur
# for a beat, then the guaranteed "0.00" PERFECT with its real x2 bonus.
func _play_golden_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	await tile.play_blur(GOLDEN_BLUR_SEC)
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("PERFECT", "0.00", RESULT_HOLD_SEC, "x2")
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token)

# BLACKOUT - counts down visibly, blanks to the real "??.??" once inside
# blackout_duration (1.5s), keeps draining unseen, then reveals the true value
# the instant it resolves - exactly what the real slot does on stop - with its
# real x2.5 bonus (the highest of any type, per StageController.compute_bonus_factor).
func _play_blackout_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	var stop := _random_perfect_stop()
	await tile.play_countdown(BLACKOUT_START, stop, BLACKOUT_THRESHOLD)
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("PERFECT", "%.2f" % stop, RESULT_HOLD_SEC, "x2.5")
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token)

# DECAY - counts UP from 0.00, stepping through the same four tier colours the
# real board uses, and auto-resolves as MISS at its ceiling. Never FAIL - a
# locked-in rule (Decay can't cost a life), not an oversight.
func _play_decay_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	await tile.play_decay_climb(DECAY_PERFECT_END, DECAY_GOOD_END, DECAY_OKAY_END, DECAY_MISS_END)
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("MISS", "%.2f" % DECAY_MISS_END, RESULT_HOLD_SEC)
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token)

# RED - the two bystanders are already running when Red resolves, so cause and
# effect read in order: Red stops, THEN they visibly react. The reaction is
# permanent (matches TimerSlot.apply_speedup - it never reverts), so they run
# the rest of the demo faster and each closes out with the real x1.25 bonus a
# Red-boosted stop actually earns.
func _play_red_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	var keep: Array = [tile] + _bystander_tiles
	_dim_page1_except(keep)
	tile.set_selected(true)
	for b in _bystander_tiles:
		b.set_present(true)
	for i in range(_bystander_tiles.size()):
		_run_bystander_speedup(_bystander_tiles[i], BYSTANDER_STARTS[i], token)
	await tile.play_countdown(REACT_TILE_START, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.react_speedup_permanent()
	await get_tree().create_timer(RED_SETTLE_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token, keep)

func _run_bystander_speedup(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(b):
		return
	b.play_grade("PERFECT", "%.2f" % b.value, RESULT_HOLD_SEC, "x1.25")

# BLUE - same bystander setup as Red, but the reaction has to look undone, not
# permanent: a full 1.0s freeze (matches EndlessRunner's apply_pause(1.0)
# exactly), then a normal-speed resume with no bonus, since Blue only pauses,
# it never boosts.
func _play_blue_demo(tile: HelpDemoTile, token: int) -> void:
	_duck_music(true)
	var keep: Array = [tile] + _bystander_tiles
	_dim_page1_except(keep)
	tile.set_selected(true)
	for b in _bystander_tiles:
		b.set_present(true)
	for i in range(_bystander_tiles.size()):
		_run_bystander_plain(_bystander_tiles[i], BYSTANDER_STARTS[i], token)
	await tile.play_countdown(REACT_TILE_START, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.react_freeze(BLUE_FREEZE_SEC)
	await get_tree().create_timer(BLUE_SETTLE_SEC, true, false, true).timeout
	_duck_music(false)
	_end_type_demo(tile, token, keep)

func _run_bystander_plain(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(b):
		return
	b.play_grade("PERFECT", "%.2f" % b.value, RESULT_HOLD_SEC)

# Shared close: holds the resolved state a beat, then fades every dimmed tile
# back and resets whichever tiles this sequence actually drove. `also` covers
# the bystanders on a Red/Blue demo - Normal/Golden/Blackout/Decay only ever
# touch the tapped tile itself.
func _end_type_demo(tile: HelpDemoTile, token: int, also: Array = []) -> void:
	if not _still_demo(token) or not is_instance_valid(tile):
		return
	tile.set_selected(false)
	await get_tree().create_timer(0.3, true, false, true).timeout
	if not _still_demo(token):
		return
	_undim_page1()
	tile.idle()
	for t in also:
		if t != tile and is_instance_valid(t):
			t.idle()
			# Bystanders only exist for the demo that just finished (see
			# _play_red_demo/_play_blue_demo) - back to absent, not just idle.
			# Their row holds its space either way, so this is a fade and not a
			# layout change: nothing else on the page moves when they go.
			if _bystander_tiles.has(t):
				t.set_present(false)

# --- Page 2: powerups ---------------------------------------------------------

func _build_page_powerups() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(12))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = "ENDLESS MODE ONLY"
	label.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", _fs(12))
	for kind in PowerupSystem.ORDER:
		var b := _make_powerup_button(kind)
		_powerup_buttons.append(b)
		button_row.add_child(b)
	var button_wrap := CenterContainer.new()
	button_wrap.add_child(button_row)
	col.add_child(button_wrap)

	# A three-timer stand-in for the board. Shield is the reason this row exists
	# rather than a single tile: it is the one powerup that saves exactly one
	# timer, and seeing the other two carry on untouched is what distinguishes it
	# from Nuke and Overclock without needing a sentence to say so.
	var demo_row := HBoxContainer.new()
	demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_row.add_theme_constant_override("separation", _fs(12))
	for i in range(3):
		var tile := _make_tile(TimerData.TimerType.NORMAL, "")
		tile.interactive = false
		_powerup_tiles.append(tile)
		demo_row.add_child(tile)
		# Nothing to demonstrate until a powerup is actually tapped.
		tile.set_present(false)
	var demo_wrap := CenterContainer.new()
	demo_wrap.add_child(demo_row)
	col.add_child(demo_wrap)

	col.add_child(_make_desc_label(1, "Tap a powerup to see what it does."))
	return col

func _make_powerup_button(kind: int) -> Button:
	var accent: Color = PowerupSystem.color_of(kind)
	var button := Button.new()
	button.custom_minimum_size = POWERUP_BUTTON_SIZE * _s()
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	button.pressed.connect(_on_powerup_pressed.bind(kind))

	# The same drawn glyph the in-game buttons use, so the legend and the board
	# can't drift apart. mouse_filter IGNORE on both children so neither steals
	# the click meant for the Button underneath.
	var icon := PowerupIcon.new(kind)
	var icon_size: float = POWERUP_BUTTON_SIZE.y * _s() * 0.42
	icon.size = Vector2(icon_size, icon_size)
	icon.position = Vector2((POWERUP_BUTTON_SIZE.x * _s() - icon_size) * 0.5, POWERUP_BUTTON_SIZE.y * _s() * 0.12)
	button.add_child(icon)

	var name_label := Label.new()
	name_label.text = PowerupSystem.name_of(kind)
	name_label.add_theme_font_size_override("font_size", _fs(TILE_NAME_SIZE))
	name_label.add_theme_color_override("font_color", accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.position = Vector2(0, POWERUP_BUTTON_SIZE.y * _s() * 0.66)
	name_label.size = Vector2(POWERUP_BUTTON_SIZE.x * _s(), POWERUP_BUTTON_SIZE.y * _s() * 0.28)
	button.add_child(name_label)

	return button

func _on_powerup_pressed(kind: int) -> void:
	if _swipe_active:
		return
	_powerup_demo_token += 1
	var token := _powerup_demo_token
	var accent: Color = PowerupSystem.color_of(kind)
	_set_desc(1, "%s - %s  (%s)" % [PowerupSystem.name_of(kind),
		Powerups.describe(kind), Powerups.cooldown_text(kind)], accent)
	_dim_powerup_buttons_except(kind)
	# The same activation cue the real board plays the instant a powerup button
	# is pressed - AudioManager only, no Powerups.activate() call, so nothing
	# about cooldowns/charges is touched.
	AudioManager.play_powerup_activate(kind)

	match kind:
		PowerupSystem.Kind.CLEAR_ALL:
			_play_nuke_demo(token)
		PowerupSystem.Kind.OVERCLOCK:
			_play_overclock_demo(token)
		PowerupSystem.Kind.SHIELD:
			_play_shield_demo(token)

func _dim_powerup_buttons_except(kind: int) -> void:
	for i in range(_powerup_buttons.size()):
		var on: bool = PowerupSystem.ORDER[i] != kind
		var button := _powerup_buttons[i]
		var tween := create_tween()
		tween.tween_property(button, "modulate:a", 0.25 if on else 1.0, 0.18)
		button.disabled = on

func _undim_powerup_buttons() -> void:
	for button in _powerup_buttons:
		var tween := create_tween()
		tween.tween_property(button, "modulate:a", 1.0, 0.18)
		button.disabled = false

# Nuke's real effect is instant and forces whatever value each timer happens to
# be showing at that moment - so the three preview tiles are left running for
# NUKE_RUN_SEC first, their live values captured, then their own countdown
# loops are cancelled (cancel_playback()) before play_grade freezes them there.
# Without the cancel, each tile's still-running play_countdown would keep
# overwriting the frozen digit out from under the grade sign a frame later.
func _play_nuke_demo(token: int) -> void:
	_duck_music(true)
	for i in range(_powerup_tiles.size()):
		_powerup_tiles[i].set_present(true)
		_powerup_tiles[i].play_countdown(PREVIEW_STARTS[i], 0.0)
	await get_tree().create_timer(NUKE_RUN_SEC, true, false, true).timeout
	if not _still_powerup_demo(token):
		_duck_music(false)
		return
	# Every digit is frozen up front, then the resolutions are staggered - the
	# same two beats the real Nuke has, where Juice.freeze_gameplay() stops the
	# board and _run_nuke_cascade walks it. Capturing before the stagger is what
	# makes the freeze real: resolving tile 3 two gaps later must show the value
	# it held when the powerup landed, not one it kept counting down to since.
	var total: int = _powerup_tiles.size()
	var frozen: Array[String] = []
	for tile in _powerup_tiles:
		# Appended in both branches so frozen[i] stays aligned with tile i - the
		# cascade below indexes them together.
		if is_instance_valid(tile):
			frozen.append("%.2f" % tile.value)
			tile.cancel_playback()
		else:
			frozen.append("0.00")
	# Same fixed total length the board uses, divided the same way, so the legend
	# and the real cascade run at the same rhythm.
	var gap: float = EndlessRunner.NUKE_CASCADE_SEC / float(maxi(total, 1))
	for i in range(total):
		if not _still_powerup_demo(token):
			_duck_music(false)
			return
		var t: HelpDemoTile = _powerup_tiles[i]
		if is_instance_valid(t):
			t.play_grade("PERFECT", frozen[i], RESULT_HOLD_SEC)
			AudioManager.play_nuke_note(i, total)
		if i < total - 1:
			await get_tree().create_timer(gap, true, false, true).timeout
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

# All three run at a visible baseline speed first (OVERCLOCK_LEAD_SEC) so the
# boost reads as a change, not just "these were always fast" - then every tile
# gets react_overclock, which (unlike Red's permanent bump) reverts on its own
# once EFFECT_SEC elapses, matching the real powerup's timed duration.
func _play_overclock_demo(token: int) -> void:
	_duck_music(true)
	for i in range(_powerup_tiles.size()):
		_powerup_tiles[i].set_present(true)
		_run_preview_countdown(_powerup_tiles[i], OVERCLOCK_STARTS[i], token)
	await get_tree().create_timer(OVERCLOCK_LEAD_SEC, true, false, true).timeout
	if not _still_powerup_demo(token):
		_duck_music(false)
		return
	for tile in _powerup_tiles:
		if is_instance_valid(tile):
			tile.react_overclock(EFFECT_SEC)
	await get_tree().create_timer(EFFECT_SEC + 2.0, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

func _run_preview_countdown(tile: HelpDemoTile, start: float, token: int) -> void:
	await tile.play_countdown(start, _random_perfect_stop())
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)

# Shield acts on exactly one timer, and the demonstration is the asymmetry: the
# other two preview tiles are dimmed out entirely (they never even start
# running) while the first genuinely counts all the way out - a real FAIL,
# caught a beat later and settled as a MISS. Only one timer is ever at risk,
# which is the whole point Nuke and Overclock's demos (all three participate)
# exist to contrast against.
#
# On the real board this conversion is invisible - Powerups.filter_grade()
# runs before _play_stop_flash() ever fires, so a saved player only ever sees
# the MISS. Showing the FAIL first anyway is deliberately more than the real
# board renders: the whole point here is teaching what Shield prevented, not
# reproducing the live feed frame-for-frame.
func _play_shield_demo(token: int) -> void:
	if _powerup_tiles.is_empty():
		return
	_duck_music(true)
	# The other two never appear at all for this one - Shield only ever puts
	# one timer at risk, unlike Nuke/Overclock which reveal all three.
	var tile: HelpDemoTile = _powerup_tiles[0]
	tile.set_present(true)
	await tile.play_countdown(REACT_TILE_START, 0.0)
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	# Nobody clicks it, so it overruns rather than stopping dead at zero. This is
	# the part the demo used to get wrong: it froze at "0.00" and called that a
	# FAIL, but 0.00 is the exact centre of the PERFECT window. A FAIL is a stop
	# more than TimerSlot.MISS_MAX (1.00) from zero, which is only reachable by
	# running past it.
	await tile.play_overrun(SHIELD_FAIL_DISTANCE)
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	var overrun := "%.2f" % SHIELD_FAIL_DISTANCE
	tile.play_grade("FAIL", overrun, SHIELD_FAIL_SEC + SHIELD_SAVED_SEC)
	await get_tree().create_timer(SHIELD_FAIL_SEC, true, false, true).timeout
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	# The distance is unchanged by the save - Powerups.filter_grade() rewrites the
	# grade and nothing else, so the digit stays exactly where it landed.
	tile.play_grade("MISS", overrun, SHIELD_SAVED_SEC)
	await get_tree().create_timer(SHIELD_SAVED_SEC, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

func _end_powerup_demo(token: int) -> void:
	if not _still_powerup_demo(token):
		return
	_undim_powerup_buttons()
	for tile in _powerup_tiles:
		if is_instance_valid(tile):
			tile.set_dimmed(false)
			tile.idle()
			tile.set_present(false)

# --- Page 3: scoring ----------------------------------------------------------

func _build_page_scoring() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(12))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = "CLOSER TO 0.00 SCORES MORE"
	label.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)

	var grid := GridContainer.new()
	grid.columns = 3 if Layout.is_portrait() else 5
	grid.add_theme_constant_override("h_separation", _fs(10))
	grid.add_theme_constant_override("v_separation", _fs(10))
	for grade in GRADE_ORDER:
		var chip := _make_grade_chip(grade)
		_grade_buttons.append(chip)
		grid.add_child(chip)
	var grid_wrap := CenterContainer.new()
	grid_wrap.add_child(grid)
	col.add_child(grid_wrap)

	var demo_row := HBoxContainer.new()
	demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_row.add_theme_constant_override("separation", _fs(24))
	_score_tile = _make_tile(TimerData.TimerType.NORMAL, "")
	_score_tile.interactive = false
	demo_row.add_child(_score_tile)
	# Nothing to demonstrate until a grade is actually tapped.
	_score_tile.set_present(false)

	_score_readout = Label.new()
	_score_readout.add_theme_font_size_override("font_size", _fs(DESC_FONT_SIZE))
	_score_readout.add_theme_color_override("font_color", TEXT_FILL)
	_score_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_readout.custom_minimum_size = Vector2(300, 0) * _s()
	demo_row.add_child(_score_readout)

	var demo_wrap := CenterContainer.new()
	demo_wrap.add_child(demo_row)
	col.add_child(demo_wrap)

	col.add_child(_make_desc_label(2, "Tap a grade to see it land."))
	return col

func _make_grade_chip(grade: String) -> Button:
	var color: Color = ScoreManager.grade_color(grade)
	var chip := Button.new()
	chip.text = grade
	chip.custom_minimum_size = CHIP_SIZE * _s()
	chip.add_theme_font_size_override("font_size", _fs(TILE_NAME_SIZE + 4))
	chip.add_theme_color_override("font_color", Color.WHITE)
	chip.add_theme_color_override("font_outline_color", color)
	chip.add_theme_constant_override("outline_size", 4)
	chip.add_theme_stylebox_override("normal", _box(color, 0.85))
	chip.add_theme_stylebox_override("hover", _box(color, 0.7))
	chip.add_theme_stylebox_override("pressed", _box(color, 0.6))
	PressFeedback.apply(chip)
	chip.pressed.connect(_on_grade_pressed.bind(grade))
	return chip

# Points and the multiplier step are both computed from ScoreManager's own
# static helpers rather than transcribed into a table here, so this page cannot
# quietly disagree with real scoring if those formulas are ever retuned.
func _on_grade_pressed(grade: String) -> void:
	if _swipe_active:
		return
	_score_token += 1
	var token := _score_token
	var color: Color = ScoreManager.grade_color(grade)
	var span: Array = GRADE_RANGES[grade]
	var dist: float = randf_range(span[0], span[1])

	# The description states the window; the readout below states what this
	# particular stop scored inside it.
	var suffix := "  Ends the stage." if grade == "FAIL" else ""
	_set_desc(2, "%s - %s%s" % [grade, _range_text(grade), suffix], color)

	if _score_tile == null or not is_instance_valid(_score_tile):
		return
	# Cleared while the timer is still running: the previous stop's points must
	# not sit next to a digit that is currently counting toward a different one.
	if _score_readout != null:
		_score_readout.text = ""
	_score_tile.set_present(true)
	await _score_tile.play_countdown(
		SCORE_START_FAIL if grade == "FAIL" else SCORE_START, dist)
	if token != _score_token or not is_instance_valid(_score_tile):
		return

	var points: int = ScoreManager.base_points(dist)
	# next_multiplier() has no FAIL branch (it returns the multiplier unchanged),
	# because register_result() handles that case by resetting to 1.0 outright -
	# so FAIL is stated here rather than derived.
	var after: float = 1.0 if grade == "FAIL" \
		else ScoreManager.next_multiplier(grade, DEMO_BASE_MULT)
	_score_tile.play_grade(grade, "%.2f" % dist, RESULT_HOLD_SEC * 2.0)
	if _score_readout != null:
		_score_readout.text = "stopped %.2f from zero\n%d points\nmultiplier  x%.1f  ->  x%.1f" \
			% [dist, points, DEMO_BASE_MULT, after]
		_score_readout.add_theme_color_override("font_color", color)

	await get_tree().create_timer(RESULT_HOLD_SEC * 2.0, true, false, true).timeout
	if token != _score_token or _score_tile == null or not is_instance_valid(_score_tile):
		return
	_score_tile.set_present(false)

# PERFECT reads as a tolerance rather than a span (its lower bound is a dead-on
# 0.00, which "0.00 to 0.05" makes look like a range you have to land inside
# rather than the target itself), and FAIL is genuinely open-ended above MISS_MAX.
func _range_text(grade: String) -> String:
	var span: Array = GRADE_RANGES[grade]
	match grade:
		"PERFECT":
			return "within %.2f of zero." % float(span[1])
		"FAIL":
			return "more than %.2f from zero." % float(span[0])
	return "%.2f to %.2f from zero." % [float(span[0]), float(span[1])]

# --- Shared builders ----------------------------------------------------------

func _make_tile(type: int, display_name: String) -> HelpDemoTile:
	var s := _timer_tile_size()
	var tile := HelpDemoTile.new()
	tile.custom_minimum_size = Vector2(s, s)
	tile.configure(type, display_name, roundi(s * TIMER_DIGIT_RATIO), roundi(s * TIMER_NAME_RATIO))
	tile.idle()
	return tile

func _make_desc_label(page: int, placeholder: String) -> Control:
	var label := Label.new()
	label.text = placeholder
	label.add_theme_font_size_override("font_size", _fs(DESC_FONT_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, DESC_HEIGHT * _s())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_by_page[page] = label
	return label

# Page 1's standing "these are tappable" line. Single-height, and never rewritten
# - the type descriptions it used to carry now land in the anchored caption next
# to the tile they belong to, which is what freed the height the dot row uses.
func _make_prompt_label(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _fs(DESC_FONT_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, PROMPT_HEIGHT * _s())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _set_desc(page: int, text: String, color: Color) -> void:
	if not _desc_by_page.has(page):
		return
	var label: Label = _desc_by_page[page]
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.18)

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 64) * _s()
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

# --- Paging + swipe -----------------------------------------------------------

func _size_page_area() -> void:
	if _page_area == null:
		return
	# The reserved height comes from the tallest page's own measured content
	# rather than a hand-tuned constant. The old fixed value overflowed twice
	# (each time a font bump wrapped a description onto another line) and painted
	# over the nav row below it, because a page's children are not clipped to an
	# undersized reservation - they just spill.
	#
	# No special handling for the bystander row any more: it holds its space
	# permanently, so what is measured here is what is on screen at all times.
	var tallest := 0.0
	for p in _pages:
		tallest = maxf(tallest, p.get_combined_minimum_size().y)
	_page_area.custom_minimum_size = Vector2(0, tallest)
	_layout_pages()

func _layout_pages() -> void:
	if _page_area == null or _track == null:
		return
	var w: float = _page_area.size.x
	var h: float = _page_area.size.y
	if w <= 0.0:
		return
	_track.size = Vector2(w * float(PAGE_COUNT), h)
	for i in range(_pages.size()):
		_pages[i].position = Vector2(w * float(i), 0)
		_pages[i].size = Vector2(w, h)
	_track.position.x = -w * float(_page_index)
	# A resize or orientation change moves every tile under it.
	_position_caption()

func _on_tab_pressed(index: int) -> void:
	if _swipe_active:
		return
	_show_page(index, true)

func _show_page(index: int, animate: bool) -> void:
	_page_index = clampi(index, 0, PAGE_COUNT - 1)
	_style_tabs()
	_style_dots()
	# The caption is parented to _page_area, not to the sliding track, so it
	# would hang over the incoming page instead of leaving with the tile it
	# belongs to.
	_hide_caption()
	if _page_area == null or _track == null:
		return
	var target: float = -_page_area.size.x * float(_page_index)
	if _track_tween != null and _track_tween.is_valid():
		_track_tween.kill()
	if not animate:
		_track.position.x = target
		return
	_track_tween = create_tween()
	_track_tween.tween_property(_track, "position:x", target, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Handled in _input (which runs ahead of any Control's _gui_input) so the drag
# is already classified as a swipe or not by the time a tile or button under
# the finger fires its own signal - those handlers check _swipe_active.
func _input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.HELP:
		return
	if _page_area == null or _page_area.size.x <= 0.0:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		_update_drag(event.position)

func _begin_drag(pos: Vector2) -> void:
	_drag_from = pos
	_dragging = true
	_swipe_active = false

func _update_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	var dx: float = pos.x - _drag_from.x
	if absf(dx) > SWIPE_TAP_SLOP:
		if not _swipe_active:
			# Dismissed the moment the gesture stops being a tap, rather than on
			# release: the caption does not slide with the track, so leaving it up
			# through the drag would have it sitting still over moving content.
			_hide_caption()
		_swipe_active = true
	if _swipe_active:
		if _track_tween != null and _track_tween.is_valid():
			_track_tween.kill()
		# Resistance past the first and last page, so the strip pushes back
		# rather than sliding into empty space.
		var base: float = -_page_area.size.x * float(_page_index)
		var at_edge := (_page_index == 0 and dx > 0.0) \
			or (_page_index == PAGE_COUNT - 1 and dx < 0.0)
		_track.position.x = base + (dx * 0.35 if at_edge else dx)

func _end_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	if not _swipe_active:
		# A plain tap, not a swipe - anywhere on the screen. This runs in
		# _input(), ahead of whatever Control is actually under the finger (a
		# tile/powerup button/grade chip's own _gui_input/pressed signal fires
		# after this), so a tap that lands on a NEW one still gets its own
		# handler immediately afterward and starts its own fresh demo the normal
		# way - this only covers what used to be entirely unhandled: a tap on
		# nothing interactive while some demo (or its leftover caption) is still
		# running, which previously did nothing at all.
		_cancel_all_demos()
		return
	var dx: float = pos.x - _drag_from.x
	var commit: float = _page_area.size.x * SWIPE_COMMIT_RATIO
	if dx <= -commit:
		_show_page(_page_index + 1, true)
	elif dx >= commit:
		_show_page(_page_index - 1, true)
	else:
		_show_page(_page_index, true)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses. Guarded
# on the current state because hidden screens stay in the tree and would
# otherwise all answer the same press - see LevelSelect for the full note.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.HELP:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)



