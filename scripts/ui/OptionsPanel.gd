extends Control
class_name OptionsPanel

# Reusable options UI. Used two ways:
#  - as a full screen from Title (standalone = true -> Back returns to MENU)
#  - as an overlay from the Pause menu (standalone = false -> Back just emits closed)

signal closed

const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GOLD := Color("ffd23f")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")
const MUTED := Color("8b90a8")

# Scales type and control footprints only - it no longer sets the screen's width.
# It used to: under the old label-left/control-right layout the binding constraint
# was the widest row (360 label + 20 + 320 slider = 700 raw), which at 1.4 came to
# 980 against a 900-unit canvas and ran off both edges on device, forcing 1.2.
# The single-column layout took that constraint away entirely - width is now set
# by _content_width() against the canvas directly, independent of this - so this
# is free to change on type-size grounds alone.
const PORTRAIT_SCALE := 1.2

# Touch targets. 1 canvas unit = 0.4dp, so Android's 48dp minimum is 120 units
# and the 56dp it recommends for a primary action is 140. At PORTRAIT_SCALE
# these come out of raw 100 and 120 respectively - different raw numbers to the
# Help screen's 80/96 only because that screen scales by 1.5, not 1.2; both land
# on the same dp.
#
# Measured on this screen before this pass: the two sliders and the checkbox
# were 14.4dp - the most-used controls here and the smallest things on the
# screen - and every button was 30.7dp. All under the minimum.
const TOUCH_MIN := 100.0    # x1.2 = 120 units = 48dp
const TOUCH_BACK := 120.0   # x1.2 = 144 units = 57.6dp, matching HelpScreen's BACK

# Body text. _fs(26) measured 12.5dp, under the 14sp floor for body copy; 30
# lands at 14.4dp. Each label now owns a full-width line of its own rather than a
# 360-unit cell beside its control, so there is no longer a width ceiling on it.
# Bumped by a lot (30 -> 42) on a further user request, matching the same pass
# applied to Stage Result/Endless End/Pause/Title/tutorial screens.
const FIELD_LABEL_SIZE := 42

# Uppercase eyebrows over each group. Deliberately below body size - the
# hierarchy here is carried by colour and case, not scale - and deliberately
# MUTED rather than gold: this project reserves gold for outcomes and records,
# and spending it on group scaffolding is the same mistake the Scores table
# header was making.
const SECTION_LABEL_SIZE := 36
# The one-line explanation under a toggle. "Reduce screen effects" said nothing
# about what it actually does, which is kill screen shake, camera punch,
# hit-stop and full-screen flashes outright for motion sensitivity.
const SUBTITLE_SIZE := 36

# Absolute canvas units, deliberately NOT multiplied by _s(): this is a width
# budget against a fixed-width canvas, so scaling it would just re-introduce the
# overflow the scale factor exists to avoid. Portrait spends nearly the whole
# 900-unit canvas (40 either side) now that nothing sits beside the controls;
# landscape stays a centred column rather than stretching a slider across 1600
# units, which is neither readable nor pleasant to drag.
func _content_width() -> float:
	return 820.0 if Layout.is_portrait() else 700.0

# The touch padding is portrait-only. Landscape is desktop/web with a mouse,
# where an invisible hit area three times taller than the slider it wraps would
# only make stray clicks near the row start dragging it.
func _touch_pad() -> bool:
	return Layout.is_portrait()

# The dp floors are portrait-only, the same split ScoresScreen already uses:
# landscape is desktop/web with a mouse, where they do not apply - and it is the
# tight axis on a stacked screen, so spending 100 units on a button there buys
# nothing and costs layout. Measured, applying them to both overflowed landscape.
const BUTTON_HEIGHT_LANDSCAPE := 64.0

func _button_h() -> float:
	return TOUCH_MIN if Layout.is_portrait() else BUTTON_HEIGHT_LANDSCAPE

func _back_h() -> float:
	return TOUCH_BACK if Layout.is_portrait() else BUTTON_HEIGHT_LANDSCAPE

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

@export var standalone: bool = false  # true when used as a Title screen

var _confirm_overlay: Control
var _backdrop: ColorRect
var _center: CenterContainer
var _built_portrait: bool = false

