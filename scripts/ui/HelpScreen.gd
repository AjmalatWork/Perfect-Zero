extends Control
class_name HelpScreen

const NEON := Color("22d3ff")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")

# TIMER TYPES / POWERUPS / SCORING all share this one size and colour (NEON) -
# three section headings that used to be three different sizes (32/42/36) and
# two different colours (GREEN/NEON/GOLD) with no meaning behind the
# variation.
const SECTION_HEADING_SIZE := 36

const PAGE_COUNT := 3

# Measured content: page 1 needs 701 in landscape, 870 in portrait (see the
# page_area comment in _build). Both carry a margin above the measured figure.
const PAGE_AREA_HEIGHT_LANDSCAPE := 640.0
const PAGE_AREA_HEIGHT_PORTRAIT := 900.0

var _pages: Array[Control] = []
var _page_nav: PageNav


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact. Chosen from the measured content: content measures 484 wide; 1.5 puts it at 726 of 900.
const PORTRAIT_SCALE := 1.5

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel),
# confirmed with the user 2026-07-31 - this used to be its own smaller size and
# read inconsistent against screens reached from the same title-screen row.
const PAGE_HEADING_SIZE := 56

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

# Side margins shrink in portrait instead of growing with the type scale: at
# _fs(80) they ate 240 of a 900-unit canvas, leaving less room for the widest
# row than landscape had at a third of the relative cost.
func _side_margin() -> int:
	return 40 if Layout.is_portrait() else 80

# The description column is the widest thing on this screen. Landscape has 1440
# units of content width and this comfortably takes 600 of it; portrait has 820,
# so it is sized to what is actually left beside the name column rather than
# being scaled up with the type - autowrap turns the narrower column into more
# lines instead of running off the canvas.
const DESC_WIDTH_LANDSCAPE := 760.0
const DESC_WIDTH_PORTRAIT := 510.0

func _desc_width() -> float:
	return DESC_WIDTH_PORTRAIT if Layout.is_portrait() else DESC_WIDTH_LANDSCAPE

func _fs(base: int) -> int:
	return roundi(base * _s())

var _backdrop: ColorRect
var _margin: MarginContainer
var _built_portrait: bool = false

func _ready() -> void:
	_build()
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()


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
	# _build() appends to _pages every time it runs - without clearing it first,
	# a rebuild leaves the array holding the just-freed old pages ahead of the
	# new ones. _on_page_changed() then sets .visible on those freed references
	# (a silent no-op) instead of the new pages actually in the tree, which is
	# what left the whole page blank after switching orientation on-device.
	_pages.clear()
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
	margin.add_theme_constant_override("margin_top", _fs(24))
	margin.add_theme_constant_override("margin_bottom", _fs(24))
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", _fs(14))
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(outer)

	# Every page occupies the same reserved area (stacked, all but one hidden) so
	# the layout doesn't jump when switching pages. Sized to the tallest page's
	# actual content (page 1's 6-row type table) plus a little slack - a page's
	# own children aren't clipped to this rect, so an under-sized reservation
	# doesn't just get cropped, it visibly paints over the nav/back rows below it
	# (exactly what the Decay row's longer description exposed, twice now: once
	# at the original 21pt body size, and again when that was bumped to 24pt for
	# readability - a bigger font wraps that row to a third line, which needs
	# more height than 21pt's two lines did). Measured directly per orientation
	# rather than scaled by one factor, since landscape and portrait no longer
	# need the same amount of slack once the description column's width differs
	# between them (_desc_width()).
	var page_area := Control.new()
	page_area.custom_minimum_size = Vector2(0,
		PAGE_AREA_HEIGHT_PORTRAIT if Layout.is_portrait() else PAGE_AREA_HEIGHT_LANDSCAPE)
	page_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(page_area)

	_pages.append(_build_page_1())
	_pages.append(_build_page_2())
	_pages.append(_build_page_3())
	for p in _pages:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		page_area.add_child(p)

	# Page 1's type table runs close to the bottom of page_area's reserved
	# height, so the nav row ends up crowding it. A fixed spacer (rather than
	# just widening outer's separation) keeps that gap without also pushing
	# the back button further from the nav row than it needs to be.
	var nav_spacer := Control.new()
	nav_spacer.custom_minimum_size = Vector2(0, 18) * _s()
	outer.add_child(nav_spacer)

	_page_nav = PageNav.new()
	_page_nav.page_changed.connect(_on_page_changed)
	outer.add_child(_page_nav)
	_page_nav.configure(PAGE_COUNT)

	var back := _button("BACK", BACK_ACCENT)
	back.pressed.connect(_on_back)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	outer.add_child(back_wrap)

# --- Page 1: how to play + timer types -------------------------------------

func _build_page_1() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(18))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("HOW TO PLAY", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NEON)

	col.add_child(_line("Click a timer the instant it hits 0.00.", 24, TEXT_FILL))
	col.add_child(_heading("TIMER TYPES", SECTION_HEADING_SIZE, NEON))

	var types_grid := GridContainer.new()
	types_grid.columns = 2
	types_grid.add_theme_constant_override("h_separation", _fs(28))
	types_grid.add_theme_constant_override("v_separation", _fs(12))
	var types_wrap := CenterContainer.new()
	types_wrap.add_child(types_grid)
	col.add_child(types_wrap)
	for t in TimerTypeInfo.ORDER:
		_add_type_row(types_grid, t)

	return col

# --- Page 2: Endless powerups ------------------------------------------------

