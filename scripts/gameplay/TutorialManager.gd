extends Node
class_name TutorialManager

# Before a stage spawns, shows a one-time modal popup for each timer type the save
# file has never seen. Data-driven: whichever stage first introduces a type
# triggers its popup, so reordering/adding stages needs no changes here.

const TEXT_FILL := Color("dfe3ee")

# The popup lives on its own CanvasLayer parented to this node, so nothing in the
# screen router hides it - it has to be torn down explicitly. The stage is
# already in PLAYING when a popup is up, so the pause button is live behind it
# and the player can quit to the title mid-popup. Tracked here and freed on any
# state change out of PLAYING; a retry re-emits PLAYING too, which clears a
# stale popup instead of stacking a second one on top of it.
var _live_layer: CanvasLayer

func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)

func _on_state_changed(_new_state: int) -> void:
	_dismiss_live_popup()

func _dismiss_live_popup() -> void:
	if _live_layer != null and is_instance_valid(_live_layer):
		_live_layer.queue_free()
	_live_layer = null

func check_and_show(stage_data: StageData, on_ready: Callable) -> void:
	var new_types: Array = []
	for td in stage_data.timers:
		if td == null:
			continue
		var t: int = td.timer_type
		if not new_types.has(t) and _is_new(t):
			new_types.append(t)

	if new_types.is_empty():
		on_ready.call()  # nothing new - start immediately, no visible delay
		return
	_show_next(new_types, on_ready)

func _is_new(t: int) -> bool:
	return SaveManager.load_high_score("seen_type_%d" % t) == 0

func _show_next(types: Array, on_ready: Callable) -> void:
	var t: int = types[0]
	var on_dismiss := func() -> void:
		SaveManager.save_high_score("seen_type_%d" % t, 1)
		var rest: Array = types.slice(1)
		if rest.is_empty():
			on_ready.call()
		else:
			_show_next(rest, on_ready)
	_show_popup(t, on_dismiss)

func _show_popup(t: int, on_dismiss: Callable) -> void:
	var accent: Color = TimerTypeInfo.color_of(t)

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_live_layer = layer

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
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
	sb.border_color = accent
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(540, 0)
	panel.add_child(col)

	col.add_child(_label("NEW TIMER", 22, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER))

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	var swatch := ColorRect.new()
	swatch.color = accent
	swatch.custom_minimum_size = Vector2(34, 34)
	var swatch_wrap := CenterContainer.new()
	swatch_wrap.add_child(swatch)
	head.add_child(swatch_wrap)
	head.add_child(_label(TimerTypeInfo.name_of(t), 40, accent, HORIZONTAL_ALIGNMENT_LEFT))
	col.add_child(head)

	var desc := _label(TimerTypeInfo.desc_of(t), 24, TEXT_FILL, HORIZONTAL_ALIGNMENT_CENTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(540, 0)
	col.add_child(desc)

	var got := Button.new()
	got.text = "GOT IT"
	got.custom_minimum_size = Vector2(180, 56)
	got.add_theme_font_size_override("font_size", 26)
	got.add_theme_color_override("font_color", Color.WHITE)
	got.add_theme_color_override("font_outline_color", accent)
	got.add_theme_constant_override("outline_size", 4)
	got.add_theme_stylebox_override("normal", _box(accent, 0.8))
	got.add_theme_stylebox_override("hover", _box(accent, 0.65))
	got.add_theme_stylebox_override("pressed", _box(accent, 0.55))
	var on_got := func() -> void:
		if _live_layer == layer:
			_live_layer = null
		layer.queue_free()
		on_dismiss.call()
	got.pressed.connect(on_got)
	var got_wrap := CenterContainer.new()
	got_wrap.add_child(got)
	col.add_child(got_wrap)

func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb
