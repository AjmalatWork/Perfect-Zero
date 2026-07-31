extends Control
class_name ScoresScreen

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const MUTED := Color("8b90a8")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")

# Matches _row()'s own total width (300 + 150 + 150 + 2x24 separation) so the
# rule sits flush with the table it's ruling off, rather than an arbitrary
# independent width.
const DIVIDER_WIDTH := 648.0
const DIVIDER_ALPHA := 0.4

@export var campaign: Campaign

var _col: VBoxContainer


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact.
#
# Capped by the table row, which is the widest thing here: 300 + 150 + 150 cells
# plus two separations = 648. With the side margins no longer scaling up (see
# _side_margin) there are 820 units to spend.
#
# This was 1.25 when the base cell font was 20pt, landing the row at 810 - the
# base is now 24pt (readability pass, confirmed with the user 2026-07-31), so the
# scale is cut in the same proportion (20/24) rather than compounding both
# increases into an overflow.
const PORTRAIT_SCALE := 1.04

# Shrinks in portrait rather than growing with the type scale. At _fs(80) these
# ate 208 units of a 900-wide canvas, which pushed the table's third column
# ("Perfect") clean off the right edge.
func _side_margin() -> int:
	return 40 if Layout.is_portrait() else 80

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel),
# confirmed with the user 2026-07-31 - this used to be its own smaller size and
# read inconsistent against screens reached from the same title-screen row.
const PAGE_HEADING_SIZE := 56

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
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_col)

func _populate() -> void:
	for child in _col.get_children():
		child.queue_free()

	var title := WaveHeading.new()
	_col.add_child(title)
	title.configure("HIGH SCORES", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NEON)

	if campaign != null:
		_col.add_child(_build_stage_list(campaign.stages))

	# Rules off the Campaign table from the Endless summary below it - two
	# distinct sections that used to run together with nothing but a bare gap
	# between them.
	_col.add_child(_spacer(3))
	_col.add_child(_make_divider())
	_col.add_child(_spacer(6))

	var en: int = SaveManager.load_high_score("highscore_endless_normal")
	var eh: int = SaveManager.load_high_score("highscore_endless_hardcore")
	_col.add_child(_row("Endless Normal", str(en) if en > 0 else "-", "?????", false))
	_col.add_child(_row("Endless Hardcore", str(eh) if eh > 0 else "-", "?????", false))

	_col.add_child(_spacer(10))
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

# --- builders -------------------------------------------------------------

# Single column again (was briefly split into two side-by-side halves, which
# the user didn't like the look of). Fits 12 stages under the 900px canvas by
# tightening what actually bloats a list like this - its OWN row spacing and
# font size - rather than by fighting the height with a second column. The
# list gets its own separation (STAGE_ROW_GAP) distinct from _col's, since _col's
# 10px gap is sized for spacing between whole sections, not between individual
# rows within one.
const STAGE_ROW_GAP := 2

func _build_stage_list(stages: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", STAGE_ROW_GAP)
	col.add_child(_row("Stage", "Best", "Perfect", true))
	# Rules off the header from the 12 data rows beneath it - previously
	# nothing distinguished "Stage / Best / Perfect" from an ordinary row
	# except its gold text colour.
	col.add_child(_make_divider())
	for i in range(stages.size()):
		var stage: StageData = stages[i]
		var best: int = SaveManager.load_high_score("highscore_stage_%d" % i)
		var best_text: String = str(best) if best > 0 else "-"
		var target_text: String = str(stage.target_score) if stage.target_score > 0 else "-"
		col.add_child(_row(stage.stage_name, best_text, target_text, false))
	return col

# Narrower and smaller-type than the original single-column version (which was
# 440/200/200 at 26pt/22pt) - that combination is what overflowed once Stage 12
# arrived. Still centers as one table via the row's own ALIGNMENT_CENTER.
func _row(a: String, b: String, c: String, header: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(24))
	row.add_child(_cell(a, 300, HORIZONTAL_ALIGNMENT_LEFT, header))
	row.add_child(_cell(b, 150, HORIZONTAL_ALIGNMENT_RIGHT, header))
	row.add_child(_cell(c, 150, HORIZONTAL_ALIGNMENT_RIGHT, header))
	return row

func _cell(text: String, width: int, align: int, header: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(24))
	l.add_theme_color_override("font_color", GOLD if header else TEXT_FILL)
	l.custom_minimum_size = Vector2(width * _s(), 0)
	l.horizontal_alignment = align
	return l

func _heading(text: String, font_size: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# A fading hairline (bright at centre, transparent at both ends) rather than
# an edge-to-edge rule - same idiom StageResultScreen/EndlessEndScreen use, so
# a "rule off this section" reads as one convention across the app.
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
	rect.custom_minimum_size = Vector2(DIVIDER_WIDTH, 2.0) * _s()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(MUTED.r, MUTED.g, MUTED.b, DIVIDER_ALPHA)
	return rect

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h * _s())
	return c

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

