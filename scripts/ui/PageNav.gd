extends HBoxContainer
class_name PageNav

# The < PREV / "i / N" / NEXT > row, extracted from HelpScreen so the new
# in-game Help bubble (which also paginates, 2 pages in Endless) can share the
# exact same pagination widget rather than a second hand-rolled copy of it.
# Owns only the nav row's own UI/state (current index, button disabled state,
# the page label) - the caller still owns what a "page" actually contains and
# how it's shown/hidden.

const GOLD := Color("ffd23f")
const TEXT_FILL := Color("dfe3ee")

signal page_changed(index: int)

var _page_count: int = 1
var _page_index: int = 0
var _page_label: Label
var _prev_button: Button
var _next_button: Button

func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 32)

# Idempotent: HelpScreen only ever calls this once, but HelpBubble reuses the
# same node across repeated opens (and Arcade vs. Endless have different page
# counts), so this has to be safe to call again rather than stacking a second
# row of buttons underneath the first.
func configure(page_count: int) -> void:
	for child in get_children():
		child.queue_free()
	_page_count = maxi(page_count, 1)

	_prev_button = _nav_button("< PREV")
	_prev_button.pressed.connect(func(): show_page(_page_index - 1))
	add_child(_prev_button)

	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 24)
	_page_label.add_theme_color_override("font_color", TEXT_FILL)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(100, 0)
	add_child(_page_label)

	_next_button = _nav_button("NEXT >")
	_next_button.pressed.connect(func(): show_page(_page_index + 1))
	add_child(_next_button)

	# A single page has nothing to navigate between - the whole row would just
	# be two permanently-disabled buttons around a static "1 / 1".
	visible = _page_count > 1

	show_page(0)

func show_page(index: int) -> void:
	_page_index = clampi(index, 0, _page_count - 1)
	_page_label.text = "%d / %d" % [_page_index + 1, _page_count]
	_prev_button.disabled = _page_index == 0
	_next_button.disabled = _page_index == _page_count - 1
	page_changed.emit(_page_index)

func current_page() -> int:
	return _page_index

func _nav_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", GOLD)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(0.85))
	button.add_theme_stylebox_override("hover", _box(0.7))
	button.add_theme_stylebox_override("pressed", _box(0.6))
	button.add_theme_stylebox_override("disabled", _box(0.93))
	PressFeedback.apply(button)
	return button

func _box(darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = GOLD
	sb.set_content_margin_all(10)
	return sb
