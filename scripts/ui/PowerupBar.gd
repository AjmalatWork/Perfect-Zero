extends Control
class_name PowerupBar

# The three Endless powerup buttons, stacked in a column to the left of the
# board so they read as one control cluster instead of being split across both
# sides. Built procedurally like every other screen in this project.
#
# The 3x3 grid is 3*160 + 2*14 = 508px, centred in the 1600x900 canvas, so it
# spans x 546..1054 - this column sits clear of that, in the left margin.

const VIEWPORT_SIZE := Vector2(1600, 900)
const BUTTON_SIZE := Vector2(116, 116)

const COLUMN_X := 220.0
const SHIELD_POS := Vector2(COLUMN_X, 322)
const CLEAR_POS := Vector2(COLUMN_X, 462)
const OVERCLOCK_POS := Vector2(COLUMN_X, 602)

# Keyboard alternates to clicking. Handled as raw keycodes rather than InputMap
# actions so this needs no project.godot input wiring - the buttons are the
# primary affordance and these are a convenience.
const KEYS := {
	KEY_A: PowerupSystem.Kind.SHIELD,
	KEY_S: PowerupSystem.Kind.CLEAR_ALL,
	KEY_D: PowerupSystem.Kind.OVERCLOCK,
}

var _buttons: Array = []

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Powerups.state_changed.connect(_on_state_changed)
	Powerups.shield_absorbed.connect(_on_shield_absorbed)

func _build() -> void:
	_add_button(PowerupSystem.Kind.SHIELD, SHIELD_POS)
	_add_button(PowerupSystem.Kind.CLEAR_ALL, CLEAR_POS)
	_add_button(PowerupSystem.Kind.OVERCLOCK, OVERCLOCK_POS)

func _add_button(kind: int, pos: Vector2) -> void:
	var btn := PowerupButton.new()
	btn.position = pos
	btn.size = BUTTON_SIZE
	btn.configure(kind)
	add_child(btn)
	_buttons.append(btn)
	# Registered once, at the identity transform - activation effects are
	# parented under the same node Juice punches/shakes, so both move together
	# and the origin stays correct without re-registering every frame.
	Powerups.register_button_origin(kind, btn.global_position + BUTTON_SIZE * 0.5)

func _on_state_changed() -> void:
	for b in _buttons:
		b.refresh()

func _on_shield_absorbed(_origin: Vector2) -> void:
	for b in _buttons:
		if b.kind == PowerupSystem.Kind.SHIELD:
			b.play_absorb_flash()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not KEYS.has(event.keycode):
		return
	if Powerups.activate(KEYS[event.keycode]):
		get_viewport().set_input_as_handled()


# --- One button -------------------------------------------------------------

