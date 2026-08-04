extends Node2D
class_name MainScreenRouter

# Shows/hides screens by GameManager state, with a short cross-fade between them.

# Dev-only: set false to revert to instant screen cuts.
const USE_FADES := true
const FADE_TIME := 0.14

# Every screen in the game (all of Main's children) is built with absolute pixel
# positions against the reference canvas - none of them use anchors, so nothing
# reflows to fill extra space. project.godot's stretch/aspect is "expand", which
# grows the *available* canvas on whichever axis the real viewport is
# wider/taller than the reference, but a top-left-anchored block of content
# doesn't move to compensate - on a wider device that reads as everything pinned
# to the left edge with a dead zone on the right.
#
# The reference itself is Layout.canvas_size, which transposes between landscape
# and portrait, so this offset is what keeps the content block centred in either.

@export var title_screen: CanvasItem
@export var level_select: CanvasItem
@export var result_screen: CanvasItem
@export var help_screen: CanvasItem
@export var scores_screen: CanvasItem
@export var options_panel: CanvasItem
@export var endless_mode_select: CanvasItem
@export var endless_game: CanvasItem
@export var endless_end: CanvasItem
@export var credits_screen: CanvasItem
@export var gameplay_nodes: Array[CanvasItem] = []

var _shown: Dictionary = {}   # node -> logical visibility
var _fades: Dictionary = {}   # node -> active fade Tween
var _background: ColorRect    # fills the pillarbox bands so they read as part of the game, not a hard cut

func _ready() -> void:
	_build_background()
	# Register before the first state change so Juice has a shake/punch target.
	Juice.register_stage(self)
	get_tree().root.size_changed.connect(_recenter)
	# An orientation flip changes the reference canvas before the OS rotation
	# lands, so the offset has to be recomputed on both signals rather than
	# waiting for the resize alone.
	Layout.changed.connect(_recenter)
	_recenter()
	GameManager.state_changed.connect(_on_state_changed)
	# Launch to the title screen.
	GameManager.set_state(GameManager.GameState.MENU)

# A base-level fallback behind every screen: on a device whose aspect ratio
# doesn't match the fixed canvas, this is what used to show as the engine's
# raw default_clear_color in the letterbox bands, with a visible seam against
# whatever a given screen paints inside the canvas. Still matches the clear
# colour exactly (rather than introducing a new tone) so it stays a pure
# gap-fill - individual screens with their own dim/backdrop already extend to
# override this via ScreenLayout.cover() where they exist.
#
# Both this AND project.godot's default_clear_color are now the same
# Color(0.03, 0.03, 0.05) every screen's own backdrop uses, rather than the
# slightly lighter 0.043137 pair they shared before. The old value was invisible
# during a cross-fade (~1/255 at the midpoint, computed) but it was NOT
# invisible during gameplay: PLAYING and ENDLESS_PLAYING paint no full-bleed
# backdrop of their own, so this rect is the live background for the entire
# screen while a stage is running - which meant the background stepped very
# slightly lighter every time the player left a menu and entered a board, and
# again in reverse on the way out. One value everywhere removes that step. Well
# inside GDD §2's "near-black (#0a0a11-ish)" either way.
func _build_background() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.03, 0.03, 0.05)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	move_child(_background, 0)

# --- Pillarboxing: centering the fixed 1600x900 canvas -----------------------
#
# Main is the single shared parent every screen in the game lives under
# (see Main.tscn), and Main is a Node2D - so shifting Main.position shifts
# every child's on-screen position AND its input hit-testing together, in one
# place, with no per-screen changes. This is deliberately just a pixel offset
# on the existing fixed-size content, not a reflow/resize of anything - the
# actual anchor-based responsive rework (if it happens) is a separate, larger
# effort tracked elsewhere.
#
# Routed through Juice.recenter() rather than setting position directly:
# Juice's _process() reapplies _base_position (plus live shake/punch) to Main
# every frame regardless of what screen is showing, so writing Main.position
# from here would just be overwritten on the very next frame.
func _recenter() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var offset := (visible_size - Layout.canvas_size) * 0.5
	offset.x = maxf(offset.x, 0.0)
	offset.y = maxf(offset.y, 0.0)
	Juice.recenter(offset)
	if _background != null:
		_background.position = -offset
		_background.size = visible_size

# --- Android system back ---------------------------------------------------
#
# Android delivers its back gesture/button as NOTIFICATION_WM_GO_BACK_REQUEST.
# (application/config/quit_on_go_back is disabled in project.godot, so it no
# longer quits the app outright before anything here can react.) Desktop and
# web have no equivalent notification - there the same "go up one level" intent
# arrives as Escape, i.e. the ui_cancel action every screen already handles.
#
# Rather than give every screen a second, Android-only code path, the back
# request is simply republished here as ui_cancel. One bridge in one place, and
# from that point on the two platforms are indistinguishable to the rest of the
# game: every existing ui_cancel handler works identically on both, and there's
# no per-screen routing table living here that could drift out of sync with the
# screens themselves.
#
# The matching release is sent so the action can't stay latched for anything
# that polls Input.is_action_pressed() rather than reading the event.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	var press := InputEventAction.new()
	press.action = "ui_cancel"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = "ui_cancel"
	release.pressed = false
	Input.parse_input_event(release)

func _on_state_changed(new_state: int) -> void:
	var S := GameManager.GameState
	_apply(title_screen, new_state == S.MENU)
	_apply(level_select, new_state == S.LEVEL_SELECT)
	_apply(result_screen, new_state == S.STAGE_CLEAR or new_state == S.FAIL)
	_apply(help_screen, new_state == S.HELP)
	_apply(scores_screen, new_state == S.SCORES)
	_apply(options_panel, new_state == S.OPTIONS)
	_apply(endless_mode_select, new_state == S.ENDLESS_MODE_SELECT)
	_apply(endless_game, new_state == S.ENDLESS_PLAYING)
	_apply(endless_end, new_state == S.ENDLESS_END)
	_apply(credits_screen, new_state == S.CREDITS)
	var show_game := new_state == S.PLAYING
	for node in gameplay_nodes:
		_apply(node, show_game)

func _apply(node: CanvasItem, want_shown: bool) -> void:
	if node == null:
		return
	if _shown.has(node) and _shown[node] == want_shown:
		return
	_shown[node] = want_shown

	if not USE_FADES:
		node.visible = want_shown
		node.modulate.a = 1.0
		return

	if _fades.has(node) and is_instance_valid(_fades[node]):
		_fades[node].kill()

	if want_shown:
		node.visible = true
		node.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(node, "modulate:a", 1.0, FADE_TIME)
		_fades[node] = tw
	else:
		var tw := create_tween()
		tw.tween_property(node, "modulate:a", 0.0, FADE_TIME)
		tw.tween_callback(_hide.bind(node))
		_fades[node] = tw

func _hide(node: CanvasItem) -> void:
	node.visible = false
