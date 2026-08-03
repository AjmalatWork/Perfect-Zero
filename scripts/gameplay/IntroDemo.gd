extends Node
class_name IntroDemo

# Runs once ever, before a brand-new player's very first stage: a ghost cursor
# glides toward a real TimerSlot as a "look here" cue while it counts down, then
# the countdown itself eases to a dead stop at 0.00 - unclickable until it's
# fully settled there - so the player has to land the click themselves. Casual
# players skip text and jump straight into play, so this is the one piece of
# onboarding that teaches by making them do it rather than by being read.
# Reuses the actual TimerSlot scene at its normal size, so the flash/grade-sign/
# burst the player sees here is identical to what a real PERFECT looks like
# in play.

const DEMO_DURATION := 2.0
const SLOWDOWN_AT := 0.03  # current_time value at which the countdown starts easing toward a stop
const SETTLE_DURATION := 0.8  # how long the eased glide from SLOWDOWN_AT down to a dead stop at 0.00 takes
const HOLD_AFTER_CLICK := 0.5  # lets the stop flash/grade-sign/burst read in full before fading out
const FADE_OUT_DURATION := 0.35
const CURSOR_SIZE := Vector2(32, 32)
const CURSOR_COLOR := Color(1, 1, 1, 0.92)
const CAPTION_COLOR := Color("dfe3ee")

# Freed and re-nulled by _finish() - tracked so a click-to-skip can't double-fire
# the finish path if it races the settled timer's own click.
var _live_layer: CanvasLayer
var _dismissed: bool = false
var _on_ready: Callable

# _dim is kept separate from the rest of the demo furniture (_content) so
# _finish() can hide the timer/caption/cursor instantly (the swap to the real
# stage happens behind it) while fading only the dim veil - a single smooth
# reveal of the already-built stage, instead of a blank gap then a hard pop of
# timers appearing.
var _dim: ColorRect
var _content: Control

# Set right before EventBus.timer_stopped is connected, read by
# _on_demo_slot_stopped() once the click actually lands.
var _wait_slot: TimerSlot

func maybe_show(on_ready: Callable) -> void:
	if SaveManager.load_high_score("seen_intro_demo") != 0:
		on_ready.call()  # already seen - never delay a returning player
		return
	_run(on_ready)

