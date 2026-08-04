extends Node

signal score_changed(score: int, multiplier: float)     # campaign running total (sum of bests)
signal tally_changed(stage_tally: int, multiplier: float)  # live segment (Endless HUD)
signal campaign_total_changed(total: int)                  # live running total (Endless HUD)
signal perfect_streak_changed(count: int)                  # consecutive PERFECTs (any other grade breaks it)

const MULT_FLOOR := 1.0

# Colors for the floating grade signs (above timers on stop, and over the reveal).
const GRADE_COLORS := {
	"PERFECT": Color("ffe066"),  # bright gold
	"GOOD": Color("39ff9e"),     # green
	"OKAY": Color("22d3ff"),     # cyan
	"MISS": Color("ff8a3d"),     # orange
	"FAIL": Color("ff2e5e"),     # red
}

var score: int = 0                # campaign running total (sum of stages' committed bests)
var multiplier: float = 1.0
var multiplier_cap: float = -1.0  # -1 = uncapped; Endless sets a real cap during a run

# --- Live segment model (used by Endless; campaign uses the deferred path below).
var stage_tally: int = 0          # base points banked this segment, before the multiplier
var campaign_total: int = 0       # running sum of all banked segments this run
var perfect_streak: int = 0       # consecutive PERFECTs (live path)

# High-water mark of perfect_streak across the whole run, as opposed to the live
# value above which drops to 0 the moment a streak breaks. Endless's run summary
# reports "best streak reached", which the live counter can't answer by the time
# the run is over - it is almost always 0 at that point, since the run ends on a
# FAIL. Reset by reset_run() alongside everything else in the live model.
var run_best_streak: int = 0

static func grade_color(grade: String) -> Color:
	return GRADE_COLORS.get(grade, Color.WHITE)

# Grouped thousands, for every score the player reads. Five unbroken digits are
# measurably slower to read than "36,000", and the GDD writes score figures this
# way in both places it shows one ("BEAT YOUR BEST: 17,240", and the milestone
# ladder 10,000 -> 25,000 -> 50,000).
#
# Lives here rather than on any one screen because it was previously a private
# helper on ScoresScreen and therefore reachable, in practice, nowhere else -
# which left Scores as the ONLY screen in the game that separated its numbers.
# A player finishing an Endless run read "17240" on the summary and "17,240" on
# the Scores screen two taps later: the same number, two formats. ScoreManager
# already owns the scores and already exposes a static formatter-ish helper
# (grade_color above), so this is the one place every screen can reach.
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out

# Continuous proximity base points: full 200 at distance 0, quadratic falloff to
# 0 as distance approaches 1.0. No cliff between grade tiers.
static func base_points(distance: float) -> int:
	return int(200.0 * pow(1.0 - minf(distance, 1.0), 2.0))

# Multiplier evolution for one grade. PERFECT +1.0, GOOD +0.5, OKAY unchanged,
# MISS halves (floored at 1.0). Caller clamps to any active cap.
static func next_multiplier(grade: String, m: float) -> float:
	match grade:
		"PERFECT":
			return m + 1.0
		"GOOD":
			return m + 0.5
		"OKAY":
			return m
		"MISS":
			return maxf(m * 0.5, MULT_FLOOR)
	return m

# Replay a cleared stage's stops for the reveal. Each result is
# {grade, distance, bonus_factor}. Points scale continuously with distance and
# the (already-combined) bonus factor; the multiplier is applied once at the end.
func evaluate_stage(results: Array) -> Dictionary:
	var steps: Array = []
	var tally: int = 0
	var m: float = 1.0
	for r in results:
		var grade: String = r["grade"]
		var dist: float = r["distance"]
		var bonus: float = r.get("bonus_factor", 1.0)
		var gain: int = int(base_points(dist) * bonus)
		var m_before: float = m
		m = next_multiplier(grade, m)
		if multiplier_cap > 0.0:
			m = minf(m, multiplier_cap)
		var tally_before: int = tally
		tally += gain
		steps.append({
			"grade": grade,
			"gain": gain,
			"tally_before": tally_before, "tally_after": tally,
			"mult_before": m_before, "mult_after": m,
		})
	return {
		"steps": steps,
		"tally": tally,
		"final_mult": m,
		# Truncated, not rounded - matches resolve_stage()'s int(stage_tally *
		# multiplier) below and EndlessHUD's live tally*mult projection, so
		# Arcade and Endless bank the exact same score for the exact same
		# recorded sequence of stops instead of differing by up to 1 point.
		"stage_score": int(tally * m),
	}

# Commit a value to the campaign running total (the sum of per-stage bests).
func set_score(new_score: int, new_mult: float) -> void:
	score = new_score
	multiplier = new_mult
	score_changed.emit(score, multiplier)

func reset() -> void:
	score = 0
	multiplier = 1.0
	score_changed.emit(score, multiplier)

# --- Live segment scoring (Endless) --------------------------------------
# Score one stop immediately into the live segment. FAIL resets the multiplier
# and scores nothing; other grades add proximity points and evolve the multiplier.
func register_result(grade: String, distance: float, bonus_factor: float = 1.0) -> void:
	# PERFECT extends the streak; every other grade breaks it (even GOOD, which
	# still grows the multiplier).
	if grade == "PERFECT":
		perfect_streak += 1
	else:
		perfect_streak = 0
	run_best_streak = maxi(run_best_streak, perfect_streak)
	perfect_streak_changed.emit(perfect_streak)

	if grade == "FAIL":
		# Multiplier is deliberately left untouched here - resolve_stage() (always
		# called right after this, from EndlessRunner._handle_fail) banks
		# tally x multiplier using whatever the player actually built up, then
		# resets it to 1.0 itself. Zeroing it here first used to silently bank
		# EVERY segment (in both Normal and Hardcore - neither mode branches
		# through different code here) at a flat x1.0 regardless of the real
		# multiplier. Same-size bug everywhere it happened, but its impact scales
		# with how much of the run rides on one segment: least visible in Normal's
		# early low-life fails (a small early segment losing its multiplier is a
		# small loss), most visible in Hardcore, where the entire run is exactly
		# one segment and 100% of its score was riding on this.
		tally_changed.emit(stage_tally, multiplier)
		return

	stage_tally += int(base_points(distance) * bonus_factor)
	multiplier = next_multiplier(grade, multiplier)
	if multiplier_cap > 0.0:
		multiplier = minf(multiplier, multiplier_cap)
	tally_changed.emit(stage_tally, multiplier)

# Bank the current segment (tally x multiplier) into the run total and reset the
# segment. Returns the banked amount. Called on each Endless fail.
func resolve_stage(cleared: bool) -> int:
	var banked := 0
	if cleared:
		banked = int(stage_tally * multiplier)
		campaign_total += banked
		campaign_total_changed.emit(campaign_total)
	stage_tally = 0
	multiplier = 1.0
	tally_changed.emit(stage_tally, multiplier)
	return banked

# Zero the whole live model - called at the start of an Endless run (and a fresh
# campaign run, for cross-mode hygiene).
func reset_run() -> void:
	stage_tally = 0
	multiplier = 1.0
	campaign_total = 0
	perfect_streak = 0
	run_best_streak = 0
	tally_changed.emit(stage_tally, multiplier)
	campaign_total_changed.emit(campaign_total)
	perfect_streak_changed.emit(perfect_streak)
