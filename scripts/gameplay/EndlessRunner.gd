extends Node
class_name EndlessRunner

# Top-level controller for one Endless run: owns the 3x3 grid, the continuous
# spawn scheduler, elapsed-time escalation, and fail/lives handling. Persistent in
# Main.tscn; start_run() (re)initializes it for each run.

@export var grid_container: Node          # the empty 3x3 GridContainer (columns = 3)
@export var timer_slot_scene: PackedScene
@export var endless_hud: EndlessHUD
@export var multiplier_cap_value: float = -1.0  # -1 = uncapped

# --- Escalation config (tune by feel) ------------------------------------
@export var spawn_trigger_threshold: float = 2.0   # a timer dropping below this triggers a spawn (once)
@export var fallback_spawn_interval: float = 4.0   # force a spawn if this long passes with no spawn
@export var max_timers_start: float = 2.0          # simultaneous soft cap at t=0 ...
@export var max_timers_end: float = 9.0            # ... ramping to full grid by max_timers_ramp_time
@export var max_timers_ramp_time: float = 120.0
@export var value_high_start: float = 14.0         # start-value range high at t=0 ...
@export var value_low_start: float = 10.0          # ... and low
@export var value_high_floor: float = 7.0          # floored range by value_ramp_time
@export var value_low_floor: float = 4.0
@export var value_ramp_time: float = 90.0
@export var cell_size: float = 160.0
@export var min_zero_gap: float = 1.0              # keep spawned timers' zero-moments >= this far apart

# Per-type concurrent caps. -1 = uncapped. "Golden" is the bonus/guaranteed-PERFECT type.
@export var max_red_active: int = -1
@export var max_blue_active: int = -1
@export var max_golden_active: int = -1
@export var max_blackout_active: int = -1
@export var max_decay_active: int = -1

# Pity timer: if no colored (non-Normal) type has spawned in this long, the next
# spawn is forced to be a colored type, drawn from currently-unlocked colored
# types weighted by their own weights (Normal excluded from that draw).
@export var colored_pity_window: float = 20.0

const VALUE_PICK_ATTEMPTS := 20  # random resamples tried to satisfy min_zero_gap before settling

const BLACKOUT_VALUE_MIN := 7.0  # Blackout's own fixed start_time range -
const BLACKOUT_VALUE_MAX := 8.0  # constant regardless of elapsed_time

# Nuke cascade. Fixed total length regardless of timer count, so a full board
# reads as a faster, denser chain rather than a longer wait.
const NUKE_CASCADE_SEC := 0.34
const NUKE_PUNCH_MIN := 1.2      # punch multiplier when only one timer cleared
const NUKE_PUNCH_MAX := 3.0      # ... and at a full grid
const NUKE_PUNCH_MULT_BONUS := 1.25  # extra punch when a score multiplier is live

# Decay's ceiling windows for Endless spawns. TimerData carries per-timer
# defaults for hand-authored Campaign stages; Endless builds its TimerData in
# code, so it needs its own tunables rather than inheriting the script defaults.
# Like Blackout, these stay constant as the run escalates - Decay's pressure is
# already "act now", and shrinking it further with elapsed time made it read as
# unfair rather than urgent.
@export_group("Decay windows")
@export var decay_perfect_duration: float = 0.6
@export var decay_good_duration: float = 1.2
@export var decay_okay_duration: float = 1.8
@export var decay_miss_duration: float = 2.4
@export_group("")

# Type unlock schedule + spawn weights (mirrors the campaign teaching order).
# Defaults set on the EndlessRunner node in Main.tscn; edit there or override
# per-instance in the Inspector.
@export var type_unlocks: Array[TimerUnlock] = []

const GRID_CELLS := 9

var grid_slots: Array = []   # GRID_CELLS entries: a TimerSlot or null
var _cells: Array = []       # GRID_CELLS cell Controls (built once)
var elapsed_time: float = 0.0
var fail_count: int = 0
var max_lives: int = 3
var _time_since_spawn: float = 0.0
var _time_since_colored: float = 0.0
var _running: bool = false

# Results handed to the end screen.
var final_score: int = 0
var best_score: int = 0
var is_new_best: bool = false

func start_run(lives: int) -> void:
	max_lives = lives
	_build_grid()
	_clear_cells()

	ScoreManager.reset_run()
	ScoreManager.multiplier_cap = multiplier_cap_value

	elapsed_time = 0.0
	fail_count = 0
	_time_since_spawn = 0.0
	_time_since_colored = 0.0

	if endless_hud != null:
		endless_hud.set_max_lives(max_lives)
		endless_hud.update_crosses(0)

	_connect_events()
	_running = true
	GameManager.set_state(GameManager.GameState.ENDLESS_PLAYING)
	_try_spawn(true)  # seed the board with one timer

func _process(delta: float) -> void:
	if not _running:
		return
	# Frozen for an animation: the run clock, the spawn scheduler and the
	# difficulty ramp all hold, so a cascade can't advance the escalation or
	# drop a new timer onto a board that is visually stopped.
	if Juice.is_gameplay_frozen():
		return
	elapsed_time += delta
	_time_since_spawn += delta
	_time_since_colored += delta

	# Ambient bed follows the same ramp that drives the simultaneous-timer cap,
	# so the audio escalates in step with the actual difficulty rather than a
	# separate hardcoded timeline.
	AudioManager.set_ambient_intensity(
		clampf(elapsed_time / max_timers_ramp_time, 0.0, 1.0))

	var want_spawn := false

	# Threshold trigger: a running timer crossing below the threshold for the first time.
	for slot in grid_slots:
		if slot != null and not slot.stopped and not slot.has_triggered_spawn:
			if slot.spawn_trigger_value() <= spawn_trigger_threshold:
				slot.has_triggered_spawn = true
				want_spawn = true

	# Fallback trigger: keep the board alive if nothing crossed the threshold.
	if _time_since_spawn >= fallback_spawn_interval:
		want_spawn = true

	if want_spawn:
		_try_spawn(false)

# --- Spawning -------------------------------------------------------------

func _try_spawn(force: bool) -> void:
	var empties := _empty_cells()
	if empties.is_empty():
		return
	# Soft cap on how many timers run at once (grows with elapsed time).
	if not force and _occupied_count() >= int(round(_max_simultaneous())):
		return

	var cell: int = empties[randi() % empties.size()]
	var type := _pick_type()
	_spawn_timer(cell, type, _pick_value(type))
	_time_since_spawn = 0.0

func _spawn_timer(cell: int, type: int, start_value: float) -> void:
	var td := TimerData.new()
	td.timer_type = type
	td.start_time = start_value
	if type == TimerData.TimerType.DECAY:
		td.decay_perfect_duration = decay_perfect_duration
		td.decay_good_duration = decay_good_duration
		td.decay_okay_duration = decay_okay_duration
		td.decay_miss_duration = decay_miss_duration

	var slot: TimerSlot = timer_slot_scene.instantiate()
	slot.custom_minimum_size = Vector2(cell_size, cell_size)
	_cells[cell].add_child(slot)
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.setup(td)
	grid_slots[cell] = slot

	if type != TimerData.TimerType.NORMAL:
		_time_since_colored = 0.0

# --- Escalation -----------------------------------------------------------

func _max_simultaneous() -> float:
	var t := clampf(elapsed_time / max_timers_ramp_time, 0.0, 1.0)
	return lerpf(max_timers_start, max_timers_end, t)

func _pick_value(type: int) -> float:
	var lo: float
	var hi: float
	if type == TimerData.TimerType.BLACKOUT:
		# Blackout stays in its own fixed window regardless of elapsed time -
		# unlike every other type, it doesn't get shorter/harder to react to as
		# the run escalates, since the whole point is timing it by ear rather
		# than by a shrinking visible countdown.
		lo = BLACKOUT_VALUE_MIN
		hi = BLACKOUT_VALUE_MAX
	else:
		var t := clampf(elapsed_time / value_ramp_time, 0.0, 1.0)
		lo = lerpf(value_low_start, value_low_floor, t)
		hi = lerpf(value_high_start, value_high_floor, t)

	# Avoid spawning a timer whose zero-moment lands within min_zero_gap of a
	# timer already running, so the player is never forced to click two at once.
	var occupied := _active_zero_times()
	var best := randf_range(lo, hi)
	var best_gap := _min_gap(best, occupied)
	for i in range(VALUE_PICK_ATTEMPTS - 1):
		if best_gap >= min_zero_gap:
			break
		var candidate := randf_range(lo, hi)
		var gap := _min_gap(candidate, occupied)
		if gap > best_gap:
			best = candidate
			best_gap = gap
	return best

