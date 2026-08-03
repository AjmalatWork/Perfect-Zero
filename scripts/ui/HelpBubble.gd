extends Control
class_name HelpBubble

# In-game "?" reference bubble, top-right, live during both Arcade and Endless
# play. Content is pulled straight from TimerTypeInfo/PowerupSystem - the same
# tables the Help screen's legend already reads from - so nothing here is a
# second copy of that text. Arcade gets one page (timer types); Endless gets a
# second (powerups), paginated with the same PageNav the Help screen uses.
#
# The Timer Types page is built from TimerTypesLegend - the exact same
# component HelpScreen's own page 1 uses, not a second hand-kept-in-sync copy.
# Two independent copies of this already drifted once (tile size, text size,
# spacing, bystander size all diverged) - reusing the real thing is the actual
# fix for that, not just a one-time re-sync. What differs is only the
# description display: a single in-flow label at the bottom of the page here,
# vs. HelpScreen's anchored overlay caption - this panel is a small centred
# modal, not a tall page with a tile that could be anywhere on screen.
#
# The Powerups page is this screen's own (smaller-scaled, since it isn't the
# part that needed to match HelpScreen pixel-for-pixel).
#
# Opening freezes gameplay clocks the same way Nuke's cascade does
# (Juice.freeze_gameplay/release_gameplay) - the dim's own full-rect
# MOUSE_FILTER_STOP is what actually blocks a click from reaching a live timer
# underneath; the freeze is what stops time silently advancing behind it.
# Closing uses the same shared wipe PauseMenu's RESUME uses (Juice.resume_wipe).

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")
const MUTED := Color("8b90a8")

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
var _page_area: Control
var _scroll: ScrollContainer
var _dim: ColorRect
var _page_nav: PageNav
var _closing: bool = false

# --- Eligible-type cache (see _eligible_types()) ----------------------------
var _eligible_cache: Array[int] = []
var _eligible_cache_valid: bool = false
# Per-index "already folded into _eligible_cache" flags for Endless's
# type_unlocks - lets the per-frame check be a cheap bool scan instead of
# rebuilding the whole array, without assuming type_unlocks is time-sorted.
var _endless_unlock_flags: Array[bool] = []

func _icon_pos() -> Vector2:
	return Vector2(Layout.canvas_size.x - _icon_right_inset(), _icon_top())


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact.
const PORTRAIT_SCALE := 1.15

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

# Powerups page demo strip - this screen's own smaller scale (unchanged; the
# user's "match HelpScreen exactly" request was about the Timer Types page).
const POWERUP_DEMO_TILE_SIZE := 130.0

var _powerup_demo_token: int = 0

var _types_legend: TimerTypesLegend            # Timer Types page - shared with HelpScreen
var _powerup_tiles: Array[HelpDemoTile] = []   # Powerups page, react to the three powerups
var _powerup_buttons: Array[Button] = []
var _types_desc_label: Label
var _powerups_desc_label: Label

func _still_powerup_demo(token: int) -> bool:
	return token == _powerup_demo_token

# A fresh random landing point inside the real PERFECT window every time a demo
# auto-clicks, instead of a single fixed distance every run.
func _random_perfect_stop() -> float:
	return randf_range(0.0, TimerSlot.PERFECT_MAX)

# The duck count itself now lives on AudioManager (see its own
# duck_music()/refresh_music_mute() comments) rather than here - HelpScreen
# kept an identical, entirely separate count on the same physical bus, and
# Settings' own volume-driven mute was a third independent writer, so any two
# of the three could silently stomp each other's reason for wanting the bus
# muted or unmuted. AudioManager is the one place all three now agree.
func _duck_music(on: bool) -> void:
	AudioManager.duck_music(on)

func _force_unduck_music() -> void:
	AudioManager.force_unduck_music()

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