func _run(on_ready: Callable) -> void:
	_dismissed = false
	_on_ready = on_ready

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_live_layer = layer

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to anything behind, and catch skip-taps itself
	dim.gui_input.connect(_on_dim_input)
	root.add_child(dim)
	_dim = dim

	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(content)
	_content = content

	var caption := Label.new()
	caption.text = "STOP IT AT 0.00"
	caption.add_theme_font_size_override("font_size", 36)
	caption.add_theme_color_override("font_color", CAPTION_COLOR)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 220
	caption.modulate.a = 0.0
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(caption)
	var caption_tween := create_tween()
	caption_tween.tween_property(caption, "modulate:a", 1.0, 0.4)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(center)

	# Same scene, same default size as a real stage timer - no special-cased visuals.
	var slot: TimerSlot = preload("res://scenes/TimerSlot.tscn").instantiate()
	# Unclickable until it settles below - a premature click would grade as
	# whatever a real early click grades as (MISS/FAIL), which would make the
	# player's first-ever moment in the game a failure screen instead of a PERFECT.
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(slot)
	var data := TimerData.new()
	data.timer_type = TimerData.TimerType.NORMAL
	data.start_time = DEMO_DURATION
	slot.setup(data)

	var cursor := _make_cursor()
	content.add_child(cursor)

	# Let the CenterContainer settle the slot's final layout before reading its
	# position - global_position isn't final until at least one layout pass.
	await get_tree().process_frame
	await get_tree().process_frame
	if _dismissed:
		return

	var target: Vector2 = slot.global_position + slot.size * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	cursor.position = Vector2(viewport_size.x - 60.0, viewport_size.y - 60.0) - CURSOR_SIZE * 0.5

	# Purely a "look here" cue now, timed to arrive right as the timer grinds to
	# its dead stop - nothing about the cursor's motion resolves the timer itself.
	var move_tween := create_tween()
	move_tween.tween_property(cursor, "position", target - CURSOR_SIZE * 0.5,
		(DEMO_DURATION - SLOWDOWN_AT) + SETTLE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Let the timer count down for real, on its own clock, until it nears zero.
	while is_instance_valid(slot) and not slot.stopped and slot.current_time > SLOWDOWN_AT:
		await get_tree().process_frame
	if _dismissed or not is_instance_valid(slot) or slot.stopped:
		return

	# From here the countdown stops ticking on its own (speed_multiplier 0) and a
	# decelerating tween eases current_time the rest of the way down to an exact
	# 0.00 instead of snapping there, so the last instant reads as "grinding to a
	# halt" rather than a hard cut. TimerSlot's own _process keeps running and
	# keeps redrawing the digit label every frame - it just has nothing left to
	# subtract, so the tween is the only thing still moving the value.
	slot.speed_multiplier = 0.0
	var settle_tween := create_tween()
	settle_tween.tween_property(slot, "current_time", 0.0, SETTLE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await settle_tween.finished
	if _dismissed or not is_instance_valid(slot) or slot.stopped:
		return

	# Only clickable once it's actually dead-stopped at 0.00 - a click mid-glide
	# would grade on whatever partial value it happened to be at, undermining the
	# "wait for the true stop" lesson.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	# TimerSlot._process keeps running even at a dead-stopped current_time (it
	# has to, while the settle tween above is still moving that value) - left
	# on past this point, it plays a tick every second at its most urgent pitch
	# (progress clamps to 1.0 once current_time hits 0.0) for as long as the
	# player takes to click, which is the least appropriate moment in the game
	# for an escalating urgency cue. Nothing left in TimerSlot needs its
	# _process once it's settled and waiting - the click is handled by
	# _gui_input, not _process.
	slot.set_process(false)

	_wait_slot = slot
	EventBus.timer_stopped.connect(_on_demo_slot_stopped)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_finish()

func _on_demo_slot_stopped(source: Node, _grade: String, _type: int, _distance: float) -> void:
	if source != _wait_slot:
		return
	EventBus.timer_stopped.disconnect(_on_demo_slot_stopped)
	await get_tree().create_timer(HOLD_AFTER_CLICK).timeout
	_finish()

func _finish() -> void:
	if _dismissed:
		return
	_dismissed = true
	# _on_demo_slot_stopped() already disconnects itself once the real click
	# lands, but a skip-tap on the dim veil reaches _finish() directly and
	# never goes through that path - without this, the connection outlives the
	# demo for the rest of the session and _on_demo_slot_stopped() runs (and
	# no-ops via its source check) on every future stop in the game.
	if EventBus.timer_stopped.is_connected(_on_demo_slot_stopped):
		EventBus.timer_stopped.disconnect(_on_demo_slot_stopped)
	SaveManager.save_high_score("seen_intro_demo", 1)
	# The demo just taught NORMAL directly - skip the redundant "NEW TIMER"
	# popup TutorialManager would otherwise show for it immediately after.
	SaveManager.save_high_score("seen_type_%d" % TimerData.TimerType.NORMAL, 1)

	# Drop the demo furniture immediately and spawn the real stage while still
	# fully hidden behind the dim veil, then fade just that veil away - the
	# player sees one smooth reveal of the already-built stage, not a blank gap
	# followed by a hard pop of timers appearing.
	if is_instance_valid(_content):
		_content.visible = false
	_on_ready.call()

	if is_instance_valid(_dim):
		await get_tree().process_frame  # let the stage actually finish building before revealing it
		var fade := create_tween()
		fade.tween_property(_dim, "color:a", 0.0, FADE_OUT_DURATION)
		await fade.finished
	if is_instance_valid(_live_layer):
		_live_layer.queue_free()
	_live_layer = null

func _make_cursor() -> Panel:
	var cursor := Panel.new()
	cursor.size = CURSOR_SIZE
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.z_index = 25
	var sb := StyleBoxFlat.new()
	sb.bg_color = CURSOR_COLOR
	sb.set_corner_radius_all(int(CURSOR_SIZE.x * 0.5))
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	cursor.add_theme_stylebox_override("panel", sb)
	return cursor
