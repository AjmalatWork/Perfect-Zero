extends Control
class_name CreditsScreen

# One flowing composition, three zones, two dividers holding it together -
# not two competing columns. A prior pass tried a two-column split (the human
# credit vs. the technical attribution) and it read as two mismatched
# columns fighting for equal billing with a dead gap between them: a
# thank-you and a Pixabay attribution aren't naturally equal partners, and
# forcing them to be produced exactly that imbalance. Real credits pages have
# one emotional focal point (who made this) and a quiet footer of small
# print below it - that's the actual fix, not more column-tuning.

const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const MUTED := Color("8b90a8")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")

# Every gap on this screen is a multiple of one unit rather than an
# independently-picked value, so the rhythm actually repeats instead of each
# gap being tuned in isolation. `col` itself carries NO separation of its
# own - every gap below is an explicit spacer sized to one of these
# multiples. Combining a container separation with explicit spacers between
# the same children double-counts every gap (separation + spacer +
# separation), which is exactly what pushed this screen's total height past
# 900px and off the bottom of the canvas the first time - same bug this
# project already found and fixed once on the Endless End screen.
const UNIT := 6.0

# Portrait is a 900-wide canvas rather than 1600, and this page's composition is
# a single narrow centred column - at landscape's type sizes it occupied only
# 424 of those 900 units and read as a postcard floating in the middle of the
# screen. Everything (type, spacing, icon, buttons) is scaled by one factor so
# the rhythm the UNIT system establishes survives intact; the value is set by
# the widest element, the colophon row, landing at roughly 80% of the canvas.
const PORTRAIT_SCALE := 1.7

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

# Scaled font size and scaled UNIT multiple - every size on this page goes
# through one of these two rather than being written as a literal.
func _fs(base: int) -> int:
	return roundi(base * _s())

func _u(multiple: float) -> float:
	return UNIT * multiple * _s()

const FS_NAME := 44       # the one hero credit - the biggest text after the title
const FS_LEAD := 20       # short lead-in phrases
const FS_BODY := 21       # the thank-you message
const FS_ITEM := 20       # the "named thing"/accented highlight in a colophon group
                          # (song title's kicker, "Godot Engine", "GMTK Game Jam 2026") -
                          # MUSIC's kicker uses this same size now rather than its own
                          # smaller one, so all three colophon highlights match.
const FS_DETAIL := 17     # the smaller supporting line under a highlight

# Clamped to a fraction of the canvas as well as an absolute: at 900 this is
# exactly the width of the portrait canvas, which would run the hairline edge to
# edge and lose the fade-out at both ends that every divider in this project is
# supposed to have. Landscape is unaffected - 1600 * 0.78 is well past 900, so
# the absolute still wins there.
const DIVIDER_WIDTH := 900.0
const DIVIDER_MAX_CANVAS_FRACTION := 0.78
const DIVIDER_ALPHA := 0.4
const COLOPHON_GAP := 110.0

const DEV_LEAD := "Designed & Developed by"
const DEV_NAME := "MAKSTER"

# One merged thank-you/origin statement rather than two separate blocks - the
# jam origin is part of the same acknowledgment ("who played and rated
# this"), not a second, unrelated fact bolted on after it. GMTK_LINE keeps its
# own line so it can carry the same accent every other "named thing" on this
# screen gets.
const THANKS_LINES := ["Thanks to everyone", "who played and rated in the"]
const GMTK_LINE := "GMTK Game Jam 2026"
const THEME_LINE := "Theme: Countdown"

const MUSIC_KICKER := "MUSIC"
# Quoted and given the same plain treatment as "by arpmedia"/"via Pixabay"
# now, rather than being the group's own accented headline - MUSIC itself is
# the highlighted part of this group, so the title underneath it doesn't need
# to also compete for attention.
const MUSIC_LINES := ["\"Synthwave Retro 80s\"", "by arpmedia", "via Pixabay"]
const ENGINE_LINES := ["Made with", "Godot Engine"]

const FEEDBACK_LEAD := "We'd love your feedback"
const FEEDBACK_BUTTON := "EMAIL US"

# Pre-fills a subject/body so feedback arrives as an actual sentence rather
# than a blank compose window.
const FEEDBACK_MAILTO := "mailto:mail2makster@gmail.com?subject=Feedback%20for%20Perfect%20Zero&body=Hi%2C%0A%0AI%20wanted%20to%20share%20some%20feedback%20about%20Perfect%20Zero.%0A%0A"