class PowerupButton extends Control:
	const RING_RADIUS := 52.0
	const RING_WIDTH := 6.0

	# Active-window depletion bar, sat just below the name label.
	const DEPLETION_INSET := 16.0
	const DEPLETION_HEIGHT := 5.0
	const DEPLETION_BOTTOM := 14.0

	const ICON_SIZE := Vector2(46, 46)
	const ICON_TOP := 26.0

	var kind: int = 0
	var accent: Color = Color.WHITE

	var _style: StyleBoxFlat
	var _icon: PowerupIcon
	var _name_label: Label
	var _cd_label: Label
	var _was_cooling: bool = false
	# Last idle snapshot this button actually redrew for. Powerups.state_changed
	# fires once for the whole bar whenever ANY of the three powerups moves, so
	# without this every button repaints on every tick of any one cooldown -
	# three redraws (plus three icon redraws) a frame for two buttons that are
	# just sitting there unchanged. Only meaningful while genuinely idle (not
	# cooling, not active): mid-cooldown/active state still refreshes every
	# call, since the ring/bar geometry is animating and has to.
	var _last_idle_ready: Variant = null

	func configure(p_kind: int) -> void:
		kind = p_kind
		accent = PowerupSystem.color_of(kind)
		mouse_filter = Control.MOUSE_FILTER_STOP

		_style = StyleBoxFlat.new()
		_style.bg_color = accent.darkened(0.86)
		_style.set_corner_radius_all(18)
		_style.set_border_width_all(3)
		_style.border_color = accent
		_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
		_style.shadow_size = 12
		_style.shadow_offset = Vector2.ZERO

		# A child node, so it draws *after* (above) this control's own _draw().
		# The panel background is drawn in _draw() rather than as a child Panel
		# for the same reason - a child background would paint over the icon.
		_icon = PowerupIcon.new(kind)
		_icon.position = Vector2((size.x - ICON_SIZE.x) * 0.5, ICON_TOP)
		_icon.size = ICON_SIZE
		add_child(_icon)

		_name_label = _make_label(15, accent)
		_name_label.text = PowerupSystem.name_of(kind).to_upper()
		_name_label.position = Vector2(0, 86)
		_name_label.size = Vector2(size.x, 20)
		add_child(_name_label)

		var key_label := _make_label(14, Color(1, 1, 1, 0.5))
		key_label.text = "[%s]" % PowerupSystem.key_of(kind)
		key_label.position = Vector2(0, 2)
		key_label.size = Vector2(size.x, 18)
		add_child(key_label)

		# Sits over the icon during a cooldown, blank otherwise.
		_cd_label = _make_label(34, Color.BLACK)
		_cd_label.position = Vector2(0, 38)
		_cd_label.size = Vector2(size.x, 44)
		_cd_label.visible = false
		add_child(_cd_label)

		refresh()

	func _make_label(font_size: int, outline: Color) -> Label:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", Color("dfe3ee"))
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func refresh() -> void:
		var ready_now := Powerups.can_activate(kind)
		var active := Powerups.is_active(kind)
		var cd := Powerups.cooldown_seconds(kind)
		var cooling := cd > 0.0

		# Idle and unchanged since the last redraw: nothing on this button would
		# paint any differently, so skip it - the pulse check below still needs
		# _was_cooling kept current regardless.
		if not active and not cooling and _last_idle_ready == ready_now:
			_was_cooling = false
			return
		if not active and not cooling:
			_last_idle_ready = ready_now
		else:
			_last_idle_ready = null  # invalidated - next idle frame must redraw once

		if active:
			# Running: full brightness plus a lifted glow, so an armed Shield or a
			# live Overclock is unmistakable at a glance.
			modulate = Color(1, 1, 1, 1)
			_style.border_color = Color.WHITE
			_style.shadow_size = 24
		elif ready_now:
			modulate = Color(1, 1, 1, 1)
			_style.border_color = accent
			_style.shadow_size = 12
		else:
			modulate = Color(1, 1, 1, 0.45)
			_style.border_color = accent.darkened(0.5)
			_style.shadow_size = 0

		_cd_label.visible = cd > 0.0
		if cd > 0.0:
			_cd_label.text = "%d" % ceili(cd)
		if _icon != null:
			_icon.icon_alpha = 0.3 if cd > 0.0 else 1.0

		# Coming off cooldown gets a pulse, so "ready again" is felt rather than
		# only noticed on inspection. Gated on ready_now (which is false while
		# disarmed) so the end-of-run reset, which also drops cd to zero, can't
		# fire three spurious pulses on the way out.
		if _was_cooling and not cooling and ready_now:
			play_ready_pulse()
		_was_cooling = cooling

		queue_redraw()

	func play_ready_pulse() -> void:
		pivot_offset = size * 0.5
		var pop := create_tween()
		pop.tween_property(self, "scale", Vector2(1.12, 1.12), 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		var glow := ColorRect.new()
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.color = Color(accent.r, accent.g, accent.b, 0.45)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		var fade := create_tween()
		fade.tween_property(glow, "color:a", 0.0, 0.3)
		fade.tween_callback(glow.queue_free)

		AudioManager.play_powerup_ready()

	func _draw() -> void:
		# Drawn here rather than as a child Panel: a node's own _draw() runs
		# *before* its children, so an opaque child background would paint over
		# the cooldown ring below.
		draw_style_box(_style, Rect2(Vector2.ZERO, size))

		var centre := size * 0.5
		var cd_frac := Powerups.cooldown_fraction(kind)
		var active_frac := Powerups.active_fraction(kind)

		# Different geometry, not just different colours: a radial ring reads as
		# "recharging", a horizontal bar as "running out". The same shape for
		# both would make "about to expire" and "still on cooldown" look alike
		# at a glance.
		if cd_frac > 0.0:
			# Recharge ring: grows back around the button as the cooldown runs
			# down, so "how much longer" is readable without reading the number.
			draw_arc(centre, RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.08),
				RING_WIDTH, true)
			var swept := (1.0 - cd_frac) * TAU
			if swept > 0.0:
				draw_arc(centre, RING_RADIUS, -PI * 0.5, -PI * 0.5 + swept, 48,
					Color(accent.r, accent.g, accent.b, 0.85), RING_WIDTH, true)
		elif active_frac > 0.0:
			# Depletion bar: full width at the start of the window, shrinking to
			# nothing as it closes. Centred so it collapses inward rather than
			# draining off one side.
			var track := Rect2(DEPLETION_INSET, size.y - DEPLETION_BOTTOM,
				size.x - DEPLETION_INSET * 2.0, DEPLETION_HEIGHT)
			draw_rect(track, Color(1, 1, 1, 0.10), true)
			var lit_w := track.size.x * active_frac
			draw_rect(Rect2(track.position.x + (track.size.x - lit_w) * 0.5,
				track.position.y, lit_w, track.size.y), Color(1, 1, 1, 0.92), true)

	func play_absorb_flash() -> void:
		var flash := ColorRect.new()
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.color = Color(1, 1, 1, 0.75)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flash)
		var tween := create_tween()
		tween.tween_property(flash, "color:a", 0.0, 0.35)
		tween.tween_callback(flash.queue_free)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			# A blocked or cooling powerup simply ignores the click (activate()
			# re-checks can_activate itself, so this can't fire early).
			Powerups.activate(kind)
			accept_event()
