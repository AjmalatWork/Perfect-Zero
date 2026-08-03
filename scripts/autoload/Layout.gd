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

# Portrait's WIDTH is fixed - every dp/touch-target calibration and the
# gameplay board's own sizing (EndlessRunner.PORTRAIT_CELL_SIZE etc.) is done
# against this exact number, so changing it would invalidate all of that.
# Portrait's HEIGHT is no longer a fixed 1600, though - see
# _compute_portrait_size() below for why.
const PORTRAIT_WIDTH := 900.0
# Used only if the real window size isn't readable yet (defensive fallback) -
# this is the project's original fixed portrait size, kept as the safe default
# rather than guessing something new.
const PORTRAIT_SIZE_FALLBACK := Vector2(900, 1600)

# Clamp on the computed portrait height, in canvas units. Every portrait screen
# positions itself with absolute pixel offsets against canvas_size.y, so an
# unclamped height can collapse the whole layout: split-screen, a foldable
# unfolded, or a free-form/DeX window can all report window.x > window.y even
# on a manifest-locked-portrait build (userPortrait doesn't prevent any of
# those), which would otherwise send _compute_portrait_size() below 900 tall -
# the HUD, the board zone and the fail-cross row all start overlapping. The
# upper bound guards the opposite case (a narrow split-screen sliver) from
# stretching the canvas absurdly tall. 1200 covers a squarish 4:3-ish window
# (900/1200 = 3:4) without the board zone (720 tall) crowding the HUD above
# it; 2400 covers past 21:9 (900/2400 = 3:8) with room to spare.
const PORTRAIT_HEIGHT_MIN := 1200.0
const PORTRAIT_HEIGHT_MAX := 2400.0

var canvas_size: Vector2 = LANDSCAPE_SIZE
var _portrait: bool = false

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

# --- Dynamic portrait height --------------------------------------------------
#
# A fixed 900x1600 (9:16) canvas under stretch aspect "expand" only fills the
# real screen on a device that IS exactly 9:16. Almost no Android phone is -
# most are taller (19.5:9, 20:9, 21:9) - so "expand" becomes width-bound and
# leaves real, unused height above and below the content. The earlier portrait
# pass painted a backdrop over those bars so they read as intentional
# background rather than raw engine clear colour, but the dead margin itself
# was still there.
#
# The actual fix: hold the WIDTH fixed (so every dp/touch-target number and the
# gameplay board's sizing stays exactly what it was calibrated against) and
# make the HEIGHT match whatever the real device's aspect ratio implies -
# canvas_height = width / (real_width / real_height). That makes the canvas's
# own aspect ratio identical to the device's, so Godot's
# min(win.x/base.x, win.y/base.y) scale is the same on both axes by
# construction, for any aspect ratio - not just the common ones. Overscan
# collapses to ~0 as a direct consequence, with no changes needed to
# MainScreenRouter._recenter() or _recompute_overscan() below - both already
# derive everything from canvas_size.
func _compute_portrait_size() -> Vector2:
	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return PORTRAIT_SIZE_FALLBACK
	var aspect: float = float(window.x) / float(window.y)
	var height := clampf(roundf(PORTRAIT_WIDTH / aspect), PORTRAIT_HEIGHT_MIN, PORTRAIT_HEIGHT_MAX)
	return Vector2(PORTRAIT_WIDTH, height)

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
	return _portrait

# Settings.changed also fires for volume and the effects toggle, so this has to
# be idempotent - the guard is what stops an unrelated setting from restretching
# the window and rebuilding every screen behind it.
#
# Deliberately driven off Settings rather than off the window's actual size: the
# player's pick is the intent, and the OS rotation that follows arrives a few
# frames later as a resize. Keying off the resize instead would also catch
# desktop windows the player happened to drag taller than they are wide.
func _refresh() -> void:
	_portrait = _forced_portrait or Settings.is_portrait()
	var want: Vector2 = _compute_portrait_size() if _portrait else LANDSCAPE_SIZE
	if want == canvas_size:
		return
	canvas_size = want
	get_window().content_scale_size = Vector2i(canvas_size)
	_recompute_overscan()
	changed.emit()

# Rotation, multi-window/split-screen and foldable fold/unfold all surface here
# as a root resize, and any of them can change the real device aspect ratio -
# not just move the pillarbox bands the way a plain landscape window drag does
# - so portrait recomputes its own dynamic height first, on top of the existing
# overscan recompute.
func _on_root_resized() -> void:
	if _portrait:
		var want := _compute_portrait_size()
		if want != canvas_size:
			canvas_size = want
			get_window().content_scale_size = Vector2i(canvas_size)
			_recompute_overscan()
			changed.emit()
			return
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
