extends Node

# The reference canvas every screen positions itself against, and the one place
# the engine's stretch base is set from.
#
# Godot's "expand" stretch scales the canvas by min(win.x/base.x, win.y/base.y).
# Holding a landscape base fixed means a portrait window picks up the *width*
# ratio and renders everything at roughly half size - on a 1080x2400 phone
# that's 0.675x against landscape's 1.2x. Transposing the base instead keeps the
# scale identical in both orientations, which is what makes one canvas unit
# worth the same 0.4dp either way and lets the existing touch-target budget
# carry across unchanged rather than needing a second set of numbers.
#
# Screens read canvas_size instead of holding their own 1600x900 constant, and
# rebuild on `changed`.

signal changed

const LANDSCAPE_SIZE := Vector2(1600, 900)
const PORTRAIT_SIZE := Vector2(900, 1600)

var canvas_size: Vector2 = LANDSCAPE_SIZE

# The rect that actually reaches the screen edges, in canvas-local coordinates.
#
# MainScreenRouter centres the fixed canvas inside whatever the device's visible
# rect turns out to be, so on any aspect ratio that isn't exactly the canvas's
# own there are pillarbox bands outside it. A backdrop sized to canvas_size stops
# at those bands and leaves the engine's clear colour showing through - visible
# on a 20:9 phone as lighter strips above and below the content in portrait, and
# to either side in landscape.
#
# Anything that has to cover the whole screen (a screen's backdrop, a full-screen
# dim or flash) should use these instead of canvas_size.
var overscan_position: Vector2 = Vector2.ZERO
var overscan_size: Vector2 = LANDSCAPE_SIZE

# Dev-only. Run with `Godot --path . -- --portrait` to force the portrait canvas
# on any platform, so the layouts can be iterated on desktop instead of costing a
# device deploy per change. Unreachable in a shipped run - it needs a command
# line argument a player has no way to pass - so it is deliberately not gated on
# a debug build.
var _forced_portrait: bool = false

func _ready() -> void:
	_forced_portrait = OS.get_cmdline_user_args().has("--portrait")
	if _forced_portrait:
		# Matches the portrait canvas's 9:16 at a size that fits a desktop screen.
		# Note --write-movie cannot preview this: it renders at the project's
		# configured viewport size regardless of the window or content_scale_size,
		# so portrait has to be judged from the running window.
		DisplayServer.window_set_size(Vector2i(506, 900))
	Settings.changed.connect(_refresh)
	# Rotation, split-screen and desktop window drags all land here, and all of
	# them move the pillarbox bands even when the orientation hasn't changed.
	get_tree().root.size_changed.connect(_on_root_resized)
	_refresh()
	_recompute_overscan()

func is_portrait() -> bool:
	return canvas_size == PORTRAIT_SIZE

# Settings.changed also fires for volume and the effects toggle, so this has to
# be idempotent - the guard is what stops an unrelated setting from restretching
# the window and rebuilding every screen behind it.
#
# Deliberately driven off Settings rather than off the window's actual size: the
# player's pick is the intent, and the OS rotation that follows arrives a few
# frames later as a resize. Keying off the resize instead would also catch
# desktop windows the player happened to drag taller than they are wide.
func _refresh() -> void:
	var want: Vector2 = PORTRAIT_SIZE if (_forced_portrait or Settings.is_portrait()) \
		else LANDSCAPE_SIZE
	if want == canvas_size:
		return
	canvas_size = want
	get_window().content_scale_size = Vector2i(canvas_size)
	_recompute_overscan()
	changed.emit()

func _on_root_resized() -> void:
	if _recompute_overscan():
		changed.emit()

# True when the values actually moved - the guard is what keeps a resize that
# changes nothing from rebuilding every screen behind it.
func _recompute_overscan() -> bool:
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var off := Vector2(
		maxf((visible.x - canvas_size.x) * 0.5, 0.0),
		maxf((visible.y - canvas_size.y) * 0.5, 0.0))
	# Mirrors MainScreenRouter._recenter()'s offset, negated: the router shifts
	# every screen down-right by `off`, so a rect starting at -off lands on the
	# real top-left corner of the display.
	var pos := -off
	var siz := canvas_size + off * 2.0
	if pos == overscan_position and siz == overscan_size:
		return false
	overscan_position = pos
	overscan_size = siz
	return true
