extends Node2D
class_name MainScreenRouter

# Shows/hides screens by GameManager state, with a short cross-fade between them.

# Dev-only: set false to revert to instant screen cuts.
const USE_FADES := true
const FADE_TIME := 0.14

@export var title_screen: CanvasItem
@export var level_select: CanvasItem
@export var result_screen: CanvasItem
@export var help_screen: CanvasItem
@export var scores_screen: CanvasItem
@export var options_panel: CanvasItem
@export var endless_mode_select: CanvasItem
@export var endless_game: CanvasItem
@export var endless_end: CanvasItem
@export var gameplay_nodes: Array[CanvasItem] = []

var _shown: Dictionary = {}   # node -> logical visibility
var _fades: Dictionary = {}   # node -> active fade Tween

func _ready() -> void:
	# Register before the first state change so Juice has a shake/punch target.
	Juice.register_stage(self)
	GameManager.state_changed.connect(_on_state_changed)
	# Launch to the title screen.
	GameManager.set_state(GameManager.GameState.MENU)

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
