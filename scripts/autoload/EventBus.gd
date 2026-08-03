extends Node

signal timer_stopped(source: Node, grade: String, type: int, distance: float)

# A timer ran past zero unclicked. `grade` is the FINAL grade, already passed
# through Powerups.filter_grade() by the emitter - so it is "MISS" when an
# armed Shield absorbed the fail and "FAIL" otherwise.
#
# Carrying the resolved grade is deliberate, and replaces a real ordering
# hazard. This signal used to carry only the source, which left presentation
# listeners (Juice above all) needing to know whether the fail they were about
# to react to was going to be absorbed - and the only way to know was to ask
# Powerups *before* EndlessRunner got its turn to offer the grade to Shield.
# That worked solely because autoloads happen to connect to EventBus before
# scene nodes do, an invisible dependency that any reordering would have
# broken silently, and in a way that would have shown up as "an absorbed
# expiry briefly plays the full FAIL reaction" rather than as an obvious fault.
# Resolving once at the emitter removes the guess entirely.
signal timer_expired(source: Node, grade: String)
signal stage_cleared()
signal stage_failed()

# A Red/Blue timer's reaction fired. Emitted by StageController (Campaign) and
# EndlessRunner (Endless) after the effect is applied, so presentation can hook
# the same moment in both modes instead of re-deriving it.
signal reaction_fired(source: Node, type: int, affected: Array)

# Live PERFECT-streak "heat", 0..1. Presentation only - carries no numeric
# information, so it's safe to react to during Campaign's deferred scoring.
signal heat_changed(heat: float)
