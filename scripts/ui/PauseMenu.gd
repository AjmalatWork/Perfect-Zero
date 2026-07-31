extends Control
class_name PauseMenu

# Pause overlay, works in both Campaign and Endless. Uses get_tree().paused to
# freeze everything (timers + tick audio + Endless spawning). This node runs with
# PROCESS_MODE_ALWAYS so it stays interactive while the rest of the tree is frozen.

# Authored (inset-free) position; _apply_safe_area() offsets from this.
# Authored (inset-free) corner position; _apply_safe_area() offsets from this.
# A function rather than a const now that the canvas it hangs off transposes.
func _pause_button_pos() -> Vector2:
	return Vector2(Layout.canvas_size.x - 92, 28)
const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GREY := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")

@export var campaign_navigator: CampaignNavigator
@export var endless_runner: EndlessRunner

@export var help_bubble: HelpBubble

var _pause_button: Button
var _menu: Control
var _dim: ColorRect
var _center: CenterContainer
var _options: OptionsPanel
var _paused: bool = false
var _resuming: bool = false
var _menu_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100  # above all gameplay z_index usage (timer digits/signs peak at 20)
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	SafeArea.changed.connect(_apply_safe_area)
	Layout.changed.connect(_apply_canvas)
	if help_bubble != null:
		help_bubble.open_state_changed.connect(_on_help_bubble_open_state_changed)
	_apply_canvas()
	_update_pause_button_visibility(GameManager.current_state)

# Reflow only. Unlike the screens that rebuild on an orientation change, this
# one is a dim plus a centred button column and carries live paused state - a
# rebuild mid-pause would drop the menu out from under the player.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _menu != null:
		_menu.position = Vector2.ZERO
		_menu.size = Layout.canvas_size
	if _center != null:
		_center.size = Layout.canvas_size
	ScreenLayout.cover(_dim)
	_apply_safe_area()

# Top-right corner, immediately right of the Help icon - same cutout/rounded
# corner exposure, so it's inset the same way. Only the pause button needs
# this: the menu itself is a full-rect dim with centred content, which no
# inset can clip.
func _apply_safe_area() -> void:
	_pause_button.position = _pause_button_pos() + Vector2(-SafeArea.right, SafeArea.top)

func _on_state_changed(new_state: int) -> void:
	_update_pause_button_visibility(new_state)

func _on_help_bubble_open_state_changed() -> void:
	_update_pause_button_visibility(GameManager.current_state)

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

	# The icon fades back in across the same beat the menu fades out, rather
	# than staying hidden for the entire wipe and popping in only once it's
	# fully finished - that made the icon's return read as a stall on top of
	# the wipe itself instead of part of the same motion. Safe to reveal this
	# early: a stray click on it mid-wipe still hits pause()'s own `_paused`
	# guard and silently no-ops until this function actually finishes below.
	_pause_button.visible = _in_game()
	_pause_button.modulate.a = 0.0
	var icon_tween := create_tween()
	icon_tween.tween_property(_pause_button, "modulate:a", 1.0, Juice.RESUME_WIPE_SEC)

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
	_pause_button.position = _pause_button_pos()
	_pause_button.pressed.connect(pause)
	add_child(_pause_button)
	_build_pause_icon(_pause_button)

	# Pause menu (dim + buttons), hidden until paused.
	_menu = Control.new()
	_menu.position = Vector2.ZERO
	_menu.size = Layout.canvas_size
	_menu.visible = false
	add_child(_menu)

	# Raised from 0.82 - the live board behind this is bright, glowing timer
	# digits, not a static backdrop, and at 0.82 they read clearly enough to
	# compete with the tertiary row's own borderless buttons (see _button()'s
	# TERTIARY case below, which also got a touch more backing for the same
	# reason).
	_dim = ColorRect.new()
	var dim := _dim
	dim.position = Layout.overscan_position
	dim.size = Layout.overscan_size
	dim.color = Color(0.02, 0.02, 0.04, 0.93)
	_menu.add_child(dim)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = Layout.canvas_size
	_center = center
	_menu.add_child(center)

	# Separation left at 0 - every gap in this column is an explicit _spacer()
	# instead, so the actual pixel gap between two children is exactly the
	# spacer's height rather than a container separation plus a spacer stacked
	# on top of it. That's what makes the tier groupings below (small gap
	# within a choice, bigger gap between tiers) land as the values actually
	# written, not some compounded total.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_heading("PAUSED", 64, NEON))
	col.add_child(_spacer(28))

	# Three tiers by how central each choice is to why this menu is open at
	# all, not four equal buttons: RESUME is the entire reason to pause, so it
	# gets the loudest treatment. RESTART is a real, deliberate choice but not
	# the default path - same cyan family as RESUME (matching RETRY's colour
	# everywhere else in the game, rather than gold, which now specifically
	# means "the outcome" elsewhere and had no business describing a restart).
	# OPTIONS and BACK TO TITLE don't touch the run at all - both are "go
	# somewhere else" detours - so they're demoted into one small, quiet row.
	col.add_child(_menu_button("RESUME", NEON, resume, Emphasis.PRIMARY, 32, Vector2(380, 84), true))
	col.add_child(_spacer(36))
	col.add_child(_menu_button("RESTART", NEON, _on_restart, Emphasis.SECONDARY, 28, Vector2(320, 68)))
	col.add_child(_spacer(36))

	var detour_row := HBoxContainer.new()
	detour_row.alignment = BoxContainer.ALIGNMENT_CENTER
	detour_row.add_theme_constant_override("separation", 20)
	var options_btn := _button("OPTIONS", NEON, Emphasis.TERTIARY, 22, Vector2(190, 54))
	options_btn.pressed.connect(_open_options)
	_menu_buttons.append(options_btn)
	detour_row.add_child(options_btn)
	var title_btn := _button("BACK TO TITLE", GREY, Emphasis.TERTIARY, 22, Vector2(190, 54))
	title_btn.pressed.connect(_on_title)
	_menu_buttons.append(title_btn)
	detour_row.add_child(title_btn)
	col.add_child(detour_row)

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

