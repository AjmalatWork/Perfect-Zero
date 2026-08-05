extends Node
class_name TutorialManager

# Before a stage spawns, shows a one-time modal popup for each timer type the save
# file has never seen. Data-driven: whichever stage first introduces a type
# triggers its popup, so reordering/adding stages needs no changes here.
#
# The popup demonstrates the type with a live HelpDemoTile running the exact
# same scripted animation the Help screen's own legend uses (same constants,
# same coroutines) rather than a static name/description card - a first-time
# player sees the type actually behave before ever facing it for real. Red and
# Blue additionally spawn two bystander Normal tiles reacting, matching the
# Help screen's own demo for those two types - a plain single tile can't show
# what either one DOES, since the effect lands on other timers, not itself.
#
# GOT IT starts disabled and only unlocks once the demo has played through
# once - a user-requested change from the previous version, where the popup
# could be dismissed the instant it appeared without the player ever having
# seen what the type does.

const TEXT_FILL := Color("dfe3ee")

# --- Demo timing - mirrors HelpScreen's own constants exactly, so the
# tutorial and the reference legend show the identical animation. ---------
const RESULT_HOLD_SEC := 1.6
const NORMAL_START := 3.0
const GOLDEN_BLUR_SEC := 1.8
const BLACKOUT_START := 3.0
const BLACKOUT_THRESHOLD := 1.5
const DECAY_PERFECT_END := 0.24
const DECAY_GOOD_END := 0.72
const DECAY_OKAY_END := 1.44
const DECAY_MISS_END := 2.4
const REACT_TILE_START := 1.2     # Red/Blue's own tile before it resolves
const BYSTANDER_STARTS := [2.0, 2.6]
const RED_SETTLE_SEC := 1.5
const BLUE_FREEZE_SEC := 1.0      # matches EndlessRunner's apply_pause(1.0) exactly
const BLUE_SETTLE_SEC := 2.5
# Beat of stillness between one playthrough ending and the next starting -
# reads as a deliberate reset rather than an abrupt jump-cut restart.
const LOOP_GAP_SEC := 1.0

# Matches PauseMenu's/EndlessEndScreen's/StageResultScreen's own portrait
# button treatment - a user request for GOT IT to be sized/styled the same as
# every other redesigned button this pass touched.
const BUTTON_SIZE := Vector2(380, 140)
const BUTTON_FONT := 46  # bumped by a lot on a further user request

# Matches the real board's own portrait cell size, so the demo tile reads as
# an actual timer rather than a scaled-down illustration.
const TILE_SIZE := 200.0
const TILE_DIGIT_RATIO := 0.27
const TILE_NAME_RATIO := 0.18

# The popup lives on its own CanvasLayer parented to this node, so nothing in the
# screen router hides it - it has to be torn down explicitly. The stage is
# already in PLAYING when a popup is up, so the pause button is live behind it
# and the player can quit to the title mid-popup. Tracked here and freed on any
# state change out of PLAYING; a retry re-emits PLAYING too, which clears a
# stale popup instead of stacking a second one on top of it.
var _live_layer: CanvasLayer

# Bumped whenever the live popup is torn down (a state change, or a fresh
# popup replacing it) - an in-flight demo coroutine checks this before
# touching any node, so a stage change mid-animation can't leave a stray
# callback writing to freed UI a moment later.
var _demo_token: int = 0

func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(_new_state: int) -> void:
	_dismiss_live_popup()

func _dismiss_live_popup() -> void:
	_demo_token += 1
	if _live_layer != null and is_instance_valid(_live_layer):
		_live_layer.queue_free()
	_live_layer = null

func check_and_show(stage_data: StageData, on_ready: Callable) -> void:
	var new_types: Array = []
	for td in stage_data.timers:
		if td == null:
			continue
		var t: int = td.timer_type
		if not new_types.has(t) and _is_new(t):
			new_types.append(t)

	if new_types.is_empty():
		on_ready.call()  # nothing new - start immediately, no visible delay
		return
	_show_next(new_types, on_ready)

func _is_new(t: int) -> bool:
	return SaveManager.load_high_score("seen_type_%d" % t) == 0

