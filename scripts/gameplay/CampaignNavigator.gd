extends Node
class_name CampaignNavigator

@export var campaign: Campaign
@export var stage_controller: StageController
@export var tutorial_manager: TutorialManager
@export var intro_demo: IntroDemo

# Clearing this many stages unlocks the ENDLESS button on the title screen. A
# single easily-tunable constant, per the brief - confirmed at 3 with the
# designer rather than assumed.
const ENDLESS_UNLOCK_STAGE := 3

var current_index: int = 0

func _ready() -> void:
	EventBus.stage_cleared.connect(_on_stage_cleared)

# Entry point for a FRESH campaign run (Title / Level Select). Clears any Endless
# leftovers so the campaign starts uncapped with a zero total, then starts play.
# advance_next()/retry() deliberately do NOT reset - they continue the same run.
func enter_campaign(index: int) -> void:
	ScoreManager.multiplier_cap = -1.0
	ScoreManager.reset_run()
	ScoreManager.set_score(0, 1.0)  # campaign running total (sum of bests) starts fresh
	start_from_index(index, true)

func start_from_index(index: int, reset_base: bool = true) -> void:
	var stage_count: int = campaign.stages.size() if campaign != null else 0
	if index < 0 or index >= stage_count:
		push_error("CampaignNavigator: invalid stage index %d (campaign has %d stages). Did you populate Campaign.tres's stages array?" % [index, stage_count])
		return
	# A pause-menu RESTART (retry()) and advancing to the next stage both go
	# PLAYING -> PLAYING - pausing never touches GameManager.current_state, and
	# neither call ever leaves PLAYING in between - so Juice's own "leaving
	# play" cleanup (see reset_run_effects()) never fires for either. Without
	# this, a stage retried/advanced while a PERFECT's heat/streak/hit-stop was
	# still settling handed that leftover animation to the new stage - same
	# root cause as the Endless restart fix in EndlessRunner.start_run().
	Juice.reset_run_effects()
	current_index = index
	GameManager.set_state(GameManager.GameState.PLAYING)

	# Show the one-time ghost-cursor intro demo, then any first-time timer-type
	# tutorials, then actually spawn the stage.
	var stage: StageData = campaign.stages[current_index]
	var spawn := func() -> void:
		stage_controller.start_stage(stage, reset_base)
	var show_tutorials := func() -> void:
		if tutorial_manager != null:
			tutorial_manager.check_and_show(stage, spawn)
		else:
			spawn.call()
	if intro_demo != null:
		intro_demo.maybe_show(show_tutorials)
	else:
		show_tutorials.call()

func _on_stage_cleared() -> void:
	# Persist unlock progress the moment a stage is cleared, independent of whether
	# the player then advances or retries. Advancing itself is now driven by the
	# StageResultScreen buttons (advance_next / retry), not automatically here.
	var highest: int = SaveManager.load_high_score("highest_stage_reached")
	if current_index + 1 > highest:
		SaveManager.save_high_score("highest_stage_reached", current_index + 1)
	if stage_controller != null and stage_controller.is_all_perfect():
		_record_all_perfect(current_index)

# --- All-PERFECT record ----------------------------------------------------
# Per stage, whether it has EVER been cleared with every timer graded PERFECT.
# Binary and permanent by design: there is deliberately no tier/rank system here
# (no Bronze/Silver/Gold, no star rating), and a later scrappier clear never
# takes an earned flag back - the same "best persists" rule the per-stage score
# records already follow.
#
# Stored through the int-typed, type-guarded save_high_score path rather than
# the untyped generic store, matching `highest_stage_reached` and
# `endless_unlock_seen` - an unset stage simply reads 0, which is the correct
# "not earned yet" answer with no migration needed for existing saves.
const ALL_PERFECT_KEY := "allperfect_stage_%d"

# A second, transient flag per stage: "earned but not yet shown on Level
# Select." Persisted (not just an in-memory var) rather than the reveal being
# played the instant the flag is set - StageResultScreen is a separate screen
# from Level Select, and this is what lets the badge's own "it just filled in"
# animation happen the next time the player actually looks at the grid, rather
# than requiring some awkward hand-off between two unrelated screens. Consumed
# (read-and-cleared) by LevelSelect via take_pending_all_perfect() the moment
# it plays the reveal, so revisiting later shows the plain settled state.
const ALL_PERFECT_PENDING_KEY := "allperfect_pending_%d"

func has_all_perfect(index: int) -> bool:
	return SaveManager.load_high_score(ALL_PERFECT_KEY % index) != 0

func _record_all_perfect(index: int) -> void:
	if has_all_perfect(index):
		return
	SaveManager.save_high_score(ALL_PERFECT_KEY % index, 1)
	SaveManager.save_high_score(ALL_PERFECT_PENDING_KEY % index, 1)

# Every stage index whose reveal hasn't been shown yet, in stage order.
# Clearing the flags here (rather than leaving that to the caller) means an
# animation interrupted mid-play - back button, a fast re-entry - simply isn't
# repeated next visit instead of risking a stuck or doubled reveal; Level
# Select rebuilds its whole grid from scratch on every visit anyway, so the
# settled (fully-earned, unanimated) state is always there to fall back to.
func take_pending_all_perfect() -> Array[int]:
	var out: Array[int] = []
	var stage_count: int = campaign.stages.size() if campaign != null else 0
	for i in range(stage_count):
		if SaveManager.load_high_score(ALL_PERFECT_PENDING_KEY % i) != 0:
			out.append(i)
			SaveManager.save_high_score(ALL_PERFECT_PENDING_KEY % i, 0)
	return out

func is_last_stage() -> bool:
	return campaign == null or current_index + 1 >= campaign.stages.size()

# Two independent progression gates, both read off the same persisted
# `highest_stage_reached` rather than their own separate flags - Endless's gate
# is a stage count, Hardcore's is "all of them," and both are just different
# thresholds against the one number CampaignNavigator already maintains.
func is_endless_unlocked() -> bool:
	return SaveManager.load_high_score("highest_stage_reached") >= ENDLESS_UNLOCK_STAGE

func is_campaign_complete() -> bool:
	var stage_count: int = campaign.stages.size() if campaign != null else 0
	return stage_count > 0 and SaveManager.load_high_score("highest_stage_reached") >= stage_count

func advance_next() -> void:
	# StageResultScreen checks is_last_stage() itself and shows the campaign-complete
	# message in place instead of calling this when there's no next stage.
	if is_last_stage():
		push_warning("CampaignNavigator.advance_next() called on the last stage.")
		return
	start_from_index(current_index + 1)

func retry() -> void:
	# Keep the base (previous stages' total) so re-attempting doesn't re-anchor it.
	start_from_index(current_index, false)
