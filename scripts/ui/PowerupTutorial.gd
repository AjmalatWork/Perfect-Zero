extends RefCounted
class_name PowerupTutorial

# One-time modal introducing the three Endless powerups, shown the first time
# the player opens Endless mode.
#
# Deliberately separate from TutorialManager: that one is Campaign-only and
# data-driven off a stage's timer types, whereas this fires once per save on
# entering a mode. It reuses the same save-key convention (SaveManager flag) and
# the same popup styling so the two read as one system to the player.

const SEEN_KEY := "seen_endless_powerups"
const TEXT_FILL := Color("dfe3ee")
const NEON := Color("22d3ff")

static func is_new() -> bool:
	return SaveManager.load_high_score(SEEN_KEY) == 0

static func mark_seen() -> void:
	SaveManager.save_high_score(SEEN_KEY, 1)

# Builds the popup under `host` and marks it seen once dismissed. `on_dismiss`
# (optional) fires right after mark_seen() - lets a caller defer starting the
# actual run until the player has closed this, rather than starting underneath it.
#
# Returns the popup's CanvasLayer so a caller can tear it down itself. That
# matters because the popup is a CanvasLayer, not a CanvasItem: hiding the host
# screen does NOT hide it (the same reason TutorialManager tracks and explicitly
# frees its own popup layer), so any path that leaves the screen while this is
# up has to free it or it survives as orphaned UI over the next screen.
static func show_popup(host: Node, on_dismiss: Callable = Callable()) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 30
	host.add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to anything behind
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f1118")
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = NEON
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(NEON.r, NEON.g, NEON.b, 0.4)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	col.add_child(_label("POWERUPS", 34, NEON, HORIZONTAL_ALIGNMENT_CENTER))
	var intro := _label(
		"Endless gives you three. They start on cooldown, and recharge as you play.",
		21, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(660, 0)
	col.add_child(intro)

	for kind in PowerupSystem.ORDER:
		col.add_child(_row(kind))

	var got := _button("GOT IT", NEON)
	var on_got := func() -> void:
		mark_seen()
		layer.queue_free()
		if on_dismiss.is_valid():
			on_dismiss.call()
	got.pressed.connect(on_got)
	var got_wrap := CenterContainer.new()
	got_wrap.add_child(got)
	col.add_child(got_wrap)
	return layer

static func _row(kind: int) -> Control:
	var accent: Color = PowerupSystem.color_of(kind)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var icon := PowerupIcon.new(kind)
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size = Vector2(52, 52)
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(icon)
	row.add_child(icon_wrap)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 2)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_label(PowerupSystem.name_of(kind), 24, accent, HORIZONTAL_ALIGNMENT_LEFT))
	head.add_child(_label("[%s]" % PowerupSystem.key_of(kind), 18,
		Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT))
	head.add_child(_label(Powerups.cooldown_text(kind), 18,
		Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT))
	text_col.add_child(head)

	var desc := _label(Powerups.describe(kind), 19, TEXT_FILL, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(600, 0)
	text_col.add_child(desc)

	row.add_child(text_col)
	return row

static func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

static func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 56)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.8))
	button.add_theme_stylebox_override("hover", _box(accent, 0.65))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.55))
	return button

static func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb
