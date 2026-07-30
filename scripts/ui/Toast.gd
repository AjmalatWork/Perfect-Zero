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
const POSITION_Y := 800.0

static func show(host: Control, text: String, accent: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", TEXT_FILL)
	label.add_theme_color_override("font_outline_color", accent)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = POSITION_Y
	label.modulate.a = 0.0
	label.z_index = 40
	host.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, FADE_IN_SEC)
	tween.tween_interval(HOLD_SEC)
	tween.tween_property(label, "modulate:a", 0.0, FADE_OUT_SEC)
	tween.tween_callback(label.queue_free)
