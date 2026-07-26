extends Control
class_name PowerupIcon

# One powerup glyph, drawn live rather than loaded as a rasterized SVG texture.
# A baked bitmap goes soft under this project's canvas_items stretch scaling the
# 1600x900 canvas to the real window size; a primitive redrawn each frame can't.
# Same reasoning as the drawn pause icon, the life-crosses, and NeonCheckBox.
#
# Shared by the powerup buttons, the Help screen legend and the first-run
# tutorial, so the three can't drift apart the way separate copies would.
#
# All geometry below is normalized to a -1..1 box and scaled to whatever size
# the node is given, so one definition serves every call site's icon size.

const SHIELD_POLY := [
	Vector2(0, -0.844), Vector2(0.719, -0.563), Vector2(0.719, 0.063),
	Vector2(0, 0.844), Vector2(-0.719, 0.063), Vector2(-0.719, -0.563),
]
const SHIELD_CHECK := [
	Vector2(-0.34, -0.03), Vector2(-0.09, 0.22), Vector2(0.38, -0.28),
]

const CLEAR_RING_RADIUS := 0.344
const CLEAR_RAY_INNER := 0.531
const CLEAR_RAY_OUTER := 0.875
const CLEAR_CORNER_OFFSET := 0.625
const CLEAR_CORNER_HALF := 0.094

const BOLT_POLY := [
	Vector2(0.219, -0.875), Vector2(-0.375, 0.063), Vector2(-0.031, 0.063),
	Vector2(-0.156, 0.875), Vector2(0.5, -0.125), Vector2(0.125, -0.125),
]
const SPEED_LINES := [
	[Vector2(-0.813, -0.4375), Vector2(-0.375, -0.4375)],
	[Vector2(-0.875, 0.0), Vector2(-0.5, 0.0)],
	[Vector2(-0.813, 0.4375), Vector2(-0.375, 0.4375)],
]

# Stroke widths are authored against this icon radius and scale from it, so a
# small icon gets proportionally thinner strokes instead of a clogged blob.
const REFERENCE_RADIUS := 27.0

var kind: int = 0
var icon_alpha: float = 1.0:
	set(v):
		icon_alpha = v
		queue_redraw()

func _init(p_kind: int = 0) -> void:
	kind = p_kind

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _radius() -> float:
	return minf(size.x, size.y) * 0.5

func _p(p: Vector2) -> Vector2:
	return size * 0.5 + p * _radius()

func _w(width: float) -> float:
	return maxf(width * (_radius() / REFERENCE_RADIUS), 1.0)

func _draw() -> void:
	match kind:
		PowerupSystem.Kind.SHIELD:
			_draw_shield()
		PowerupSystem.Kind.CLEAR_ALL:
			_draw_clear_all()
		PowerupSystem.Kind.OVERCLOCK:
			_draw_overclock()

# A soft wide copy underneath the crisp stroke - the same "translucent halo
# behind a solid core" trick NeonSlider's knob uses for its glow.
func _glow_poly(points: PackedVector2Array, color: Color, width: float) -> void:
	var w := _w(width)
	draw_polyline(points, Color(color.r, color.g, color.b, color.a * 0.35 * icon_alpha), w * 2.5, true)
	draw_polyline(points, Color(color.r, color.g, color.b, color.a * icon_alpha), w, true)

func _draw_shield() -> void:
	var accent := PowerupSystem.color_of(PowerupSystem.Kind.SHIELD)
	var pts := PackedVector2Array()
	for n in SHIELD_POLY:
		pts.append(_p(n))
	pts.append(pts[0])

	draw_colored_polygon(pts, Color(accent.r, accent.g, accent.b, 0.14 * icon_alpha))
	_glow_poly(pts, accent, 4.0)

	var check := PackedVector2Array()
	for n in SHIELD_CHECK:
		check.append(_p(n))
	_glow_poly(check, Color.WHITE, 4.5)

func _draw_clear_all() -> void:
	var gold := PowerupSystem.color_of(PowerupSystem.Kind.CLEAR_ALL)
	# Fading corner cells - the board being cashed in.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := _p(Vector2(sx * CLEAR_CORNER_OFFSET, sy * CLEAR_CORNER_OFFSET))
			var half := CLEAR_CORNER_HALF * _radius()
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0),
				Color(gold.r, gold.g, gold.b, 0.28 * icon_alpha), true)

	# Eight burst rays: one vector rotated, rather than eight placed by hand.
	for i in range(8):
		var ang := deg_to_rad(i * 45.0)
		_glow_poly(PackedVector2Array([
			_p(Vector2(0, -CLEAR_RAY_INNER).rotated(ang)),
			_p(Vector2(0, -CLEAR_RAY_OUTER).rotated(ang)),
		]), gold, 4.0)

	var ring := _ring_points(CLEAR_RING_RADIUS)
	draw_colored_polygon(ring, Color(gold.r, gold.g, gold.b, 0.22 * icon_alpha))
	_glow_poly(ring + PackedVector2Array([ring[0]]), Color.WHITE, 4.0)

func _draw_overclock() -> void:
	var red := PowerupSystem.color_of(PowerupSystem.Kind.OVERCLOCK)
	for line in SPEED_LINES:
		_glow_poly(PackedVector2Array([_p(line[0]), _p(line[1])]),
			Color(red.r, red.g, red.b, 0.45), 3.5)

	var pts := PackedVector2Array()
	for n in BOLT_POLY:
		pts.append(_p(n))
	pts.append(pts[0])
	draw_colored_polygon(pts, Color(red.r, red.g, red.b, 0.18 * icon_alpha))
	_glow_poly(pts, red, 4.0)

func _ring_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(24):
		var ang := i * TAU / 24.0
		pts.append(_p(Vector2(cos(ang), sin(ang)) * radius))
	return pts