func _ready() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so it works as an overlay too
	_build()
	Layout.changed.connect(_apply_canvas)
	# Deferred, not called directly, only for this first call: a Control's size
	# setter always clamps up to its current get_combined_minimum_size(), and on
	# the very first synchronous frame - before any Container has run its own
	# (also-deferred) sort_children pass even once - an AUTOWRAP_WORD_SMART
	# label's width is still 0, so its wrap-height computation degenerates to a
	# huge placeholder value instead of the real ~2-line height. That bogus
	# number gets baked into _center's size right here and nothing ever shrinks
	# it back down afterward, which is exactly the symptom reported on-device: a
	# ~350dp dead zone above the title with the bottom of the panel clipped off
	# screen. Deferring this one call runs it after every add_child() queued
	# during _build() has had its own deferred sort resolve real widths, so the
	# label's minimum height is already correct by the time this reads it.
	call_deferred("_apply_canvas")

# A plain resize is a re-measure; an orientation change is a rebuild, because
# _s() feeds every font size and a Label's font size is fixed once created.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _center != null:
		_center.size = Layout.canvas_size
	_apply_overscan()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_center = null
	_confirm_overlay = null
	_build()
	_apply_overscan()

func _apply_overscan() -> void:
	ScreenLayout.cover_all([_backdrop, _confirm_overlay])

func _build() -> void:
	_built_portrait = Layout.is_portrait()

	_backdrop = ColorRect.new()
	_backdrop.position = Layout.overscan_position
	_backdrop.size = Layout.overscan_size
	_backdrop.color = Color(0.03, 0.03, 0.05, 0.96)
	add_child(_backdrop)

	_center = CenterContainer.new()
	_center.position = Vector2.ZERO
	_center.size = Layout.canvas_size
	add_child(_center)

	# Every gap on this screen is an explicit spacer and the containers'
	# separation is zeroed. A container separation PLUS spacer children between
	# the same items double-counts every gap - the bug already hit and fixed on
	# EndlessEndScreen, PauseMenu and CreditsScreen - so the pixel value written
	# here is the actual pixel gap.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.custom_minimum_size = Vector2(_content_width(), 0)
	_center.add_child(outer)

	var title := WaveHeading.new()
	outer.add_child(title)
	title.configure("OPTIONS", _fs(72), TEXT_FILL, NEON)
	outer.add_child(_gap(18))

	# The settings sit on a panel rather than floating on the backdrop, so each
	# group reads as a bounded block instead of a loose stack of rows.
	var card := _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	col.add_child(_section_label("AUDIO"))
	col.add_child(_gap(8))
	col.add_child(_rule(0.22))
	col.add_child(_gap(14))

	# Two independent sliders on two separate audio buses. The SFX one is the
	# original "Volume" control, relabelled - its saved key is unchanged, so
	# existing players keep the level they set.
	var sfx_slider := NeonSlider.new()
	sfx_slider.scale_by(_s(), _touch_pad())
	sfx_slider.value = Settings.volume
	sfx_slider.value_changed.connect(func(v): Settings.set_volume(v))
	col.add_child(_field("SFX volume", sfx_slider))

	col.add_child(_gap(12))
	col.add_child(_rule(0.12))
	col.add_child(_gap(12))

	var music_slider := NeonSlider.new()
	music_slider.scale_by(_s(), _touch_pad())
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(func(v): Settings.set_music_volume(v))
	col.add_child(_field("Music volume", music_slider))

	col.add_child(_gap(26))
	col.add_child(_section_label("DISPLAY"))
	col.add_child(_gap(8))
	col.add_child(_rule(0.22))

	# Reduce screen effects - turns off screen shake, camera punch, hit-stop and
	# every full-screen flash or wash outright (scaling those down still shakes
	# and still flashes). Localized effects, the powerup state overlays and audio
	# are left alone.
	var reduce := NeonToggle.new()
	reduce.scale_by(_s())
	reduce.set_initial(Settings.reduce_intensity)
	reduce.toggled.connect(func(on): Settings.set_reduce_intensity(on))
	col.add_child(_toggle_field("Reduce effects",
		"Fewer particles, no screen shake", reduce))

	# Dev-only test override - never present in a release export. Cycles
	# OFF -> PERFECT -> GOOD -> OFF; while non-OFF, every click on any timer
	# grades as that grade instead of its real timing, for testing scoring/UI
	# reactions without needing precise clicks.
	if OS.is_debug_build():
		col.add_child(_rule(0.12))
		var dev_cycle := _button(_dev_grade_label(Settings.dev_force_grade), GOLD)
		dev_cycle.custom_minimum_size = Vector2(200, _button_h()) * _s()
		dev_cycle.pressed.connect(func():
			Settings.set_dev_force_grade(_next_dev_grade(Settings.dev_force_grade))
			dev_cycle.text = _dev_grade_label(Settings.dev_force_grade))
		col.add_child(_gap(12))
		col.add_child(_field("Dev: force grade", dev_cycle, false))

	col.add_child(_gap(26))
	col.add_child(_section_label("DATA"))
	col.add_child(_gap(8))
	col.add_child(_rule(0.22))
	col.add_child(_gap(14))

	var reset := _button("RESET SAVE DATA", RED)
	reset.pressed.connect(_on_reset_pressed)
	col.add_child(_wrap(reset))

	# Back stays bottom-centred at the size every other screen's BACK uses,
	# rather than becoming a top-left arrow: six screens share that treatment,
	# and the top-left corner is the hardest place on a phone to reach one-handed
	# for the control a player uses most on this screen.
	outer.add_child(_gap(18))
	var back := _button("BACK", BACK_ACCENT)
	back.custom_minimum_size = Vector2(200, _back_h()) * _s()
	back.pressed.connect(_on_back)
	outer.add_child(_wrap(back))

	_build_confirm_overlay()
# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape. Two OptionsPanel instances exist in the tree at once - the standalone
# title-screen one and the pause menu's overlay copy - so this has to work out
# which (if either) is actually live before answering a press.
#
# Ownership is deliberately split with PauseMenu rather than duplicated: the
# overlay copy is a *child* of PauseMenu, and _unhandled_input runs children
# first, so this gets first refusal on the press and hands the rest back.
#   - Confirm prompt open (either mode): this closes the prompt and consumes
#     the press, so back can never blow past a destructive "erase everything?"
#     step straight out of the panel.
#   - Otherwise, standalone: closes the panel via the same _on_back() the
#     on-screen BACK button uses.
#   - Otherwise, overlay mode: deliberately left unconsumed for PauseMenu's own
#     handler, which already owns closing options back to the pause menu.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if standalone:
		if GameManager.current_state != GameManager.GameState.OPTIONS:
			return
	elif not visible:
		return

	if _confirm_overlay.visible:
		_confirm_overlay.visible = false
		get_viewport().set_input_as_handled()
		return

	if standalone:
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	closed.emit()
	if standalone:
		GameManager.set_state(GameManager.GameState.MENU)

# --- Reset confirmation ---------------------------------------------------

func _on_reset_pressed() -> void:
	_confirm_overlay.visible = true

func _build_confirm_overlay() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.position = Layout.overscan_position
	_confirm_overlay.size = Layout.overscan_size
	_confirm_overlay.color = Color(0, 0, 0, 0.75)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(20))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_heading("Are you sure?", _fs(52), RED))
	# Wrapped rather than leaning on the hard newline alone: at the larger body
	# size the first sentence no longer fits one line on a 900-unit portrait
	# canvas, and an unwrapped Label would just run off both edges.
	var warning := _line("This erases all high scores, progress, and settings.\nThis can't be undone.",
		_fs(FIELD_LABEL_SIZE))
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(700 * _s(), 0)
	col.add_child(warning)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _fs(24))
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

# --- layout helpers ---------------------------------------------------------

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.082, 0.105, 1.0)
	sb.set_corner_radius_all(roundi(18 * _s()))
	sb.set_border_width_all(maxi(roundi(_s()), 1))
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_content_margin_all(_fs(20) if Layout.is_portrait() else 12)
	card.add_theme_stylebox_override("panel", sb)
	return card

