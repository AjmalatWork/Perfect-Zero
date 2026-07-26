extends Node2D
class_name RadialBurst

# Expanding ring drawn in _draw(), used for click-point feedback and for
# Red/Blue reaction ripples. Procedural rather than a textured sprite so it
# satisfies the project's no-external-assets constraint.
#
# Frees itself once the animation completes.

var _color: Color = Color.WHITE
var _max_radius: float = 64.0
var _duration: float = 0.3
var _width: float = 4.0
var _double: bool = false
var _inward: bool = false
var _t: float = 0.0

func configure(color: Color, max_radius: float, duration: float, width: float,
		double_ring: bool = false, inward: bool = false) -> void:
	_color = color
	_max_radius = max_radius
	_duration = maxf(duration, 0.01)
	_width = width
	_double = double_ring
	_inward = inward
	z_index = 30  # above grade signs (20), below the pause overlay (100)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta / _duration
	if _t >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var eased: float
	var alpha: float
	if _inward:
		# Collapsing ring for powerup wind-ups: accelerates inward and brightens
		# as it closes, so it reads as energy gathering rather than dissipating -
		# the opposite arc to the outward burst below in both senses.
		eased = 1.0 - pow(_t, 3.0)
		alpha = _t * _color.a
	else:
		eased = 1.0 - pow(1.0 - _t, 3.0)  # quick expansion, slow settle
		alpha = (1.0 - _t) * _color.a
	var ring := Color(_color.r, _color.g, _color.b, alpha)
	var radius := _max_radius * eased
	if radius > 0.5:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ring, _width * (1.0 - _t * 0.6), true)
	if _double:
		var inner := radius * 0.55
		if inner > 0.5:
			draw_arc(Vector2.ZERO, inner, 0.0, TAU, 40,
				Color(ring.r, ring.g, ring.b, alpha * 0.7), _width * 0.6, true)
