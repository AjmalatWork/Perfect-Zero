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
# HelpScreen.PRACTICE_START, etc.), which is what guarantees this component
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

# Host opt-in: raise the focused tile above the host's own full-screen focus
# dim by z_index. HelpScreen sets this, because its dim is a sibling of the
# whole content tree and would otherwise cover the tile being practised.
# HelpBubble leaves it off - the bubble is already a modal sitting entirely
# above the board (its root is at z 90), so lifting a tile inside it would only
# raise that tile above the bubble's own furniture for no gain.
var lift_focused_tiles: bool = false

var _demo_token: int = 0
var _type_tiles: Array[HelpDemoTile] = []
var _bystander_tiles: Array[HelpDemoTile] = []
var _bystander_row: HBoxContainer
# Grades from the bystanders' own parallel runs, keyed by tile - see
# _run_bystander for why a parallel coroutine has to report this way.
var _bystander_results: Dictionary = {}

func _s() -> float:
	return HelpScreen.PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

func _still_demo(token: int) -> bool:
	return token == _demo_token

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
			# Timed by the player too now, not scenery - a Red/Blue pass runs
			# all three tiles together and all three are stoppable.
			#
			# Deliberately NOT connected to _on_type_tapped: a bystander's tap
			# is only ever its own run's stop, which the tile consumes itself
			# before the signal fires. Routing it here would try to start a
			# second practice loop, for a plain Normal timer, on top of the
			# Red/Blue pass that already owns this tile.
			b.interactive = true
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

# Starts one tile's practice loop. Tiles sit idle showing their name until
# tapped; that tap starts the loop and only then is the tile live and
# stoppable. Everything else on the page stays idle, so the "one focused
# animation at a time" rule (see HelpDemoTile's header for why six simultaneous
# ones was rejected) still holds - what changed is that the player stops the
# running tile now, repeatedly, instead of a script tapping it once.
#
# Bumping _demo_token first is what lets a tap on a DIFFERENT tile cleanly
# abandon whatever loop is still running.
func _on_type_tapped(tile: HelpDemoTile) -> void:
	if block_taps:
		return
	# A tap on the tile that is already running IS that run's stop - the tile
	# consumed it itself before this signal ever arrived. Restarting the loop
	# here would cancel the run on the exact frame the player's timing mattered.
	if tile.is_practice_run_active():
		return
	# Bumping the token only ends the LOOP. The outgoing tile's own run
	# coroutine keeps counting - and keeps swallowing taps as its stop - until
	# its own _play_token moves on, which only idle() does. Stopping the tiles
	# before the bump is what makes a tap on a second tile actually abandon the
	# first rather than leave it running invisibly underneath.
	_stop_all_tiles()
	_demo_token += 1
	var token := _demo_token
	var text := "%s - %s" % [TimerTypeInfo.name_of(tile.timer_type),
		TimerTypeInfo.desc_of(tile.timer_type)]
	var accent: Color = TimerTypeInfo.color_of(tile.timer_type)
	type_tapped.emit(tile, text, accent)
	_run_practice_loop(tile, token)

# Runs `tile` over and over until something bumps the token. Each pass is one
# real, stoppable run followed by the pause its ending earned - which is why
# the tile reports last_run_was_tapped rather than the host inferring it from
# the grade: a late enough tap grades FAIL just like never tapping at all, and
# those two endings want different beats.
func _run_practice_loop(tile: HelpDemoTile, token: int) -> void:
	duck_requested.emit(true)
	var focus := _focus_group(tile)
	_dim_page1_except(focus)
	if lift_focused_tiles:
		for t in focus:
			if is_instance_valid(t):
				t.set_focus_lifted(true)
	tile.set_selected(true)
	while _still_demo(token) and is_instance_valid(tile):
		var grade := await _run_practice_pass(tile, token)
		# "" means the run was cancelled mid-flight (see HelpDemoTile) - the
		# tile has already moved on to whatever cancelled it, so this loop must
		# not restart it or touch it again.
		if grade == "" or not _still_demo(token) or not is_instance_valid(tile):
			break
		var delay: float = replay_delay_after_stop if tile.last_run_was_tapped \
			else replay_delay_after_expire
		await get_tree().create_timer(delay, true, false, true).timeout
	# Unconditional, and paired with the emit(true) above. The host's duck is
	# reference-counted, so gating this on _still_demo() would mean every loop
	# abandoned by a tap on another tile skipped its own decrement and left the
	# music one step further from ever coming back up.
	duck_requested.emit(false)

# One pass. Red and Blue take the bystander path because their whole rule is
# what they do to other timers; every other type is just its own run.
func _run_practice_pass(tile: HelpDemoTile, token: int) -> String:
	match tile.timer_type:
		TimerData.TimerType.GOLDEN:
			# Never counts, never expires - it churns until taken, so there is
			# no expiry beat for it and its loop only ever turns over on a tap.
			return await tile.run_tappable_golden("x2")
		TimerData.TimerType.DECAY:
			return await tile.run_tappable_decay(
				HelpScreen.PRACTICE_DECAY_PERFECT_END, HelpScreen.PRACTICE_DECAY_GOOD_END,
				HelpScreen.PRACTICE_DECAY_OKAY_END, HelpScreen.PRACTICE_DECAY_MISS_END)
		TimerData.TimerType.BLACKOUT:
			return await tile.run_tappable_countdown(
				HelpScreen.PRACTICE_START, HelpScreen.BLACKOUT_THRESHOLD, "x2.5")
		TimerData.TimerType.RED, TimerData.TimerType.BLUE:
			return await _run_reaction_pass(tile, token)
	return await tile.run_tappable_countdown(HelpScreen.PRACTICE_START)