func _show_next(types: Array, on_ready: Callable) -> void:
	var t: int = types[0]
	var on_dismiss := func() -> void:
		SaveManager.save_high_score("seen_type_%d" % t, 1)
		var rest: Array = types.slice(1)
		if rest.is_empty():
			on_ready.call()
		else:
			_show_next(rest, on_ready)
	_show_popup(t, on_dismiss)

func _show_popup(t: int, on_dismiss: Callable) -> void:
	_demo_token += 1
	var token := _demo_token
	var accent: Color = TimerTypeInfo.color_of(t)

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_live_layer = layer

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
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
	sb.border_color = accent
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.custom_minimum_size = Vector2(620, 0)
	panel.add_child(col)

	col.add_child(_label("NEW TIMER", 26, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_label(TimerTypeInfo.name_of(t), 48, accent, HORIZONTAL_ALIGNMENT_CENTER))

	var desc := _label(TimerTypeInfo.desc_of(t), 30, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(600, 0)
	col.add_child(desc)

	var tile := _make_tile(t, "")
	var tile_wrap := CenterContainer.new()
	tile_wrap.add_child(tile)
	col.add_child(tile_wrap)

	# Red/Blue need bystanders reacting for the effect to actually read - a
	# tile counting down in isolation can't show "this makes OTHER timers
	# speed up/freeze", so these two get the same two-Normal-tile row the Help
	# screen's own demo uses.
	var bystanders: Array[HelpDemoTile] = []
	if t == TimerData.TimerType.RED or t == TimerData.TimerType.BLUE:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		for i in range(2):
			var b := _make_tile(TimerData.TimerType.NORMAL, TimerTypeInfo.name_of(TimerData.TimerType.NORMAL))
			row.add_child(b)
			bystanders.append(b)
		col.add_child(row)

	var got := Button.new()
	got.text = "GOT IT"
	got.custom_minimum_size = BUTTON_SIZE
	got.add_theme_font_size_override("font_size", BUTTON_FONT)
	got.add_theme_color_override("font_color", Color.WHITE)
	got.add_theme_color_override("font_outline_color", accent)
	got.add_theme_constant_override("outline_size", 4)
	got.add_theme_stylebox_override("normal", _box(accent, 0.85, 0.35, 8))
	got.add_theme_stylebox_override("hover", _box(accent, 0.7, 0.5, 12))
	got.add_theme_stylebox_override("pressed", _box(accent, 0.6, 0.4, 6))
	# Locked until the demo below finishes playing through once - see this
	# file's own header comment for why.
	got.disabled = true
	got.modulate.a = 0.4
	var on_got := func() -> void:
		if got.disabled:
			return
		if _live_layer == layer:
			_live_layer = null
		layer.queue_free()
		on_dismiss.call()
	got.pressed.connect(on_got)
	var got_wrap := CenterContainer.new()
	got_wrap.add_child(got)
	col.add_child(got_wrap)

	# Loops rather than playing once and freezing - a player who was still
	# reading the description when the first playthrough finished (a
	# user-reported real case) gets another look instead of a dead final
	# frame. GOT IT unlocks the first time it completes and stays unlocked;
	# the demo just keeps going until the player actually dismisses it.
	_play_demo(t, tile, bystanders, token, func() -> void:
		if is_instance_valid(got):
			got.disabled = false
			got.modulate.a = 1.0
	)

func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _box(accent: Color, darken: float, shadow_alpha: float = 0.0, shadow_size: int = 0) -> StyleBoxFlat:
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

func _make_tile(type: int, display_name: String) -> HelpDemoTile:
	var tile := HelpDemoTile.new()
	tile.interactive = false  # plays itself; not tappable, unlike the Help screen's
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.configure(type, display_name, roundi(TILE_SIZE * TILE_DIGIT_RATIO), roundi(TILE_SIZE * TILE_NAME_RATIO))
	tile.idle()
	return tile

# --- Demo dispatch (mirrors HelpScreen._on_type_tapped and its per-type
# functions, trimmed of the whole-screen dimming/caption machinery this popup
# doesn't have) ---------------------------------------------------------------

func _still(token: int) -> bool:
	return token == _demo_token

func _random_perfect_stop() -> float:
	return randf_range(0.0, ScoreManager.perfect_max)

# Loops the demo for as long as the popup stays open, rather than playing
# once and leaving the tile frozen on its last frame - see the call site's own
# comment for why. `on_first_finished` fires only after the very first
# playthrough (what unlocks GOT IT); every loop after that just keeps playing.
func _play_demo(t: int, tile: HelpDemoTile, bystanders: Array[HelpDemoTile], token: int,
		on_first_finished: Callable) -> void:
	var unlocked := false
	while _still(token) and is_instance_valid(tile):
		match t:
			TimerData.TimerType.NORMAL:
				await _play_normal(tile, token)
			TimerData.TimerType.GOLDEN:
				await _play_golden(tile, token)
			TimerData.TimerType.BLACKOUT:
				await _play_blackout(tile, token)
			TimerData.TimerType.DECAY:
				await _play_decay(tile, token)
			TimerData.TimerType.RED:
				await _play_red(tile, bystanders, token)
			TimerData.TimerType.BLUE:
				await _play_blue(tile, bystanders, token)
		if not _still(token):
			return
		if not unlocked:
			unlocked = true
			on_first_finished.call()
		await get_tree().create_timer(LOOP_GAP_SEC, true, false, true).timeout
		if not _still(token) or not is_instance_valid(tile):
			return
		tile.idle()
		for b in bystanders:
			if is_instance_valid(b):
				b.idle()

func _play_normal(tile: HelpDemoTile, token: int) -> void:
	var stop := _random_perfect_stop()
	await tile.play_countdown(NORMAL_START, stop)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % stop, RESULT_HOLD_SEC)
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout

func _play_golden(tile: HelpDemoTile, token: int) -> void:
	await tile.play_blur(GOLDEN_BLUR_SEC)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "0.00", RESULT_HOLD_SEC, "x2")
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout

func _play_blackout(tile: HelpDemoTile, token: int) -> void:
	var stop := _random_perfect_stop()
	await tile.play_countdown(BLACKOUT_START, stop, BLACKOUT_THRESHOLD)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % stop, RESULT_HOLD_SEC, "x2.5")
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout

func _play_decay(tile: HelpDemoTile, token: int) -> void:
	await tile.play_decay_climb(DECAY_PERFECT_END, DECAY_GOOD_END, DECAY_OKAY_END, DECAY_MISS_END)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("MISS", "%.2f" % DECAY_MISS_END, RESULT_HOLD_SEC)
	await get_tree().create_timer(RESULT_HOLD_SEC, true, false, true).timeout

func _play_red(tile: HelpDemoTile, bystanders: Array[HelpDemoTile], token: int) -> void:
	for i in range(bystanders.size()):
		_run_bystander_speedup(bystanders[i], BYSTANDER_STARTS[i], token)
	var stop := _random_perfect_stop()
	await tile.play_countdown(REACT_TILE_START, stop)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)
	for b in bystanders:
		if is_instance_valid(b):
			b.react_speedup_permanent()
	await get_tree().create_timer(RED_SETTLE_SEC, true, false, true).timeout

func _run_bystander_speedup(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
	if not _still(token) or not is_instance_valid(b):
		return
	b.play_grade("PERFECT", "%.2f" % b.value, RESULT_HOLD_SEC, "x1.25")

func _play_blue(tile: HelpDemoTile, bystanders: Array[HelpDemoTile], token: int) -> void:
	for i in range(bystanders.size()):
		_run_bystander_plain(bystanders[i], BYSTANDER_STARTS[i], token)
	var stop := _random_perfect_stop()
	await tile.play_countdown(REACT_TILE_START, stop)
	if not _still(token) or not is_instance_valid(tile):
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, RESULT_HOLD_SEC)
	for b in bystanders:
		if is_instance_valid(b):
			b.react_freeze(BLUE_FREEZE_SEC)
	await get_tree().create_timer(BLUE_SETTLE_SEC, true, false, true).timeout

func _run_bystander_plain(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
