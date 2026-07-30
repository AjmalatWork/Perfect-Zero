extends Control
class_name HelpScreen

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const GREEN := Color("39ff9e")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")
const VIEWPORT_SIZE := Vector2(1600, 900)

const PAGE_COUNT := 3

var _pages: Array[Control] = []
var _page_nav: PageNav

func _ready() -> void:
	_build()

func _build() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEWPORT_SIZE
	backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.position = Vector2.ZERO
	margin.size = VIEWPORT_SIZE
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(outer)

	# Every page occupies the same reserved area (stacked, all but one hidden) so
	# the layout doesn't jump when switching pages. Sized to the tallest page's
	# actual content (page 1's 6-row type table) plus a little slack - NOT a
	# round number, so it doesn't overflow the 900px viewport once the
	# heading/nav/back rows around it are accounted for.
	var page_area := Control.new()
	page_area.custom_minimum_size = Vector2(0, 560)
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
	nav_spacer.custom_minimum_size = Vector2(0, 18)
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
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("HOW TO PLAY", 42, TEXT_FILL, NEON)

	col.add_child(_line("Click a timer the instant it hits 0.00.", 24, TEXT_FILL))
	col.add_child(_heading("Timer types", 32, GREEN))

	var types_grid := GridContainer.new()
	types_grid.columns = 2
	types_grid.add_theme_constant_override("h_separation", 28)
	types_grid.add_theme_constant_override("v_separation", 12)
	var types_wrap := CenterContainer.new()
	types_wrap.add_child(types_grid)
	col.add_child(types_wrap)
	for t in TimerTypeInfo.ORDER:
		_add_type_row(types_grid, t)

	return col

# --- Page 2: Endless powerups ------------------------------------------------

func _build_page_2() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_heading("POWERUPS", 42, NEON))
	col.add_child(_line("Endless mode only. They start on cooldown and recharge as you play.",
		22, TEXT_FILL))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 18)
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
	icon.custom_minimum_size = Vector2(46, 46)
	icon.size = Vector2(46, 46)
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(icon)
	grid.add_child(icon_wrap)

	var name_cell := VBoxContainer.new()
	name_cell.add_theme_constant_override("separation", 0)
	name_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(_cell_label(
		"%s  [%s]" % [PowerupSystem.name_of(kind), PowerupSystem.key_of(kind)], 24, accent))
	name_cell.add_child(_cell_label(Powerups.cooldown_text(kind), 18, Color(1, 1, 1, 0.5)))
	grid.add_child(name_cell)

	grid.add_child(_wrap_cell_label(Powerups.describe(kind), 21, TEXT_FILL))

# --- Page 3: scoring ---------------------------------------------------------

func _build_page_3() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_heading("Scoring", 36, GOLD))
	col.add_child(_line(
		"Points scale with how close to 0.00 you stop - closer scores more.",
		22, TEXT_FILL))

	var scoring_grid := GridContainer.new()
	scoring_grid.columns = 3
	scoring_grid.add_theme_constant_override("h_separation", 40)
	scoring_grid.add_theme_constant_override("v_separation", 16)
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
	grid.add_child(_cell_label(window, 22, TEXT_FILL))
	grid.add_child(_cell_label(effect, 22, TEXT_FILL))

func _add_type_row(grid: GridContainer, t: int) -> void:
	var name_cell := HBoxContainer.new()
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_cell.add_theme_constant_override("separation", 12)

	var swatch := ColorRect.new()
	swatch.color = TimerTypeInfo.color_of(t)
	swatch.custom_minimum_size = Vector2(22, 22)
	# Without this, the swatch (a plain Control that fills by default) stretches
	# to match the row's height - and rows vary in height because the
	# description column wraps to 1 or 2 lines, so swatches ended up different
	# sizes depending on how long that type's description happens to be.
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(swatch)
	name_cell.add_child(_cell_label(TimerTypeInfo.name_of(t), 24, TimerTypeInfo.color_of(t)))
	grid.add_child(name_cell)

	grid.add_child(_wrap_cell_label(TimerTypeInfo.desc_of(t), 21, TEXT_FILL))

# Plain cell: hugs its own text, no forced minimum width. Used wherever text is
# short and fixed (grade names, distance windows, effect text) - giving every
# cell a wide forced minimum was what made the scoring grid's columns spread
# out across most of the screen despite none of that text needing the room.
func _cell_label(text: String, font_size: int, color: Color) -> Label:
	var l := _line(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

# Wrapping cell: reserves width and wraps - only for the timer-type
# descriptions, which are full sentences that genuinely need it.
func _wrap_cell_label(text: String, font_size: int, color: Color) -> Label:
	var l := _cell_label(text, font_size, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 64)
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
	sb.set_content_margin_all(10)
	return sb
