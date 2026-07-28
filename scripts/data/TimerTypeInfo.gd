class_name TimerTypeInfo
extends RefCounted

# Central copy + colors for the timer-type legend, shared by the Help screen and
# the tutorial popups so the two never drift apart. Colors match TimerSlot.TYPE_COLORS.

const NAMES := {
	TimerData.TimerType.NORMAL: "Normal",
	TimerData.TimerType.RED: "Red",
	TimerData.TimerType.BLUE: "Blue",
	TimerData.TimerType.GOLDEN: "Golden",
	TimerData.TimerType.BLACKOUT: "Blackout",
	TimerData.TimerType.DECAY: "Decay",
}

const COLORS := {
	TimerData.TimerType.NORMAL: Color("e6e9ff"),
	TimerData.TimerType.RED: Color("ff2e5e"),
	TimerData.TimerType.BLUE: Color("22d3ff"),
	TimerData.TimerType.GOLDEN: Color("ffd23f"),
	TimerData.TimerType.BLACKOUT: Color("5a5f70"),
	TimerData.TimerType.DECAY: Color("b06bff"),
}

const DESCRIPTIONS := {
	TimerData.TimerType.NORMAL: "A plain timer. Just stop it at 0.00.",
	TimerData.TimerType.RED: "On stop, speeds up every other timer - and makes them score more.",
	TimerData.TimerType.BLUE: "On stop, pauses every other timer for a second.",
	TimerData.TimerType.GOLDEN: "A guaranteed PERFECT whenever you click it, worth double.",
	TimerData.TimerType.BLACKOUT: "Its digits vanish near zero - time it by ear. Worth 2.5×.",
	TimerData.TimerType.DECAY: "Counts up, not down. Stop it fast - its best grade drains away as it climbs.",
}

# DECAY's border steps through these as its ceiling drops, so the tier is
# readable at a glance without parsing the digits. Index matches the tier order
# PERFECT / GOOD / OKAY / MISS. The first entry is the type's own accent, so a
# fresh Decay timer still reads as "a Decay timer" rather than as some other
# type; it drains toward grey from there.
# Dims monotonically but holds its saturation the whole way down, so the ramp
# reads as one value draining rather than four unrelated states. Tier 0 is
# deliberately the brightest thing on the board - a Decay spawns alongside
# timers that have already been running for seconds, so it has to win attention
# immediately or it gets missed entirely.
#
# Critically, the late tiers stay unmistakably PURPLE rather than fading toward
# grey: a desaturated Decay is easily misread as a Blackout (Color("5a5f70")),
# which behaves nothing like it. Brightness carries the drain; hue carries the
# identity.
const DECAY_TIER_COLORS := [
	Color("e0a5ff"),  # PERFECT - hot, vivid purple
	Color("b06bff"),  # GOOD - the type's own accent
	Color("8244c9"),  # OKAY - deeper, still clearly purple
	Color("5c2d8f"),  # MISS - spent, but never grey
]

# Presentation profile per type, kept beside the names/colors/descriptions so
# the Help screen and the in-game feedback can't drift apart.
#
# BURST_TINTS overrides the click-burst colour; SHINE_TYPES get a coin-shine
# sweep on stop; AUDIO_CUE_TYPES swap the standard tick for their own timbre.
const BURST_TINTS := {
	TimerData.TimerType.GOLDEN: Color("fff3c4"),   # warmer than an earned PERFECT
	TimerData.TimerType.BLACKOUT: Color("cfd6ff"),
}
const SHINE_TYPES := [TimerData.TimerType.GOLDEN]
const AUDIO_CUE_TYPES := [TimerData.TimerType.BLACKOUT]

# Campaign order, for iterating the full legend.
const ORDER := [
	TimerData.TimerType.NORMAL,
	TimerData.TimerType.RED,
	TimerData.TimerType.BLUE,
	TimerData.TimerType.GOLDEN,
	TimerData.TimerType.BLACKOUT,
	TimerData.TimerType.DECAY,
]

static func name_of(t: int) -> String:
	return NAMES.get(t, "?")

static func color_of(t: int) -> Color:
	return COLORS.get(t, Color.WHITE)

static func desc_of(t: int) -> String:
	return DESCRIPTIONS.get(t, "")

static func burst_tint_of(t: int, fallback: Color) -> Color:
	return BURST_TINTS.get(t, fallback)

static func has_shine(t: int) -> bool:
	return SHINE_TYPES.has(t)

static func has_audio_cue(t: int) -> bool:
	return AUDIO_CUE_TYPES.has(t)

# tier: 0 PERFECT / 1 GOOD / 2 OKAY / 3 MISS. Clamped so a tier past the table
# holds the last (most drained) colour rather than erroring.
static func decay_tier_color(tier: int) -> Color:
	return DECAY_TIER_COLORS[clampi(tier, 0, DECAY_TIER_COLORS.size() - 1)]