func _menu_button(text: String, accent: Color, handler: Callable, emphasis: int = Emphasis.PRIMARY,
		font_size: int = 28, min_size: Vector2 = Vector2(340, 68), glow: bool = false) -> Control:
	var b := _button(text, accent, emphasis, font_size, min_size, glow)
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

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# Rank within the menu, expressed as weight rather than hue - the same
# language StageResultScreen's own Emphasis enum uses. PRIMARY is a solid lit
# panel, SECONDARY the same accent with the fill and glow taken away, TERTIARY
# is bare text that only becomes a button under the cursor. All three keep the
# accent, so RESUME/RESTART still read as one cyan family despite the weight
# difference.
enum Emphasis { PRIMARY, SECONDARY, TERTIARY }

# `glow` is separate from `emphasis` rather than implied by PRIMARY, since
# _button() also builds the corner pause icon (called with every other
# argument left at its default) - that one predates this tier system and was
# never meant to pick up RESUME's new shadow along with it.
func _button(text: String, accent: Color, emphasis: int = Emphasis.PRIMARY,
		font_size: int = 28, min_size: Vector2 = Vector2(340, 68), glow: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	PressFeedback.apply(button)

	match emphasis:
		Emphasis.SECONDARY:
			button.add_theme_font_size_override("font_size", font_size)
			button.add_theme_color_override("font_color", accent.lerp(TEXT_FILL, 0.5))
			button.add_theme_constant_override("outline_size", 0)
			button.add_theme_stylebox_override("normal", _box(accent, 0.93, 0.0, 2, 0.55))
			button.add_theme_stylebox_override("hover", _box(accent, 0.82, 0.3, 2, 0.9))
			button.add_theme_stylebox_override("pressed", _box(accent, 0.72, 0.25, 2, 0.9))
		Emphasis.TERTIARY:
			button.add_theme_font_size_override("font_size", font_size)
			button.add_theme_color_override("font_color", accent)
			button.add_theme_color_override("font_hover_color", TEXT_FILL)
			button.add_theme_color_override("font_pressed_color", TEXT_FILL)
			button.add_theme_constant_override("outline_size", 0)
			# darken just under 1.0 (not 1.0) - still no border and still reads
			# as bare text rather than a boxed button, but gives OPTIONS/BACK TO
			# TITLE a faint near-black plate of their own to sit on. At fully
			# transparent (1.0) these two had nothing behind them but the dim
			# overlay, and the bright board underneath was winning that fight.
			button.add_theme_stylebox_override("normal", _box(accent, 0.95, 0.0, 0))
			button.add_theme_stylebox_override("hover", _box(accent, 0.85, 0.0, 0))
			button.add_theme_stylebox_override("pressed", _box(accent, 0.78, 0.0, 0))
		_:
			button.add_theme_font_size_override("font_size", font_size)
			button.add_theme_color_override("font_color", Color.WHITE)
			button.add_theme_color_override("font_outline_color", accent)
			button.add_theme_constant_override("outline_size", 4)
			# Glow only when asked for (RESUME) - the same idiom the title
			# screen's own primary buttons use, to make it the loudest thing on
			# screen. The plain corner pause icon stays exactly as it looked
			# before this tier system existed.
			var shadow: float = 0.35 if glow else 0.0
			var shadow_hover: float = 0.5 if glow else 0.0
			var shadow_pressed: float = 0.4 if glow else 0.0
			button.add_theme_stylebox_override("normal", _box(accent, 0.85, shadow, 3, 1.0, 8))
			button.add_theme_stylebox_override("hover", _box(accent, 0.7, shadow_hover, 3, 1.0, 12))
			button.add_theme_stylebox_override("pressed", _box(accent, 0.6, shadow_pressed, 3, 1.0, 6))

	return button

# `darken` of 1.0 plus a 0-alpha border is what makes a flat, invisible box for
# the tertiary state - content margins still apply, so the label keeps the
# same padding as a real button and the row doesn't shift on hover.
func _box(accent: Color, darken: float, shadow_alpha: float = 0.0, border_width: int = 3,
		border_alpha: float = 1.0, shadow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.darkened(darken), 0.0 if darken >= 1.0 else 1.0)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(border_width)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.0 if border_width == 0 else border_alpha)
	sb.set_content_margin_all(10)
	if shadow_alpha > 0.0:
		sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2.ZERO
	return sb
