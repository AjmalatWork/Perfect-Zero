extends Control
class_name HelpBubble

# In-game "?" reference bubble, top-right, live during both Arcade and Endless
# play. Content is pulled straight from TimerTypeInfo/PowerupSystem - the same
# tables the Help screen's legend already reads from - so nothing here is a
# second copy of that text. Arcade gets one page (timer types); Endless gets a
# second (powerups), paginated with the same PageNav the Help screen uses.
#
# Opening freezes gameplay clocks the same way Nuke's cascade does
# (Juice.freeze_gameplay/release_gameplay) - the dim's own full-rect
# MOUSE_FILTER_STOP is what actually blocks a click from reaching a live timer
# underneath; the freeze is what stops time silently advancing behind it.
# Closing uses the same shared wipe PauseMenu's RESUME uses (Juice.resume_wipe).

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")

# Sits left of PauseMenu's pause button with clearance, so the two never collide
# regardless of which is added to the tree first. Held as an inset from the right
# edge rather than the absolute 1428 it used to be: that is the landscape figure,
# and it would put the icon 500 units off the right edge of a 900-wide portrait
# canvas.
const ICON_RIGHT_INSET := 172.0
const ICON_SIZE := Vector2(64, 64)
# 64 units is 26dp - well under Android's 48dp minimum. Grown to 120 (48dp) in
# portrait only; landscape is desktop/web with a mouse, where dp minimums don't
# apply. The inset grows too, so the bigger icon still clears PauseMenu's own
# (also-grown) corner icon with the same gap the two kept in landscape.
const ICON_SIZE_PORTRAIT := Vector2(120, 120)
# Recomputed to keep the same 20-unit gap to PauseMenu's own icon now that
# PauseMenu's right margin grew from 24 to 32 (see PauseMenu.
# PAUSE_ICON_RIGHT_MARGIN_PORTRAIT's own comment - phone corner-curve
# clearance, a user request). PauseMenu's icon now spans x 748..868; this
# icon's right edge has to land 20 short of that (728), and this inset is
# measured to the icon's LEFT edge, so 900 - (728 - 120) = 292.
const ICON_RIGHT_INSET_PORTRAIT := 292.0
# Matches PauseMenu's own PAUSE_ICON_TOP_MARGIN_PORTRAIT so both icons sit on
# the same top edge - see that constant's comment for the phone corner-curve
# reasoning.
const ICON_TOP_MARGIN_PORTRAIT := 40.0

func _icon_size() -> Vector2:
	return ICON_SIZE_PORTRAIT if Layout.is_portrait() else ICON_SIZE

func _icon_right_inset() -> float:
	return ICON_RIGHT_INSET_PORTRAIT if Layout.is_portrait() else ICON_RIGHT_INSET

func _icon_top() -> float:
	return ICON_TOP_MARGIN_PORTRAIT if Layout.is_portrait() else 28.0

const BADGE_COLOR := Color("ffd23f")
const BADGE_PULSE_HZ := 1.6
const BADGE_SIZE := 16.0

# PauseMenu's own pause button visibility depends on is_open (see
# _update_pause_button_visibility there), which it can only re-check when
# told to - this is that notification.
signal open_state_changed

@export var stage_controller: StageController
@export var endless_runner: EndlessRunner

var is_open: bool = false

var _icon_button: Button
var _badge: Control
var _bubble: Control       # dim + panel, faded as one unit by resume_wipe
var _heading_label: Label
var _panel_pages: Array[Control] = []
var _dim: ColorRect
var _page_nav: PageNav
var _closing: bool = false

func _icon_pos() -> Vector2:
	return Vector2(Layout.canvas_size.x - _icon_right_inset(), _icon_top())


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact. Chosen from the measured content: the panel already measures 736 wide, so this only has 1.22x of headroom.
const PORTRAIT_SCALE := 1.15

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

func _ready() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90  # below PauseMenu (100), above ordinary gameplay (peaks at 20)
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	SafeArea.changed.connect(_apply_safe_area)
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()
	_update_icon_visibility(GameManager.current_state)

# The icon sits hard against the top-right corner, which in landscape is
# precisely where a camera cutout or a rounded corner lands - so its anchor is
# pulled in by whatever the display actually reports. The badge rides along,
# since it's positioned relative to the icon rather than parented to it.
# Displays with no insets (desktop, web, phones without cutouts) report zero
# and leave both exactly where they were authored.
#
# Reflow only - this overlay carries live open/closed state during play, so a
# rebuild on rotation would tear the panel out from under the player mid-read.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	# _bubble and its dim are PRESET_FULL_RECT against this control, which stops
	# at the canvas; the dim has to reach past it to cover the pillarbox bands.
	if _dim != null and _bubble != null:
		_dim.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_dim.position = Layout.overscan_position
		_dim.size = Layout.overscan_size
	_apply_safe_area()

func _apply_safe_area() -> void:
	var origin := _icon_pos() + Vector2(-SafeArea.right, SafeArea.top)
	_icon_button.position = origin
	_badge.position = origin + Vector2(_icon_size().x - BADGE_SIZE * 0.6, -BADGE_SIZE * 0.4)

func _process(_delta: float) -> void:
	if _badge == null:
		return
	var eligible := not is_open and _icon_button.visible and _has_unseen_type()
	_badge.visible = eligible
	if eligible:
		var t := Time.get_ticks_msec() / 1000.0
		_badge.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * TAU * BADGE_PULSE_HZ))

func _unhandled_input(event: InputEvent) -> void:
	if is_open and not _closing and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_state_changed(new_state: int) -> void:
	var in_game := new_state == GameManager.GameState.PLAYING or new_state == GameManager.GameState.ENDLESS_PLAYING
	# Mirrors TutorialManager's own guard: leaving play while the bubble is open
	# (quitting to Title from the Pause Menu, mid-bubble) would otherwise strand
	# it open forever - the next PLAYING/ENDLESS_PLAYING would show a "closed"
	# icon sitting behind an already-open bubble from the previous run. Reset
	# instantly rather than animating; Juice's own state-change handler already
	# zeroes the freeze count independently, so this only needs to fix this
	# node's own idea of whether it's open.
	if not in_game and is_open:
		is_open = false
		_closing = false
		_bubble.visible = false
		_bubble.modulate.a = 1.0
	_update_icon_visibility(new_state)

func _update_icon_visibility(state: int) -> void:
	var in_game := state == GameManager.GameState.PLAYING or state == GameManager.GameState.ENDLESS_PLAYING
	_icon_button.visible = in_game and not is_open and not get_tree().paused

# --- New-type badge ---------------------------------------------------------

# "Spawn-eligible" reads differently per mode: Arcade's TutorialManager already
# walks the player through every new type before a stage spawns (marking it seen
# in the process), so by the time this icon is even visible the current stage's
# types are already flagged - this will almost always be false in Arcade, which
# is correct, not a bug. Endless has no such modal, so this is where the badge
# actually earns its keep: unlocked-so-far types per the same schedule
# EndlessRunner's spawner reads.
func _eligible_types() -> Array[int]:
	var eligible: Array[int] = []
	if GameManager.current_state == GameManager.GameState.PLAYING and stage_controller != null:
		eligible = stage_controller.current_stage_timer_types()
	elif GameManager.current_state == GameManager.GameState.ENDLESS_PLAYING and endless_runner != null:
		for u in endless_runner.type_unlocks:
			if endless_runner.elapsed_time >= u.time and not eligible.has(u.type):
				eligible.append(u.type)
	return eligible

func _has_unseen_type() -> bool:
	for t in _eligible_types():
		if SaveManager.load_high_score("seen_type_%d" % t) == 0:
			return true
	return false

# --- Open / close ------------------------------------------------------------

