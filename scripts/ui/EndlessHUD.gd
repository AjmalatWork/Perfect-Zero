extends Control
class_name EndlessHUD

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const FAIL_RED := Color("ff2e5e")
const TEXT_FILL := Color("dfe3ee")

# Combo meter. The live segment (tally x multiplier) grows super-linearly, so
# the bar uses a square-root curve to stay legible instead of pinning early.
const METER_WIDTH := 420.0
const METER_HEIGHT := 12.0
const METER_FULL := 20000.0     # segment value that fills the bar completely
const METER_FILL_SPEED := 900.0 # px/sec the fill chases its target

var _equation: Label
var _total: Label
var _streak_popup: Label
var _streak_tween: Tween
var _crosses_row: HBoxContainer
var _cross_labels: Array = []
var _last_mult: float = 1.0
var _last_streak: int = 0
var _meter_track: ColorRect
var _meter_fill: ColorRect
var _meter_target: float = 0.0

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

	ScoreManager.tally_changed.connect(_on_tally_changed)
	ScoreManager.campaign_total_changed.connect(_on_total_changed)
	ScoreManager.perfect_streak_changed.connect(_on_streak_changed)
	_on_tally_changed(ScoreManager.stage_tally, ScoreManager.multiplier)
	_on_total_changed(ScoreManager.campaign_total)

func _build() -> void:
	_equation = _make_label(56, NEON)
	_equation.position = Vector2(0, 14)
	_equation.size = Vector2(VIEWPORT_SIZE.x, 72)
	add_child(_equation)

	_total = _make_label(26, GOLD.darkened(0.15))
	_total.position = Vector2(0, 90)
	_total.size = Vector2(VIEWPORT_SIZE.x, 34)
	add_child(_total)

	# Combo meter - the live-scoring vessel the numeric HUD lacks.
	_meter_track = ColorRect.new()
	_meter_track.position = Vector2((VIEWPORT_SIZE.x - METER_WIDTH) * 0.5, 126)
	_meter_track.size = Vector2(METER_WIDTH, METER_HEIGHT)
	_meter_track.color = Color(1, 1, 1, 0.10)
	_meter_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter_track)

	_meter_fill = ColorRect.new()
	_meter_fill.position = Vector2.ZERO
	_meter_fill.size = Vector2(0, METER_HEIGHT)
	_meter_fill.color = NEON
	_meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_track.add_child(_meter_fill)

	_streak_popup = _make_label(38, GOLD)
	_streak_popup.position = Vector2(0, 140)
	_streak_popup.size = Vector2(VIEWPORT_SIZE.x, 46)
	_streak_popup.modulate.a = 0.0
	add_child(_streak_popup)

	# Fail crosses, bottom-center.
	var bottom := Control.new()
	bottom.position = Vector2(0, VIEWPORT_SIZE.y - 60)
	bottom.size = Vector2(VIEWPORT_SIZE.x, 50)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = Vector2(VIEWPORT_SIZE.x, 50)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(center)

	_crosses_row = HBoxContainer.new()
	_crosses_row.add_theme_constant_override("separation", 16)
	center.add_child(_crosses_row)

func _on_tally_changed(tally: int, mult: float) -> void:
	_equation.text = "%d   ×   %.1f" % [tally, mult]
	if mult > _last_mult:
		_pop(_equation)
	_last_mult = mult
	# resolve_stage() zeroes the segment on a fail, so the bar drains on its own.
	_meter_target = clampf(sqrt(float(tally) * mult / METER_FULL), 0.0, 1.0)

func _on_total_changed(total: int) -> void:
	_total.text = "TOTAL   %d" % total
	_flash_meter()

# The only thing that banks a segment in Endless is a fail, so the bank flash
# doubles as the "you lost the combo" read.
func _flash_meter() -> void:
	if _meter_track == null:
		return
	_meter_track.color = Color(FAIL_RED.r, FAIL_RED.g, FAIL_RED.b, 0.55)
	var tween := create_tween()
	tween.tween_property(_meter_track, "color", Color(1, 1, 1, 0.10), 0.45)

func _process(delta: float) -> void:
	if _meter_fill == null or _meter_track == null:
		return
	var target_w := _meter_track.size.x * _meter_target
	_meter_fill.size.x = move_toward(_meter_fill.size.x, target_w, delta * METER_FILL_SPEED)
	# Cool cyan through gold to hot red as the segment climbs.
	var t := _meter_target
	if t < 0.5:
		_meter_fill.color = NEON.lerp(GOLD, t * 2.0)
	else:
		_meter_fill.color = GOLD.lerp(FAIL_RED, (t - 0.5) * 2.0)

func _on_streak_changed(count: int) -> void:
	# Celebrate a growing streak (2+); don't announce it breaking.
	if count > _last_streak and count >= 2:
		_show_streak_popup(count)
	_last_streak = count

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

# Drawn as two diagonal Line2Ds rather than a "✕" text glyph - some exported
# builds' bundled font (notably HTML5/Web) lacks that Unicode character and
# shows tofu boxes.
func _build_cross_icon(color: Color) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(40, 40)
	for points in [[Vector2(8, 8), Vector2(32, 32)], [Vector2(32, 8), Vector2(8, 32)]]:
		var line := Line2D.new()
		line.width = 6
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
