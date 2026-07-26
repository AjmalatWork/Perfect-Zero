extends Resource
class_name TimerUnlock

# One entry in EndlessRunner's type-unlock schedule: `type` becomes eligible to
# spawn once elapsed_time >= time, then competes with other unlocked types by
# `weight` (see EndlessRunner._pick_type).

@export var time: float = 0.0
@export var type: TimerData.TimerType = TimerData.TimerType.NORMAL
@export var weight: float = 1.0