var _backdrop: ColorRect
var _center: CenterContainer
var _built_portrait: bool = false

func _ready() -> void:
	_build()
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

# The composition re-centres itself, so a plain resize is just a re-measure. An
# orientation change is a rebuild instead: _s() feeds every font size, and a
# Label's font size is fixed once it has been created.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _center != null:
		_center.size = Layout.canvas_size
	_apply_overscan()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_center = null
	_build()
	_apply_overscan()

# The backdrop covers the pillarbox bands too, not just the design canvas -
# sizing it to canvas_size leaves the engine's clear colour showing as lighter
# strips beyond it on any aspect ratio that isn't the canvas's own.
func _apply_overscan() -> void:
	if _backdrop != null:
		_backdrop.position = Layout.overscan_position
		_backdrop.size = Layout.overscan_size

func _build() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_built_portrait = Layout.is_portrait()

	_backdrop = ColorRect.new()
	_backdrop.position = Layout.overscan_position
	_backdrop.size = Layout.overscan_size
	_backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_center = CenterContainer.new()
	_center.position = Vector2.ZERO
	_center.size = Layout.canvas_size
	add_child(_center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_child(col)

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("CREDITS", _fs(56), TEXT_FILL, NEON)
	col.add_child(_spacer(_u(4.0)))

	# --- Zone 1: the hero credit ------------------------------------------
	col.add_child(_stack_line(DEV_LEAD, _fs(FS_LEAD), MUTED))
	col.add_child(_spacer(_u(1.0)))
	col.add_child(_stack_line(DEV_NAME, _fs(FS_NAME), TEXT_FILL, GOLD, 5))
	col.add_child(_spacer(_u(4.0)))
	col.add_child(_make_heart())
	col.add_child(_spacer(_u(2.0)))
	col.add_child(_stack_line(THANKS_LINES[0], _fs(FS_BODY), TEXT_FILL))
	col.add_child(_spacer(_u(1.0)))
	col.add_child(_stack_line(THANKS_LINES[1], _fs(FS_BODY), TEXT_FILL))
	col.add_child(_spacer(_u(1.0)))
	# NEON, not gold - gold stays reserved for "MAKSTER" alone, even here
	# right next to it, so there's still exactly one hero credit on the page.
	col.add_child(_stack_line(GMTK_LINE, _fs(FS_ITEM), TEXT_FILL, NEON, 3))
	col.add_child(_spacer(_u(0.5)))
	col.add_child(_stack_line(THEME_LINE, _fs(FS_DETAIL), MUTED))

	col.add_child(_spacer(_u(4.0)))
	col.add_child(_make_divider())
	col.add_child(_spacer(_u(4.0)))

	# --- Zone 2: the colophon - two quiet peers side by side (Origin moved up
	# into Zone 1, see above) -------------------------------------------------
	var colophon := HBoxContainer.new()
	colophon.add_theme_constant_override("separation", int(COLOPHON_GAP * _s()))
	colophon.alignment = BoxContainer.ALIGNMENT_CENTER
	colophon.add_child(_colophon_group("", MUSIC_LINES, false, MUSIC_KICKER))
	# "Godot Engine" now gets the same accent treatment as GMTK Game Jam 2026 -
	# "Made with" is the plain lead-in, matching the plain-then-accent pattern
	# already used for "Originally created for" / "GMTK Game Jam 2026".
	colophon.add_child(_colophon_group(ENGINE_LINES[1], [ENGINE_LINES[0]], true))
	col.add_child(colophon)

	col.add_child(_spacer(_u(4.0)))
	col.add_child(_make_divider())
	col.add_child(_spacer(_u(4.0)))

	# --- Zone 3: feedback + back --------------------------------------------
	col.add_child(_stack_line(FEEDBACK_LEAD, _fs(FS_LEAD), MUTED))
	col.add_child(_spacer(_u(2.0)))
	var feedback_button := _button(FEEDBACK_BUTTON, NEON)
	feedback_button.pressed.connect(func(): OS.shell_open(FEEDBACK_MAILTO))
	col.add_child(_wrap(feedback_button))

	col.add_child(_spacer(_u(2.0)))
	var back := _button("BACK", BACK_ACCENT)
	back.pressed.connect(_on_back)
	col.add_child(_wrap(back))

# One colophon entry: an (optional) kicker - the ONE highlighted element in a
# group, used only where the content alone wouldn't say what it is ("MUSIC"
# above a song title, which doesn't announce itself the way "Made with Godot
# Engine" does) - plus an (optional) accented "named thing", plus plain
# supporting lines. A group gets a kicker OR a named-thing accent, never
# both: the kicker already is the group's one highlighted element, so its
# content stays uniformly plain underneath it (this is why Music's own title
# is quoted plain text now, not a second competing accent). `lead_with_plain_
# first` puts the named line second rather than first, for a group whose own
# name needs an introducing phrase before it. Cyan is used for every accent
# here, never gold - gold is reserved entirely for "MAKSTER", so there's one
# hero credit on the whole page, not several fighting for the same weight.
func _colophon_group(named_line: String, plain_lines: Array, lead_with_plain_first: bool = false,
		kicker: String = "") -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", int(_u(0.5)))
	group.alignment = BoxContainer.ALIGNMENT_CENTER

	if not kicker.is_empty():
		group.add_child(_stack_line(kicker, _fs(FS_ITEM), TEXT_FILL, NEON, 3))
		group.add_child(_spacer(_u(0.5)))

	var named: Label = _stack_line(named_line, _fs(FS_ITEM), TEXT_FILL, NEON, 3) if not named_line.is_empty() else null

	if lead_with_plain_first and plain_lines.size() > 0:
		group.add_child(_stack_line(plain_lines[0], _fs(FS_DETAIL), MUTED))
		if named != null:
			group.add_child(named)
		for i in range(1, plain_lines.size()):
			group.add_child(_stack_line(plain_lines[i], _fs(FS_DETAIL), MUTED))
	else:
		if named != null:
			group.add_child(named)
		for line in plain_lines:
			group.add_child(_stack_line(line, _fs(FS_DETAIL), MUTED))

	return group

# Hand-authored SVG (icons/credits_heart.svg) rather than a Unicode "❤"
# glyph - the project already learned this lesson once with the pause icon
# (some export targets, notably Web, don't reliably render every Unicode
# glyph the editor preview shows) - and rather than a procedurally-drawn
# shape, matching the same house style every other icon in icons/ uses:
# translucent accent fill + bold accent stroke, no glow filter (thorvg blurs
# the whole composited shape rather than giving a soft halo behind a crisp
# one).
func _make_heart() -> Control:
	var heart := TextureRect.new()
	heart.texture = load("res://icons/credits_heart.svg")
	heart.custom_minimum_size = Vector2(40, 38) * _s()
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _wrap(heart)

# --- Structure ----------------------------------------------------------

# Same fading hairline every overhauled screen uses (Stage Result/Endless
# End/Scores) - the thread that ties this page's three zones into one flow
# instead of three disconnected blocks.
func _make_divider() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 1

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(_divider_width(), 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(MUTED.r, MUTED.g, MUTED.b, DIVIDER_ALPHA)
	return rect

func _divider_width() -> float:
	return minf(DIVIDER_WIDTH, Layout.canvas_size.x * DIVIDER_MAX_CANVAS_FRACTION)

func _wrap(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

# `outline_size` 0 (the default) skips the outline entirely, for the plain
# muted/detail lines that don't need one - only the hero name and the two
# colophon "named things" get an accent outline.
func _stack_line(text: String, font_size: int, color: Color, outline: Color = Color.TRANSPARENT,
		outline_size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline_size > 0:
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", outline_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	# 64 raw is only ~43.5dp effective at this screen's 1.7 scale - just under
	# Android's 48dp minimum. Bumped to 72 (~49dp) in portrait only; landscape
	# (desktop/web) keeps the original 64. Applies to both BACK and EMAIL US,
	# the only two buttons this helper builds.
	var button_h: float = 72.0 if Layout.is_portrait() else 64.0
	button.custom_minimum_size = Vector2(220, button_h) * _s()
	button.add_theme_font_size_override("font_size", _fs(26))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	return button

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses. Guarded
# on the current state because hidden screens stay in the tree and would
# otherwise all answer the same press - see LevelSelect for the full note.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.CREDITS:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