# _eligible_types() used to allocate a fresh Array[int] on every single frame
# this icon is visible (and in Arcade, re-walked the current stage's whole
# timer list every frame to do it) - this cache is what makes it a per-run-
# entry-and-per-unlock cost instead.

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
		_cancel_all_demos()
		is_open = false
		_closing = false
		_bubble.visible = false
		_bubble.modulate.a = 1.0
		# close() never ran on this path, so its own restore never fires -
		# without this the flag outlives the overlay that set it and the next
		# run starts with powerup input silently dead. (Powerups._arm() also
		# clears it defensively; this is the correct, specific place.)
		Powerups.set_input_suspended(false)
	# GameManager.set_state() emits unconditionally, even PLAYING -> PLAYING
	# (CampaignNavigator.start_from_index() calls it on every stage advance) -
	# so this fires on every fresh stage/run entry, which is exactly when a
	# stale eligible-type cache needs invalidating.
	_eligible_cache_valid = false
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
	_refresh_eligible_cache()
	return _eligible_cache

# Rebuilds _eligible_cache only when _on_state_changed() has flagged it stale
# (a fresh stage/run entry). Within a live Endless run, rather than re-walking
# the whole type_unlocks list into a new array every call, only the types that
# newly crossed their unlock time since the last check are folded in -
# _endless_unlock_flags tracks which indices are already accounted for, so
# this doesn't assume type_unlocks is authored in time order.
func _refresh_eligible_cache() -> void:
	var state := GameManager.current_state
	if not _eligible_cache_valid:
		_eligible_cache_valid = true
		_eligible_cache.clear()
		_endless_unlock_flags.clear()
		if state == GameManager.GameState.PLAYING and stage_controller != null:
			_eligible_cache = stage_controller.current_stage_timer_types()
		elif state == GameManager.GameState.ENDLESS_PLAYING and endless_runner != null:
			_endless_unlock_flags.resize(endless_runner.type_unlocks.size())
			_endless_unlock_flags.fill(false)
	if state == GameManager.GameState.ENDLESS_PLAYING and endless_runner != null:
		for i in range(endless_runner.type_unlocks.size()):
			if i < _endless_unlock_flags.size() and _endless_unlock_flags[i]:
				continue
			var u := endless_runner.type_unlocks[i]
			if endless_runner.elapsed_time >= u.time:
				if i < _endless_unlock_flags.size():
					_endless_unlock_flags[i] = true
				if not _eligible_cache.has(u.type):
					_eligible_cache.append(u.type)

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
	# Separate from the freeze above, and it has to be: the freeze stops clocks
	# advancing behind a stopped screen, but says nothing about input, and this
	# overlay deliberately does NOT pause the tree. The dim below blocks
	# mouse/touch, but PowerupBar's A/S/D keyboard handler runs on
	# _unhandled_input and stayed live underneath - so on desktop/web, pressing
	# S here fired a real Nuke that resolved and banked the entire board behind
	# the panel. See Powerups._input_suspended for why this can't just reuse
	# Juice.is_gameplay_frozen().
	Powerups.set_input_suspended(true)
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_bubble, "modulate:a", 1.0, 0.15)
	open_state_changed.emit()

func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	_cancel_all_demos()
	await Juice.resume_wipe(_bubble)
	_bubble.visible = false
	_bubble.modulate.a = 1.0
	Juice.release_gameplay()
	# Lifted alongside the freeze, not before it - resume_wipe()'s own contract
	# is "interactive again at the end of the wipe, not partway through it", and
	# restoring input while the clocks are still held would let a powerup fire
	# into a board that hasn't started moving again.
	Powerups.set_input_suspended(false)
	is_open = false
	_closing = false
	_update_icon_visibility(GameManager.current_state)
	open_state_changed.emit()

# Stops every in-flight type/powerup demo, resetting every tile touched back to
# idle - shared between closing the bubble, leaving play entirely mid-bubble,
# and switching between the Timer Types / Powerups pages (a demo left running
# on a page that just got hidden would still fire Juice.click_burst - that call
# spawns on a global overlay layer, not as a child of the tile, so it would be
# visible even though the tile itself no longer is).
func _cancel_all_demos() -> void:
	_powerup_demo_token += 1
	_force_unduck_music()
	AudioManager.stop_all_sfx()
	if _types_legend != null:
		_types_legend.cancel_demos()
	for p in _powerup_tiles:
		if is_instance_valid(p):
			p.idle()
			p.set_present(false)
	_undim_powerup_buttons()

