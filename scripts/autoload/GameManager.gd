extends Node

enum GameState {
	MENU, LEVEL_SELECT, PLAYING, STAGE_CLEAR, FAIL, GAME_OVER, HELP, SCORES,
	ENDLESS_MODE_SELECT, ENDLESS_PLAYING, ENDLESS_END, OPTIONS, CREDITS,
}

signal state_changed(new_state: GameState)

var current_state: GameState = GameState.MENU
var current_campaign: Campaign
var current_stage_index: int = 0

# Single entry point for state changes so state_changed always fires. Route every
# state transition through this rather than assigning current_state directly.
func set_state(new_state: GameState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