# Projected real-seconds-from-now that each running timer hits zero, given its
# current speed (a Red-boosted timer reaches zero sooner than its raw current_time).
func _active_zero_times() -> Array:
	var out: Array = []
	# Overclock speeds up every live timer, so without this the projections are
	# all ~1.5x too long exactly while the board is at its most crowded.
	var scale: float = maxf(Powerups.timer_speed_scale(), 0.0001)
	for slot in grid_slots:
		if slot != null and not slot.stopped:
			if slot.data == null:
				continue
			# DECAY counts up and GOLDEN never counts at all, so neither has a
			# real zero-moment to collide with - GOLDEN's current_time just sits
			# frozen at its start value. Both are excluded, matching
			# spawn_trigger_value()'s INF for GOLDEN.
			var t: int = slot.data.timer_type
			if t == TimerData.TimerType.DECAY or t == TimerData.TimerType.GOLDEN:
				continue
			out.append(slot.current_time / (maxf(slot.speed_multiplier, 0.0001) * scale))
	return out

func _min_gap(value: float, occupied: Array) -> float:
	if occupied.is_empty():
		return INF
	var closest := INF
	for o in occupied:
		closest = minf(closest, absf(value - o))
	return closest

func _pick_type() -> int:
	if _time_since_colored >= colored_pity_window:
		var forced := _pick_colored_type()
		if forced != -1:
			return forced

	var pool: Array[TimerUnlock] = []
	var total := 0.0
	for u in type_unlocks:
		if elapsed_time >= u.time and _under_type_cap(u.type):
			pool.append(u)
			total += u.weight
	if pool.is_empty():
		return TimerData.TimerType.NORMAL
	var r := randf() * total
	for u in pool:
		r -= u.weight
		if r <= 0.0:
			return u.type
	return TimerData.TimerType.NORMAL

# Weighted pick among unlocked, under-cap colored (non-Normal) types only.
# Returns -1 if none qualify (e.g. nothing colored unlocked yet, or all at cap).
func _pick_colored_type() -> int:
	var pool: Array[TimerUnlock] = []
	var total := 0.0
	for u in type_unlocks:
		if u.type != TimerData.TimerType.NORMAL and elapsed_time >= u.time and _under_type_cap(u.type):
			pool.append(u)
			total += u.weight
	if pool.is_empty():
		return -1
	var r := randf() * total
	for u in pool:
		r -= u.weight
		if r <= 0.0:
			return u.type
	return pool[-1].type

# -1 (uncapped) types, and Normal, always pass. Capped types are excluded from
# the pool once that many are already running on the grid.
func _under_type_cap(type: int) -> bool:
	var cap := _cap_for_type(type)
	if cap < 0:
		return true
	return _count_active_type(type) < cap

func _cap_for_type(type: int) -> int:
	match type:
		TimerData.TimerType.RED:
			return max_red_active
		TimerData.TimerType.BLUE:
			return max_blue_active
		TimerData.TimerType.GOLDEN:
			return max_golden_active
		TimerData.TimerType.BLACKOUT:
			return max_blackout_active
		TimerData.TimerType.DECAY:
			return max_decay_active
		_:
			return -1

func _count_active_type(type: int) -> int:
	var n := 0
	for slot in grid_slots:
		if slot != null and not slot.stopped and slot.data.timer_type == type:
			n += 1
	return n

# --- Grid bookkeeping -----------------------------------------------------

func _build_grid() -> void:
	if not _cells.is_empty():
		return  # cells are persistent - build once
	grid_slots.resize(GRID_CELLS)
	for i in range(GRID_CELLS):
		grid_slots[i] = null
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(cell_size, cell_size)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid_container.add_child(cell)
		_cells.append(cell)

func _clear_cells() -> void:
	for i in range(GRID_CELLS):
		if grid_slots[i] != null and is_instance_valid(grid_slots[i]):
			grid_slots[i].queue_free()
		grid_slots[i] = null

func _empty_cells() -> Array:
	var out: Array = []
	for i in range(GRID_CELLS):
		if grid_slots[i] == null:
			out.append(i)
	return out

func _occupied_count() -> int:
	var n := 0
	for s in grid_slots:
		if s != null:
			n += 1
	return n

# --- Stop / fail handling -------------------------------------------------

func _on_timer_stopped(source: TimerSlot, grade: String, type: int, distance: float) -> void:
	if not _running:
		return
	var idx := grid_slots.find(source)
	if idx == -1:
		return  # not one of ours (campaign timer) - ignore

	# Overclock's score multiplier rides on the bonus factor rather than being a
	# parallel calculation, so it stacks with type/Red-stack bonuses and then
	# flows through the same tally x multiplier model as everything else.
	var bonus := StageController.compute_bonus_factor(
		source.data.timer_type, source.speed_boost_stacks, grade) * Powerups.score_scale()
	ScoreManager.register_result(grade, distance, bonus)
	if grade == "FAIL":
		_handle_fail()
	else:
		_dispatch_reaction(source, type)
	_free_cell_after_delay(idx, source)

func _on_timer_expired(source: TimerSlot) -> void:
	if not _running:
		return
	var idx := grid_slots.find(source)
	if idx == -1:
		return

	# An expiry never passes through TimerSlot's grading, so Shield has to be
	# offered the FAIL here too - otherwise it would only ever catch a mistimed
	# *click*, and miss the far more common "ran out the clock" fail.
	var grade := Powerups.filter_grade("FAIL", _slot_centre(source))
	ScoreManager.register_result(grade, 1.0)  # distance irrelevant - neither grade scores
	if grade == "FAIL":
		_handle_fail()
	_free_cell_after_delay(idx, source)

# Red/Blue reactions affect every other running timer on the board (this is what
# builds Red stacks + tints - the same interaction as campaign).
func _dispatch_reaction(source: TimerSlot, type: int) -> void:
	var affected: Array = []
	match type:
		TimerData.TimerType.RED:
			for slot in grid_slots:
				if slot != null and slot != source and not slot.stopped:
					slot.apply_speedup(0.25)
					affected.append(slot)
		TimerData.TimerType.BLUE:
			for slot in grid_slots:
				if slot != null and slot != source and not slot.stopped:
					slot.apply_pause(1.0)
					affected.append(slot)
	if not affected.is_empty():
		EventBus.reaction_fired.emit(source, type, affected)

func _handle_fail() -> void:
	# resolve_stage banks tally x multiplier then resets the segment - exactly what
	# a fail needs. (The multiplier was just reset to 1.0 by register_result("FAIL"),
	# so the failed segment banks at x1.0.)
	ScoreManager.resolve_stage(true)
	fail_count += 1
	if endless_hud != null:
		endless_hud.update_crosses(fail_count)
	if fail_count >= max_lives:
		_end_run()

func _free_cell_after_delay(idx: int, slot: TimerSlot) -> void:
	# The slot owns its own hold+fade timing (TimerSlot.faded_out) and already
	# uses a time_scale-ignoring timer internally, so a PERFECT's hit-stop can't
	# stretch this. Waiting for the real signal - rather than a flat timer here
	# - is what makes the cell only count as empty once the timer has actually
	# finished disappearing, not the instant it's clicked.
	if is_instance_valid(slot):
		await slot.faded_out
	if idx >= 0 and idx < GRID_CELLS and grid_slots[idx] == slot:
		grid_slots[idx] = null
	if is_instance_valid(slot):
		slot.queue_free()

# --- End of run -----------------------------------------------------------

# Abandon the current run without saving/ending (e.g. quitting to Title from pause).
func abort_run() -> void:
	_running = false
	_disconnect_events()
	_clear_cells()

func _end_run() -> void:
	_running = false
	_disconnect_events()
	_clear_cells()

	final_score = ScoreManager.campaign_total
	var key := "highscore_endless_hardcore" if max_lives <= 1 else "highscore_endless_normal"
	best_score = SaveManager.load_high_score(key)
	is_new_best = final_score > best_score
	if is_new_best:
		best_score = final_score
		SaveManager.save_high_score(key, final_score)

	GameManager.set_state(GameManager.GameState.ENDLESS_END)

# --- Signal wiring --------------------------------------------------------

func _connect_events() -> void:
	if not EventBus.timer_stopped.is_connected(_on_timer_stopped):
		EventBus.timer_stopped.connect(_on_timer_stopped)
	if not EventBus.timer_expired.is_connected(_on_timer_expired):
		EventBus.timer_expired.connect(_on_timer_expired)
	if not Powerups.clear_all_fired.is_connected(_on_clear_all):
		Powerups.clear_all_fired.connect(_on_clear_all)

