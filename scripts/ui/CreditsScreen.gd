extends Control
class_name CreditsScreen

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")
const VIEWPORT_SIZE := Vector2(1600, 900)

# Placeholder wording throughout, per the brief - final copy to be supplied by
# the designer. Left as clearly-labelled placeholders rather than guessed-at
# final text, so nothing here is mistaken for the real credited wording.
const DEV_LINE := "Made by [Your Name] - design, code, procedural art, synthesized audio"
const THANKS_LINE := "Thanks to everyone who played and rated the jam build!"
const LINKS_LINE := "itch.io: [link]   -   Play Store: [link]   -   [email / socials]"

func _ready() -> void:
	_build()

func _build() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEWPORT_SIZE
	backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(900, 0)
	center.add_child(col)

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("CREDITS", 56, TEXT_FILL, NEON)

	col.add_child(_line(DEV_LINE, 24, TEXT_FILL))
	col.add_child(_line(THANKS_LINE, 20, Color(1, 1, 1, 0.75)))

	col.add_child(_spacer(10))
	col.add_child(_heading("MUSIC", 24, GOLD))
	col.add_child(_line("\"Synthwave Retro 80s\" by arpmedia - via Pixabay", 20, TEXT_FILL))

	col.add_child(_spacer(10))
	col.add_child(_heading("ENGINE", 24, GOLD))
	col.add_child(_line("Made with Godot Engine %s" % Engine.get_version_info().string, 20, TEXT_FILL))

	col.add_child(_spacer(10))
	col.add_child(_line("Originally created for GMTK Game Jam 2026 - theme: Countdown", 20,
		Color(1, 1, 1, 0.75)))

	col.add_child(_spacer(16))
	col.add_child(_line(LINKS_LINE, 19, Color(1, 1, 1, 0.6)))

	col.add_child(_spacer(10))
	var back := _button("BACK", BACK_ACCENT)
	back.pressed.connect(_on_back)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	col.add_child(back_wrap)

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses. Guarded
# on the current state because hidden screens stay in the tree and would
# otherwise all answer the same press - see LevelSelect for the full note.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.CREDITS:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _heading(text: String, font_size: int, accent: Color) -> Label:
	var l := _line(text, font_size, TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 4)
	return l

func _line(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(880, 0)
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 64)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	return button

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb
