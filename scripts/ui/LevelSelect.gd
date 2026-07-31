extends Control
class_name LevelSelect

const NORMAL_ACCENT := Color("22d3ff")  # cyan, matches BLUE timer family
const BONUS_ACCENT := Color("ffd23f")   # gold, matches the GOLDEN timer color
const LOCKED_ACCENT := Color("8b90a8")  # muted grey
const TEXT_FILL := Color("dfe3ee")

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel).
# This screen previously had no heading at all - reached straight from the
# title screen's ARCADE button with nothing naming it, unlike every other
# screen in the game's own navigation.
const PAGE_HEADING_SIZE := 56

@export var campaign: Campaign
@export var campaign_navigator: CampaignNavigator

@onready var grid: GridContainer = $Center/Col/Grid
@onready var _col: VBoxContainer = $Center/Col
@onready var _center: CenterContainer = $Center

var _backdrop: ColorRect

func _ready() -> void:
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	GameManager.state_changed.connect(_on_state_changed)
	_add_heading()
	_add_back_button()
	_add_backdrop()
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

# Placed first in _col (ahead of Grid, which the scene file already parents
# there), so it reads as this screen's title the same way every other screen's
# WaveHeading does.
func _add_heading() -> void:
	var heading := WaveHeading.new()
	_col.add_child(heading)
	_col.move_child(heading, 0)
	heading.configure("LEVEL SELECT", PAGE_HEADING_SIZE, TEXT_FILL, NORMAL_ACCENT)

# This screen is authored in LevelSelect.tscn rather than built procedurally, so
# its root and its centring container both carried the scene's hard-coded
# 1600x900 rect. On the 900-wide portrait canvas that put the centre at x=800
# instead of 450 and pushed the whole grid off the right edge - the one screen
# the rest of this pass missed, because it had no VIEWPORT_SIZE constant to find.
#
# The 3x4 grid of 220-wide buttons measures 708 units, which already sits well
# inside 900, so nothing here needs a portrait type scale - only the centring.
func _apply_canvas() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	if _center != null:
		_center.position = Vector2.ZERO
		_center.size = Layout.canvas_size
	ScreenLayout.cover(_backdrop)

# Added behind the content (as the first child) rather than in the scene, since
# this screen previously relied on the engine's clear colour showing through -
# which reads a shade lighter than every other screen's own backdrop.
func _add_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	move_child(_backdrop, 0)

# Centered below the grid, last item in the same column - matching where every
# other screen (Help/Scores/Credits/Endless Mode Select) puts BACK, rather than
# pinned to a fixed top-left corner on its own.
func _add_back_button() -> void:
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(200, 64)  # matches the Scores screen's BACK button
	_style_button(back, NORMAL_ACCENT)  # same cyan as the title screen's ARCADE button
	back.pressed.connect(_on_back)
	PressFeedback.apply(back)
	var wrap := CenterContainer.new()
	wrap.add_child(back)
	_col.add_child(wrap)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses.
#
# Guarded on the current state rather than on visibility: every screen stays in
# the tree while hidden - MainScreenRouter only toggles `visible` - and
# _unhandled_input still fires on hidden nodes, so without this guard a single
# back press would be answered by every screen in the game at once.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.LEVEL_SELECT:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)

func _on_state_changed(new_state: int) -> void:
	# Rebuild each time the screen is shown so unlock progress is always current.
	if new_state == GameManager.GameState.LEVEL_SELECT:
		_populate()

func _populate() -> void:
	for child in grid.get_children():
		child.queue_free()
	if campaign == null:
		push_error("LevelSelect: no campaign assigned.")
		return

	var highest: int = SaveManager.load_high_score("highest_stage_reached")
	for i in range(campaign.stages.size()):
		var stage: StageData = campaign.stages[i]
		var button := Button.new()
		button.text = stage.stage_name
		button.custom_minimum_size = Vector2(220, 120)

		var locked: bool = i > highest
		if locked:
			button.disabled = true
			button.modulate = Color(1, 1, 1, 0.45)
			_style_button(button, LOCKED_ACCENT)
		else:
			var accent: Color = BONUS_ACCENT if stage.is_bonus_stage else NORMAL_ACCENT
			_style_button(button, accent)
			var index := i  # fresh binding so the lambda captures this stage's index
			button.pressed.connect(func(): campaign_navigator.enter_campaign(index))
			PressFeedback.apply(button)

		grid.add_child(button)

func _style_button(button: Button, accent: Color) -> void:
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 5)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	button.add_theme_stylebox_override("normal", _make_box(accent, 0.85, 0.35, 8))
	button.add_theme_stylebox_override("hover", _make_box(accent, 0.7, 0.5, 12))
	button.add_theme_stylebox_override("pressed", _make_box(accent, 0.6, 0.4, 6))
	button.add_theme_stylebox_override("disabled", _make_box(accent, 0.9, 0.15, 4))

func _make_box(accent: Color, darken: float, shadow_alpha: float, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb
