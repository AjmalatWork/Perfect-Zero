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

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")

# Left of PauseMenu's pause button (which sits at x=1508..1572, y=28..92) with
# clearance, so the two never collide regardless of which is added to the tree
# first.
const ICON_POS := Vector2(1428, 28)
const ICON_SIZE := Vector2(64, 64)

const BADGE_COLOR := Color("ffd23f")
const BADGE_PULSE_HZ := 1.6
const BADGE_SIZE := 16.0

@export var stage_controller: StageController
@export var endless_runner: EndlessRunner

var is_open: bool = false

var _icon_button: Button
var _badge: Control
var _bubble: Control       # dim + panel, faded as one unit by resume_wipe
var _heading_label: Label
var _panel_pages: Array[Control] = []
var _page_nav: PageNav
var _closing: bool = false

func _ready() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90  # below PauseMenu (100), above ordinary gameplay (peaks at 20)
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_icon_visibility(GameManager.current_state)

# The icon sits hard against the top-right corner, which in landscape is
# precisely where a camera cutout or a rounded corner lands - so its anchor is
# pulled in by whatever the display actually reports. The badge rides along,
# since it's positioned relative to the icon rather than parented to it.
# Displays with no insets (desktop, web, phones without cutouts) report zero
# and leave both exactly where they were authored.
func _apply_safe_area() -> void:
	var origin := ICON_POS + Vector2(-SafeArea.right, SafeArea.top)
	_icon_button.position = origin
	_badge.position = origin + Vector2(ICON_SIZE.x - BADGE_SIZE * 0.6, -BADGE_SIZE * 0.4)

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
	_icon_button.position = ICON_POS
	_icon_button.custom_minimum_size = ICON_SIZE
	_icon_button.add_theme_font_size_override("font_size", 30)
	_icon_button.add_theme_color_override("font_color", Color.WHITE)
	_icon_button.add_theme_color_override("font_outline_color", NEON)
	_icon_button.add_theme_constant_override("outline_size", 4)
	var circle := StyleBoxFlat.new()
	circle.bg_color = NEON.darkened(0.75)
	circle.set_corner_radius_all(int(ICON_SIZE.x * 0.5))
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
	_badge.position = ICON_POS + Vector2(ICON_SIZE.x - BADGE_SIZE * 0.6, -BADGE_SIZE * 0.4)
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

	var dim := ColorRect.new()
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
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(680, 0)
	panel.add_child(col)

	_heading_label = _heading(PAGE_TITLES[0], 30, NEON)
	col.add_child(_heading_label)

	var page_area := Control.new()
	page_area.custom_minimum_size = Vector2(0, 380)
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
	close_button.pressed.connect(close)
	var close_wrap := CenterContainer.new()
	close_wrap.add_child(close_button)
	col.add_child(close_wrap)

func _build_types_page() -> Control:
	var wrap := CenterContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	wrap.add_child(grid)
	for t in TimerTypeInfo.ORDER:
		_add_type_row(grid, t)
	return wrap

func _add_type_row(grid: GridContainer, t: int) -> void:
	var name_cell := HBoxContainer.new()
	name_cell.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = TimerTypeInfo.color_of(t)
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(swatch)
	name_cell.add_child(_cell_label(TimerTypeInfo.name_of(t), 21, TimerTypeInfo.color_of(t)))
	grid.add_child(name_cell)
	grid.add_child(_wrap_cell_label(TimerTypeInfo.desc_of(t)))

func _build_powerups_page() -> Control:
	var wrap := CenterContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	wrap.add_child(grid)
	for kind in PowerupSystem.ORDER:
		_add_powerup_row(grid, kind)
	return wrap

func _add_powerup_row(grid: GridContainer, kind: int) -> void:
	var accent: Color = PowerupSystem.color_of(kind)
	var name_cell := VBoxContainer.new()
	name_cell.add_theme_constant_override("separation", 0)
	name_cell.add_child(_cell_label(
		"%s  [%s]" % [PowerupSystem.name_of(kind), PowerupSystem.key_of(kind)], 21, accent))
	name_cell.add_child(_cell_label(Powerups.cooldown_text(kind), 16, Color(1, 1, 1, 0.5)))
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
	var l := _cell_label(text, 19, TEXT_FILL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
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
	button.custom_minimum_size = Vector2(180, 56)
	button.add_theme_font_size_override("font_size", 26)
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
