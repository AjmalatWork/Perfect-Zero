extends Control
class_name EndlessModeSelect

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")

@export var runner: EndlessRunner

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameManager.state_changed.connect(_on_state_changed)

# The powerup primer fires the first time Endless is opened - here rather than
# at run start so the player reads it before committing to a mode, and can still
# see the board unobstructed once the run actually begins.
func _on_state_changed(new_state: int) -> void:
	if new_state != GameManager.GameState.ENDLESS_MODE_SELECT:
		return
	if PowerupTutorial.is_new():
		PowerupTutorial.show_popup(self)

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
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("ENDLESS", 72, TEXT_FILL, NEON)

	col.add_child(_heading("Choose your mode", 26, TEXT_FILL, 0))

	var normal := _button("NORMAL   -   3 lives", NEON)
	normal.pressed.connect(func(): _start(3))
	col.add_child(_wrap(normal))

	var hardcore := _button("HARDCORE   -   1 life", RED)
	hardcore.pressed.connect(func(): _start(1))
	col.add_child(_wrap(hardcore))

	var back := _button("BACK", GOLD)
	back.pressed.connect(func(): GameManager.set_state(GameManager.GameState.MENU))
	col.add_child(_wrap(back))

func _start(lives: int) -> void:
	runner.start_run(lives)

func _wrap(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _heading(text: String, font_size: int, accent: Color, outline: int = 5) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", accent)
		l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 76)
	button.add_theme_font_size_override("font_size", 30)
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
