extends Node

# Display safe area - notch / camera cutout / gesture navigation bar / rounded
# corners - expressed as insets in this game's own canvas units rather than
# physical pixels.
#
# That conversion is the entire point of this autoload. DisplayServer reports
# the safe area in physical pixels, but every screen in this project positions
# itself in canvas units against whichever fixed canvas Layout has resolved
# (1600x900 landscape, or 900 x dynamic-height portrait), so raw DisplayServer
# values are unusable without being mapped through the stretch ratio first.
#
# Collapses to zero on every platform without cutouts: get_display_safe_area()
# returns the full screen on desktop and web, so callers need no platform
# branch and desktop/web layout is bit-for-bit unchanged.
#
# Mind the two coordinate spaces involved, because they are NOT the same one:
# get_display_safe_area() is in SCREEN pixels, while window_get_size() is the
# WINDOW's own extent. On a fullscreen app the window sits at the screen origin
# and the two coincide, which is why subtracting them directly appeared to work
# - but under split-screen, multi-window or DeX the window is offset from the
# screen, and the raw screen-space safe rect then bleeds that offset into the
# insets (a window pushed halfway down the screen would report a top inset of
# half the screen). _compute() translates into window space and intersects
# before converting, so an off-origin window reports the insets that actually
# overlap it and nothing more.
#
# Orientation note: on Android this game is portrait, so a cutout along the
# physical top edge lands on the canvas's top edge too and the gesture bar runs
# along the bottom. Desktop/web are landscape and report no insets at all.
# Corner- and edge-pinned UI is what actually needs these - centred content is
# generally fine.

signal changed

var left: float = 0.0
var top: float = 0.0
var right: float = 0.0
var bottom: float = 0.0

func _ready() -> void:
	# Rotation, multi-window/split-screen resize, and entering or leaving
	# fullscreen all surface as a root-window resize.
	get_tree().root.size_changed.connect(_recompute)
	# Layout autoloads *after* this one, so it isn't in the tree yet at
	# _ready() - deferring is what makes the singleton resolvable (same fix
	# Juice.gd applies for Powerups). Without this, _compute() below ran its
	# very first pass against the pre-Layout landscape viewport, and nothing
	# ever re-ran it once Layout assigned its own portrait content_scale_size -
	# every inset this autoload reports was computed against the wrong canvas.
	call_deferred("_connect_layout")
	_recompute()

func _connect_layout() -> void:
	Layout.changed.connect(_recompute)
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

	# Screen space -> window space. window_get_position() is where this window's
	# top-left sits on the screen the safe rect is measured against, so
	# subtracting it puts both rects in the same frame of reference. On a
	# fullscreen app this is (0, 0) and changes nothing; under split-screen or a
	# free-form/DeX window it is what stops the window's own screen offset being
	# misread as an enormous top/left inset.
	var origin: Vector2i = DisplayServer.window_get_position()
	var safe_local := Rect2i(safe.position - origin, safe.size)

	# Only the part of the safe rect that actually overlaps this window can
	# constrain this window's layout. Without the intersection, a safe rect
	# extending past the window (or sitting entirely outside it, which is what a
	# stale/odd report looks like) would produce negative or nonsensical edges
	# that the maxf() guards below would silently flatten to zero on one side
	# while leaving the opposite side wildly overstated.
	var window_rect := Rect2i(Vector2i.ZERO, window)
	safe_local = window_rect.intersection(safe_local)
	if safe_local.size.x <= 0 or safe_local.size.y <= 0:
		return  # no usable overlap - treat as "no insets" rather than guessing

	# Canvas units per physical pixel. With stretch aspect "expand" the visible
	# rect grows to fill the window instead of letterboxing, so this ratio is
	# what maps a physical inset into the coordinate space the screens use.
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var scale_x: float = visible.x / float(window.x)
	var scale_y: float = visible.y / float(window.y)

	left = maxf(0.0, float(safe_local.position.x)) * scale_x
	top = maxf(0.0, float(safe_local.position.y)) * scale_y
	right = maxf(0.0, float(window.x - (safe_local.position.x + safe_local.size.x))) * scale_x
	bottom = maxf(0.0, float(window.y - (safe_local.position.y + safe_local.size.y))) * scale_y
