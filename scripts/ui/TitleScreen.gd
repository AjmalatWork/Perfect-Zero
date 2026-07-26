extends Control
class_name TitleScreen

const NEON := Color("22d3ff")

@export var campaign_navigator: CampaignNavigator

@onready var title_label: Label = $TitleLabel
@onready var play_button: Button = $PlayButton
@onready var endless_button: Button = $EndlessButton
@onready var options_button: Button = $OptionsButton
@onready var help_button: Button = $HelpButton
@onready var scores_button: Button = $ScoresButton

func _ready() -> void:
	_style()
	_build_title_wave()
	play_button.pressed.connect(_on_play_pressed)
	endless_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.ENDLESS_MODE_SELECT))
	options_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.OPTIONS))
	help_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.HELP))
	scores_button.pressed.connect(func(): GameManager.set_state(GameManager.GameState.SCORES))

# TitleLabel is a fixed-rect Label (unlike the other screens' headings, which
# sit in a centered VBoxContainer column) - it keeps that rect as an anchor and
# renders nothing itself; the WaveHeading fills it via PRESET_FULL_RECT instead
# of being sized by a parent VBoxContainer the way the other screens' are.
func _build_title_wave() -> void:
	var text := title_label.text
	title_label.text = ""

	var wave := WaveHeading.new()
	wave.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.add_child(wave)
	wave.configure(text, 96, Color.WHITE, NEON, 16)

func _style() -> void:
	for button in [play_button, endless_button, options_button, help_button, scores_button]:
		button.add_theme_font_size_override("font_size", 36)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", NEON)
		button.add_theme_constant_override("outline_size", 5)
		button.add_theme_stylebox_override("normal", _make_box(0.85, 0.35, 8))
		button.add_theme_stylebox_override("hover", _make_box(0.7, 0.5, 12))
		button.add_theme_stylebox_override("pressed", _make_box(0.6, 0.4, 6))
		PressFeedback.apply(button)

func _make_box(darken: float, shadow_alpha: float, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = NEON.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = NEON
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(NEON.r, NEON.g, NEON.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb

func _on_play_pressed() -> void:
	# Always through Level Select, first play included. LevelSelect already
	# locks everything past highest_stage_reached (0 for a first-time player),
	# so a new player sees Stage 1 unlocked and 11 more stages visibly locked
	# behind it - showing the scope of the campaign up front, rather than
	# dropping them straight into Stage 1 with no sense of how much game there
	# is to stick around for.
	GameManager.set_state(GameManager.GameState.LEVEL_SELECT)
