extends Control
class_name PauseMenu

# Pause overlay, works in both Campaign and Endless. Uses get_tree().paused to
# freeze everything (timers + tick audio + Endless spawning). This node runs with
# PROCESS_MODE_ALWAYS so it stays interactive while the rest of the tree is frozen.

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const RED := Color("ff2e5e")
const GREY := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")

@export var campaign_navigator: CampaignNavigator
@export var endless_runner: EndlessRunner

var _pause_button: Button
var _menu: Control
var _countdown_bg: ColorRect
var _countdown: Label
var _options: OptionsPanel
var _paused: bool = false
var _resuming: bool = false
var _menu_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100  # above all gameplay z_index usage (timer digits/signs peak at 20)
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	_update_pause_button_visibility(GameManager.current_state)

func _on_state_changed(new_state: int) -> void:
	_update_pause_button_visibility(new_state)

func _update_pause_button_visibility(state: int) -> void:
	var in_game := state == GameManager.GameState.PLAYING or state == GameManager.GameState.ENDLESS_PLAYING
	_pause_button.visible = in_game and not _paused

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _resuming:
		return
	if _paused:
		if _options.visible:
			_close_options()
		else:
			resume()
	elif _in_game():
		pause()

func _in_game() -> bool:
	var s := GameManager.current_state
	return s == GameManager.GameState.PLAYING or s == GameManager.GameState.ENDLESS_PLAYING

# --- Pause / resume -------------------------------------------------------

func pause() -> void:
	if _paused or not _in_game():
		return
	_paused = true
	_pause_button.visible = false
	_menu.visible = true
	get_tree().paused = true

func resume() -> void:
	if not _paused or _resuming:
		return
	_fade_menu_out()
	_resuming = true
	_run_countdown()

# Restart gets a straight-to-black screen fade rather than resume's 3-2-1 -
# there's no "get back into position" moment to bridge the way there is coming
# out of a pause, so a countdown here would just be dead time. The swap to the
# new run happens at the black frame, so the player never sees the old board
# get torn down and rebuilt. Fade itself lives on Juice - shared with the
# Endless end screen's RETRY, so both read as the same beat.
func _on_restart() -> void:
	if _resuming:
		return
	_resuming = true
	for b in _menu_buttons:
		b.disabled = true

	var start := func() -> void:
		get_tree().paused = false
		_paused = false
		_menu.visible = false
		if GameManager.current_state == GameManager.GameState.ENDLESS_PLAYING:
			endless_runner.start_run(endless_runner.max_lives)
		else:
			campaign_navigator.retry()
	await Juice.run_transition(start)

	_resuming = false
	for b in _menu_buttons:
		b.disabled = false
	_update_pause_button_visibility(GameManager.current_state)

func _fade_menu_out() -> void:
	# Buttons disabled up front, not after the tween - a Control's mouse_filter
	# doesn't stop its own children from receiving clicks, so a bare visibility
	# fade would leave the menu clickable for the whole 0.18s (mashable into a
	# double-fire). Disabling each Button directly is what actually blocks it.
	for b in _menu_buttons:
		b.disabled = true
	var tween := create_tween()
	tween.tween_property(_menu, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func():
		_menu.visible = false
		_menu.modulate.a = 1.0
		for b in _menu_buttons:
			b.disabled = false)

func _run_countdown() -> void:
	_countdown_bg.visible = true
	_countdown.visible = true
	for n in [3, 2, 1]:
		_countdown.text = str(n)
		_pop(_countdown)
		await get_tree().create_timer(1.0, true).timeout  # process_always -> ticks while paused
	_countdown_bg.visible = false
	_countdown.visible = false
	get_tree().paused = false
	_paused = false
	_resuming = false
	_update_pause_button_visibility(GameManager.current_state)

func _on_title() -> void:
	get_tree().paused = false
	_paused = false
	_menu.visible = false
	_options.visible = false
	if GameManager.current_state == GameManager.GameState.ENDLESS_PLAYING:
		endless_runner.abort_run()
	elif GameManager.current_state == GameManager.GameState.PLAYING:
		campaign_navigator.stage_controller.abort()
	GameManager.set_state(GameManager.GameState.MENU)

func _open_options() -> void:
	_menu.visible = false
	_options.visible = true

func _close_options() -> void:
	_options.visible = false
	_menu.visible = true

# --- UI -------------------------------------------------------------------

func _build() -> void:
	# Small pause button, top-right, shown only during gameplay. Drawn as two
	# bars rather than a "❚❚" text glyph - some exported builds' bundled font
	# (notably HTML5/Web) lacks that Unicode character and shows tofu boxes.
	_pause_button = _button("", GREY)
	_pause_button.custom_minimum_size = Vector2(64, 64)
	_pause_button.position = Vector2(VIEWPORT_SIZE.x - 92, 28)
	_pause_button.pressed.connect(pause)
	add_child(_pause_button)
	_build_pause_icon(_pause_button)

	# Pause menu (dim + buttons), hidden until paused.
	_menu = Control.new()
	_menu.position = Vector2.ZERO
	_menu.size = VIEWPORT_SIZE
	_menu.visible = false
	add_child(_menu)

	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = VIEWPORT_SIZE
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	_menu.add_child(dim)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	_menu.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_heading("PAUSED", 64, NEON))
	col.add_child(_menu_button("RESUME", NEON, resume))
	col.add_child(_menu_button("RESTART", GOLD, _on_restart))
	col.add_child(_menu_button("OPTIONS", NEON, _open_options))
	col.add_child(_menu_button("BACK TO TITLE", GREY, _on_title))

	# Resume countdown overlay.
	_countdown_bg = ColorRect.new()
	_countdown_bg.position = Vector2.ZERO
	_countdown_bg.size = VIEWPORT_SIZE
	_countdown_bg.color = Color(0.02, 0.02, 0.04, 0.82)
	_countdown_bg.visible = false
	_countdown_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_countdown_bg)

	_countdown = Label.new()
	_countdown.add_theme_font_size_override("font_size", 200)
	_countdown.add_theme_color_override("font_color", TEXT_FILL)
	_countdown.add_theme_color_override("font_outline_color", NEON)
	_countdown.add_theme_constant_override("outline_size", 8)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.position = Vector2.ZERO
	_countdown.size = VIEWPORT_SIZE
	_countdown.visible = false
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_countdown)

	# Options overlay (reuses OptionsPanel; closes back to the pause menu).
	_options = preload("res://scenes/OptionsPanel.tscn").instantiate()
	_options.standalone = false
	_options.visible = false
	_options.closed.connect(_close_options)
	add_child(_options)

func _build_pause_icon(button: Button) -> void:
	var bar_size := Vector2(8, 22)
	var gap := 8.0
	var total_w := bar_size.x * 2 + gap
	var center := button.custom_minimum_size * 0.5
	for i in range(2):
		var bar := ColorRect.new()
		bar.color = Color.WHITE
		bar.size = bar_size
		bar.position = Vector2(
			center.x - total_w * 0.5 + i * (bar_size.x + gap),
			center.y - bar_size.y * 0.5
		)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(bar)

func _pop(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _menu_button(text: String, accent: Color, handler: Callable) -> Control:
	var b := _button(text, accent)
	b.custom_minimum_size = Vector2(340, 68)
	b.pressed.connect(handler)
	_menu_buttons.append(b)
	var w := CenterContainer.new()
	w.add_child(b)
	return w

func _heading(text: String, font_size: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
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