func open() -> void:
	if is_open:
		return
	is_open = true
	_closing = false
	_update_icon_visibility(GameManager.current_state)

	# Endless gets both pages; Arcade only ever needs the timer-type one.
	var page_count := 2 if GameManager.current_state == GameManager.GameState.ENDLESS_PLAYING else 1
	_page_nav.configure(page_count)

	# The bubble's own page 1 IS the full reference for every eligible type
	# regardless of whether it's actually spawned yet - so reading it here is
	# what satisfies the badge, rather than waiting on a type to randomly spawn
	# and trigger EndlessRunner's separate live callout. Without this, the badge
	# could stay lit indefinitely after the player has already read exactly the
	# information it was flagging.
	for t in _eligible_types():
		SaveManager.save_high_score("seen_type_%d" % t, 1)

	Juice.freeze_gameplay()
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_bubble, "modulate:a", 1.0, 0.15)
	open_state_changed.emit()

func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	await Juice.resume_wipe(_bubble)
	_bubble.visible = false
	_bubble.modulate.a = 1.0
	Juice.release_gameplay()
	is_open = false
	_closing = false
	_update_icon_visibility(GameManager.current_state)
	open_state_changed.emit()

const PAGE_TITLES := ["TIMER TYPES", "POWERUPS"]

func _on_page_changed(index: int) -> void:
	for i in range(_panel_pages.size()):
		_panel_pages[i].visible = i == index
	if _heading_label != null:
		_heading_label.text = PAGE_TITLES[clampi(index, 0, PAGE_TITLES.size() - 1)]

# --- UI construction ---------------------------------------------------------

func _build() -> void:
	_icon_button = Button.new()
	_icon_button.text = "?"
	_icon_button.position = _icon_pos()
	_icon_button.custom_minimum_size = _icon_size()
	# The glyph is scaled directly against the bigger portrait circle, not
	# through _fs() (which only carries the modest 1.15 text-scale factor) - a
	# 30pt "?" would read tiny in a 120-unit circle nearly twice ICON_SIZE's
	# landscape diameter.
	_icon_button.add_theme_font_size_override("font_size", 46 if Layout.is_portrait() else _fs(30))
	_icon_button.add_theme_color_override("font_color", Color.WHITE)
	_icon_button.add_theme_color_override("font_outline_color", NEON)
	_icon_button.add_theme_constant_override("outline_size", 4)
	var circle := StyleBoxFlat.new()
	circle.bg_color = NEON.darkened(0.75)
	circle.set_corner_radius_all(int(_icon_size().x * 0.5))
	circle.set_border_width_all(3)
	circle.border_color = NEON
	_icon_button.add_theme_stylebox_override("normal", circle)
	var circle_hover := circle.duplicate()
	circle_hover.bg_color = NEON.darkened(0.55)
	_icon_button.add_theme_stylebox_override("hover", circle_hover)
	_icon_button.pressed.connect(open)
	PressFeedback.apply(_icon_button)
	add_child(_icon_button)

	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_badge.position = _icon_pos() + Vector2(ICON_SIZE.x - BADGE_SIZE * 0.6, -BADGE_SIZE * 0.4)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = BADGE_COLOR
	badge_box.set_corner_radius_all(int(BADGE_SIZE * 0.5))
	var badge_panel := Panel.new()
	badge_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_panel.add_theme_stylebox_override("panel", badge_box)
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(badge_panel)
	add_child(_badge)

	_bubble = Control.new()
	_bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble.visible = false
	add_child(_bubble)

	_dim = ColorRect.new()
	var dim := _dim
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks to any live timer underneath
	_bubble.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f1118")
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = NEON
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(NEON.r, NEON.g, NEON.b, 0.4)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(16))
	# Widened from 680 to fit the name column (swatch + 25pt label) alongside
	# the wrap cell's now-500-wide budget without squeezing either.
	col.custom_minimum_size = Vector2(700, 0) * _s()
	panel.add_child(col)

	_heading_label = _heading(PAGE_TITLES[0], 30, NEON)
	col.add_child(_heading_label)

	# Reserved height, not clipped - a page's actual content painting past this
	# rect would overlap the nav/close row below it rather than just being
	# cropped, so this has to fit the tallest page's real content (same issue
	# HelpScreen's own page area has, see its comment). Bumped from 430 to fit
	# the taller 24pt wrapped rows now that body text isn't the pre-pass 19pt.
	var page_area := Control.new()
	page_area.custom_minimum_size = Vector2(0, 500) * _s()
	col.add_child(page_area)

	var types_page := _build_types_page()
	types_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_area.add_child(types_page)
	_panel_pages.append(types_page)

	var powerups_page := _build_powerups_page()
	powerups_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	powerups_page.visible = false
	page_area.add_child(powerups_page)
	_panel_pages.append(powerups_page)

	_page_nav = PageNav.new()
	_page_nav.page_changed.connect(_on_page_changed)
	col.add_child(_page_nav)

	var close_button := _button("CLOSE", NEON)
	# 180x56 at this screen's 1.15 scale is only ~26dp tall - well under
	# Android's 48dp minimum. Bumped directly in portrait only; landscape
	# (desktop/web) keeps _button()'s original size.
	if Layout.is_portrait():
		close_button.custom_minimum_size = Vector2(200, 110)
	close_button.pressed.connect(close)
	var close_wrap := CenterContainer.new()
	close_wrap.add_child(close_button)
	col.add_child(close_wrap)

