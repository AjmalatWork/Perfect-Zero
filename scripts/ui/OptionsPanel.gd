extends Control
class_name OptionsPanel

# Reusable options UI. Used two ways:
#  - as a full screen from Title (standalone = true -> Back returns to MENU)
#  - as an overlay from the Pause menu (standalone = false -> Back just emits closed)

signal closed

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")

@export var standalone: bool = false  # true when used as a Title screen

var _confirm_overlay: Control

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so it works as an overlay too
	_build()

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEWPORT_SIZE
	backdrop.color = Color(0.03, 0.03, 0.05, 0.96)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = VIEWPORT_SIZE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(620, 0)
	center.add_child(col)

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("OPTIONS", 56, TEXT_FILL, NEON)

	# Two independent sliders on two separate audio buses. The SFX one is the
	# original "Volume" control, relabelled - its saved key is unchanged, so
	# existing players keep the level they set.
	var sfx_slider := NeonSlider.new()
	sfx_slider.value = Settings.volume
	sfx_slider.value_changed.connect(func(v): Settings.set_volume(v))
	col.add_child(_field("SFX volume", sfx_slider))

	var music_slider := NeonSlider.new()
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(func(v): Settings.set_music_volume(v))
	col.add_child(_field("Music volume", music_slider))

	# Reduce screen effects - turns off screen shake, camera punch, hit-stop and
	# every full-screen flash or wash outright (scaling those down still shakes
	# and still flashes). Localized effects, the powerup state overlays and audio
	# are left alone.
	var reduce := NeonCheckBox.new()
	reduce.checked = Settings.reduce_intensity
	reduce.toggled.connect(func(on): Settings.set_reduce_intensity(on))
	col.add_child(_field("Reduce screen effects", reduce))

	# Reset save data.
	var reset := _button("RESET SAVE DATA", RED)
	reset.pressed.connect(_on_reset_pressed)
	col.add_child(_wrap(reset))

	# Back / close.
	var back := _button("BACK", GOLD)
	back.pressed.connect(_on_back)
	col.add_child(_wrap(back))

	_build_confirm_overlay()

func _on_back() -> void:
	closed.emit()
	if standalone:
		GameManager.set_state(GameManager.GameState.MENU)

# --- Reset confirmation ---------------------------------------------------

func _on_reset_pressed() -> void:
	_confirm_overlay.visible = true

func _build_confirm_overlay() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.position = Vector2.ZERO
	_confirm_overlay.size = VIEWPORT_SIZE
	_confirm_overlay.color = Color(0, 0, 0, 0.75)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_heading("Are you sure?", 40, RED))
	col.add_child(_line("This erases all high scores, progress, and settings.\nThis can't be undone.", 24))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var yes := _button("ERASE", RED)
	yes.pressed.connect(_on_confirm_reset)
	row.add_child(yes)
	var cancel := _button("CANCEL", NEON)
	cancel.pressed.connect(func(): _confirm_overlay.visible = false)
	row.add_child(cancel)

func _on_confirm_reset() -> void:
	SaveManager.clear_all()
	_confirm_overlay.visible = false

# --- Builders -------------------------------------------------------------

func _field(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := _line(label_text, 26)
	l.custom_minimum_size = Vector2(360, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(200, 0)
	wrap.add_child(control)
	row.add_child(wrap)
	return row

func _wrap(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _heading(text: String, font_size: int, accent: Color) -> Label:
	var l := _line(text, font_size)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _line(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 64)
	button.add_theme_font_size_override("font_size", 26)
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

# Godot's built-in CheckBox draws its box/check as faint default-theme icons
# tuned for a light editor background - on this project's near-black panels the
# unchecked box was effectively invisible. Same class of problem as the Web
# export's "tofu box" glyphs and the old Unicode pause icon: drawn here instead
# of left to a theme, so both states are always clearly legible.
class NeonCheckBox extends Control:
	const SIZE := Vector2(30, 30)
	const ACCENT := Color("22d3ff")

	signal toggled(on: bool)

	var checked: bool = false:
		set(v):
			checked = v
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size = SIZE
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle()
			accept_event()
		elif event.is_action_pressed("ui_accept") and has_focus():
			_toggle()

	func _toggle() -> void:
		checked = not checked
		toggled.emit(checked)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, SIZE)
		# Always-visible outline box, regardless of state.
		draw_rect(r, Color(1, 1, 1, 0.08), true)
		draw_rect(r, ACCENT, false, 3.0)
		if checked:
			var pad := 7.0
			draw_line(Vector2(pad, SIZE.y * 0.55), Vector2(SIZE.x * 0.42, SIZE.y - pad),
				ACCENT, 4.0, true)
			draw_line(Vector2(SIZE.x * 0.42, SIZE.y - pad), Vector2(SIZE.x - pad, pad),
				ACCENT, 4.0, true)

# Same reasoning as NeonCheckBox: the default HSlider's grip/track icons are
# tuned for a light theme and read as a near-invisible sliver against this
# project's dark panels. Drawn here instead - filled track, bright fill up to
# the value, and a glowing grip knob that's unmistakable at a glance.
class NeonSlider extends Control:
	const SIZE := Vector2(320, 30)
	const TRACK_HEIGHT := 8.0
	const KNOB_RADIUS := 11.0
	const ACCENT := Color("22d3ff")

	signal value_changed(v: float)

	var value: float = 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()

	var _dragging: bool = false

	func _ready() -> void:
		custom_minimum_size = SIZE
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_set_from_x(event.position.x)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from_x(event.position.x)
			accept_event()
		elif event.is_action_pressed("ui_left") and has_focus():
			_set_value(value - 0.05)
		elif event.is_action_pressed("ui_right") and has_focus():
			_set_value(value + 0.05)

	func _set_from_x(x: float) -> void:
		var usable := SIZE.x - KNOB_RADIUS * 2.0
		_set_value((x - KNOB_RADIUS) / maxf(usable, 0.0001))

	func _set_value(v: float) -> void:
		var snapped := snappedf(clampf(v, 0.0, 1.0), 0.05)
		if is_equal_approx(snapped, value):
			return
		value = snapped
		value_changed.emit(value)

	func _draw() -> void:
		var y := SIZE.y * 0.5
		var x0 := KNOB_RADIUS
		var x1 := SIZE.x - KNOB_RADIUS
		var knob_x := lerpf(x0, x1, value)

		# Empty track, always visible regardless of value.
		draw_rect(Rect2(x0, y - TRACK_HEIGHT * 0.5, x1 - x0, TRACK_HEIGHT),
			Color(1, 1, 1, 0.08), true)
		# Filled portion up to the current value.
		if knob_x > x0:
			draw_rect(Rect2(x0, y - TRACK_HEIGHT * 0.5, knob_x - x0, TRACK_HEIGHT),
				ACCENT, true)

		# Glowing knob: a soft wide translucent disc under a solid bright one,
		# the same "shadow reads as neon glow" trick used on the timer panels.
		draw_circle(Vector2(knob_x, y), KNOB_RADIUS * 1.7, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25))
		draw_circle(Vector2(knob_x, y), KNOB_RADIUS, ACCENT)
		draw_circle(Vector2(knob_x, y), KNOB_RADIUS * 0.5, Color.WHITE)
