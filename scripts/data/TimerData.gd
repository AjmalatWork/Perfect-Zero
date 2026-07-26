extends Resource
class_name TimerData

enum TimerType { NORMAL, RED, BLUE, GOLDEN, BLACKOUT, DECAY }

@export var start_time: float = 8.0
@export var timer_type: TimerType = TimerType.NORMAL
@export var blackout_duration: float = 1.5

# --- Decay windows --------------------------------------------------------
# DECAY is the one type that counts UP from 0.00 rather than down to it, so it
# is graded on elapsed time rather than on distance from zero, against its own
# (much wider) windows instead of the global PERFECT/GOOD/OKAY thresholds. Each
# value below is that tier's *duration*, not an absolute cut-off - the tiers run
# back to back, so the grade for a click is decided by which window the elapsed
# time falls in:
#
#   0.00 .. P                   -> PERFECT
#   P    .. P+G                 -> GOOD
#   P+G  .. P+G+O               -> OKAY
#   P+G+O.. P+G+O+M             -> MISS, then it expires (also a MISS)
#
# start_time is unused by DECAY (it starts at zero by definition); the total of
# these four is what determines how long a Decay timer lives.
@export var decay_perfect_duration: float = 0.6
@export var decay_good_duration: float = 1.2
@export var decay_okay_duration: float = 1.8
@export var decay_miss_duration: float = 2.4

# Absolute end of each tier, measured from spawn.
func decay_perfect_end() -> float:
	return decay_perfect_duration

func decay_good_end() -> float:
	return decay_perfect_duration + decay_good_duration

func decay_okay_end() -> float:
	return decay_good_end() + decay_okay_duration

# Total lifetime - past this the timer expires (resolving as a MISS).
func decay_miss_end() -> float:
	return decay_okay_end() + decay_miss_duration
