extends RefCounted
class_name Toast

# A short fading text notice, non-blocking and non-modal - for "not yet, here's
# why" taps (a locked button) where a full popup would be overkill. Shared by
# every locked-button tap in the game so they all read as the same language
# rather than each screen inventing its own.

const TEXT_FILL := Color("dfe3ee")
const HOLD_SEC := 1.6
const FADE_IN_SEC := 0.12
const FADE_OUT_SEC := 0.4

# Bottom-center, clear of both the title screen's button columns and any
# per-screen content - a fixed, predictable spot regardless of which locked
# button triggered it.
#
# Measured UP from the canvas's own bottom edge rather than written as an
# absolute y. This was a hardcoded 800, which IS 100 units clear of the bottom
# on the 1600x900 landscape canvas it was authored against - but portrait's
# canvas is 900 x ~2000 (dynamic, see Layout._compute_portrait_size), where 800
# lands roughly 40% DOWN the screen: above the button stack this is meant to sit
# under, and nowhere near the locked button that triggered it. Portrait takes
# the larger margin because it also has a gesture-nav bar to clear, on top of
# the SafeArea inset applied below.
const BOTTOM_MARGIN_LANDSCAPE := 100.0
const BOTTOM_MARGIN_PORTRAIT := 160.0

# 1 canvas unit ~= 0.4dp, so landscape's 24 is ~9.6sp. Fine at desktop viewing
# distance, but well under the 14sp body floor this project holds itself to on a
# phone - and it made this, the string explaining why a button did nothing, the
# smallest text in the game. 36 lands at ~14.4dp, the same floor ScoresScreen's
# own CELL_FONT_SIZE was raised to for the same reason.
#
# This is a shared component reachable from screens with different scale factors
# (TitleScreen has no PORTRAIT_SCALE at all; EndlessModeSelect uses 1.7), so it
# carries its own pair rather than borrowing any one screen's.
const FONT_SIZE_LANDSCAPE := 24
const FONT_SIZE_PORTRAIT := 36

static func show(host: Control, text: String, accent: Color) -> void:
	var portrait: bool = Layout.is_portrait()

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",
		FONT_SIZE_PORTRAIT if portrait else FONT_SIZE_LANDSCAPE)
	label.add_theme_color_override("font_color", TEXT_FILL)
	label.add_theme_color_override("font_outline_color", accent)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Read once here rather than tracked via SafeArea.changed: this node lives for
	# ~2.1s and then frees itself, so an inset change mid-toast isn't worth a
	# subscription.
	var margin: float = BOTTOM_MARGIN_PORTRAIT if portrait else BOTTOM_MARGIN_LANDSCAPE
	label.offset_top = Layout.canvas_size.y - margin - SafeArea.bottom
	label.modulate.a = 0.0
	label.z_index = 40
	host.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, FADE_IN_SEC)
	tween.tween_interval(HOLD_SEC)
	tween.tween_property(label, "modulate:a", 0.0, FADE_OUT_SEC)
	tween.tween_callback(label.queue_free)
