extends Control
class_name PowerupBar

# The three Endless powerup buttons, kept together as one control cluster rather
# than split across both sides of the board. Built procedurally like every other
# screen in this project.
#
# Landscape: a column in the left margin. The 3x3 grid is 3*160 + 2*14 = 508px
# centred in the 1600x900 canvas, so it spans x 546..1054 and this column sits
# clear of it.
#
# Portrait: that margin doesn't exist - the grid is 640 wide in a 900 canvas
# (x 130..770) - so the column becomes a row below the grid instead. That also
# puts the board and the powerups both inside one-handed thumb reach, which the
# landscape layout never had to solve for.
const LANDSCAPE_BUTTON_SIZE := Vector2(116, 116)
const PORTRAIT_BUTTON_SIZE := Vector2(140, 140)   # 46dp -> 56dp, clearing the 48dp minimum

# Ordered SHIELD, CLEAR_ALL, OVERCLOCK - see _build().
const LANDSCAPE_POSITIONS: Array[Vector2] = [
	Vector2(220, 322), Vector2(220, 462), Vector2(220, 602),
]
# 3*140 + 2*40 = 500 wide, centred in 900. Sat below PORTRAIT_GRID_ZONE, which
# ends at y 1100.
const PORTRAIT_POSITIONS: Array[Vector2] = [
	Vector2(200, 1150), Vector2(380, 1150), Vector2(560, 1150),
]

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Layout.changed.connect(_build)
	Powerups.state_changed.connect(_on_state_changed)
	Powerups.shield_absorbed.connect(_on_shield_absorbed)

# Rebuilt wholesale on an orientation flip rather than repositioned: the button
# scales its own internals off its height (see PowerupButton.configure), so a
# size change has to go back through configure() anyway.
func _build() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()

	size = Layout.canvas_size
	var portrait := Layout.is_portrait()
	var positions: Array[Vector2] = PORTRAIT_POSITIONS if portrait else LANDSCAPE_POSITIONS
	var button_size: Vector2 = PORTRAIT_BUTTON_SIZE if portrait else LANDSCAPE_BUTTON_SIZE

	_add_button(PowerupSystem.Kind.SHIELD, positions[0], button_size)
	_add_button(PowerupSystem.Kind.CLEAR_ALL, positions[1], button_size)
	_add_button(PowerupSystem.Kind.OVERCLOCK, positions[2], button_size)

func _add_button(kind: int, pos: Vector2, button_size: Vector2) -> void:
	var btn := PowerupButton.new()
	btn.position = pos
	btn.size = button_size
	btn.configure(kind)
	add_child(btn)
	_buttons.append(btn)
	# Registered once per build, at the identity transform - activation effects
	# are parented under the same node Juice punches/shakes, so both move together
	# and the origin stays correct without re-registering every frame. A rebuild
	# (orientation flip) re-registers, so the effects follow the buttons.
	Powerups.register_button_origin(kind, btn.global_position + button_size * 0.5)

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
	# Every measurement below is authored against this height and multiplied by
	# _s, the ratio the button was actually built at. Portrait uses a bigger
	# button to clear the 48dp touch minimum, and without this the icon, labels
	# and cooldown ring would all stay pinned to their landscape offsets inside a
	# taller panel.
	const BASE_HEIGHT := 116.0

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
	var _s: float = 1.0

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
		# size is assigned by _add_button before this runs, so the ratio is known.
		_s = size.y / BASE_HEIGHT

		_style = StyleBoxFlat.new()
		_style.bg_color = accent.darkened(0.86)
		_style.set_corner_radius_all(roundi(18 * _s))
		_style.set_border_width_all(3)
		_style.border_color = accent
		_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
		_style.shadow_size = 12
		_style.shadow_offset = Vector2.ZERO

		# A child node, so it draws *after* (above) this control's own _draw().
		# The panel background is drawn in _draw() rather than as a child Panel
		# for the same reason - a child background would paint over the icon.
		_icon = PowerupIcon.new(kind)
		_icon.size = ICON_SIZE * _s
		_icon.position = Vector2((size.x - _icon.size.x) * 0.5, ICON_TOP * _s)
		add_child(_icon)

		_name_label = _make_label(roundi(15 * _s), accent)
		_name_label.text = PowerupSystem.name_of(kind).to_upper()
		_name_label.position = Vector2(0, 86 * _s)
		_name_label.size = Vector2(size.x, 20 * _s)
		add_child(_name_label)

		# Omitted entirely on mobile - PowerupSystem.key_hint() returns "" there,
		# and an empty label would still reserve a visibly blank line above the icon.
		var hint := PowerupSystem.key_hint(kind)
		if not hint.is_empty():
			var key_label := _make_label(roundi(14 * _s), Color(1, 1, 1, 0.5))
			key_label.text = hint
			key_label.position = Vector2(0, 2 * _s)
			key_label.size = Vector2(size.x, 18 * _s)
			add_child(key_label)

		# Sits over the icon during a cooldown, blank otherwise.
		_cd_label = _make_label(roundi(34 * _s), Color.BLACK)
		_cd_label.position = Vector2(0, 38 * _s)
		_cd_label.size = Vector2(size.x, 44 * _s)
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
			draw_arc(centre, RING_RADIUS * _s, 0.0, TAU, 48, Color(1, 1, 1, 0.08),
				RING_WIDTH * _s, true)
			var swept := (1.0 - cd_frac) * TAU
			if swept > 0.0:
				draw_arc(centre, RING_RADIUS * _s, -PI * 0.5, -PI * 0.5 + swept, 48,
					Color(accent.r, accent.g, accent.b, 0.85), RING_WIDTH * _s, true)
		elif active_frac > 0.0:
			# Depletion bar: full width at the start of the window, shrinking to
			# nothing as it closes. Centred so it collapses inward rather than
			# draining off one side.
			var track := Rect2(DEPLETION_INSET * _s, size.y - DEPLETION_BOTTOM * _s,
				size.x - DEPLETION_INSET * _s * 2.0, DEPLETION_HEIGHT * _s)
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