func _build_page_2() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(18))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_heading("POWERUPS", SECTION_HEADING_SIZE, NEON))
	col.add_child(_line("Endless mode only. They recharge as you play.",
		24, TEXT_FILL))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", _fs(20))
	grid.add_theme_constant_override("v_separation", _fs(18))
	var wrap := CenterContainer.new()
	wrap.add_child(grid)
	col.add_child(wrap)
	for kind in PowerupSystem.ORDER:
		_add_powerup_row(grid, kind)

	return col

func _add_powerup_row(grid: GridContainer, kind: int) -> void:
	var accent: Color = PowerupSystem.color_of(kind)

	# Same drawn glyph the in-game buttons use, so the legend and the board
	# can't drift apart.
	var icon := PowerupIcon.new(kind)
	icon.custom_minimum_size = Vector2(46, 46) * _s()
	icon.size = Vector2(46, 46) * _s()
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(icon)
	grid.add_child(icon_wrap)

	var name_cell := VBoxContainer.new()
	name_cell.add_theme_constant_override("separation", _fs(0))
	name_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# No keybind hint to append on mobile (PowerupSystem.key_hint() returns ""
	# there, since there's no keyboard) - falls back to the bare name rather
	# than leaving a dangling "Shield  ".
	var hint := PowerupSystem.key_hint(kind)
	var name_text := "%s  %s" % [PowerupSystem.name_of(kind), hint] if not hint.is_empty() \
		else PowerupSystem.name_of(kind)
	name_cell.add_child(_cell_label(name_text, 24, accent))
	name_cell.add_child(_cell_label(Powerups.cooldown_text(kind), 20, Color(1, 1, 1, 0.5)))
	grid.add_child(name_cell)

	grid.add_child(_wrap_cell_label(Powerups.describe(kind), 24, TEXT_FILL))

# --- Page 3: scoring ---------------------------------------------------------

func _build_page_3() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(20))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_heading("SCORING", SECTION_HEADING_SIZE, NEON))
	col.add_child(_line(
		"Points scale with how close to 0.00 you stop - closer scores more.",
		24, TEXT_FILL))

	var scoring_grid := GridContainer.new()
	scoring_grid.columns = 3
	scoring_grid.add_theme_constant_override("h_separation", _fs(40))
	scoring_grid.add_theme_constant_override("v_separation", _fs(16))
	var scoring_wrap := CenterContainer.new()
	scoring_wrap.add_child(scoring_grid)
	col.add_child(scoring_wrap)
	_add_grade_row(scoring_grid, "PERFECT", "<= 0.05", "multiplier +1.0", GRADE_COLOR("PERFECT"))
	_add_grade_row(scoring_grid, "GOOD", "<= 0.30", "multiplier +0.5", GRADE_COLOR("GOOD"))
	_add_grade_row(scoring_grid, "OKAY", "<= 0.50", "multiplier unchanged", GRADE_COLOR("OKAY"))
	_add_grade_row(scoring_grid, "MISS", "<= 1.00", "halves multiplier (min 1x)", GRADE_COLOR("MISS"))
	_add_grade_row(scoring_grid, "FAIL", "> 1.00", "resets multiplier, ends the stage", GRADE_COLOR("FAIL"))

	return col

# --- Page navigation ---------------------------------------------------------

func _on_page_changed(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index

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

# --- content builders -----------------------------------------------------

func GRADE_COLOR(grade: String) -> Color:
	return ScoreManager.grade_color(grade)

func _heading(text: String, font_size: int, color: Color) -> Label:
	var l := _line(text, font_size, TEXT_FILL)
	l.add_theme_color_override("font_outline_color", color)
	l.add_theme_constant_override("outline_size", 5)
	return l

func _line(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _add_grade_row(grid: GridContainer, grade: String, window: String, effect: String, color: Color) -> void:
	grid.add_child(_cell_label(grade, 24, color))
	grid.add_child(_cell_label(window, 24, TEXT_FILL))
	grid.add_child(_cell_label(effect, 24, TEXT_FILL))

func _add_type_row(grid: GridContainer, t: int) -> void:
	var name_cell := HBoxContainer.new()
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_cell.add_theme_constant_override("separation", _fs(12))

	var swatch := ColorRect.new()
	swatch.color = TimerTypeInfo.color_of(t)
	swatch.custom_minimum_size = Vector2(22, 22) * _s()
	# Without this, the swatch (a plain Control that fills by default) stretches
	# to match the row's height - and rows vary in height because the
	# description column wraps to 1 or 2 lines, so swatches ended up different
	# sizes depending on how long that type's description happens to be.
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(swatch)
	name_cell.add_child(_cell_label(TimerTypeInfo.name_of(t), 24, TimerTypeInfo.color_of(t)))
	grid.add_child(name_cell)

	grid.add_child(_wrap_cell_label(TimerTypeInfo.desc_of(t), 24, TEXT_FILL))

# Plain cell: hugs its own text, no forced minimum width. Used wherever text is
# short and fixed (grade names, distance windows, effect text) - giving every
# cell a wide forced minimum was what made the scoring grid's columns spread
# out across most of the screen despite none of that text needing the room.
func _cell_label(text: String, font_size: int, color: Color) -> Label:
	var l := _line(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

# Wrapping cell: reserves width and wraps - only for the timer-type
# descriptions, which are full sentences that genuinely need it. Widened from
# 540 so the longest description (Decay's) wraps to 2 lines instead of 3 -
# there's ample room either way (types_wrap centers within a 1440px-wide
# margin, and the name column is nowhere near using the rest of it).
func _wrap_cell_label(text: String, font_size: int, color: Color) -> Label:
	var l := _cell_label(text, font_size, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_desc_width(), 0)
	return l

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


