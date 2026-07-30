extends Control
class_name PauseMenu

# Pause overlay, works in both Campaign and Endless. Uses get_tree().paused to
# freeze everything (timers + tick audio + Endless spawning). This node runs with
# PROCESS_MODE_ALWAYS so it stays interactive while the rest of the tree is frozen.

const VIEWPORT_SIZE := Vector2(1600, 900)
# Authored (inset-free) position; _apply_safe_area() offsets from this.
const PAUSE_BUTTON_POS := Vector2(VIEWPORT_SIZE.x - 92, 28)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const RED := Color("ff2e5e")
const GREY := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")

@export var campaign_navigator: CampaignNavigator
@export var endless_runner: EndlessRunner

@export var help_bubble: HelpBubble

var _pause_button: Button
var _menu: Control
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
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_pause_button_visibility(GameManager.current_state)

# Top-right corner, immediately right of the Help icon - same cutout/rounded
# corner exposure, so it's inset the same way. Only the pause button needs
# this: the menu itself is a full-rect dim with centred content, which no
# inset can clip.
func _apply_safe_area() -> void:
	_pause_button.position = PAUSE_BUTTON_POS + Vector2(-SafeArea.right, SafeArea.top)

func _on_state_changed(new_state: int) -> void:
	_update_pause_button_visibility(new_state)

func _update_pause_button_visibility(state: int) -> void:
	var in_game := state == GameManager.GameState.PLAYING or state == GameManager.GameState.ENDLESS_PLAYING
	var bubble_open := help_bubble != null and help_bubble.is_open
	_pause_button.visible = in_game and not _paused and not bubble_open

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

# --- App lifecycle (backgrounding, interrupts) -----------------------------
#
# Android can take focus away at any moment - home button, incoming call,
# notification shade, split-screen, app switcher - and none of those give the
# player a chance to pause first. In a game where the whole skill is stopping a
# timer on an exact value, a run left ticking behind a backgrounded app is a
# guaranteed loss on return, so focus loss has to pause on the player's behalf.
#
# Handled as one generic "focus lost" case rather than per-trigger: Android
# surfaces all of the above through these same lifecycle notifications, so
# there's nothing trigger-specific to branch on. APPLICATION_PAUSED is the
# mobile "went to background" signal; the two FOCUS_OUT notifications cover
# what steals focus without fully backgrounding (split-screen, the shade, and
# on desktop/web alt-tab or a browser tab switch).
#
# Deliberately routed through pause() - the same entry point the on-screen
# pause button and ui_cancel already use - rather than a second freeze path, so
# the game keeps exactly one notion of "paused".
#
# There is deliberately no matching FOCUS_IN/APPLICATION_RESUMED handler:
# coming back to a run that instantly resumes mid-timer, while the player is
# still re-orienting, is precisely the loss this is meant to prevent. Returning
# leaves the Pause Menu up, and RESUME (with its existing wipe) is the player's
# explicit "I'm ready" - the same beat as any other unpause.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_on_focus_lost()

func _on_focus_lost() -> void:
	# Notifications can arrive before _ready() has run _build(), which would
	# reach a null _pause_button/_menu inside pause(). Cheap insurance - in
	# practice the state guard in pause() already covers the startup window,
	# since the game always launches into MENU.
	if not is_node_ready():
		return
	# pause() already no-ops when not in gameplay and when already paused, so
	# focus loss on a menu screen or while paused is silently ignored.
	pause()

# --- Pause / resume -------------------------------------------------------

func pause() -> void:
	if _paused or not _in_game():
		return
	_paused = true
	_pause_button.visible = false
	_menu.visible = true
	get_tree().paused = true

# Unified resume transition (Juice.resume_wipe): the whole menu Control (dim +
# buttons) dissolves as one overlay, and the tree only actually unpauses once
# that's finished - no numeral, no "get back into position" beat, just the
# board becoming interactive again as the overlay lifts.
func resume() -> void:
	if not _paused or _resuming:
		return
	_resuming = true
	for b in _menu_buttons:
		b.disabled = true
	await Juice.resume_wipe(_menu)
	_menu.visible = false
	_menu.modulate.a = 1.0
	for b in _menu_buttons:
		b.disabled = false
	get_tree().paused = false
	_paused = false
	_resuming = false
	_update_pause_button_visibility(GameManager.current_state)

# Restart gets a straight-to-black screen fade rather than resume's wipe -
# there's a whole run/stage being torn down and rebuilt underneath, not just an
# overlay lifting off an unchanged board, so this needs a real content swap
# hidden in black rather than a dissolve. Fade itself lives on Juice - shared
# with the Endless end screen's RETRY, so both read as the same beat.
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
	_pause_button.position = PAUSE_BUTTON_POS
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