func _disconnect_events() -> void:
	if EventBus.timer_stopped.is_connected(_on_timer_stopped):
		EventBus.timer_stopped.disconnect(_on_timer_stopped)
	if EventBus.timer_expired.is_connected(_on_timer_expired):
		EventBus.timer_expired.disconnect(_on_timer_expired)
	if Powerups.clear_all_fired.is_connected(_on_clear_all):
		Powerups.clear_all_fired.disconnect(_on_clear_all)

# Nuke: every live timer resolves at a flat PERFECT, each extending the
# streak exactly as a precise click would. No per-type special cases - Golden is
# simply cashed in early, a Decay resolves at full value regardless of how far
# its ceiling had already drained, a Blackout doesn't care that its digits were
# hidden, and a Blue-frozen timer resolves along with the rest.
#
# The resolutions are *staggered* into a cascade rather than fired in one frame,
# so the event reads as a chain reaction the player set off. The board is frozen
# for the duration (Juice.freeze_gameplay), which is what keeps this presentation
# change from becoming a scoring change: nothing counts down behind the cascade,
# so no timer can expire into a FAIL partway through and no Overclock can lapse
# and quietly drop the later resolutions to a lower multiplier.
#
# Iterated over a snapshot: force_resolve() emits timer_stopped synchronously,
# which lands back in _on_timer_stopped and mutates grid_slots.
func _on_clear_all() -> void:
	if not _running:
		return
	var live: Array = []
	for slot in grid_slots:
		if slot != null and is_instance_valid(slot) and not slot.stopped:
			live.append(slot)
	if live.is_empty():
		return
	_run_nuke_cascade(live)

func _run_nuke_cascade(live: Array) -> void:
	# Ordered by distance from the button the player pressed, so the chain reads
	# as spreading outward from the source rather than in arbitrary grid order.
	var origin: Vector2 = Powerups.button_origin(PowerupSystem.Kind.CLEAR_ALL)
	live.sort_custom(func(a, b):
		return _slot_centre(a).distance_squared_to(origin) \
			< _slot_centre(b).distance_squared_to(origin))

	Juice.freeze_gameplay()

	# Total cascade length is fixed, so the gap shrinks as the board gets busier:
	# eight timers should feel like a faster, denser run of hits than two, not
	# like eight times the wait.
	var total: int = live.size()
	var gap: float = NUKE_CASCADE_SEC / float(maxi(total, 1))

	# The wind-up plays first - the cascade is the payload it anticipates.
	await get_tree().create_timer(Juice.WINDUP_SEC, false, false, true).timeout

	for i in range(total):
		# The run can end underneath a cascade (restart, back to title) - bail
		# rather than resolving slots belonging to a run that no longer exists.
		if not _running:
			Juice.release_gameplay()
			return
		var slot = live[i]
		if slot != null and is_instance_valid(slot) and not slot.stopped:
			# force_resolve already fires this slot's own click burst, so the
			# cascade gets per-resolution bursts for free rather than one shared
			# effect for the whole event.
			slot.force_resolve("PERFECT")
			AudioManager.play_nuke_note(i, total)
		if i < total - 1:
			await get_tree().create_timer(gap, false, false, true).timeout

	# The final note played above IS the resolving chord, so the flash lands on
	# the same beat rather than needing a separate completion sound.
	Juice.release_gameplay()
	Juice.nuke_completion_flash()

	# One punch at the end scaled by how much was actually cleared, instead of
	# the per-timer hit-stop/punch each PERFECT would normally trigger (eight of
	# those back to back would read as a stutter, not a climax).
	var weight: float = clampf(float(total) / 9.0, 0.0, 1.0)
	var punch_mult: float = lerpf(NUKE_PUNCH_MIN, NUKE_PUNCH_MAX, weight)
	# A Nuke cashed in under Overclock lands harder. Gated on the *live*
	# multiplier rather than on "is Overclock running" so it stays correct if the
	# multiplier is ever retuned - but applied as a fixed modest bonus, because
	# scaling by score_scale() itself (2x) on top of a full-board 3x would be a
	# 27% zoom, which is nauseating rather than emphatic.
	if Powerups.score_scale() > 1.0:
		punch_mult *= NUKE_PUNCH_MULT_BONUS
	Juice.punch(punch_mult)
	Juice.shake(Juice.ShakeProfile.DECAY, lerpf(0.6, 1.3, weight))

func _slot_centre(slot) -> Vector2:
	return slot.global_position + slot.size * 0.5