const PAGE_TITLES := ["TIMER TYPES", "POWERUPS"]

func _on_page_changed(index: int) -> void:
	_cancel_all_demos()
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

	# The Timer Types page now uses HelpScreen's own full-size tiles/text (see
	# TimerTypesLegend), which are sized for a full screen, not a small popup -
	# their combined height can genuinely exceed what fits between the heading
	# and CLOSE on this modal. A ScrollContainer is the safety net: CLOSE/PageNav
	# stay fixed and always reachable, and only the page content scrolls if it
	# doesn't fit, instead of silently overflowing past the visible screen (the
	# bug this replaces - CLOSE pushed off-screen entirely with no way back).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_page_area = Control.new()
	_page_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page_area)

	var types_page := _build_types_page()
	types_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_area.add_child(types_page)
	_panel_pages.append(types_page)

	var powerups_page := _build_powerups_page()
	powerups_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	powerups_page.visible = false
	_page_area.add_child(powerups_page)
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

	call_deferred("_size_page_area", panel, col, _heading_label, _page_nav, close_wrap)

# Reserved height comes from the tallest page's own measured content, the same
# fix HelpScreen's own page area needed - but then CAPPED against how much
# room is actually left on screen once every other fixed element (heading,
# nav, close, panel padding, the dim's own edge margin) is accounted for, so
# the ScrollContainer above only ever scrolls the genuine overflow rather than
# growing the whole popup past the visible canvas.
func _size_page_area(panel: PanelContainer, col: VBoxContainer, heading: Label,
		nav: PageNav, close_wrap: Control) -> void:
	if _page_area == null or _scroll == null:
		return
	var tallest := 0.0
	for p in _panel_pages:
		tallest = maxf(tallest, p.get_combined_minimum_size().y)
	_page_area.custom_minimum_size = Vector2(0, tallest)

	var chrome: float = heading.get_combined_minimum_size().y \
		+ nav.get_combined_minimum_size().y + close_wrap.get_combined_minimum_size().y \
		+ col.get_theme_constant("separation") * 3.0
	var panel_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	var padding: float = (panel_style.content_margin_top + panel_style.content_margin_bottom) \
		if panel_style != null else 0.0
	# A little breathing room against the dim's own edge, same spirit as this
	# screen's other outer margins - a popup touching the physical screen edge
	# reads as broken even before anything is actually clipped.
	var edge_margin := 120.0
	var available: float = maxf(Layout.canvas_size.y - chrome - padding - edge_margin, 200.0)
	_scroll.custom_minimum_size = Vector2(0, minf(tallest, available))

# --- Timer Types page ---------------------------------------------------------

func _build_types_page() -> Control:
	_types_legend = TimerTypesLegend.new()
	_types_legend.type_tapped.connect(_on_legend_type_tapped)
	_types_legend.duck_requested.connect(_duck_music)
	_types_legend.build()

	var legend_scale: float = HelpScreen.PORTRAIT_SCALE if Layout.is_portrait() else 1.0
	_types_desc_label = _make_desc_label("Tap a timer to see what it does.",
		legend_scale, HelpScreen.DESC_FONT_SIZE)
	_types_legend.add_child(_types_desc_label)
	return _types_legend

func _on_legend_type_tapped(_tile: HelpDemoTile, text: String, accent: Color) -> void:
	_set_bubble_desc(_types_desc_label, text, accent)

# --- Powerups page --------------------------------------------------------------

