extends VBoxContainer
class_name TimerTypesLegend

# The live, tappable Timer Types legend (self/board groups, divider, tap-to-see
# demos, Red/Blue bystanders) - extracted so HelpScreen's page 1 and the
# in-game HelpBubble's Timer Types page can share ONE implementation instead
# of two hand-kept-in-sync copies. The two copies drifted in practice (tile
# size, text size, spacing, bystander size all diverged between them) - this
# is the fix for that drift, not just this one round of it.
#
# Sizing/timing constants are deliberately NOT redeclared here - they're read
# straight off HelpScreen's own consts (HelpScreen.TIMER_TILE_PORTRAIT,
# HelpScreen.NORMAL_START, etc.), which is what guarantees this component
# renders and behaves pixel-for-pixel like HelpScreen's page 1 always did,
# with nothing to keep in sync by hand.
#
# This IS the page's own VBoxContainer (not a wrapper around one) - a host
# adds it directly wherever HelpScreen used to build `col` inline. It emits
# `type_tapped` the instant a tile is tapped (before the demo starts) so the
# host can show the description however fits its own layout - HelpScreen's
# portrait anchored-overlay caption and HelpBubble's simple in-flow label are
# both real UI differences, not something worth forcing into one shape.

signal type_tapped(tile: HelpDemoTile, text: String, accent: Color)

# Emitted instead of calling AudioServer directly - duck state has to be one
# shared counter per HOST (HelpScreen already ducks for pages 2/3 too, and the
# two can legitimately overlap - a page-1 demo still finishing as the player
# swipes to page 2), so owning a second, independent counter in here would let
# this component's own demo finishing unmute music a page-2 demo still expects
# muted. The host connects this to its own existing _duck_music.
signal duck_requested(on: bool)

const MUTED := Color("8b90a8")

# Host sets this true while its own gesture (HelpScreen's page-swipe) is
# active, so a tap that's actually the tail end of a swipe doesn't start a
# demo. HelpBubble never needs to set it.
var block_taps: bool = false

# Practice-mode replay pacing, assigned by the host. Plain vars rather than the
# statically-read HelpScreen consts this component uses everywhere else,
# because these two are @export instance vars on HelpScreen (Inspector-tunable)
# and there is no host reference here to read them through - see
# HelpScreen._build_page_types(), which pushes them in. Defaults match
# HelpScreen's own so HelpBubble, which sets neither, still behaves sensibly.
var replay_delay_after_stop: float = 2.0
var replay_delay_after_expire: float = 2.0

var _demo_token: int = 0
var _type_tiles: Array[HelpDemoTile] = []
var _bystander_tiles: Array[HelpDemoTile] = []
var _bystander_row: HBoxContainer

func _s() -> float:
	return HelpScreen.PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

func _still_demo(token: int) -> bool:
	return token == _demo_token

func _random_perfect_stop() -> float:
	return randf_range(0.0, TimerSlot.PERFECT_MAX)

# --- Build --------------------------------------------------------------------

# Explicit, not _ready() - the host builds this fully off-tree (same pattern
# every other page/group builder in this codebase already uses) and attaches
# it afterward. Self-building in _ready() would race the host's own
# add_child() calls made before this ever entered the tree (e.g. appending a
# trailing prompt label): _ready() only fires once the whole branch is in the
# tree, by which point anything the host already added would sort ahead of
# this method's own children instead of after them.
func build() -> void:
	add_theme_constant_override("separation", _fs(12))
	alignment = BoxContainer.ALIGNMENT_CENTER

	var self_group := _build_type_group("AFFECTS ONLY ITSELF", [
		TimerData.TimerType.NORMAL, TimerData.TimerType.GOLDEN,
		TimerData.TimerType.BLACKOUT, TimerData.TimerType.DECAY,
	], false)
	var board_group := _build_type_group("AFFECTS THE WHOLE BOARD", [
		TimerData.TimerType.RED, TimerData.TimerType.BLUE,
	], true)

	# Portrait stacks the two groups; landscape sets them side by side - the one
	# place the extra width is genuinely worth using.
	if Layout.is_portrait():
		add_child(self_group)
		# Fixed-size gap, not an expanding one - see HelpScreen's own history on
		# this exact constant: an expanding gap absorbed nearly a whole screen's
		# free space and read as a broken layout rather than a deliberate seam.
		var group_gap := CenterContainer.new()
		group_gap.custom_minimum_size = Vector2(0, _fs(46))
		group_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_gap.add_child(_make_divider())
		add_child(group_gap)
		add_child(board_group)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _fs(56))
		row.add_child(self_group)
		row.add_child(board_group)
		var wrap := CenterContainer.new()
		wrap.add_child(row)
		add_child(wrap)

# `with_bystanders` gives Red and Blue something to visibly act on - they are
# the only two types whose rule mentions other timers at all. Bystanders are
# plain Normal tiles at the SAME size as every other tile - never shrunk.
func _build_type_group(heading: String, types: Array, with_bystanders: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(6))

	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", _fs(HelpScreen.SECTION_LABEL_SIZE))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _fs(12))
	grid.add_theme_constant_override("v_separation", _fs(12))
	for t in types:
		var tile := _make_tile(t, TimerTypeInfo.name_of(t))
		tile.tapped.connect(_on_type_tapped)
		_type_tiles.append(tile)
		grid.add_child(tile)

	var wrap := CenterContainer.new()
	wrap.add_child(grid)
	col.add_child(wrap)

	# The bystander row holds its space permanently and its tiles fade via
	# set_present() (modulate) rather than the row collapsing/expanding - tried
	# and reverted on HelpScreen: collapsing it shifted every other tile on the
	# page during a demo. Stationary timers win.
	if with_bystanders:
		_bystander_row = HBoxContainer.new()
		_bystander_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_bystander_row.add_theme_constant_override("separation", _fs(12))
		for i in range(2):
			var b := _make_tile(TimerData.TimerType.NORMAL,
				TimerTypeInfo.name_of(TimerData.TimerType.NORMAL))
			# Bystanders are scenery, not choices.
			b.interactive = false
			b.modulate.a = 0.0
			_bystander_tiles.append(b)
			_bystander_row.add_child(b)
		var row_wrap := CenterContainer.new()
		row_wrap.add_child(_bystander_row)
		col.add_child(row_wrap)

	return col

func _make_tile(type: int, display_name: String) -> HelpDemoTile:
	var s: float = HelpScreen.TIMER_TILE_PORTRAIT if Layout.is_portrait() else HelpScreen.TIMER_TILE_LANDSCAPE
	var tile := HelpDemoTile.new()
	tile.custom_minimum_size = Vector2(s, s)
	tile.configure(type, display_name, roundi(s * HelpScreen.TIMER_DIGIT_RATIO), roundi(s * HelpScreen.TIMER_NAME_RATIO))
	tile.idle()
	return tile

# Same fading hairline every overhauled screen uses (Credits/StageResult/
# EndlessEnd/HelpScreen itself) - centre-bright, transparent at both ends.
func _make_divider() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 1

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(_divider_width(), 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(MUTED.r, MUTED.g, MUTED.b, HelpScreen.DIVIDER_ALPHA)
	return rect

func _divider_width() -> float:
	var w: float = size.x if size.x > 0.0 else Layout.canvas_size.x
	return minf(HelpScreen.DIVIDER_WIDTH, w * HelpScreen.DIVIDER_MAX_CANVAS_FRACTION)

# --- Tap dispatch + demos ------------------------------------------------------

# Dispatches to one scripted, complete demonstration per type - a tile plays
# out its entire rule end to end (spawn through resolution) while every tile
# not involved dims out of the way. Bumping _demo_token first is what lets a
# second tap (same tile or a different one) cleanly interrupt whatever's still
# playing.
func _on_type_tapped(tile: HelpDemoTile) -> void:
	if block_taps:
		return
	_demo_token += 1
	var token := _demo_token
	var text := "%s - %s" % [TimerTypeInfo.name_of(tile.timer_type),
		TimerTypeInfo.desc_of(tile.timer_type)]
	var accent: Color = TimerTypeInfo.color_of(tile.timer_type)
	type_tapped.emit(tile, text, accent)

	match tile.timer_type:
		TimerData.TimerType.NORMAL:
			_play_normal_demo(tile, token)
		TimerData.TimerType.GOLDEN:
			_play_golden_demo(tile, token)
		TimerData.TimerType.BLACKOUT:
			_play_blackout_demo(tile, token)
		TimerData.TimerType.DECAY:
			_play_decay_demo(tile, token)
		TimerData.TimerType.RED:
			_play_red_demo(tile, token)
		TimerData.TimerType.BLUE:
			_play_blue_demo(tile, token)

func _dim_page1_except(keep: Array) -> void:
	for t in _type_tiles:
		t.set_dimmed(not keep.has(t))

func _undim_page1() -> void:
	for t in _type_tiles:
		t.set_dimmed(false)

func _play_normal_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	var stop := _random_perfect_stop()
	await tile.play_countdown(HelpScreen.NORMAL_START, stop)
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("PERFECT", "%.2f" % stop, HelpScreen.RESULT_HOLD_SEC)
	await get_tree().create_timer(HelpScreen.RESULT_HOLD_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token)

func _play_golden_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	await tile.play_blur(HelpScreen.GOLDEN_BLUR_SEC)
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("PERFECT", "0.00", HelpScreen.RESULT_HOLD_SEC, "x2")
	await get_tree().create_timer(HelpScreen.RESULT_HOLD_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token)

func _play_blackout_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	var stop := _random_perfect_stop()
	await tile.play_countdown(HelpScreen.BLACKOUT_START, stop, HelpScreen.BLACKOUT_THRESHOLD)
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("PERFECT", "%.2f" % stop, HelpScreen.RESULT_HOLD_SEC, "x2.5")
	await get_tree().create_timer(HelpScreen.RESULT_HOLD_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token)

func _play_decay_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	_dim_page1_except([tile])
	tile.set_selected(true)
	await tile.play_decay_climb(HelpScreen.DECAY_PERFECT_END, HelpScreen.DECAY_GOOD_END,
		HelpScreen.DECAY_OKAY_END, HelpScreen.DECAY_MISS_END)
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("MISS", "%.2f" % HelpScreen.DECAY_MISS_END, HelpScreen.RESULT_HOLD_SEC)
	await get_tree().create_timer(HelpScreen.RESULT_HOLD_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token)

func _play_red_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	var keep: Array = [tile] + _bystander_tiles
	_dim_page1_except(keep)
	tile.set_selected(true)
	for b in _bystander_tiles:
		b.set_present(true)
	for i in range(_bystander_tiles.size()):
		_run_bystander_speedup(_bystander_tiles[i], HelpScreen.BYSTANDER_STARTS[i], token)
	await tile.play_countdown(HelpScreen.REACT_TILE_START, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, HelpScreen.RESULT_HOLD_SEC)
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.react_speedup_permanent()
	await get_tree().create_timer(HelpScreen.RED_SETTLE_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token, keep)

func _run_bystander_speedup(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(b):
		return
	b.play_grade("PERFECT", "%.2f" % b.value, HelpScreen.RESULT_HOLD_SEC, "x1.25")

func _play_blue_demo(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	var keep: Array = [tile] + _bystander_tiles
	_dim_page1_except(keep)
	tile.set_selected(true)
	for b in _bystander_tiles:
		b.set_present(true)
	for i in range(_bystander_tiles.size()):
		_run_bystander_plain(_bystander_tiles[i], HelpScreen.BYSTANDER_STARTS[i], token)
	await tile.play_countdown(HelpScreen.REACT_TILE_START, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(tile):
		duck_requested.emit(false)
		return
	tile.play_grade("PERFECT", "%.2f" % tile.value, HelpScreen.RESULT_HOLD_SEC)
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.react_freeze(HelpScreen.BLUE_FREEZE_SEC)
	await get_tree().create_timer(HelpScreen.BLUE_SETTLE_SEC, true, false, true).timeout
	duck_requested.emit(false)
	_end_type_demo(tile, token, keep)

func _run_bystander_plain(b: HelpDemoTile, start: float, token: int) -> void:
	await b.play_countdown(start, _random_perfect_stop())
	if not _still_demo(token) or not is_instance_valid(b):
		return
	b.play_grade("PERFECT", "%.2f" % b.value, HelpScreen.RESULT_HOLD_SEC)

# Shared close: holds the resolved state a beat, then fades every dimmed tile
# back and resets whichever tiles this sequence actually drove.
func _end_type_demo(tile: HelpDemoTile, token: int, also: Array = []) -> void:
	if not _still_demo(token) or not is_instance_valid(tile):
		return
	tile.set_selected(false)
	await get_tree().create_timer(0.3, true, false, true).timeout
	if not _still_demo(token):
		return
	_undim_page1()
	tile.idle()
	for t in also:
		if t != tile and is_instance_valid(t):
			t.idle()
			if _bystander_tiles.has(t):
				t.set_present(false)

# --- Host API -------------------------------------------------------------

# Stops whatever demo is currently playing and resets every tile to idle -
# call on close/leave/page-switch. Doesn't touch music-ducking or caption/
# description display - those are the host's own shared state; the host's own
# cancel-everything function already does a hard reset of both independently
# of this.
func cancel_demos() -> void:
	_demo_token += 1
	for t in _type_tiles:
		if is_instance_valid(t):
			t.idle()
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.idle()
			b.set_present(false)
	_undim_page1()