func _build_types_page() -> Control:
	var wrap := CenterContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _fs(24))
	grid.add_theme_constant_override("v_separation", _fs(10))
	wrap.add_child(grid)
	for t in TimerTypeInfo.ORDER:
		_add_type_row(grid, t)
	return wrap

func _add_type_row(grid: GridContainer, t: int) -> void:
	var name_cell := HBoxContainer.new()
	name_cell.add_theme_constant_override("separation", _fs(10))
	var swatch := ColorRect.new()
	swatch.color = TimerTypeInfo.color_of(t)
	swatch.custom_minimum_size = Vector2(18, 18) * _s()
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(swatch)
	name_cell.add_child(_cell_label(TimerTypeInfo.name_of(t), 25, TimerTypeInfo.color_of(t)))
	grid.add_child(name_cell)
	grid.add_child(_wrap_cell_label(TimerTypeInfo.desc_of(t)))

func _build_powerups_page() -> Control:
	var wrap := CenterContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _fs(24))
	grid.add_theme_constant_override("v_separation", _fs(14))
	wrap.add_child(grid)
	for kind in PowerupSystem.ORDER:
		_add_powerup_row(grid, kind)
	return wrap

func _add_powerup_row(grid: GridContainer, kind: int) -> void:
	var accent: Color = PowerupSystem.color_of(kind)
	var name_cell := VBoxContainer.new()
	name_cell.add_theme_constant_override("separation", _fs(0))
	# No keybind hint on mobile - see HelpScreen's identical guard.
	var hint := PowerupSystem.key_hint(kind)
	var name_text := "%s  %s" % [PowerupSystem.name_of(kind), hint] if not hint.is_empty() \
		else PowerupSystem.name_of(kind)
	name_cell.add_child(_cell_label(name_text, 25, accent))
	name_cell.add_child(_cell_label(Powerups.cooldown_text(kind), 18, Color(1, 1, 1, 0.5)))
	grid.add_child(name_cell)
	grid.add_child(_wrap_cell_label(Powerups.describe(kind)))

func _cell_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

func _wrap_cell_label(text: String) -> Label:
	var l := _cell_label(text, 24, TEXT_FILL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Widened from 460 (itself widened from 420) to give the bigger 24pt body
	# text the same two-line budget the 19pt version had - col is 680 wide and
	# the name column next to this is nowhere near using the rest of it.
	l.custom_minimum_size = Vector2(500, 0) * _s()
	return l

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
	button.custom_minimum_size = Vector2(180, 56) * _s()
	button.add_theme_font_size_override("font_size", _fs(26))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.8))
	button.add_theme_stylebox_override("hover", _box(accent, 0.65))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.55))
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