func _build_powerups_page() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(12))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = "ENDLESS MODE ONLY"
	label.add_theme_font_size_override("font_size", _fs(HelpScreen.SECTION_LABEL_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", _fs(12))
	for kind in PowerupSystem.ORDER:
		var b := _make_powerup_button(kind)
		_powerup_buttons.append(b)
		button_row.add_child(b)
	var button_wrap := CenterContainer.new()
	button_wrap.add_child(button_row)
	col.add_child(button_wrap)

	# A three-timer stand-in for the board, same reason HelpScreen's own page 2
	# uses one - Shield is the one powerup that saves exactly one timer, and
	# seeing the other two carry on untouched is what distinguishes it from
	# Nuke and Overclock without needing a sentence to say so.
	var demo_row := HBoxContainer.new()
	demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_row.add_theme_constant_override("separation", _fs(12))
	for i in range(3):
		var tile := _make_tile(TimerData.TimerType.NORMAL, "", POWERUP_DEMO_TILE_SIZE, _s())
		tile.interactive = false
		_powerup_tiles.append(tile)
		demo_row.add_child(tile)
		tile.set_present(false)
	var demo_wrap := CenterContainer.new()
	demo_wrap.add_child(demo_row)
	col.add_child(demo_wrap)

	_powerups_desc_label = _make_desc_label("Tap a powerup to see what it does.", _s(), 20)
	col.add_child(_powerups_desc_label)
	return col

func _make_powerup_button(kind: int) -> Button:
	var accent: Color = PowerupSystem.color_of(kind)
	var button := Button.new()
	var bsize: Vector2 = HelpScreen.POWERUP_BUTTON_SIZE * _s()
	button.custom_minimum_size = bsize
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	button.pressed.connect(_on_powerup_pressed.bind(kind))

	# The same drawn glyph the in-game buttons use, so the legend and the board
	# can't drift apart.
	var icon := PowerupIcon.new(kind)
	var icon_size: float = bsize.y * 0.42
	icon.size = Vector2(icon_size, icon_size)
	icon.position = Vector2((bsize.x - icon_size) * 0.5, bsize.y * 0.12)
	button.add_child(icon)

	var name_label := Label.new()
	name_label.text = PowerupSystem.name_of(kind)
	name_label.add_theme_font_size_override("font_size", _fs(14))
	name_label.add_theme_color_override("font_color", accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.position = Vector2(0, bsize.y * 0.66)
	name_label.size = Vector2(bsize.x, bsize.y * 0.28)
	button.add_child(name_label)

	return button

func _on_powerup_pressed(kind: int) -> void:
	_powerup_demo_token += 1
	var token := _powerup_demo_token
	var accent: Color = PowerupSystem.color_of(kind)
	_set_bubble_desc(_powerups_desc_label, "%s - %s  (%s)" % [PowerupSystem.name_of(kind),
		Powerups.describe(kind), Powerups.cooldown_text(kind)], accent)
	_dim_powerup_buttons_except(kind)
	# The same activation cue the real board plays the instant a powerup button
	# is pressed - AudioManager only, no Powerups.activate() call, so nothing
	# about cooldowns/charges is touched.
	AudioManager.play_powerup_activate(kind)

	match kind:
		PowerupSystem.Kind.CLEAR_ALL:
			_play_nuke_demo(token)
		PowerupSystem.Kind.OVERCLOCK:
			_play_overclock_demo(token)
		PowerupSystem.Kind.SHIELD:
			_play_shield_demo(token)

func _dim_powerup_buttons_except(kind: int) -> void:
	for i in range(_powerup_buttons.size()):
		var on: bool = PowerupSystem.ORDER[i] != kind
		var button := _powerup_buttons[i]
		var tween := create_tween()
		tween.tween_property(button, "modulate:a", 0.25 if on else 1.0, 0.18)
		button.disabled = on

func _undim_powerup_buttons() -> void:
	for button in _powerup_buttons:
		var tween := create_tween()
		tween.tween_property(button, "modulate:a", 1.0, 0.18)
		button.disabled = false

# Nuke's real effect is instant and forces whatever value each timer happens to
# be showing at that moment - see HelpScreen's identical function for the full
# reasoning on capturing before the stagger.
func _play_nuke_demo(token: int) -> void:
	_duck_music(true)
	for i in range(_powerup_tiles.size()):
		_powerup_tiles[i].set_present(true)
		_powerup_tiles[i].play_countdown(HelpScreen.PREVIEW_STARTS[i], 0.0)
	await get_tree().create_timer(HelpScreen.NUKE_RUN_SEC, true, false, true).timeout
	if not _still_powerup_demo(token):
		_duck_music(false)
		return
	var total: int = _powerup_tiles.size()
	var frozen: Array[String] = []
	for tile in _powerup_tiles:
		if is_instance_valid(tile):
			frozen.append("%.2f" % tile.value)
			tile.cancel_playback()
		else:
			frozen.append("0.00")
	var gap: float = EndlessRunner.NUKE_CASCADE_SEC / float(maxi(total, 1))
	for i in range(total):
		if not _still_powerup_demo(token):
			_duck_music(false)
			return
		var t: HelpDemoTile = _powerup_tiles[i]
		if is_instance_valid(t):
			t.play_grade("PERFECT", frozen[i], HelpScreen.RESULT_HOLD_SEC)
			AudioManager.play_nuke_note(i, total)
		if i < total - 1:
			await get_tree().create_timer(gap, true, false, true).timeout
	await get_tree().create_timer(HelpScreen.RESULT_HOLD_SEC, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

func _play_overclock_demo(token: int) -> void:
	_duck_music(true)
	for i in range(_powerup_tiles.size()):
		_powerup_tiles[i].set_present(true)
		_run_preview_countdown(_powerup_tiles[i], HelpScreen.OVERCLOCK_STARTS[i], token)
	await get_tree().create_timer(HelpScreen.OVERCLOCK_LEAD_SEC, true, false, true).timeout
	if not _still_powerup_demo(token):
		_duck_music(false)
		return
	for tile in _powerup_tiles:
		if is_instance_valid(tile):
			tile.react_overclock(HelpScreen.EFFECT_SEC)
	await get_tree().create_timer(HelpScreen.EFFECT_SEC + 2.0, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

func _run_preview_countdown(tile: HelpDemoTile, start: float, token: int) -> void:
	await tile.play_countdown(start, _random_perfect_stop())
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, HelpScreen.RESULT_HOLD_SEC)

func _play_shield_demo(token: int) -> void:
	if _powerup_tiles.is_empty():
		return
	_duck_music(true)
	var tile: HelpDemoTile = _powerup_tiles[0]
	tile.set_present(true)
	await tile.play_countdown(HelpScreen.REACT_TILE_START, 0.0)
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	await tile.play_overrun(HelpScreen.SHIELD_FAIL_DISTANCE)
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	var overrun := "%.2f" % HelpScreen.SHIELD_FAIL_DISTANCE
	tile.play_grade("FAIL", overrun, HelpScreen.SHIELD_FAIL_SEC + HelpScreen.SHIELD_SAVED_SEC)
	await get_tree().create_timer(HelpScreen.SHIELD_FAIL_SEC, true, false, true).timeout
	if not _still_powerup_demo(token) or not is_instance_valid(tile):
		_duck_music(false)
		return
	tile.play_grade("MISS", overrun, HelpScreen.SHIELD_SAVED_SEC)
	await get_tree().create_timer(HelpScreen.SHIELD_SAVED_SEC, true, false, true).timeout
	_duck_music(false)
	_end_powerup_demo(token)

func _end_powerup_demo(token: int) -> void:
	if not _still_powerup_demo(token):
		return
	_undim_powerup_buttons()
	for tile in _powerup_tiles:
		if is_instance_valid(tile):
			tile.set_dimmed(false)
			tile.idle()
			tile.set_present(false)

# --- Shared builders -----------------------------------------------------------

func _make_tile(type: int, display_name: String, tile_size: float, scale: float) -> HelpDemoTile:
	var tile := HelpDemoTile.new()
	var sz: float = tile_size * scale
	tile.custom_minimum_size = Vector2(sz, sz)
	tile.configure(type, display_name, roundi(sz * HelpScreen.TIMER_DIGIT_RATIO), roundi(sz * HelpScreen.TIMER_NAME_RATIO))
	tile.idle()
	return tile

# Timer Types page passes the legend's own scale/HelpScreen.DESC_FONT_SIZE
# (exact match to HelpScreen); Powerups page passes this screen's own _s()/20,
# unchanged.
func _make_desc_label(placeholder: String, scale: float, font_size: int) -> Label:
	var label := Label.new()
	label.text = placeholder
	label.add_theme_font_size_override("font_size", roundi(font_size * scale))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, roundi(60 * scale))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _set_bubble_desc(label: Label, text: String, color: Color) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.18)

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