# Red/Blue plus their two bystanders, all three tappable and all three timed by
# the player. The bystanders start later than the acting tile on purpose (see
# HelpScreen.PRACTICE_BYSTANDER_STARTS) so they are still counting when the
# reaction lands and it can be seen arriving.
func _run_reaction_pass(tile: HelpDemoTile, token: int) -> String:
	_bystander_results.clear()
	for b in _bystander_tiles:
		b.set_present(true)
	for i in range(_bystander_tiles.size()):
		_run_bystander(_bystander_tiles[i], HelpScreen.PRACTICE_BYSTANDER_STARTS[i], token)

	var grade := await tile.run_tappable_countdown(HelpScreen.PRACTICE_START)
	if grade == "" or not _still_demo(token) or not is_instance_valid(tile):
		return grade

	# Fires on ANY resolved grade, not just a good one - EndlessRunner's own
	# _dispatch_reaction does the same. The reaction is about the timer
	# resolving at all, so a demo that only showed it after a clean stop would
	# be teaching a rule the board does not have.
	for b in _bystander_tiles:
		if not is_instance_valid(b):
			continue
		if tile.timer_type == TimerData.TimerType.RED:
			b.react_speedup_permanent()
		else:
			b.react_freeze(HelpScreen.BLUE_FREEZE_SEC)

	# The group restarts together, so the pass isn't over until the bystanders
	# have been stopped (or run out) too - otherwise a restart would yank live
	# timers out from under a player still working on them.
	while _still_demo(token) and _bystander_results.size() < _bystander_tiles.size():
		await get_tree().process_frame
	return grade

# Fire-and-forget wrapper: GDScript forbids capturing a coroutine's handle to
# await later, so a parallel run has to stash its own result instead of
# returning it.
func _run_bystander(b: HelpDemoTile, start: float, token: int) -> void:
	var g := await b.run_tappable_countdown(start)
	if _still_demo(token):
		_bystander_results[b] = g

# Which tiles stay lit while `tile` practises. Red and Blue keep their
# bystanders visible because those are part of what is being demonstrated.
func _focus_group(tile: HelpDemoTile) -> Array:
	if tile.timer_type == TimerData.TimerType.RED \
			or tile.timer_type == TimerData.TimerType.BLUE:
		return [tile] + _bystander_tiles
	return [tile]

func _dim_page1_except(keep: Array) -> void:
	for t in _type_tiles:
		t.set_dimmed(not keep.has(t))

func _undim_page1() -> void:
	for t in _type_tiles:
		t.set_dimmed(false)

# --- Host API -------------------------------------------------------------

# True when `global_pos` lands on a tile that currently has a live practice
# run - meaning that tap IS that run's stop.
#
# Hosts need this because they see the release first: HelpScreen classifies
# swipe-vs-tap in _input(), which runs ahead of any Control's _gui_input, and
# its plain-tap branch cancels every running demo. Without this check that
# cancel lands before the tile has been given the release, so the tile is idled
# out from under its own stop - the tap then falls through to "start a demo"
# and RESTARTS the timer the player was trying to stop, on the exact frame
# their timing mattered.
# Forwarded to every tile - see HelpDemoTile.suppress_taps. block_taps above
# only stops a swipe from STARTING a demo; this is what stops one from resolving
# a demo already running, which the tile owns itself and this component never
# sees.
func set_suppress_taps(on: bool) -> void:
	for t in _type_tiles + _bystander_tiles:
		if is_instance_valid(t):
			t.suppress_taps = on

func tap_lands_on_active_run(global_pos: Vector2) -> bool:
	for t in _type_tiles + _bystander_tiles:
		if is_instance_valid(t) and t.is_practice_run_active() \
				and t.get_global_rect().has_point(global_pos):
			return true
	return false

# Stops whatever demo is currently playing and resets every tile to idle -
# call on close/leave/page-switch. Doesn't touch music-ducking or caption/
# description display - those are the host's own shared state; the host's own
# cancel-everything function already does a hard reset of both independently
# of this.
func cancel_demos() -> void:
	_demo_token += 1
	_stop_all_tiles()
	_undim_page1()

# Idles every tile this component owns, which is what actually halts an
# in-flight run coroutine (via the tile's own _play_token) as opposed to merely
# ending the loop that started it.
func _stop_all_tiles() -> void:
	_bystander_results.clear()
	for t in _type_tiles:
		if is_instance_valid(t):
			t.idle()
	for b in _bystander_tiles:
		if is_instance_valid(b):
			b.idle()
			b.set_present(false)
