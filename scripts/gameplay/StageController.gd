extends Node
class_name StageController

@export var current_stage_data: StageData
@export var timer_container: Node
@export var timer_slot_scene: PackedScene

var active_slots: Array[TimerSlot] = []
var stage_start_score: int = 0
var pending_results: Array = []  # {grade, distance, bonus_factor} per stop - revealed at stage end
var _active_stage_data: StageData
var _stage_ending: bool = false

# Presentation-only consecutive-PERFECT count, pushed to Juice to drive the
# wordless heat visual. Campaign's scoring stays fully deferred - this never
# feeds ScoreManager and reveals no numbers to the player.
var _live_perfect_streak: int = 0

const END_STAGE_PAUSE := 0.7  # lets the final stop's flash/tick settle before cutting to the result screen
const TIMERS_PER_ROW := 3      # timers fill a centered row up to this many, then wrap

func _ready() -> void:
	EventBus.timer_stopped.connect(_on_timer_stopped)
	EventBus.timer_expired.connect(_on_timer_expired)
	# Stages are launched by CampaignNavigator now, not auto-started here, so the
	# title screen can show first. current_stage_data is left as a vestigial export.

func start_stage(stage_data: StageData, reset_base: bool = true) -> void:
	_active_stage_data = stage_data
	_stage_ending = false
	pending_results.clear()
	_live_perfect_streak = 0
	Juice.set_streak(0)
	_clear_slots()

	# stage_start_score is the running total coming in (previous stages' best
	# scores). A retry keeps the same base so the campaign total stays anchored
	# while you re-attempt; a fresh entry re-reads it from the committed total.
	if reset_base:
		stage_start_score = ScoreManager.score

	# Multiplier resets to 1.0 at the start of every stage (including retries) -
	# each stage's reveal builds its multiplier fresh from x1.0.
	ScoreManager.set_score(ScoreManager.score, 1.0)

	# Lay timers out in centered rows (timer_container is a VBox of HBox rows,
	# itself centered on screen). Each row centers its own timers, so 1 sits dead
	# center, 2 straddle center, 3 puts the middle one on center, then it wraps.
	var row: HBoxContainer = null
	for i in range(stage_data.timers.size()):
		if i % TIMERS_PER_ROW == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 28)
			timer_container.add_child(row)
		var slot: TimerSlot = timer_slot_scene.instantiate()
		row.add_child(slot)
		slot.setup(stage_data.timers[i])
		active_slots.append(slot)

	GameManager.set_state(GameManager.GameState.PLAYING)

# The distinct timer types the current stage actually contains - read by
# HelpBubble's new-type badge, which needs to know what's "spawn-eligible" in
# Arcade the same way EndlessRunner's type_unlocks answers it for Endless.
func current_stage_timer_types() -> Array[int]:
	var out: Array[int] = []
	if _active_stage_data == null:
		return out
	for td in _active_stage_data.timers:
		if td != null and not out.has(td.timer_type):
			out.append(td.timer_type)
	return out

func _clear_slots() -> void:
	# Free the row containers (which frees the timers inside them).
	for child in timer_container.get_children():
		child.queue_free()
	active_slots.clear()

# Abandon the current stage without clearing/failing it (e.g. quitting to Title
# from the pause menu). Blocks any further stop/expire handling.
func abort() -> void:
	_stage_ending = true
	_clear_slots()

func _on_timer_stopped(source: TimerSlot, grade: String, type: int, distance: float) -> void:
	# Only handle our own timers - Endless mode shares this EventBus signal.
	if not active_slots.has(source):
		return
	if _stage_ending:
		return

	# A FAIL grade (stopped too early/late) ends the stage immediately - it's not
	# tallied and triggers no reaction.
	if grade == "FAIL":
		_live_perfect_streak = 0
		Juice.set_streak(0)
		_end_stage(false)
		return

	# Scoring is deferred to the end-of-stage reveal; here we record the result
	# (with its distance + the bonus factor computed now, since it depends on the
	# stack count at this moment) and apply immediate timer-to-timer reactions.
	pending_results.append({
		"grade": grade,
		"distance": distance,
		"bonus_factor": _bonus_factor(source, grade),
	})

	# PERFECT extends the streak; every other scoring grade breaks it (matching
	# ScoreManager's live rule in Endless).
	if grade == "PERFECT":
		_live_perfect_streak += 1
	else:
		_live_perfect_streak = 0
	Juice.set_streak(_live_perfect_streak)

	var affected: Array = []
	match type:
		TimerData.TimerType.RED:
			for slot in active_slots:
				if slot != source and not slot.stopped:
					slot.apply_speedup(0.25)
					affected.append(slot)
		TimerData.TimerType.BLUE:
			for slot in active_slots:
				if slot != source and not slot.stopped:
					slot.apply_pause(1.0)
					affected.append(slot)
		_:
			# NORMAL / GOLDEN (scored via bonus factor) / BLACKOUT: no reaction.
			pass
	if not affected.is_empty():
		EventBus.reaction_fired.emit(source, type, affected)

	_check_stage_clear()

# Combined scoring bonus for this stop: type factor x Red-stack factor. Both are
# gated to the PERFECT/GOOD/OKAY tiers (MISS and FAIL get no bonus). ScoreManager
# stays type-agnostic - it just receives the final factor.
func _bonus_factor(source: TimerSlot, grade: String) -> float:
	return compute_bonus_factor(source.data.timer_type, source.speed_boost_stacks, grade)

# Shared so Endless mode computes bonuses identically (kept out of ScoreManager,
# which stays type-agnostic).
static func compute_bonus_factor(timer_type: int, stacks: int, grade: String) -> float:
	var scoring_grade := grade == "PERFECT" or grade == "GOOD" or grade == "OKAY"

	var type_factor := 1.0
	match timer_type:
		TimerData.TimerType.GOLDEN:
			if grade == "PERFECT":
				type_factor = 2.0
		TimerData.TimerType.BLACKOUT:
			if scoring_grade:
				type_factor = 2.5

	var stack_factor := 1.0
	if scoring_grade:
		stack_factor = 1.0 + 0.25 * stacks

	return type_factor * stack_factor

func _on_timer_expired(source: TimerSlot) -> void:
	if not active_slots.has(source):
		return
	if _stage_ending:
		return
	_end_stage(false)

func _check_stage_clear() -> void:
	for slot in active_slots:
		if not slot.stopped:
			return
	_end_stage(true)

func _end_stage(cleared: bool) -> void:
	if _stage_ending:
		return
	_stage_ending = true  # blocks further scoring/input immediately; slots keep rendering during the pause below

	await get_tree().create_timer(END_STAGE_PAUSE, true, false, true).timeout

	_clear_slots()  # halt timers now; the reveal reads pending_results, already captured

	if cleared:
		GameManager.set_state(GameManager.GameState.STAGE_CLEAR)
		EventBus.stage_cleared.emit()
	else:
		GameManager.set_state(GameManager.GameState.FAIL)
		EventBus.stage_failed.emit()

# Input is mouse-only: timers are stopped by clicking them (TimerSlot._gui_input).
# The old 1-6 keyboard mapping was removed in the mouse-only pass.
