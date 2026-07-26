extends Control
class_name EndlessEndScreen

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const GREEN := Color("39ff9e")
const FAIL_RED := Color("ff2e5e")
const TEXT_FILL := Color("dfe3ee")

@export var runner: EndlessRunner

var _final_label: Label
var _best_label: Label
var _newbest_label: Label
var _retry_button: Button
var _back_button: Button
var _transitioning: bool = false

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.ENDLESS_END:
		_refresh()

func _refresh() -> void:
	if runner == null:
		return
	_final_label.text = "Final score:  %d" % runner.final_score
	_best_label.text = "Best (%s):  %d" % [_mode_name(), runner.best_score]
	_newbest_label.visible = runner.is_new_best

func _mode_name() -> String:
	return "Hardcore" if runner.max_lives <= 1 else "Normal"

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
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_label("RUN OVER", 64, FAIL_RED))

	_newbest_label = _label("* NEW BEST! *", 34, GREEN)
	_newbest_label.visible = false
	col.add_child(_newbest_label)

	_final_label = _label("Final score:  0", 40, NEON)
	col.add_child(_final_label)

	_best_label = _label("Best:  0", 28, GOLD.darkened(0.15))
	col.add_child(_best_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	_retry_button = _button("RETRY", NEON)
	_retry_button.pressed.connect(_on_retry)
	row.add_child(_retry_button)

	_back_button = _button("BACK TO TITLE", GOLD)
	_back_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.MENU))
	row.add_child(_back_button)

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
	_retry_button.disabled = false
	_back_button.disabled = false

func _label(text: String, font_size: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 76)
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
	sb.set_content_margin_all(12)
	return sb