# Every gap is written as a portrait value. Landscape is the SHORTER canvas here
# (900 against portrait's 1600), so the same raw number eats about 1.5x as much
# of it - measured, the portrait rhythm overflowed landscape by 136 units. This
# is the same trap the Scores screen hit: on a stacked screen, landscape is the
# tight axis, not the roomy one.
func _gap_scale() -> float:
	return _s() if Layout.is_portrait() else 0.55

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h * _gap_scale())
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _rule(alpha: float) -> Control:
	var line := ColorRect.new()
	line.color = Color(MUTED.r, MUTED.g, MUTED.b, alpha)
	line.custom_minimum_size = Vector2(0, maxf(_s(), 1.0))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _section_label(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE))
	l.add_theme_color_override("font_color", MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A toggle is a row, not a stacked block: label and its explanation on the left,
# the switch on the right. Sliders stack because they need the full width to be
# draggable; a switch does not, and putting it inline is what mobile settings
# screens do.
#
# The whole row is the target, not just the switch - which is what makes this
# comfortably clear 48dp even though the switch itself is smaller than that.
func _toggle_field(label_text: String, subtitle: String, toggle: NeonToggle) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.focus_mode = Control.FOCUS_ALL
	if Layout.is_portrait():
		row.custom_minimum_size = Vector2(0, TOUCH_MIN * _s())
	var sb := StyleBoxEmpty.new()
	sb.content_margin_top = _fs(10)
	sb.content_margin_bottom = _fs(10)
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", _fs(16))
	row.add_child(h)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", _fs(2))
	h.add_child(texts)

	var l := _line(label_text, _fs(FIELD_LABEL_SIZE))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(l)

	if not subtitle.is_empty():
		var sub := _line(subtitle, _fs(SUBTITLE_SIZE))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sub.add_theme_color_override("font_color", MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(sub)

	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(toggle)

	# Release rather than press, matching every other tap handler in this
	# project, so a drag that starts on the row does not flip the setting.
	row.gui_input.connect(func(event: InputEvent) -> void:
		var released: bool = (event is InputEventMouseButton 				and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) 			or (event is InputEventScreenTouch and not event.pressed)
		if released:
			toggle.toggle()
			row.accept_event()
		elif event.is_action_pressed("ui_accept") and row.has_focus():
			toggle.toggle()
			row.accept_event())
	return row

func _dev_grade_label(value: String) -> String:
	return value if value != "" else "OFF"

func _next_dev_grade(value: String) -> String:
	match value:
		"":
			return "PERFECT"
		"PERFECT":
			return "GOOD"
		_:
			return ""

# One setting per full-width block, label above its own control, rather than the
# old label-left / control-right pair.
#
# Two columns were what pinned this screen's width: the label cell (360) plus the
# slider (320) came to 840 of a 900-unit portrait canvas with 30 units either
# side and nothing to spare, and the slider was squeezed into well under half the
# screen while the label sat in dead space beside it. Stacking hands the control
# the whole column, which is both the mobile-settings convention and a much wider
# drag target on the one control that needs one.
#
# `fill` is off only for controls that shouldn't stretch to the full column - the
# dev grade cycler, which is a plain button and reads as broken at 820 wide.
func _field(label_text: String, control: Control, fill: bool = true) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", _fs(8))
	# _line() already centres; the old two-column version was the thing overriding
	# it to left-aligned.
	var l := _line(label_text, _fs(FIELD_LABEL_SIZE))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(l)
	if fill:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_child(control)
	else:
		var wrap := CenterContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_child(control)
		block.add_child(wrap)
	return block

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
	button.custom_minimum_size = Vector2(240, _button_h()) * _s()
	# Bumped by a lot (28 -> 38 base, ~46 effective at this screen's 1.2 scale)
	# on a further user request, matching the other redesigned buttons.
	button.add_theme_font_size_override("font_size", _fs(38))
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

# An on/off switch rather than a checkbox, for two reasons. A checkbox states
# its value only by whether a small mark is present, which is the weakest signal
# available on a dark panel; and the box this replaces drew at 21dp inside a
# full-width row, reading as unfinished next to sliders that visually fill their
# line. A pill switch states its value by position AND colour, and carries the
# same visual weight as a slider.
#
# Godot's built-in CheckBox/CheckButton draw their states as faint default-theme
# icons tuned for a light editor background - on this project's near-black panels
# the unchecked state was effectively invisible, which is the same reason the
# slider below is hand-drawn too.
#
# Input is owned by the row (see _toggle_field), not by this control, so the
# whole row is the touch target - hence MOUSE_FILTER_IGNORE here.
class NeonToggle extends Control:
	const SIZE := Vector2(78, 42)
	const ACCENT := Color("22d3ff")
	const OFF_TRACK := Color("3a4050")

	signal toggled(on: bool)

	var checked: bool = false

	var _scale: float = 1.0
	# Visual position of the knob, 0 = off. Kept separate from `checked` so the
	# knob can slide between them instead of the state snapping the drawing.
	var _knob_t: float = 0.0
	var _tween: Tween

	# Called before the control is parented - see NeonSlider.scale_by.
	func scale_by(s: float) -> void:
		_scale = s
		custom_minimum_size = SIZE * s
		size = custom_minimum_size
		queue_redraw()

	func _ready() -> void:
		custom_minimum_size = SIZE * _scale
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	# Settles at a state without animating - for the value loaded from Settings.
	func set_initial(on: bool) -> void:
		checked = on
		_knob_t = 1.0 if on else 0.0
		queue_redraw()

	func toggle() -> void:
		checked = not checked
		var target: float = 1.0 if checked else 0.0
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if is_inside_tree():
			_tween = create_tween()
			_tween.tween_method(_set_knob, _knob_t, target, 0.16) 				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			_set_knob(target)
		toggled.emit(checked)

	func _set_knob(v: float) -> void:
		_knob_t = v
		queue_redraw()

	# draw_rect has no corner radius, so the pill is two end circles plus the bar
	# between them - exact at any scale, and cheaper than a StyleBox round-trip.
	func _pill(rect: Rect2, col: Color) -> void:
		var r: float = rect.size.y * 0.5
		var cy: float = rect.position.y + r
		draw_circle(Vector2(rect.position.x + r, cy), r, col)
		draw_circle(Vector2(rect.position.x + rect.size.x - r, cy), r, col)
		draw_rect(Rect2(rect.position.x + r, rect.position.y,
			rect.size.x - r * 2.0, rect.size.y), col, true)

	func _draw() -> void:
		var box := SIZE * _scale
		# Centred in whatever the row gave this control, not pinned top-left.
		var origin := (size - box) * 0.5
		var border: float = 3.0 * _scale

		# Outer pill doubles as the border: drawn full size in the border colour,
		# then the fill inset by `border`.
		_pill(Rect2(origin, box), OFF_TRACK.lerp(ACCENT, _knob_t))
		_pill(Rect2(origin + Vector2(border, border), box - Vector2(border, border) * 2.0),
			Color(0.06, 0.07, 0.09).lerp(ACCENT.darkened(0.55), _knob_t))

		var r: float = box.y * 0.5
		var cy: float = origin.y + r
		var kr: float = r - border - 3.0 * _scale
		var kx: float = lerpf(origin.x + r, origin.x + box.x - r, _knob_t)
		# Same "soft wide disc under a solid bright one" glow the slider knob uses.
		if _knob_t > 0.01:
			draw_circle(Vector2(kx, cy), kr * 1.7,
				Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25 * _knob_t))
		draw_circle(Vector2(kx, cy), kr, Color.WHITE)

# Same reasoning as NeonToggle: the default HSlider's grip/track icons are
# tuned for a light theme and read as a near-invisible sliver against this
# project's dark panels. Drawn here instead - filled track, bright fill up to
# the value, and a glowing grip knob that's unmistakable at a glance.
class NeonSlider extends Control:
	const SIZE := Vector2(320, 30)
	# Hit height in portrait - see OptionsPanel.TOUCH_MIN. The track and knob keep
	# their own dimensions and centre inside it, so the control is 48dp tall to a
	# finger while looking exactly as it did before.
	const TOUCH_HEIGHT := 100.0
	const TRACK_HEIGHT := 8.0
	const KNOB_RADIUS := 11.0
	const ACCENT := Color("22d3ff")

	signal value_changed(v: float)

	var value: float = 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()

	var _dragging: bool = false
	var _scale: float = 1.0
	var _height: float = SIZE.y

	# SIZE.x is only a minimum now - the single-column layout stretches this to the
	# full content width, and both _draw and _set_from_x read `size` so the track,
	# the knob position and the value a click maps to all follow the real width
	# rather than the declared one.
	#
	# Called before the control is parented - see NeonToggle.scale_by.
	func scale_by(s: float, touch: bool = false) -> void:
		_scale = s
		_height = TOUCH_HEIGHT if touch else SIZE.y
		custom_minimum_size = Vector2(SIZE.x, _height) * s
		size = custom_minimum_size
		queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(SIZE.x, _height) * _scale
		size = custom_minimum_size
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
		var knob := KNOB_RADIUS * _scale
		var usable := size.x - knob * 2.0
		_set_value((x - knob) / maxf(usable, 0.0001))

	func _set_value(v: float) -> void:
		var snapped := snappedf(clampf(v, 0.0, 1.0), 0.05)
		if is_equal_approx(snapped, value):
			return
		value = snapped
		value_changed.emit(value)

	func _draw() -> void:
		var knob := KNOB_RADIUS * _scale
		var track := TRACK_HEIGHT * _scale
		var y := _height * _scale * 0.5
		var x0 := knob
		var x1 := size.x - knob
		var knob_x := lerpf(x0, x1, value)

		# Empty track, always visible regardless of value.
		draw_rect(Rect2(x0, y - track * 0.5, x1 - x0, track),
			Color(1, 1, 1, 0.08), true)
		# Filled portion up to the current value.
		if knob_x > x0:
			draw_rect(Rect2(x0, y - track * 0.5, knob_x - x0, track), ACCENT, true)

		# Glowing knob: a soft wide translucent disc under a solid bright one,
		# the same "shadow reads as neon glow" trick used on the timer panels.
		draw_circle(Vector2(knob_x, y), knob * 1.7, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25))
		draw_circle(Vector2(knob_x, y), knob, ACCENT)
		draw_circle(Vector2(knob_x, y), knob * 0.5, Color.WHITE)

