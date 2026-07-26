extends Resource
class_name StageData

@export var stage_name: String = "Stage 1"
@export var is_bonus_stage: bool = false
@export var timers: Array[TimerData] = []
@export var target_score: int = 0  # manually authored per stage; 0 = unset (see Scores screen)
