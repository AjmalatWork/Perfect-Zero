extends Node

signal timer_stopped(source: Node, grade: String, type: int, distance: float)
signal timer_expired(source: Node)
signal stage_cleared()
signal stage_failed()

# A Red/Blue timer's reaction fired. Emitted by StageController (Campaign) and
# EndlessRunner (Endless) after the effect is applied, so presentation can hook
# the same moment in both modes instead of re-deriving it.
signal reaction_fired(source: Node, type: int, affected: Array)

# Live PERFECT-streak "heat", 0..1. Presentation only - carries no numeric
# information, so it's safe to react to during Campaign's deferred scoring.
signal heat_changed(heat: float)
