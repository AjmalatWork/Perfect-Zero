extends Node

# Display safe area - notch / camera cutout / gesture navigation bar / rounded
# corners - expressed as insets in this game's own 1600x900 canvas units rather
# than physical pixels.
#
# That conversion is the entire point of this autoload. DisplayServer reports
# the safe area in physical screen pixels, but every screen in this project
# positions itself in canvas units against a fixed 1600x900 viewport, so raw
# DisplayServer values are unusable without being mapped through the stretch
# ratio first.
#
# Collapses to zero on every platform without cutouts: get_display_safe_area()
# returns the full screen on desktop and web, so callers need no platform
# branch and desktop/web layout is bit-for-bit unchanged.
#
# Worth keeping in mind that this game is landscape: a cutout that sits along
# the top edge in portrait ends up on the LEFT or RIGHT edge here, and the
# gesture bar runs along the bottom. Corner- and edge-pinned UI is what
# actually needs these - centred content is generally fine.

signal changed

var left: float = 0.0
var top: float = 0.0
var right: float = 0.0
var bottom: float = 0.0

func _ready() -> void:
	# Rotation, multi-window/split-screen resize, and entering or leaving
	# fullscreen all surface as a root-window resize.
	get_tree().root.size_changed.connect(_recompute)
	_recompute()

func _recompute() -> void:
	var previous := Vector4(left, top, right, bottom)
	_compute()
	if Vector4(left, top, right, bottom) != previous:
		changed.emit()

func _compute() -> void:
	left = 0.0
	top = 0.0
	right = 0.0
	bottom = 0.0

	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return  # unreported/unsupported - treat as "no insets" rather than guessing

	# Canvas units per physical pixel. With stretch aspect "expand" the visible
	# rect grows to fill the window instead of letterboxing, so this ratio is
	# what maps a physical inset into the coordinate space the screens use.
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var scale_x: float = visible.x / float(window.x)
	var scale_y: float = visible.y / float(window.y)

	left = maxf(0.0, float(safe.position.x)) * scale_x
	top = maxf(0.0, float(safe.position.y)) * scale_y
	right = maxf(0.0, float(window.x - (safe.position.x + safe.size.x))) * scale_x
	bottom = maxf(0.0, float(window.y - (safe.position.y + safe.size.y))) * scale_y
