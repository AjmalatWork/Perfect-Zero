extends Control
class_name ScoresScreen

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")
const VIEWPORT_SIZE := Vector2(1600, 900)

@export var campaign: Campaign

var _col: VBoxContainer

func _ready() -> void:
	_build_shell()
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int) -> void:
	# Rebuild each time the screen is shown so freshly-set bests appear.
	if new_state == GameManager.GameState.SCORES:
		_populate()

func _build_shell() -> void:
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
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_col)

func _populate() -> void:
	for child in _col.get_children():
		child.queue_free()

	var title := WaveHeading.new()
	_col.add_child(title)
	title.configure("HIGH SCORES", 40, TEXT_FILL, NEON)

	if campaign != null:
		_col.add_child(_build_stage_list(campaign.stages))

	_col.add_child(_spacer(12))

	var en: int = SaveManager.load_high_score("highscore_endless_normal")
	var eh: int = SaveManager.load_high_score("highscore_endless_hardcore")
	_col.add_child(_row("Endless Normal", str(en) if en > 0 else "—", "?????", false))
	_col.add_child(_row("Endless Hardcore", str(eh) if eh > 0 else "—", "?????", false))

	_col.add_child(_spacer(16))
	var back := _button("BACK", NEON)
	back.pressed.connect(_on_back)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	_col.add_child(back_wrap)

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
const STAGE_ROW_GAP := 5

func _build_stage_list(stages: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", STAGE_ROW_GAP)
	col.add_child(_row("Stage", "Best", "Perfect", true))
	for i in range(stages.size()):
		var stage: StageData = stages[i]
		var best: int = SaveManager.load_high_score("highscore_stage_%d" % i)
		var best_text: String = str(best) if best > 0 else "—"
		var target_text: String = str(stage.target_score) if stage.target_score > 0 else "—"
		col.add_child(_row(stage.stage_name, best_text, target_text, false))
	return col

# Narrower and smaller-type than the original single-column version (which was
# 440/200/200 at 26pt/22pt) - that combination is what overflowed once Stage 12
# arrived. Still centers as one table via the row's own ALIGNMENT_CENTER.
func _row(a: String, b: String, c: String, header: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.add_child(_cell(a, 300, HORIZONTAL_ALIGNMENT_LEFT, header))
	row.add_child(_cell(b, 150, HORIZONTAL_ALIGNMENT_RIGHT, header))
	row.add_child(_cell(c, 150, HORIZONTAL_ALIGNMENT_RIGHT, header))
	return row

func _cell(text: String, width: int, align: int, header: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", GOLD if header else TEXT_FILL)
	l.custom_minimum_size = Vector2(width, 0)
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

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

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
