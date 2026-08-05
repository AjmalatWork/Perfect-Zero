extends RefCounted
class_name PowerupTutorial

# One-time modal introducing the three Endless powerups, shown the first time
# the player opens Endless mode.
#
# Deliberately separate from TutorialManager: that one is Campaign-only and
# data-driven off a stage's timer types, whereas this fires once per save on
# entering a mode. It reuses the same save-key convention (SaveManager flag) and
# the same popup styling so the two read as one system to the player.
#
# The three-tile demo row below plays the exact same scripted Shield/Nuke/
# Overclock animations the Help screen's own powerups page uses (same
# constants, same HelpDemoTile coroutines), one after another, automatically -
# a first-time player sees what each powerup actually does before ever having
# one to use. GOT IT stays locked until all three have played through once.

const SEEN_KEY := "seen_endless_powerups"
const TEXT_FILL := Color("dfe3ee")
const NEON := Color("22d3ff")

# --- Demo timing - mirrors HelpScreen's own constants exactly. -------------
const RESULT_HOLD_SEC := 1.6
const PREVIEW_STARTS := [1.9, 2.5, 3.1]
const NUKE_RUN_SEC := 0.6
const OVERCLOCK_STARTS := [2.5, 4.0, 5.5]
const OVERCLOCK_LEAD_SEC := 1.0
const EFFECT_SEC := 2.0
const SHIELD_FAIL_SEC := 0.6
const SHIELD_SAVED_SEC := 2.0
const SHIELD_FAIL_DISTANCE := 1.25
const REACT_TILE_START := 1.2

const TILE_SIZE := 200.0
const TILE_DIGIT_RATIO := 0.27
const TILE_NAME_RATIO := 0.18
# Beat of stillness between one full Shield->Nuke->Overclock cycle ending and
# the next starting.
const LOOP_GAP_SEC := 1.0

# Matches PauseMenu's/EndlessEndScreen's/StageResultScreen's own portrait
# button treatment - a user request for GOT IT to be sized/styled the same as
# every other redesigned button this pass touched.
const BUTTON_SIZE := Vector2(380, 140)
const BUTTON_FONT := 46  # bumped by a lot on a further user request

static func is_new() -> bool:
	return SaveManager.load_high_score(SEEN_KEY) == 0

static func mark_seen() -> void:
	SaveManager.save_high_score(SEEN_KEY, 1)

# Builds the popup under `host` and marks it seen once dismissed. `on_dismiss`
# (optional) fires right after mark_seen() - lets a caller defer starting the
# actual run until the player has closed this, rather than starting underneath it.
#
# Returns the popup's CanvasLayer so a caller can tear it down itself. That
# matters because the popup is a CanvasLayer, not a CanvasItem: hiding the host
# screen does NOT hide it (the same reason TutorialManager tracks and explicitly
# frees its own popup layer), so any path that leaves the screen while this is
# up has to free it or it survives as orphaned UI over the next screen.
static func show_popup(host: Node, on_dismiss: Callable = Callable()) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 30
	host.add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to anything behind
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f1118")
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = NEON
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(NEON.r, NEON.g, NEON.b, 0.4)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	col.add_child(_label("POWERUPS", 40, NEON, HORIZONTAL_ALIGNMENT_CENTER))
	var intro := _label(
		"Endless gives you three. They recharge as you play. Watch what each does:",
		26, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(680, 0)
	col.add_child(intro)

	# A three-timer stand-in for the board - same reasoning as the Help
	# screen's own version: Shield only ever puts one timer at risk, and
	# seeing the other two carry on untouched (or all three moving together
	# for Nuke/Overclock) is what distinguishes the three from each other.
	var demo_row := HBoxContainer.new()
	demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_row.add_theme_constant_override("separation", 16)
	var tiles: Array[HelpDemoTile] = []
	for i in range(3):
		var tile := _make_tile()
		demo_row.add_child(tile)
		tile.set_present(false)  # nothing to show until its own demo starts
		tiles.append(tile)
	var demo_wrap := CenterContainer.new()
	demo_wrap.add_child(demo_row)
	col.add_child(demo_wrap)

	for kind in PowerupSystem.ORDER:
		col.add_child(_row(kind))

	var got := _button("GOT IT", NEON)
	# Locked until all three demos below have played through once - see this
	# file's own header comment for why.
	got.disabled = true
	got.modulate.a = 0.4
	var on_got := func() -> void:
		if got.disabled:
			return
		mark_seen()
		layer.queue_free()
		if on_dismiss.is_valid():
			on_dismiss.call()
	got.pressed.connect(on_got)
	var got_wrap := CenterContainer.new()
	got_wrap.add_child(got)
	col.add_child(got_wrap)

	# Loops the whole Shield->Nuke->Overclock cycle rather than playing once and
	# stopping - a player who was still reading the description when it first
	# finished (a user-reported real case) gets another look instead of a dead
	# board. GOT IT unlocks after the first full cycle and stays unlocked; the
	# demo just keeps cycling until the player actually dismisses it.
	_play_all_demos(host, tiles, func() -> void:
		if is_instance_valid(got):
			got.disabled = false
			got.modulate.a = 1.0
	)
	return layer

static func _row(kind: int) -> Control:
	var accent: Color = PowerupSystem.color_of(kind)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var icon := PowerupIcon.new(kind)
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size = Vector2(52, 52)
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(icon)
	row.add_child(icon_wrap)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 2)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_label(PowerupSystem.name_of(kind), 28, accent, HORIZONTAL_ALIGNMENT_LEFT))
	# No keybind hint on mobile - there's no keyboard to bind, and the label is
	# skipped outright rather than left empty so it doesn't reserve a hollow gap
	# in the row.
	var hint := PowerupSystem.key_hint(kind)
	if not hint.is_empty():
		head.add_child(_label(hint, 20, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT))
	head.add_child(_label(Powerups.cooldown_text(kind), 20,
		Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT))
	text_col.add_child(head)

	var desc := _label(Powerups.describe(kind), 23, TEXT_FILL, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(620, 0)
	text_col.add_child(desc)

	row.add_child(text_col)
	return row

static func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

static func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", BUTTON_FONT)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85, 0.35, 8))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7, 0.5, 12))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6, 0.4, 6))
	return button

static func _box(accent: Color, darken: float, shadow_alpha: float = 0.0, shadow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	if shadow_alpha > 0.0:
		sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2.ZERO
	return sb

static func _make_tile() -> HelpDemoTile:
	var tile := HelpDemoTile.new()
	tile.interactive = false  # plays itself; not tappable, unlike the Help screen's
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.configure(TimerData.TimerType.NORMAL, "", roundi(TILE_SIZE * TILE_DIGIT_RATIO),
		roundi(TILE_SIZE * TILE_NAME_RATIO))
	tile.idle()
	return tile

# --- Demo dispatch (mirrors HelpScreen's _play_shield_demo/_play_nuke_demo/
# _play_overclock_demo, trimmed of the whole-screen dimming/token machinery -
# this popup has no tap-to-retrigger, so there's nothing to guard a retrigger
# against; is_instance_valid() alone covers the popup being torn down early
# from outside, e.g. backing out of Endless Mode Select mid-animation) --------

static func _random_perfect_stop() -> float:
	return randf_range(0.0, ScoreManager.perfect_max)

# Loops for as long as the popup stays open (checked via tiles[0]'s own
# validity - the popup's CanvasLayer freeing its children is the only signal
# available here, since this is a static function with no token/instance
# state of its own). `on_first_finished` fires only after the first full
# cycle (what unlocks GOT IT); every cycle after that just keeps playing.
static func _play_all_demos(host: Node, tiles: Array[HelpDemoTile], on_first_finished: Callable) -> void:
	if tiles.is_empty():
		return
	var unlocked := false
	while is_instance_valid(tiles[0]):
		await _play_shield_demo(host, tiles)
		_reset_tiles(tiles)
		if not is_instance_valid(tiles[0]):
			return
		await _play_nuke_demo(host, tiles)
		_reset_tiles(tiles)
		if not is_instance_valid(tiles[0]):
			return
		await _play_overclock_demo(host, tiles)
		if not is_instance_valid(tiles[0]):
			return
		if not unlocked:
			unlocked = true
			on_first_finished.call()
		_reset_tiles(tiles)
		await host.get_tree().create_timer(LOOP_GAP_SEC, true, false, true).timeout

static func _reset_tiles(tiles: Array[HelpDemoTile]) -> void:
	for t in tiles:
		if is_instance_valid(t):
			t.set_dimmed(false)
			t.idle()
			t.set_present(false)

# Shield acts on exactly one timer, and the demonstration is the asymmetry: the
# other two preview tiles never appear at all for this one, while the first
# genuinely counts all the way out - a real FAIL, caught a beat later and
# settled as a MISS.
static func _play_shield_demo(host: Node, tiles: Array[HelpDemoTile]) -> void:
	if tiles.is_empty():
		return
	var tile := tiles[0]
	tile.set_present(true)
	await tile.play_countdown(REACT_TILE_START, 0.0)
	if not is_instance_valid(tile):
		return
	# Nobody clicks it, so it overruns rather than stopping dead at zero. A FAIL
	# is a stop more than TimerSlot.MISS_MAX (1.00) from zero, reachable only by
	# running past it - 0.00 itself is dead centre of the PERFECT window.
	await tile.play_overrun(SHIELD_FAIL_DISTANCE)
	if not is_instance_valid(tile):
		return
	var overrun := "%.2f" % SHIELD_FAIL_DISTANCE
	tile.play_grade("FAIL", overrun, SHIELD_FAIL_SEC + SHIELD_SAVED_SEC)
	await host.get_tree().create_timer(SHIELD_FAIL_SEC, true, false, true).timeout
	if not is_instance_valid(tile):
		return
	# The distance is unchanged by the save - Powerups.filter_grade() rewrites
	# the grade and nothing else, so the digit stays exactly where it landed.
	tile.play_grade("MISS", overrun, SHIELD_SAVED_SEC)
	await host.get_tree().create_timer(SHIELD_SAVED_SEC, true, false, true).timeout

# Nuke's real effect is instant and forces whatever value each timer happens to
# be showing at that moment - so the three preview tiles are left running for
# NUKE_RUN_SEC first, their live values captured, then their own countdown
# loops are cancelled before play_grade freezes them there.
static func _play_nuke_demo(host: Node, tiles: Array[HelpDemoTile]) -> void:
	for i in range(tiles.size()):
		tiles[i].set_present(true)
		tiles[i].play_countdown(PREVIEW_STARTS[i], 0.0)
	await host.get_tree().create_timer(NUKE_RUN_SEC, true, false, true).timeout
	var total: int = tiles.size()
	var frozen: Array[String] = []
	for tile in tiles:
		if is_instance_valid(tile):
			frozen.append("%.2f" % tile.value)
			tile.cancel_playback()
		else:
			frozen.append("0.00")
	# Same fixed total length the board uses, divided the same way, so the
	# legend and the real cascade run at the same rhythm.
	var gap: float = EndlessRunner.NUKE_CASCADE_SEC / float(maxi(total, 1))
	for i in range(total):
		var t: HelpDemoTile = tiles[i]
		if is_instance_valid(t):
			t.play_grade("PERFECT", frozen[i], RESULT_HOLD_SEC)
			AudioManager.play_nuke_note(i, total)
		if i < total - 1:
			await host.get_tree().create_timer(gap, true, false, true).timeout
	await host.get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout

# All three run at a visible baseline speed first (OVERCLOCK_LEAD_SEC) so the
# boost reads as a change, not just "these were always fast" - then every tile
# gets react_overclock, which reverts on its own once EFFECT_SEC elapses.
static func _play_overclock_demo(host: Node, tiles: Array[HelpDemoTile]) -> void:
	for i in range(tiles.size()):
		tiles[i].set_present(true)
		_run_preview_countdown(tiles[i], OVERCLOCK_STARTS[i])
	await host.get_tree().create_timer(OVERCLOCK_LEAD_SEC, true, false, true).timeout
	for tile in tiles:
		if is_instance_valid(tile):
			tile.react_overclock(EFFECT_SEC)
	await host.get_tree().create_timer(EFFECT_SEC + 1.0, true, false, true).timeout

static func _run_preview_countdown(tile: HelpDemoTile, start: float) -> void:
	await tile.play_countdown(start, _random_perfect_stop())
	if not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)
